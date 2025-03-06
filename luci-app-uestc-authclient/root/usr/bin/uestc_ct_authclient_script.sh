#!/bin/sh

# Source the shared logging utility functions
. /usr/lib/uestc_authclient/log_utils.sh

# Get the system language
LANG=$(uci get luci.main.lang 2>/dev/null)
[ -z "$LANG" ] && LANG="en"

# Define messages based on the language
if [ "$LANG" = "zh_cn" ]; then
    MSG_RELEASE_DHCP="释放接口 %s 的 DHCP..."
    MSG_RENEW_IP="重新获取接口 %s 的 IP 地址..."
    MSG_GOT_IP="接口 %s 已获取到 IP 地址：%s"
    MSG_WAIT_IP_TIMEOUT="等待 %s 秒后，接口 %s 仍未获取到 IP 地址，放弃登录。"
    MSG_EXECUTE_LOGIN="执行电信登录程序..."
    MSG_LOGIN_SUCCESS="登录成功，更新上次登录时间。"
    MSG_LOGIN_FAILURE="登录失败，未更新上次登录时间。"
    MSG_LOGIN_OUTPUT="登录输出：%s"
else
    MSG_RELEASE_DHCP="Releasing DHCP on interface %s..."
    MSG_RENEW_IP="Renewing IP address on interface %s..."
    MSG_GOT_IP="Interface %s obtained IP address: %s"
    MSG_WAIT_IP_TIMEOUT="After waiting %s seconds, interface %s still has no IP address, aborting login."
    MSG_EXECUTE_LOGIN="Executing CT login script..."
    MSG_LOGIN_SUCCESS="Login successful, updated last login time."
    MSG_LOGIN_FAILURE="Login failed, did not update last login time."
    MSG_LOGIN_OUTPUT="Login output: %s"
fi

# Initialize logging
log_init "/tmp/uestc_authclient.log"

# define srun authclient binary file to use
CT_BIN="/usr/bin/qsh-telecom-autologin"

# Get the interface
INTERFACE=$(uci get uestc_authclient.@authclient[0].interface 2>/dev/null)
[ -z "$INTERFACE" ] && INTERFACE="wan"

# Get ct_client settings
USERNAME=$(uci get uestc_authclient.@authclient[0].ct_client_username 2>/dev/null)
PASSWORD=$(uci get uestc_authclient.@authclient[0].ct_client_password 2>/dev/null)
HOST=$(uci get uestc_authclient.@authclient[0].ct_client_host 2>/dev/null)
[ -z "$HOST" ] && HOST="172.25.249.64"

LAST_LOGIN_FILE="/tmp/uestc_authclient_last_login"

# Release DHCP
log_printf "$MSG_RELEASE_DHCP" "$INTERFACE"
ifconfig $INTERFACE down
sleep 1

# Renew IP address
log_printf "$MSG_RENEW_IP" "$INTERFACE"
ifconfig $INTERFACE up

# Wait for interface to obtain IP address
MAX_WAIT=30
COUNT=0
while [ $COUNT -lt $MAX_WAIT ]; do
    INTERFACE_IP=$(ifstatus $INTERFACE | jsonfilter -e '@["ipv4-address"][0].address' 2>/dev/null)
    if [ -n "$INTERFACE_IP" ]; then
        log_printf "$MSG_GOT_IP" "$INTERFACE" "$INTERFACE_IP"
        break
    fi
    sleep 1
    COUNT=$((COUNT + 1))
done

if [ -z "$INTERFACE_IP" ]; then
    log_printf "$MSG_WAIT_IP_TIMEOUT" "$MAX_WAIT" "$INTERFACE"
    exit 1
fi

# Execute login script and capture output
log_message "$MSG_EXECUTE_LOGIN"
LOGIN_OUTPUT=$($CT_BIN \
    -name "$USERNAME" -passwd "$PASSWORD" -host "$HOST" -localip "$INTERFACE_IP" 2>&1)

# Write login output to log - one line at a time to avoid very long messages
echo "$LOGIN_OUTPUT" | while read -r line; do
    if [ -n "$line" ]; then
        log_printf "$MSG_LOGIN_OUTPUT" "$line"
    fi
done

# Check if login was successful
if echo "$LOGIN_OUTPUT" | grep -q "Successfully"; then
    # Login successful, record login time
    date "+%Y-%m-%d %H:%M:%S" > $LAST_LOGIN_FILE
    log_message "$MSG_LOGIN_SUCCESS"
else
    log_message "$MSG_LOGIN_FAILURE"
fi
