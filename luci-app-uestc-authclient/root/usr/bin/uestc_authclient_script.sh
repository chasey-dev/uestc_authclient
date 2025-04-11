#!/bin/sh

# Source the shared logging utility functions
. /usr/lib/uestc_authclient/log_utils.sh

# Source the internationalization support
. /usr/lib/uestc_authclient/i18n.sh

# Usage function to display help message
usage() {
    echo "Usage: $0 -t <client_type> -i <interface> -s <server> -u <username> -p <password> [-m <auth_mode>]"
    echo "  -t: Client type (ct or srun)"
    echo "  -i: Network interface (default: wan)"
    echo "  -s: Authentication server"
    echo "  -u: Username"
    echo "  -p: Password"
    echo "  -m: Authentication mode (only for srun, default: dx)"
    exit 1
}

# Default values
INTERFACE="wan"
CLIENT_TYPE=""
USERNAME=""
PASSWORD=""
HOST=""
AUTH_MODE="dx"

# Parse command line arguments
while getopts "t:i:s:u:p:m:" opt; do
    case $opt in
        t) CLIENT_TYPE="$OPTARG" ;;
        i) INTERFACE="$OPTARG" ;;
        s) HOST="$OPTARG" ;;
        u) USERNAME="$OPTARG" ;;
        p) PASSWORD="$OPTARG" ;;
        m) AUTH_MODE="$OPTARG" ;;
        *) usage ;;
    esac
done

# Check required parameters
if [ -z "$CLIENT_TYPE" ] || [ -z "$USERNAME" ] || [ -z "$PASSWORD" ] || [ -z "$HOST" ]; then
    log_message "$MSG_USERNAME_PASSWORD_NOT_SET"
    usage
fi

# Set binary based on client type
if [ "$CLIENT_TYPE" = "ct" ]; then
    AUTH_BIN="/usr/bin/qsh-telecom-autologin"
elif [ "$CLIENT_TYPE" = "srun" ]; then
    AUTH_BIN="/usr/bin/go-nd-portal"
else
    log_printf "$MSG_UNKNOWN_CLIENT_TYPE %s" "$CLIENT_TYPE"
    exit 1
fi

LAST_LOGIN_FILE="/tmp/uestc_authclient_last_login"

# Release DHCP
log_printf "$MSG_RELEASE_DHCP" "$INTERFACE"
ip link set dev "$INTERFACE" down
sleep 5

# Renew IP address
log_printf "$MSG_RENEW_IP" "$INTERFACE"
ip link set dev "$INTERFACE" up

# Wait for interface to obtain IP address
MAX_WAIT=30
COUNT=0
while [ $COUNT -lt $MAX_WAIT ]; do
    INTERFACE_IP=$(ip addr show dev "$INTERFACE" | awk '/inet / {print $2}' | cut -d/ -f1)
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

# Execute login based on client type
if [ "$CLIENT_TYPE" = "ct" ]; then
    log_message "$MSG_CT_EXECUTE_LOGIN"
    LOGIN_OUTPUT=$($AUTH_BIN \
        -name "$USERNAME" -passwd "$PASSWORD" -host "$HOST" -localip "$INTERFACE_IP" 2>&1)
    
    # Check CT login success
    if echo "$LOGIN_OUTPUT" | grep -q "Successfully"; then
        LOGIN_SUCCESS=1
        SUCCESS_MSG="$MSG_CT_LOGIN_SUCCESS"
        FAILURE_MSG="$MSG_CT_LOGIN_FAILURE"
    else
        LOGIN_SUCCESS=0
        SUCCESS_MSG="$MSG_CT_LOGIN_SUCCESS"
        FAILURE_MSG="$MSG_CT_LOGIN_FAILURE"
    fi
elif [ "$CLIENT_TYPE" = "srun" ]; then
    # Set parameters based on AUTH_MODE
    if [ "$AUTH_MODE" = "dx" ]; then
        MODE_FLAG="-x"
    else
        MODE_FLAG=""
    fi
    
    log_message "$MSG_SRUN_EXECUTE_LOGIN"
    LOGIN_OUTPUT=$($AUTH_BIN \
        -ip "$INTERFACE_IP" -n "$USERNAME" -p "$PASSWORD" $MODE_FLAG -d 2>&1)
    
    # Check Srun login success
    if echo "$LOGIN_OUTPUT" | grep -q "success"; then
        LOGIN_SUCCESS=1
        SUCCESS_MSG="$MSG_SRUN_LOGIN_SUCCESS"
        FAILURE_MSG="$MSG_SRUN_LOGIN_FAILURE"
    else
        LOGIN_SUCCESS=0
        SUCCESS_MSG="$MSG_SRUN_LOGIN_SUCCESS"
        FAILURE_MSG="$MSG_SRUN_LOGIN_FAILURE"
    fi
fi

# Write login output to log - one line at a time to avoid very long messages
echo "$LOGIN_OUTPUT" | while read -r line; do
    if [ -n "$line" ]; then
        log_printf "$MSG_LOGIN_OUTPUT" "$line"
    fi
done

# Check if login was successful
if [ "$LOGIN_SUCCESS" = "1" ]; then
    # Login successful, record login time
    date "+%Y-%m-%d %H:%M:%S" > $LAST_LOGIN_FILE
    log_message "$SUCCESS_MSG"
else
    log_message "$FAILURE_MSG"
fi
