#!/bin/sh

# 获取监听接口
INTERFACE=$(uci get uestc_ct_authclient.@authclient[0].interface 2>/dev/null)
if [ -z "$INTERFACE" ]; then
    INTERFACE="wan"
fi

LOG_FILE="/tmp/uestc_ct_authclient.log"

# 释放DHCP
echo "$(date): 释放接口 $INTERFACE 的 DHCP..." >> $LOG_FILE
ifconfig $INTERFACE down
sleep 1

# 重新获取IP地址
echo "$(date): 重新获取接口 $INTERFACE 的 IP 地址..." >> $LOG_FILE
ifconfig $INTERFACE up

# 等待接口获取IP地址
MAX_WAIT=30
COUNT=0
while [ $COUNT -lt $MAX_WAIT ]; do
    INTERFACE_IP=$(ifstatus $INTERFACE | jsonfilter -e '@["ipv4-address"][0].address' 2>/dev/null)
    if [ -n "$INTERFACE_IP" ]; then
        echo "$(date): 接口 $INTERFACE 已获取到 IP 地址：$INTERFACE_IP" >> $LOG_FILE
        break
    fi
    sleep 1
    COUNT=$((COUNT + 1))
done

if [ -z "$INTERFACE_IP" ]; then
    echo "$(date): 等待 $MAX_WAIT 秒后，接口 $INTERFACE 仍未获取到 IP 地址，放弃登录。" >> $LOG_FILE
    exit 1
fi

# 执行登录程序，并捕获输出
echo "$(date): 执行登录程序..." >> $LOG_FILE
LOGIN_OUTPUT=$(/usr/bin/uestc_ct_authclient 2>&1)

# 将登录输出写入日志
echo "$LOGIN_OUTPUT" >> $LOG_FILE

# 检查登录是否成功
if echo "$LOGIN_OUTPUT" | grep -q "\[INFO\] 使用账号"; then
    # 登录成功，记录登录时间
    date > /tmp/uestc_ct_authclient_last_login
    echo "$(date): 登录成功，更新上次登录时间。" >> $LOG_FILE
else
    echo "$(date): 登录失败，未更新上次登录时间。" >> $LOG_FILE
fi
