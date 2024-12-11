#!/bin/sh

# Get the system language
LANG=$(uci get luci.main.lang 2>/dev/null)
[ -z "$LANG" ] && LANG="en"

# Define messages based on the language
if [ "$LANG" = "zh_cn" ]; then
    MSG_MONITOR_STARTED="监控脚本已启动。"
    MSG_UNKNOWN_CLIENT_TYPE="未知的客户端类型："
    MSG_NOTHING_TO_COMPILE="没有需要编译的内容"
    MSG_NETWORK_REACHABLE="网络已恢复正常。"
    MSG_NETWORK_UNREACHABLE="网络连通性检查失败 (%s/%s)"
    MSG_TRY_RELOGIN="连续 %s 次网络不可达，尝试重新登录..."
    MSG_INTERFACE_NO_IP="接口 %s 没有获取到IP地址，等待下一次检查。"
    MSG_DISCONNECT_TIME="达到计划断网时间，断开网络连接。"
    MSG_RECONNECT_TIME="计划断网时间结束，恢复网络连接。"
    MSG_MONITOR_SCRIPT_STARTED="监控脚本已启动。"
    MSG_SERVICE_DISABLED="服务在配置中被禁用，不启动服务。"
    MSG_SERVICE_STARTED="服务已启动。"
    MSG_SERVICE_STOPPED="服务已停止。"
    MSG_LOG_CLEARED="日志已清除。"
    MSG_LIMITED_MONITORING_ENABLED="限时监控已启用。"
    MSG_LIMITED_MONITORING_DISABLED="限时监控已禁用。"
    MSG_MONITOR_WINDOW_ACTIVE="在监控时间窗口内，进行网络监控和重连。"
    MSG_MONITOR_WINDOW_INACTIVE="不在监控时间窗口内，暂停网络监控和重连。"
else
    MSG_MONITOR_STARTED="Monitor script started."
    MSG_UNKNOWN_CLIENT_TYPE="Unknown client type:"
    MSG_NOTHING_TO_COMPILE="Nothing to compile"
    MSG_NETWORK_REACHABLE="Network has recovered."
    MSG_NETWORK_UNREACHABLE="Network connectivity check failed (%s/%s)"
    MSG_TRY_RELOGIN="Network unreachable for %s times, attempting to re-login..."
    MSG_INTERFACE_NO_IP="Interface %s has no IP address, waiting for the next check."
    MSG_DISCONNECT_TIME="Reached scheduled disconnect time, disconnecting network."
    MSG_RECONNECT_TIME="Scheduled disconnect time ended, restoring network connection."
    MSG_MONITOR_SCRIPT_STARTED="Monitor script started."
    MSG_SERVICE_DISABLED="Service is disabled in the configuration, not starting."
    MSG_SERVICE_STARTED="Service started."
    MSG_SERVICE_STOPPED="Service stopped."
    MSG_LOG_CLEARED="Logs have been cleared."
    MSG_LIMITED_MONITORING_ENABLED="Limited monitoring enabled."
    MSG_LIMITED_MONITORING_DISABLED="Limited monitoring disabled."
    MSG_MONITOR_WINDOW_ACTIVE="Within monitoring time window, performing network monitoring and reconnection."
    MSG_MONITOR_WINDOW_INACTIVE="Outside monitoring time window, pausing network monitoring and reconnection."
fi

# Get configuration
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

# Limited monitoring
LIMITED_MONITORING=$(uci get uestc_authclient.@authclient[0].limited_monitoring 2>/dev/null)
[ -z "$LIMITED_MONITORING" ] && LIMITED_MONITORING=1

LOG_FILE="/tmp/uestc_authclient.log"

echo "$(date): $MSG_MONITOR_SCRIPT_STARTED" >> $LOG_FILE

# Select authentication script based on client type
if [ "$CLIENT_TYPE" = "ct" ]; then
    AUTH_SCRIPT="/usr/bin/uestc_ct_authclient_script.sh"
