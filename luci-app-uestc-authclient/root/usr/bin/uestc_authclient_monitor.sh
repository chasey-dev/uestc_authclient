#!/bin/sh

# Main script for monitoring network connectivity and handling authentication

# Source the shared logging utility functions
. /usr/lib/uestc_authclient/log_utils.sh

# Source the internationalization support
. /usr/lib/uestc_authclient/i18n.sh

#######################################
# Global – session id is mandatory
#######################################
SESSION_ID="$1"
[ -z "$SESSION_ID" ] && {
    echo "Usage: $0 <session_id>" >&2
    exit 1
}

log_to_global() {
    set_log_domain "global"
    log_printf "$MSG_MONITOR_SCRIPT_EXIT (%s)" "$SESSION_ID"
}
trap log_to_global EXIT

#######################################
# uci_get – Handle uci config gets safely
# uci_get <config> <section> <option> <default>
#######################################
uci_get() {
    local _val
    _val=$(uci -q get "$1.$2.$3")
    if [ -n "$_val" ]; then
        printf "%s\n" "$_val"
    else
        printf "%s\n" "$4"
    fi
}

#######################################
# Load configuration and initialize variables
#######################################
init_config() {
    ############################
    # basic / enable check
    ############################
    ENABLED=$(uci_get uestc_authclient "$SESSION_ID" enabled 0)
    if [ "$ENABLED" != "1" ]; then
        # log_printf "$MSG_SESSION_DISABLED %s" "$SESSION_ID"
        exit 0    # exit gracefully
    fi
    
    ############################
    # required fields
    ############################
    AUTH_TYPE=$(uci_get uestc_authclient "$SESSION_ID" auth_type "")
    USERNAME=$(uci_get uestc_authclient "$SESSION_ID" auth_username "")
    PASSWORD=$(uci_get uestc_authclient "$SESSION_ID" auth_password "")
    HOST=$(uci_get uestc_authclient "$SESSION_ID" auth_host "")

    if [ -z "$AUTH_TYPE" ] || [ -z "$USERNAME" ] || \
       [ -z "$PASSWORD" ] || [ -z "$HOST" ]; then
        log_printf "$MSG_USERNAME_PASSWORD_NOT_SET"
        exit 1
    fi

    # Set log domain
    set_log_domain "$SESSION_ID"

    ############################
    # optional with defaults
    ############################
    LIMITED_MONITORING=$(uci_get uestc_authclient "$SESSION_ID" lm_enabled 0)

    # listening block
    CHECK_INTERVAL=$(uci_get uestc_authclient "$SESSION_ID" listen_check_interval 30)
    INTERFACE=$(uci_get uestc_authclient "$SESSION_ID" listen_interface wan)
    HEARTBEAT_HOSTS=$(uci -q get "uestc_authclient.$SESSION_ID.listen_hosts") || \
        HEARTBEAT_HOSTS="223.5.5.5 119.29.29.29"

    # logging block
    LOG_RETENTION_DAYS=$(uci_get uestc_authclient "$SESSION_ID" log_rdays 7)
    
    # schedule block
    scheduled_disconnect_enabled=$(uci_get uestc_authclient "$SESSION_ID" schedule_enabled 0)
    scheduled_disconnect_start=$(uci_get uestc_authclient "$SESSION_ID" schedule_start 3)
    scheduled_disconnect_end=$(uci_get uestc_authclient "$SESSION_ID"   schedule_end   4)

    ############################
    # build AUTH_PARAMS
    ############################
    # TODO: add MAX_WAIT setting in cbi
    MAX_WAIT=30
    if [ "$AUTH_TYPE" = "ct" ]; then
        AUTH_PARAMS="-t ct   -i $INTERFACE -s $HOST -u $USERNAME -p $PASSWORD -w $MAX_WAIT"
    elif [ "$AUTH_TYPE" = "srun" ]; then
        AUTH_MODE=$(uci_get uestc_authclient "$SESSION_ID" auth_mode qsh-edu)
        AUTH_PARAMS="-t srun -i $INTERFACE -s $HOST -u $USERNAME -p $PASSWORD \
                     -m $AUTH_MODE -w $MAX_WAIT"
    else
        log_printf "$MSG_UNKNOWN_CLIENT_TYPE" "$AUTH_TYPE"
        exit 1
    fi

    ############################
    # Define files and variables
    ############################
    LAST_LOGIN_FILE="/tmp/uestc_authclient/$SESSION_ID/last_login"
    NETWORK_STATUS_FILE="/tmp/uestc_authclient/$SESSION_ID/network_status"

    # Use the new unified authentication script
    AUTH_SCRIPT="/usr/bin/uestc_authclient_script.sh"

    # Define maximum consecutive failures
    MAX_FAILURES=3  # Maximum failure count
    failure_count=0
    network_down=0  # Indicates if the network is down
    CURRENT_CHECK_INTERVAL=$CHECK_INTERVAL  # Initialize network check interval
    ORIGINAL_CHECK_INTERVAL=$CHECK_INTERVAL  # Store the original interval for reset
    MAX_BACKOFF_INTERVAL=1800  # Maximum backoff interval (30 minutes)
    
    # Simple interface status tracking
    interface_is_down=0  # Track if interface is currently down
    interface_is_down_reason=""  # Reason for interface down: "scheduled" "backoff" or "forced"
    backoff_start_time=0  # When backoff mode started
    
    limited_monitoring_notice_flag=0  # Flag to prevent loop logging
    in_backoff_mode=0  # Flag to indicate if we're in backoff mode

    log_message "$MSG_MONITOR_SCRIPT_STARTED"

    # Log limited monitoring status
    if [ "$LIMITED_MONITORING" -eq 1 ]; then
        log_message "$MSG_LIMITED_MONITORING_ENABLED"
    else
        log_message "$MSG_LIMITED_MONITORING_DISABLED"
    fi
}

