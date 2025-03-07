#!/bin/sh

# Source the shared logging utility functions
. /usr/lib/uestc_authclient/log_utils.sh

# Source the internationalization support
. /usr/lib/uestc_authclient/i18n.sh

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
log_message "$MSG_CT_EXECUTE_LOGIN"
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
    log_message "$MSG_CT_LOGIN_SUCCESS"
else
    log_message "$MSG_CT_LOGIN_FAILURE"
fi