elif [ "$CLIENT_TYPE" = "srun" ]; then
    AUTH_SCRIPT="/usr/bin/uestc_srun_authclient_script.sh"
else
    echo "$(date): $MSG_UNKNOWN_CLIENT_TYPE $CLIENT_TYPE" >> $LOG_FILE
    exit 1
fi

# Define maximum consecutive failures
MAX_FAILURES=3  # Maximum failure count
failure_count=0
network_down=0  # Indicates if the network is down
CURRENT_CHECK_INTERVAL=$CHECK_INTERVAL  # Initialize network check interval

scheduled_disconnect_enabled=$(uci get uestc_authclient.@authclient[0].scheduled_disconnect_enabled 2>/dev/null)
[ -z "$scheduled_disconnect_enabled" ] && scheduled_disconnect_enabled=0

scheduled_disconnect_start=$(uci get uestc_authclient.@authclient[0].scheduled_disconnect_start 2>/dev/null)
[ -z "$scheduled_disconnect_start" ] && scheduled_disconnect_start=3

scheduled_disconnect_end=$(uci get uestc_authclient.@authclient[0].scheduled_disconnect_end 2>/dev/null)
[ -z "$scheduled_disconnect_end" ] && scheduled_disconnect_end=4

disconnect_done=0  # Indicates if disconnection has been performed

if [ "$LIMITED_MONITORING" -eq 1 ]; then
    echo "$(date): $MSG_LIMITED_MONITORING_ENABLED" >> $LOG_FILE
else
    echo "$(date): $MSG_LIMITED_MONITORING_DISABLED" >> $LOG_FILE
fi

