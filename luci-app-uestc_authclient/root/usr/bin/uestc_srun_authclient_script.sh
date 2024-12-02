#!/bin/sh

# define srun authclient binary file to use
SRUN_BIN="/usr/bin/go-nd-portal"

# 获取监听接口
INTERFACE=$(uci get uestc_authclient.@authclient[0].interface 2>/dev/null)
[ -z "$INTERFACE" ] && INTERFACE="wan"

# 获取 srun_client 配置项
USERNAME=$(uci get uestc_authclient.@authclient[0].srun_client_username 2>/dev/null)
PASSWORD=$(uci get uestc_authclient.@authclient[0].srun_client_password 2>/dev/null)
AUTH_MODE=$(uci get uestc_authclient.@authclient[0].srun_client_auth_mode 2>/dev/null)
[ -z "$AUTH_MODE" ] && AUTH_MODE="dx"
HOST=$(uci get uestc_authclient.@authclient[0].srun_client_host 2>/dev/null)
[ -z "$HOST" ] && HOST="10.253.0.237"

LOG_FILE="/tmp/uestc_authclient.log"

# 检查用户名和密码是否设置
if [ -z "$USERNAME" ] || [ -z "$PASSWORD" ]; then
    echo "$(date): Srun 认证方式的用户名或密码未设置，无法登录。" >> $LOG_FILE
    exit 1
fi

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

# 根据 AUTH_MODE 设置参数
if [ "$AUTH_MODE" = "dx" ]; then
    MODE_FLAG="-x"
else
    MODE_FLAG=""
fi

# 执行登录程序，并捕获输出
echo "$(date): 执行 Srun 认证方式登录程序..." >> $LOG_FILE
LOGIN_OUTPUT=$($SRUN_BIN \
    -ip "$INTERFACE_IP" -n "$USERNAME" -p "$PASSWORD" $MODE_FLAG -d 2>&1)

# 将登录输出写入日志
echo "$LOGIN_OUTPUT" >> $LOG_FILE

# 检查登录是否成功
if echo "$LOGIN_OUTPUT" | grep -q "success"; then
    # 登录成功，记录登录时间
    date > /tmp/uestc_authclient_last_login
    echo "$(date): Srun 认证方式登录成功，更新上次登录时间。" >> $LOG_FILE
else
    echo "$(date): Srun 认证方式登录失败，未更新上次登录时间。" >> $LOG_FILE
fi
