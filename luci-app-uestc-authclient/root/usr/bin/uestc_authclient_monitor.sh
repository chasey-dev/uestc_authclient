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
    CLIENT_TYPE=$(uci get uestc_authclient.@authclient[0].client_type 2>/dev/null)
    [ -z "$CLIENT_TYPE" ] && CLIENT_TYPE="ct"  # Default to ct client

    CHECK_INTERVAL=$(uci get uestc_authclient.@authclient[0].check_interval 2>/dev/null)
    [ -z "$CHECK_INTERVAL" ] && CHECK_INTERVAL=30  # Default check interval is 30 seconds

    # Get heartbeat hosts list
    HEARTBEAT_HOSTS=$(uci -q get uestc_authclient.@authclient[0].heartbeat_hosts)
    [ -z "$HEARTBEAT_HOSTS" ] && HEARTBEAT_HOSTS="223.5.5.5 119.29.29.29"

    INTERFACE=$(uci get uestc_authclient.@authclient[0].interface 2>/dev/null)
    [ -z "$INTERFACE" ] && INTERFACE="wan"

    LOG_RETENTION_DAYS=$(uci get uestc_authclient.@authclient[0].log_retention_days 2>/dev/null)
    [ -z "$LOG_RETENTION_DAYS" ] && LOG_RETENTION_DAYS=7

    # Initialize logging with the correct log file
    log_init "/tmp/uestc_authclient.log"

    # Limited monitoring
    LIMITED_MONITORING=$(uci get uestc_authclient.@authclient[0].limited_monitoring 2>/dev/null)
    [ -z "$LIMITED_MONITORING" ] && LIMITED_MONITORING=1

    # Scheduled disconnect configuration
    scheduled_disconnect_enabled=$(uci get uestc_authclient.@authclient[0].scheduled_disconnect_enabled 2>/dev/null)
    [ -z "$scheduled_disconnect_enabled" ] && scheduled_disconnect_enabled=0

    scheduled_disconnect_start=$(uci get uestc_authclient.@authclient[0].scheduled_disconnect_start 2>/dev/null)
    [ -z "$scheduled_disconnect_start" ] && scheduled_disconnect_start=3

    scheduled_disconnect_end=$(uci get uestc_authclient.@authclient[0].scheduled_disconnect_end 2>/dev/null)
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
    
    # Select authentication script based on client type
    if [ "$CLIENT_TYPE" = "ct" ]; then
        AUTH_SCRIPT="/usr/bin/uestc_ct_authclient_script.sh"
    elif [ "$CLIENT_TYPE" = "srun" ]; then
        AUTH_SCRIPT="/usr/bin/uestc_srun_authclient_script.sh"
    else
        log_printf "$MSG_UNKNOWN_CLIENT_TYPE %s" "$CLIENT_TYPE"
        exit 1
    fi

    log_message "$MSG_MONITOR_SCRIPT_STARTED"

    # Log limited monitoring status
    if [ "$LIMITED_MONITORING" -eq 1 ]; then
        log_message "$MSG_LIMITED_MONITORING_ENABLED"
        LAST_LOGIN=$(cat $LAST_LOGIN_FILE 2>/dev/null)
        if [ -z "$LAST_LOGIN" ]; then
            log_message "$MSG_MONITOR_WINDOW_ACTIVE (last login time unknown)"
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
                # Disable network interface using ifconfig
                ifconfig $INTERFACE down
                disconnect_done=1
            fi
            return 1  # Signal to skip other operations
        else
            if [ "$disconnect_done" -eq 1 ]; then
                log_message "$MSG_RECONNECT_TIME"
                # Enable network interface using ifconfig
                ifconfig $INTERFACE up
                disconnect_done=0
                # Remove last login file to de-function limited monitoring
                rm $LAST_LOGIN_FILE
                # Wait for network to recover
                sleep 30
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
    INTERFACE_IP=$(ifstatus $INTERFACE | jsonfilter -e '@["ipv4-address"][0].address' 2>/dev/null)
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
        ping -c 1 -W 1 -n $HOST >/dev/null 2>&1
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
            $AUTH_SCRIPT
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