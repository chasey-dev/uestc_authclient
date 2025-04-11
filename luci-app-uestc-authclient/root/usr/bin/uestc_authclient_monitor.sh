#!/bin/sh

# Main script for monitoring network connectivity and handling authentication

# Source the shared logging utility functions
. /usr/lib/uestc_authclient/log_utils.sh

# Source the internationalization support
. /usr/lib/uestc_authclient/i18n.sh

#######################################
# Load configuration and initialize variables
#######################################
init_config() {
    # Get client configuration
    AUTH_TYPE=$(uci get uestc_authclient.auth.auth_type 2>/dev/null)
    [ -z "$AUTH_TYPE" ] && AUTH_TYPE="ct"  # Default to ct client

    CHECK_INTERVAL=$(uci get uestc_authclient.listening.check_interval 2>/dev/null)
    [ -z "$CHECK_INTERVAL" ] && CHECK_INTERVAL=30  # Default check interval is 30 seconds

    # Get heartbeat hosts list
    HEARTBEAT_HOSTS=$(uci -q get uestc_authclient.listening.heartbeat_hosts)
    [ -z "$HEARTBEAT_HOSTS" ] && HEARTBEAT_HOSTS="223.5.5.5 119.29.29.29"

    INTERFACE=$(uci get uestc_authclient.listening.interface 2>/dev/null)
    [ -z "$INTERFACE" ] && INTERFACE="wan"

    LOG_RETENTION_DAYS=$(uci get uestc_authclient.logging.retention_days 2>/dev/null)
    [ -z "$LOG_RETENTION_DAYS" ] && LOG_RETENTION_DAYS=7

    # Limited monitoring
    LIMITED_MONITORING=$(uci get uestc_authclient.basic.limited_monitoring 2>/dev/null)
    [ -z "$LIMITED_MONITORING" ] && LIMITED_MONITORING=1

    # Scheduled disconnect configuration
    scheduled_disconnect_enabled=$(uci get uestc_authclient.schedule.enabled 2>/dev/null)
    [ -z "$scheduled_disconnect_enabled" ] && scheduled_disconnect_enabled=0

    scheduled_disconnect_start=$(uci get uestc_authclient.schedule.disconnect_start 2>/dev/null)
    [ -z "$scheduled_disconnect_start" ] && scheduled_disconnect_start=3

    scheduled_disconnect_end=$(uci get uestc_authclient.schedule.disconnect_end 2>/dev/null)
    [ -z "$scheduled_disconnect_end" ] && scheduled_disconnect_end=4

    # Define files and variables
    LAST_LOGIN_FILE="/tmp/uestc_authclient_last_login"
    
    # Define maximum consecutive failures
    MAX_FAILURES=3  # Maximum failure count
    failure_count=0
    network_down=0  # Indicates if the network is down
    CURRENT_CHECK_INTERVAL=$CHECK_INTERVAL  # Initialize network check interval
    disconnect_done=0  # Indicates if disconnection has been performed
    limited_monitoring_notice_flag=0  # Flag to prevent loop logging
    
    # Use the new unified authentication script
    AUTH_SCRIPT="/usr/bin/uestc_authclient_script.sh"
    
    # Get authentication parameters based on client type
    if [ "$AUTH_TYPE" = "ct" ]; then
        USERNAME=$(uci get uestc_authclient.auth.ct_username 2>/dev/null)
        PASSWORD=$(uci get uestc_authclient.auth.ct_password 2>/dev/null)
        HOST=$(uci get uestc_authclient.auth.ct_host 2>/dev/null)
        [ -z "$HOST" ] && HOST="172.25.249.64"
        AUTH_PARAMS="-t ct -i $INTERFACE -s $HOST -u $USERNAME -p $PASSWORD"
    elif [ "$AUTH_TYPE" = "srun" ]; then
        USERNAME=$(uci get uestc_authclient.auth.srun_username 2>/dev/null)
        PASSWORD=$(uci get uestc_authclient.auth.srun_password 2>/dev/null)
        AUTH_MODE=$(uci get uestc_authclient.auth.srun_auth_mode 2>/dev/null)
        [ -z "$AUTH_MODE" ] && AUTH_MODE="dx"
        HOST=$(uci get uestc_authclient.auth.srun_host 2>/dev/null)
        [ -z "$HOST" ] && HOST="10.253.0.237"
        AUTH_PARAMS="-t srun -i $INTERFACE -s $HOST -u $USERNAME -p $PASSWORD -m $AUTH_MODE"
    else
        log_printf "$MSG_UNKNOWN_CLIENT_TYPE %s" "$AUTH_TYPE"
        exit 1
    fi

    log_message "$MSG_MONITOR_SCRIPT_STARTED"

    # Log limited monitoring status
    if [ "$LIMITED_MONITORING" -eq 1 ]; then
        log_message "$MSG_LIMITED_MONITORING_ENABLED"
        LAST_LOGIN=$(cat $LAST_LOGIN_FILE 2>/dev/null)
        if [ -z "$LAST_LOGIN" ]; then
            log_printf "$MSG_MONITOR_WINDOW_ACTIVE %s" "($MSG_LAST_LOGIN_UNKNOWN)"
        fi
    else
        log_message "$MSG_LIMITED_MONITORING_DISABLED"
    fi
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
# Handle scheduled disconnection
#######################################
handle_scheduled_disconnect() {
    if [ "$scheduled_disconnect_enabled" -eq 1 ]; then
        if [ "$CURRENT_HOUR" -ge "$scheduled_disconnect_start" ] && [ "$CURRENT_HOUR" -lt "$scheduled_disconnect_end" ]; then
            if [ "$disconnect_done" -eq 0 ]; then
                log_message "$MSG_DISCONNECT_TIME"
                # Disable network interface
                ip link set dev "$INTERFACE" down
                disconnect_done=1
            fi
            return 1  # Signal to skip other operations
        else
            if [ "$disconnect_done" -eq 1 ]; then
                log_message "$MSG_RECONNECT_TIME"
                # Enable network interface
                ip link set dev "$INTERFACE" up
                disconnect_done=0
                # Remove last login file to de-function limited monitoring
                rm $LAST_LOGIN_FILE
            fi
        fi
    fi
    return 0  # Signal to continue with other operations
}

#######################################
# Check if current time is within monitoring window
#######################################
check_limited_monitoring() {
    if [ "$LIMITED_MONITORING" -eq 1 ]; then
        LAST_LOGIN=$(cat $LAST_LOGIN_FILE 2>/dev/null)
        # Convert last login time to seconds since epoch
        if [ -n "$LAST_LOGIN" ]; then
            # Extract time (hours and minutes) from last login time
            LOGIN_HOUR=$(date -d "$LAST_LOGIN" -D "%Y-%m-%d %H:%M:%S" +%H)
            LOGIN_MIN=$(date -d "$LAST_LOGIN" -D "%Y-%m-%d %H:%M:%S" +%M)

            # Convert times to minutes since midnight
            LOGIN_TOTAL_MIN=$(expr "$LOGIN_HOUR" \* 60 + "$LOGIN_MIN")
            
            # Current time
            CURRENT_HOUR=$(date +%H)
            CURRENT_MIN=$(date +%M)
            # Calculate difference
            CURRENT_TOTAL_MIN=$(expr "$CURRENT_HOUR" \* 60 + "$CURRENT_MIN")
            
            # Adjust for day wrap-around
            DIFF_MIN=$(expr "$CURRENT_TOTAL_MIN" - "$LOGIN_TOTAL_MIN")
            if [ $DIFF_MIN -lt -720 ]; then  # More than 12 hours behind
                DIFF_MIN=$((DIFF_MIN + 1440)) # Add 24 hours
            elif [ $DIFF_MIN -gt 720 ]; then # More than 12 hours ahead
                DIFF_MIN=$((DIFF_MIN - 1440)) # Subtract 24 hours
            fi
            
            # Check if within the monitor window
            if [ $DIFF_MIN -lt -10 ] || [ $DIFF_MIN -gt 10 ]; then
                if [ "$limited_monitoring_notice_flag" -ne 1 ]; then
                    log_message "$MSG_MONITOR_WINDOW_INACTIVE"
                    limited_monitoring_notice_flag=1
                fi
                return 1  # Signal to skip network check
            else
                if [ "$limited_monitoring_notice_flag" -eq 1 ]; then
                    log_message "$MSG_MONITOR_WINDOW_ACTIVE"
                    limited_monitoring_notice_flag=0
                fi
            fi
        fi
    fi
    return 0  # Signal to continue with network check
}

#######################################
# Check if interface has IP address
#######################################
check_interface_ip() {
    INTERFACE_IP=$(ip addr show dev "$INTERFACE" | awk '/inet / {print $2}' | cut -d/ -f1)
    if [ -z "$INTERFACE_IP" ]; then
        log_printf "$MSG_INTERFACE_NO_IP" "$INTERFACE"
        return 1  # Signal no IP address
    fi
    return 0  # Signal IP address exists
}

#######################################
# Check network connectivity and handle login if needed
#######################################
check_network_connectivity() {
    # Check network connectivity
    network_reachable=0
    for HOST in $HEARTBEAT_HOSTS; do
        ping -I $INTERFACE -c 1 -W 1 -n $HOST >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            network_reachable=1
            break
        fi
    done

    if [ "$network_reachable" -eq 0 ]; then
        failure_count=$((failure_count + 1))
        log_printf "$MSG_NETWORK_UNREACHABLE" "$failure_count" "$MAX_FAILURES"
        if [ "$failure_count" -ge "$MAX_FAILURES" ]; then
            log_printf "$MSG_TRY_RELOGIN" "$MAX_FAILURES"
            $AUTH_SCRIPT $AUTH_PARAMS
            failure_count=0
        fi
        network_down=1
        # Shorten check interval when network is down
        CURRENT_CHECK_INTERVAL=$((CHECK_INTERVAL / 2))
    else
        # Network is up
        if [ "$failure_count" -ne 0 ] || [ "$network_down" -eq 1 ]; then
            log_message "$MSG_NETWORK_REACHABLE"
        fi
        # Reset failure count
        failure_count=0
        network_down=0
        # Use default check interval when network is up
        CURRENT_CHECK_INTERVAL=$CHECK_INTERVAL
    fi
}

#######################################
# Main function to execute the monitor loop
#######################################
main() {
    # Initialize configuration
    init_config

    # Main monitoring loop
    while true; do
        CURRENT_TIME=$(date +%s)
        CURRENT_HOUR=$(date +%H)
        CURRENT_MIN=$(date +%M)

        # Clean logs (only runs at configured intervals)
        clean_logs

        # Handle scheduled disconnection
        handle_scheduled_disconnect
        if [ $? -eq 1 ]; then
            sleep $CHECK_INTERVAL
            continue
        fi

        # Check if we should run monitoring based on time window
        check_limited_monitoring
        if [ $? -eq 1 ]; then
            sleep $CHECK_INTERVAL
            continue
        fi

        # Check if interface has IP
        check_interface_ip
        if [ $? -eq 1 ]; then
            sleep $CHECK_INTERVAL
            continue
        fi

        # Check network connectivity and handle reconnection
        check_network_connectivity

        # Sleep until next check
        sleep $CURRENT_CHECK_INTERVAL
    done
}

# Start the main function
main