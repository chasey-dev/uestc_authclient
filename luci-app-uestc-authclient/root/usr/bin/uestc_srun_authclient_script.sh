#!/bin/sh

# Source the shared logging utility functions
. /usr/lib/uestc_authclient/log_utils.sh

# Source the internationalization support
. /usr/lib/uestc_authclient/i18n.sh

# Initialize logging
log_init "/tmp/uestc_authclient.log"

# define srun authclient binary file to use
SRUN_BIN="/usr/bin/go-nd-portal"

# Get the interface
INTERFACE=$(uci get uestc_authclient.listening.interface 2>/dev/null)
[ -z "$INTERFACE" ] && INTERFACE="wan"

# Get srun_client settings
USERNAME=$(uci get uestc_authclient.auth.srun_username 2>/dev/null)
PASSWORD=$(uci get uestc_authclient.auth.srun_password 2>/dev/null)
AUTH_MODE=$(uci get uestc_authclient.auth.srun_auth_mode 2>/dev/null)
[ -z "$AUTH_MODE" ] && AUTH_MODE="dx"
HOST=$(uci get uestc_authclient.auth.srun_host 2>/dev/null)
[ -z "$HOST" ] && HOST="10.253.0.237"

LAST_LOGIN_FILE="/tmp/uestc_authclient_last_login"

# Check if username and password are set
if [ -z "$USERNAME" ] || [ -z "$PASSWORD" ]; then
    log_message "$MSG_SRUN_USERNAME_PASSWORD_NOT_SET"
    exit 1
fi

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

# Set parameters based on AUTH_MODE
if [ "$AUTH_MODE" = "dx" ]; then
    MODE_FLAG="-x"
else
    MODE_FLAG=""
fi

# Execute login script and capture output
log_message "$MSG_SRUN_EXECUTE_LOGIN"
LOGIN_OUTPUT=$($SRUN_BIN \
    -ip "$INTERFACE_IP" -n "$USERNAME" -p "$PASSWORD" $MODE_FLAG -d 2>&1)

# Write login output to log - one line at a time to avoid very long messages
echo "$LOGIN_OUTPUT" | while read -r line; do
    if [ -n "$line" ]; then
        log_printf "$MSG_LOGIN_OUTPUT" "$line"
    fi
done

# Check if login was successful
if echo "$LOGIN_OUTPUT" | grep -q "success"; then
    # Login successful, record login time
    date "+%Y-%m-%d %H:%M:%S" > $LAST_LOGIN_FILE
    log_message "$MSG_SRUN_LOGIN_SUCCESS"
else
    log_message "$MSG_SRUN_LOGIN_FAILURE"
fi
