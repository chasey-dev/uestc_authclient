#!/bin/sh

# 获取配置
CHECK_INTERVAL=$(uci get uestc_ct_authclient.@authclient[0].check_interval 2>/dev/null)
if [ -z "$CHECK_INTERVAL" ]; then
    CHECK_INTERVAL=60
fi

HEARTBEAT_HOST=$(uci get uestc_ct_authclient.@authclient[0].heartbeat_host 2>/dev/null)
if [ -z "$HEARTBEAT_HOST" ]; then
    HEARTBEAT_HOST="223.5.5.5"
fi

INTERFACE=$(uci get uestc_ct_authclient.@authclient[0].interface 2>/dev/null)
if [ -z "$INTERFACE" ]; then
    INTERFACE="wan"
fi

LOG_FILE="/tmp/uestc_ct_authclient.log"

echo "$(date): 监控脚本已启动。" >> $LOG_FILE

while true; do
    # 检查接口是否有IP地址
    INTERFACE_IP=$(ifstatus $INTERFACE | jsonfilter -e '@["ipv4-address"][0].address' 2>/dev/null)
    if [ -z "$INTERFACE_IP" ]; then
        echo "$(date): 接口 $INTERFACE 没有获取到IP地址，等待下一次检查。" >> $LOG_FILE
        sleep $CHECK_INTERVAL
        continue
    fi

    # 检查网络连通性
    # 增加 ping 次数，并判断结果
    ping -c 3 -W 1 $HEARTBEAT_HOST >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "$(date): 网络不可达，尝试重新登录..." >> $LOG_FILE
        /usr/bin/uestc_ct_authclient_script.sh >> $LOG_FILE 2>&1
    fi
    sleep $CHECK_INTERVAL
done