while true; do
    CURRENT_TIME=$(date +%s)
    CURRENT_DATE=$(date +%Y-%m-%d)
    CURRENT_HOUR=$(date +%H)
    CURRENT_MIN=$(date +%M)

    # Check and clean logs
    if [ -f "$LOG_FILE" ]; then
        TEMP_LOG_FILE="${LOG_FILE}.tmp"
        > "$TEMP_LOG_FILE"  # Ensure temporary file exists
        while read -r line; do
            # Extract the date and time from the log line
            log_date=$(echo "$line" | awk '{print $1" "$2" "$3}')
            log_timestamp=$(date -d "$log_date" +%s 2>/dev/null)
            if [ -z "$log_timestamp" ]; then
                # Unable to parse date and time, keep the line
                echo "$line" >> "$TEMP_LOG_FILE"
                continue
            fi
            # Calculate date difference
            diff_days=$(( (CURRENT_TIME - log_timestamp) / 86400 ))
            if [ $diff_days -lt $LOG_RETENTION_DAYS ]; then
                # Keep logs within retention period
                echo "$line" >> "$TEMP_LOG_FILE"
            fi
        done < "$LOG_FILE"
        # Check if temporary file exists and is not empty
        if [ -s "$TEMP_LOG_FILE" ]; then
            mv "$TEMP_LOG_FILE" "$LOG_FILE"
        else
            rm -f "$LOG_FILE" "$TEMP_LOG_FILE"
        fi
    fi

    # Scheduled disconnection feature
    if [ "$scheduled_disconnect_enabled" -eq 1 ]; then
        if [ "$CURRENT_HOUR" -ge "$scheduled_disconnect_start" ] && [ "$CURRENT_HOUR" -lt "$scheduled_disconnect_end" ]; then
            if [ "$disconnect_done" -eq 0 ]; then
                echo "$(date): $MSG_DISCONNECT_TIME" >> $LOG_FILE
                # Disable network interface using ifconfig
                ifconfig $INTERFACE down
                disconnect_done=1
            fi
            sleep $CHECK_INTERVAL
            continue  # Do not perform other operations during disconnection
        else
            if [ "$disconnect_done" -eq 1 ]; then
                echo "$(date): $MSG_RECONNECT_TIME" >> $LOG_FILE
                # Enable network interface using ifconfig
                ifconfig $INTERFACE up
                disconnect_done=0
                # Wait for network to recover
                sleep 30
            fi
        fi
    fi

    # Limited monitoring feature
    if [ "$LIMITED_MONITORING" -eq 1 ]; then
        LAST_LOGIN=$(cat /tmp/uestc_authclient_last_login 2>/dev/null)
        # Convert last login time to seconds since epoch
        if [ -n "$LAST_LOGIN" ]; then
        
            # Extract time (hours and minutes) from last login time
            LOGIN_HOUR=$(date -d "$LAST_LOGIN" +%H)
            LOGIN_MIN=$(date -d "$LAST_LOGIN" +%M)
            # Convert times to minutes since midnight
            LOGIN_TOTAL_MIN=$((10#$LOGIN_HOUR * 60 + 10#$LOGIN_MIN))
            
            # Current time
            CURRENT_HOUR=$(date +%H)
            CURRENT_MIN=$(date +%M)
            # Calculate difference
            CURRENT_TOTAL_MIN=$((10#$CURRENT_HOUR * 60 + 10#$CURRENT_MIN))
            
            # Adjust for day wrap-around
            DIFF_MIN=$((CURRENT_TOTAL_MIN - LOGIN_TOTAL_MIN))
            if [ $DIFF_MIN -lt -720 ]; then  # More than 12 hours behind
                DIFF_MIN=$((DIFF_MIN + 1440)) # Add 24 hours
            elif [ $DIFF_MIN -gt 720 ]; then # More than 12 hours ahead
                DIFF_MIN=$((DIFF_MIN - 1440)) # Subtract 24 hours
            fi
            
            # Check if within the monitor window
            if [ $DIFF_MIN -lt -10 ] || [ $DIFF_MIN -gt 10 ]; then
                echo "$(date): $MSG_MONITOR_WINDOW_INACTIVE" >> $LOG_FILE
                sleep $CHECK_INTERVAL
                continue
            else
                echo "$(date): $MSG_MONITOR_WINDOW_ACTIVE" >> $LOG_FILE
            fi
        else
            # Last login time unknown, monitor continuously
            echo "$(date): $MSG_MONITOR_WINDOW_ACTIVE (last login time unknown)" >> $LOG_FILE
        fi
    fi

    # Check if the interface has an IP address
    INTERFACE_IP=$(ifstatus $INTERFACE | jsonfilter -e '@["ipv4-address"][0].address' 2>/dev/null)
    if [ -z "$INTERFACE_IP" ]; then
        printf "$(date): $MSG_INTERFACE_NO_IP\n" "$INTERFACE" >> $LOG_FILE
        sleep $CHECK_INTERVAL
        continue
    fi

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
        printf "$(date): $MSG_NETWORK_UNREACHABLE\n" "$failure_count" "$MAX_FAILURES" >> $LOG_FILE
        if [ "$failure_count" -ge "$MAX_FAILURES" ]; then
            printf "$(date): $MSG_TRY_RELOGIN\n" "$MAX_FAILURES" >> $LOG_FILE
            $AUTH_SCRIPT >> $LOG_FILE 2>&1
            failure_count=0
        fi
        network_down=1
    else
        # Network is up
        if [ "$failure_count" -ne 0 ] || [ "$network_down" -eq 1 ]; then
            echo "$(date): $MSG_NETWORK_REACHABLE" >> $LOG_FILE
        fi
        # Reset failure count
        failure_count=0
        network_down=0
    fi

    if [ "$failure_count" -ge 1 ]; then
        CURRENT_CHECK_INTERVAL=$((CURRENT_CHECK_INTERVAL / 2))  # Shorten check interval when network is down
    else
        CURRENT_CHECK_INTERVAL=$CHECK_INTERVAL  # Use default check interval when network is up
    fi

    sleep $CURRENT_CHECK_INTERVAL
done