#######################################
# Handle authentication process, capture output and update last login file
# Arguments:
#   $1 - Authentication parameters to pass to the auth script
# Returns:
#   0 if authentication was successful, 1 otherwise
#######################################
handle_auth() {
    local auth_params="$1"

    log_printf "$MSG_EXECUTE_LOGIN" "$AUTH_TYPE"
    
    # Execute the auth script and capture output
    local auth_output auth_exit_code
    auth_output=$($AUTH_SCRIPT $auth_params 2>&1)
    auth_exit_code=$?

    # Handle based on exit code
    case "$auth_exit_code" in
        0|3)  
            # Success or authentication failure - log the output
            # Write login output to log - one line at a time to avoid very long messages
            echo "$auth_output" | while read -r line; do
                if [ -n "$line" ]; then
                    log_printf "$MSG_LOGIN_OUTPUT" "$line"
                fi
            done
            
            if [ "$auth_exit_code" -eq 0 ]; then
                # Login successful, record login time as Unix timestamp
                mkdir -p "$(dirname "$LAST_LOGIN_FILE")" 2>/dev/null
                date +%s > "$LAST_LOGIN_FILE"
                log_printf "$MSG_LOGIN_SUCCESS" "$AUTH_TYPE"
                return 0
            else
                log_printf "$MSG_LOGIN_FAILURE" "$AUTH_TYPE"
                return 1
            fi
            ;;
            
        1)  
            # Usage error or unknown client type
            log_message "$MSG_AUTH_PARAM_ERROR"
            return 1
            ;;
            
        2)  
            # Network error - couldn't get IP
            log_printf "$MSG_WAIT_IP_TIMEOUT" "$MAX_WAIT" "$INTERFACE"
            return 1
            ;;
    esac
}

