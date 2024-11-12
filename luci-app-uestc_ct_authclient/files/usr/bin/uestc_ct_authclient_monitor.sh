#!/bin/sh

# 获取配置
CHECK_INTERVAL=$(uci get uestc_ct_authclient.@authclient[0].check_interval 2>/dev/null)
[ -z "$CHECK_INTERVAL" ] && CHECK_INTERVAL=30  # 默认检测间隔30秒

# 获取心跳检测地址列表
HEARTBEAT_HOSTS=$(uci -q get uestc_ct_authclient.@authclient[0].heartbeat_hosts)
[ -z "$HEARTBEAT_HOSTS" ] && HEARTBEAT_HOSTS="223.5.5.5 8.8.8.8"

INTERFACE=$(uci get uestc_ct_authclient.@authclient[0].interface 2>/dev/null)
[ -z "$INTERFACE" ] && INTERFACE="wan"

LOG_RETENTION_DAYS=$(uci get uestc_ct_authclient.@authclient[0].log_retention_days 2>/dev/null)
[ -z "$LOG_RETENTION_DAYS" ] && LOG_RETENTION_DAYS=7

LOG_FILE="/tmp/uestc_ct_authclient.log"

echo "$(date): 监控脚本已启动。" >> $LOG_FILE

# 定义最大连续失败次数
MAX_FAILURES=2  # 最大失败次数
failure_count=0
network_down=0  # 用于记录网络是否处于故障状态

scheduled_disconnect_enabled=$(uci get uestc_ct_authclient.@authclient[0].scheduled_disconnect_enabled 2>/dev/null)
[ -z "$scheduled_disconnect_enabled" ] && scheduled_disconnect_enabled=0

scheduled_disconnect_start=$(uci get uestc_ct_authclient.@authclient[0].scheduled_disconnect_start 2>/dev/null)
[ -z "$scheduled_disconnect_start" ] && scheduled_disconnect_start=3

scheduled_disconnect_end=$(uci get uestc_ct_authclient.@authclient[0].scheduled_disconnect_end 2>/dev/null)
[ -z "$scheduled_disconnect_end" ] && scheduled_disconnect_end=4

disconnect_done=0  # 是否已经断开网络

while true; do
    CURRENT_TIME=$(date +%s)
    CURRENT_DATE=$(date +%Y-%m-%d)
    CURRENT_HOUR=$(date +%H)
    CURRENT_MIN=$(date +%M)

    # 检查并清理日志
    if [ -f "$LOG_FILE" ]; then
        TEMP_LOG_FILE="${LOG_FILE}.tmp"
        > "$TEMP_LOG_FILE"  # 确保临时文件存在
        while read -r line; do
            # 提取日志行的日期时间
            log_date=$(echo "$line" | awk '{print $1" "$2" "$3}')
            log_timestamp=$(date -d "$log_date" +%s 2>/dev/null)
            if [ -z "$log_timestamp" ]; then
                # 无法解析日期时间，保留该行
                echo "$line" >> "$TEMP_LOG_FILE"
                continue
            fi
            # 计算日期差
            diff_days=$(( (CURRENT_TIME - log_timestamp) / 86400 ))
            if [ $diff_days -lt $LOG_RETENTION_DAYS ]; then
                # 保留在保留期限内的日志
                echo "$line" >> "$TEMP_LOG_FILE"
            fi
        done < "$LOG_FILE"
        # 检查临时文件是否存在并且非空
        if [ -s "$TEMP_LOG_FILE" ]; then
            mv "$TEMP_LOG_FILE" "$LOG_FILE"
        else
            rm -f "$LOG_FILE" "$TEMP_LOG_FILE"
        fi
    fi

    # 定时断网功能
    if [ "$scheduled_disconnect_enabled" -eq 1 ]; then
        if [ "$CURRENT_HOUR" -ge "$scheduled_disconnect_start" ] && [ "$CURRENT_HOUR" -lt "$scheduled_disconnect_end" ]; then
            if [ "$disconnect_done" -eq 0 ]; then
                echo "$(date): 达到计划断网时间，断开网络连接。" >> $LOG_FILE
                # 使用 ifconfig 禁用网络接口
                ifconfig $INTERFACE down
                disconnect_done=1
            fi
            sleep $CHECK_INTERVAL
            continue  # 在断网期间，不进行其他操作
        else
            if [ "$disconnect_done" -eq 1 ]; then
                echo "$(date): 计划断网时间结束，恢复网络连接。" >> $LOG_FILE
                # 使用 ifconfig 启用网络接口
                ifconfig $INTERFACE up
                disconnect_done=0
                # 等待网络恢复
                sleep 30
            fi
        fi
    fi

    # 检查接口是否有IP地址
    INTERFACE_IP=$(ifstatus $INTERFACE | jsonfilter -e '@["ipv4-address"][0].address' 2>/dev/null)
    if [ -z "$INTERFACE_IP" ]; then
        echo "$(date): 接口 $INTERFACE 没有获取到IP地址，等待下一次检查。" >> $LOG_FILE
        sleep $CHECK_INTERVAL
        continue
    fi

    # 检查网络连通性
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
        echo "$(date): 网络连通性检查失败 ($failure_count/$MAX_FAILURES)" >> $LOG_FILE
        if [ "$failure_count" -ge "$MAX_FAILURES" ]; then
            echo "$(date): 连续 $MAX_FAILURES 次网络不可达，尝试重新登录..." >> $LOG_FILE
            /usr/bin/uestc_ct_authclient_script.sh >> $LOG_FILE 2>&1
            failure_count=0
        fi
        network_down=1
    else
        # 网络正常
        if [ "$failure_count" -ne 0 ] || [ "$network_down" -eq 1 ]; then
            echo "$(date): 网络已恢复正常。" >> $LOG_FILE
        fi
        # 重置失败计数
        failure_count=0
        network_down=0
    fi

    # 动态调整检测间隔
    if [ "$failure_count" -ge 1 ]; then
        CURRENT_CHECK_INTERVAL=10  # 网络异常时，缩短检测间隔为10秒
    else
        CURRENT_CHECK_INTERVAL=$CHECK_INTERVAL  # 网络正常时，使用默认检测间隔
    fi

    sleep $CURRENT_CHECK_INTERVAL
done
