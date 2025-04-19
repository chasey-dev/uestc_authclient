#!/bin/sh

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
    echo "ERROR: Required parameters not set"
    usage
fi

# Set binary based on client type
if [ "$CLIENT_TYPE" = "ct" ]; then
    AUTH_BIN="/usr/bin/qsh-telecom-autologin"
elif [ "$CLIENT_TYPE" = "srun" ]; then
    AUTH_BIN="/usr/bin/go-nd-portal"
else
    echo "ERROR: Unknown client type: $CLIENT_TYPE"
    exit 1
fi

# Release DHCP
ip link set dev "$INTERFACE" down
sleep 5

# Renew IP address
ip link set dev "$INTERFACE" up

# Wait for interface to obtain IP address
MAX_WAIT=30
COUNT=0
while [ $COUNT -lt $MAX_WAIT ]; do
    INTERFACE_IP=$(ip addr show dev "$INTERFACE" | awk '/inet / {print $2}' | cut -d/ -f1)
    if [ -n "$INTERFACE_IP" ]; then
        break
    fi
    sleep 1
    COUNT=$((COUNT + 1))
done

if [ -z "$INTERFACE_IP" ]; then
    echo "ERROR: Failed to get IP address for interface $INTERFACE after $MAX_WAIT seconds"
    exit 2
fi

# Execute login based on client type
if [ "$CLIENT_TYPE" = "ct" ]; then
    LOGIN_OUTPUT=$($AUTH_BIN \
        -name "$USERNAME" -passwd "$PASSWORD" -host "$HOST" -localip "$INTERFACE_IP" 2>&1)
    
    # Check CT login success
    if echo "$LOGIN_OUTPUT" | grep -q "Successfully"; then
        RETURN_CODE=0  # Exit code 0 means success
    else
        RETURN_CODE=3  # Exit code 3 means authentication failure
    fi
elif [ "$CLIENT_TYPE" = "srun" ]; then
    # Set parameters based on AUTH_MODE
    if [ "$AUTH_MODE" = "dx" ]; then
        MODE_FLAG="-x"
    else
        MODE_FLAG=""
    fi
    
    LOGIN_OUTPUT=$($AUTH_BIN \
        -ip "$INTERFACE_IP" -n "$USERNAME" -p "$PASSWORD" $MODE_FLAG -d 2>&1)
    
    # Check Srun login success
    if echo "$LOGIN_OUTPUT" | grep -q "success"; then
        RETURN_CODE=0  # Exit code 0 means success
    else
        RETURN_CODE=3  # Exit code 3 means authentication failure
    fi
fi

# Output the login result for the caller to process
echo "$LOGIN_OUTPUT"

# Return the login status
exit $RETURN_CODE