#######################################
# Clean logs older than retention period
#######################################
clean_logs() {
    # Call the shared log_clean function with our retention period
    # Clean logs daily (24 hours interval)
    log_clean "$LOG_RETENTION_DAYS" 24
}

#######################################
# Check if currently in scheduled disconnect window
# Returns:
#   0 if not in scheduled window, 1 if in scheduled window
#######################################
is_in_scheduled_window() {
    if [ "$scheduled_disconnect_enabled" -ne 1 ]; then
        return 0  # Not enabled, so not in window
    fi
    
    # Get current timestamp
    local current_ts=$(date +%s)
    
    # Get today's date parts for timestamp calculation
    local today=$(date +%Y-%m-%d)
    
    # Calculate start and end timestamps for today
    local start_ts=$(date -d "$today $scheduled_disconnect_start:00:00" +%s 2>/dev/null)
    local end_ts=$(date -d "$today $scheduled_disconnect_end:00:00" +%s 2>/dev/null)
    
    # Handle overnight case (end time < start time)
    if [ "$end_ts" -lt "$start_ts" ]; then
        # If current time is after start time, use tomorrow's end time
        if [ "$current_ts" -ge "$start_ts" ]; then
            local tomorrow=$(date -d "tomorrow" +%Y-%m-%d)
            end_ts=$(date -d "$tomorrow $scheduled_disconnect_end:00:00" +%s 2>/dev/null)
        # If current time is before end time, use today's end time but yesterday's start time
        elif [ "$current_ts" -lt "$end_ts" ]; then
            local yesterday=$(date -d "yesterday" +%Y-%m-%d)
            start_ts=$(date -d "$yesterday $scheduled_disconnect_start:00:00" +%s 2>/dev/null)
        fi
    fi
    
    # Check if we're in the scheduled disconnect window
    if [ "$current_ts" -ge "$start_ts" ] && [ "$current_ts" -lt "$end_ts" ]; then
        return 1  # In scheduled window
    else
        return 0  # Not in scheduled window
    fi
}

#######################################
# Control network interface
# Arguments:
#   $1 - Action: "up" or "down"
#   $2 - Reason: "scheduled", "backoff" or "forced"
# Returns:
#   0 if action was taken, 1 if no action was needed
#######################################
control_network() {
    local action="$1"
    local reason="$2"
    
    # Handle network down action
    if [ "$action" = "down" ]; then
        # If already down for the same reason, no action needed
        if [ "$interface_is_down" -eq 1 ] && [ "$interface_is_down_reason" = "$reason" ]; then
            return 1
        fi
        
        # If down for another reason, check priorities
        if [ "$interface_is_down" -eq 1 ]; then
            # If scheduled already has priority, don't override with backoff
            if [ "$interface_is_down_reason" = "scheduled" ] && [ "$reason" = "backoff" ]; then
                return 1
            fi
            
            # Otherwise, we'll change the reason without physically toggling the interface
            interface_is_down_reason="$reason"
            
            # If changing from backoff to scheduled, reset backoff state
            if [ "$reason" = "scheduled" ] && [ "$in_backoff_mode" -eq 1 ]; then
                log_message "$MSG_BACKOFF_RESET_AFTER_SCHEDULE"
                in_backoff_mode=0
                CURRENT_CHECK_INTERVAL=$ORIGINAL_CHECK_INTERVAL
            fi
            
            return 0
        fi
        
        # Actually disconnect the network
        if [ "$reason" = "scheduled" ]; then
            log_message "$MSG_DISCONNECT_TIME"
            # If we were in backoff mode, reset it due to scheduled disconnect priority
            if [ "$in_backoff_mode" -eq 1 ]; then
                log_message "$MSG_BACKOFF_RESET_AFTER_SCHEDULE"
                in_backoff_mode=0
                CURRENT_CHECK_INTERVAL=$ORIGINAL_CHECK_INTERVAL
            fi

            # Write status code 0 to the network status file to update LuCI status
            # Do this only in scheduled disconnect case
            mkdir -p "$(dirname "$NETWORK_STATUS_FILE")" 2>/dev/null
            echo "0" > $NETWORK_STATUS_FILE 2>/dev/null
            
        elif [ "$reason" = "backoff" ]; then
            log_message "$MSG_BACKOFF_DISCONNECT"
        fi
        
        # Physically disconnect
        ip link set dev "$INTERFACE" down
        interface_is_down=1
        interface_is_down_reason="$reason"
        return 0
        
    # Handle network up action
    elif [ "$action" = "up" ]; then
        # If already up, no action needed
        # But if it is forced set interface up anyway
        if [ "$interface_is_down" -eq 0 ] && [ "$reason" != "forced" ]; then
            return 1
        fi
        
        # If down for a different reason than requested, respect priorities
        if [ "$interface_is_down_reason" != "$reason" ]; then
            # If trying to reconnect from backoff but scheduled has priority, don't do it
            if [ "$reason" = "backoff" ] && [ "$interface_is_down_reason" = "scheduled" ]; then
                return 1
            fi
        fi
        
        # Perform reconnect based on reason
        if [ "$reason" = "scheduled" ]; then
            log_message "$MSG_RECONNECT_TIME"
            # Reset all states when scheduled disconnect ends
            in_backoff_mode=0
            CURRENT_CHECK_INTERVAL=$ORIGINAL_CHECK_INTERVAL
            failure_count=0
            network_down=0
            # Remove last login file to reset limited monitoring
            rm -f $LAST_LOGIN_FILE 2>/dev/null
        elif [ "$reason" = "backoff" ]; then
            log_message "$MSG_BACKOFF_RECONNECT"
            # Don't reset backoff mode yet - let network check determine if truly back online
        fi
        
        # Physically reconnect
        ip link set dev "$INTERFACE" up
        interface_is_down=0
        interface_is_down_reason=""
        
        # Allow time for interface to come up
        sleep 5
        return 0
    fi
    
    # Invalid action
    return 1
}

#######################################
# Handle scheduled disconnection
#######################################
handle_scheduled_disconnect() {
    if [ "$scheduled_disconnect_enabled" -ne 1 ]; then
        return 0
    fi
    
    # Check if we're in scheduled window
    is_in_scheduled_window
    local in_window=$?
    
    if [ "$in_window" -eq 1 ]; then
        # We're in scheduled disconnect window
        control_network "down" "scheduled"
        # Skip other checks while in scheduled window
        return 1
    else
        # We're outside scheduled window, check if we need to reconnect
        if [ "$interface_is_down" -eq 1 ] && [ "$interface_is_down_reason" = "scheduled" ]; then
            control_network "up" "scheduled"
        fi
    fi
    
    # Continue with other operations if not in scheduled window or no action needed
    return 0
}

#######################################
# Check if current time is within monitoring window
#######################################
check_limited_monitoring() {
    # If in backoff mode, bypass limited monitoring
    if [ "$in_backoff_mode" -eq 1 ]; then
        return 0  # Signal to continue with network check
    fi

    if [ "$LIMITED_MONITORING" -ne 1 ]; then
        # Limited monitoring disabled, always monitor
        return 0
    fi
    
    # Get last login timestamp
    LAST_LOGIN_TS=$(cat $LAST_LOGIN_FILE 2>/dev/null)
    
    if [ -z "$LAST_LOGIN_TS" ]; then
        # No last login time, assume we should monitor
        if [ "$limited_monitoring_notice_flag" -ne 2 ]; then
            log_printf "$MSG_MONITOR_WINDOW_ACTIVE %s" "($MSG_LAST_LOGIN_UNKNOWN)"
            limited_monitoring_notice_flag=2
        fi
        return 0
    fi
    
    # Check if interface has IP
    check_interface_ip
    if [ $? -eq 1 ]; then
        # Remove LAST_LOGIN_FILE here since interface IP is lost
        # should cancel limited monitoring
        if [ -n "$LAST_LOGIN_TS" ]; then
            log_printf "$MSG_INTERFACE_NO_IP" "$INTERFACE"
            rm -f $LAST_LOGIN_FILE 2>/dev/null
            # Set the flag to prevent redundant logging
            limited_monitoring_notice_flag=2
        fi
        
        return 0
    fi

    # Get current timestamp
    CURRENT_TS=$(date +%s)

    # Get the Hour:Minute:Second of the last login
    # This will be used to determine the target monitoring window for *today*
    LAST_LOGIN_HOD=$(date -d "@$LAST_LOGIN_TS" "+%H:%M:%S")
    # Calculate today's timestamp at the Hour:Minute:Second of the last login
    TARGET_TS_TODAY=$(date -d "$LAST_LOGIN_HOD" +%s)
    # Calculate the difference between the current time and today's target time
    TIME_DIFF=$((CURRENT_TS - TARGET_TS_TODAY))
    # Take the absolute value of the time difference
    TIME_DIFF_ABS=${TIME_DIFF#-}
    # Check if current time is within the ±10 minutes (600 seconds) window 
    # around the daily login time
    if [ "$TIME_DIFF_ABS" -le 600 ]; then
        # Within ±10 minutes of the daily login time
        if [ "$limited_monitoring_notice_flag" -ne 0 ]; then
            log_message "$MSG_MONITOR_WINDOW_ACTIVE" # Message indicates monitoring is active
            limited_monitoring_notice_flag=0
        fi
        return 0 # Continue with network check
    else
        # Outside the daily ±10 minutes monitoring window
        if [ "$limited_monitoring_notice_flag" -ne 1 ]; then
            log_message "$MSG_MONITOR_WINDOW_INACTIVE" # Message indicates monitoring is inactive
            limited_monitoring_notice_flag=1
        fi
        return 1  # Signal to skip network check
    fi
}

#######################################
# Check if interface has IP address
#######################################
check_interface_ip() {
    INTERFACE_IP=$(ip addr show dev "$INTERFACE" | awk '/inet / {print $2}' | cut -d/ -f1)
    if [ -z "$INTERFACE_IP" ]; then
        return 1  # Signal no IP address
    fi
    return 0  # Signal IP address exists
}

#######################################
# Ping heartbeat hosts
#######################################
ping_heartbeat_hosts() {
    local status_code=0
    # Check if the heartbeat hosts are reachable
    for HOST in $HEARTBEAT_HOSTS; do
        ping -I $INTERFACE -c 1 -W 1 -n $HOST >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            status_code=1  # Host is reachable
        fi
    done
    # Write status code to the network status file
    mkdir -p "$(dirname "$NETWORK_STATUS_FILE")" 2>/dev/null
    echo "$status_code" > $NETWORK_STATUS_FILE 2>/dev/null

    return $status_code  # No hosts reachable
}


#######################################
# Check network connectivity and handle login if needed
# Arguments: $1 - is in limited monitoring or not
#######################################
check_network_connectivity() {

    # Check network connectivity
    ping_heartbeat_hosts
    network_reachable=$?

    if [ "$1" -eq 1 ]; then
        # Skip network check if in limited monitoring
        return
    fi

    # Network is unreachable case
    if [ "$network_reachable" -eq 0 ]; then
        failure_count=$((failure_count + 1))
        network_down=1
        
        if [ "$in_backoff_mode" -eq 0 ]; then
            # Not in backoff mode yet
            log_printf "$MSG_NETWORK_UNREACHABLE" "$failure_count" "$MAX_FAILURES"
            
            # Shorten check interval when network is down before backoff is triggered
            CURRENT_CHECK_INTERVAL=$((CURRENT_CHECK_INTERVAL / 2))
        fi
        
        # Attempt authentication if needed
        if [ "$failure_count" -ge "$MAX_FAILURES" ]; then
            # Show appropriate message based on state
            if [ "$in_backoff_mode" -eq 1 ]; then
                log_message "$MSG_TRY_RELOGIN_BACKOFF"
            else
                log_printf "$MSG_TRY_RELOGIN" "$MAX_FAILURES"
            fi
            
            # Try to authenticate
            handle_auth "$AUTH_PARAMS"

            # Should reset since AUTH_SCRIPT will make the network interface up
            interface_is_down=0
            interface_is_down_reason=""

            # Check if network is now reachable after authentication
            ping_heartbeat_hosts
            network_reachable=$?
            
            if [ "$network_reachable" -eq 0 ]; then
                # Auth failed to restore network
                log_message "$MSG_AUTH_FAILED_NETWORK_STILL_DOWN"

                # Apply exponential backoff
                CURRENT_CHECK_INTERVAL=$((CURRENT_CHECK_INTERVAL * 2))

                if [ "$CURRENT_CHECK_INTERVAL" -le "$ORIGINAL_CHECK_INTERVAL" ]; then
                    # This can happen on first backoff if we were at half interval
                    CURRENT_CHECK_INTERVAL=$ORIGINAL_CHECK_INTERVAL
                fi

                # Ensure we don't exceed the maximum backoff interval
                if [ "$CURRENT_CHECK_INTERVAL" -gt "$MAX_BACKOFF_INTERVAL" ]; then
                    CURRENT_CHECK_INTERVAL=$MAX_BACKOFF_INTERVAL
                fi
                
                log_printf "$MSG_BACKOFF_APPLIED" "$CURRENT_CHECK_INTERVAL"

                # Immediately disconnect network for backoff
                in_backoff_mode=1
                control_network "down" "backoff"

                # Keep failure_count at MAX_FAILURES for next cycle
                failure_count=$MAX_FAILURES
                
            else
                # Auth succeeded in restoring network
                log_message "$MSG_NETWORK_REACHABLE"
                
                # Reset everything
                if [ "$in_backoff_mode" -eq 1 ]; then
                    log_printf "$MSG_BACKOFF_RESET" "$ORIGINAL_CHECK_INTERVAL"
                    in_backoff_mode=0
                fi
                CURRENT_CHECK_INTERVAL=$ORIGINAL_CHECK_INTERVAL
                failure_count=0
                network_down=0
            fi
        fi
    else
        # Network is reachable case
        if [ "$network_down" -eq 1 ]; then
            # Only show recovery message if we were previously down
            log_message "$MSG_NETWORK_REACHABLE"
        fi
        
        # If we're in backoff mode and network is now reachable, reset backoff
        if [ "$in_backoff_mode" -eq 1 ]; then
            log_printf "$MSG_BACKOFF_RESET" "$ORIGINAL_CHECK_INTERVAL"
            in_backoff_mode=0
        fi
        
        # Reset everything when network is up
        CURRENT_CHECK_INTERVAL=$ORIGINAL_CHECK_INTERVAL
        failure_count=0
        network_down=0
    fi
}

#######################################
# Main function to execute the monitor loop
#######################################
main() {
    # Initialize configuration
    init_config
    
    # Force the network interface up in case it was previously down
    control_network "up" "forced"

    # Main monitoring loop
    while true; do
        
        # Clean logs (only runs at configured intervals)
        clean_logs

        # Handle scheduled disconnection (highest priority)
        handle_scheduled_disconnect
        if [ $? -eq 1 ]; then
            sleep $CHECK_INTERVAL
            continue
        fi

        # Check if we should run monitoring based on time window
        check_limited_monitoring

        # Check network connectivity and handle authentication
        check_network_connectivity $?

        # Sleep until next check, if it is backoff mode this var will be greater than CHECK_INTERVAL
        sleep $CURRENT_CHECK_INTERVAL
    done
}

# Start the main function
main
