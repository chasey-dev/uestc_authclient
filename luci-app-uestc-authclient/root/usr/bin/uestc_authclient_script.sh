#!/bin/sh
#
# Auto‑login helper script
# ------------------------------------------------------------
# Handles CT (`qsh-telecom-autologin`) and SRUN (`go-nd-portal`)
# clients on a given network interface.
#
# Exit status:
#   0  – login success
#   3  – authentication failure
#   1  – bad parameters / usage error
#   2  – network error (no IP)
# ------------------------------------------------------------

###############################################################################
# Usage helper
###############################################################################
usage() {
    printf "Usage: %s -t <client_type> -i <interface> -s <server> " "$0"
    printf "-u <username> -p <password> [-m <auth_mode>] [-w <wait_sec>]\n"
    printf "  -t: Client type (ct or srun)\n"
    printf "  -i: Network interface (default: wan)\n"
    printf "  -s: Authentication server / host\n"
    printf "  -u: Username\n"
    printf "  -p: Password\n"
    printf "  -m: Authentication mode {qsh-edu | qsh-dx | qshd-dx | qshd-cmcc | sh-edu | sh-dx | sh-cmcc} (srun only, default: qsh-edu)\n"
    printf "  -w: Timeout (seconds) waiting for IP on interface (default: 30)\n"
    exit 1
}

###############################################################################
# Default values
###############################################################################
INTERFACE="wan"
CLIENT_TYPE=""
USERNAME=""
PASSWORD=""
HOST=""
AUTH_MODE="qsh-edu"
WAIT_IP_TIMEOUT=30

###############################################################################
# Parse command‑line arguments
###############################################################################
while getopts ":t:i:s:u:p:m:w:" opt; do
    case "$opt" in
        t) CLIENT_TYPE="$OPTARG" ;;
        i) INTERFACE="$OPTARG" ;;
        s) HOST="$OPTARG" ;;
        u) USERNAME="$OPTARG" ;;
        p) PASSWORD="$OPTARG" ;;
        m) AUTH_MODE="$OPTARG" ;;
        w) WAIT_IP_TIMEOUT="$OPTARG" ;;
        *) usage ;;
    esac
done

###############################################################################
# Validate required parameters
###############################################################################
[ -z "$CLIENT_TYPE" ] || [ -z "$USERNAME" ] || \
[ -z "$PASSWORD" ]    || [ -z "$HOST" ] && {
    printf "ERROR: Required parameters not set\n"
    usage
}

###############################################################################
# Determine client binary
###############################################################################
case "$CLIENT_TYPE" in
    ct)   AUTH_BIN="/usr/bin/qsh-telecom-autologin" ;;
    srun) AUTH_BIN="/usr/bin/go-nd-portal"          ;;
    *)    printf "ERROR: Unknown client type: %s\n" "$CLIENT_TYPE"; exit 1 ;;
esac

command -v ip >/dev/null 2>&1 || {
    printf "ERROR: 'ip' command not found in PATH\n"
    exit 1
}

[ -x "$AUTH_BIN" ] || {
    printf "ERROR: Auth binary not found or not executable: %s\n" "$AUTH_BIN"
    exit 1
}

###############################################################################
# Helper: wait until interface gets an IPv4 address
# Args: $1 = interface, $2 = timeout seconds
# Returns: IPv4 address via stdout or empty
###############################################################################
wait_for_ip() {
    iface="$1"
    timeout="$2"
    elapsed=0
    while [ "$elapsed" -lt "$timeout" ]; do
        ip_addr=$(ip -o -4 addr show dev "$iface" | awk '{print $4}' | cut -d/ -f1)
        [ -n "$ip_addr" ] && { printf "%s\n" "$ip_addr"; return; }
        sleep 1
        elapsed=$((elapsed + 1))
    done
}

###############################################################################
# Bring interface down/up to trigger DHCP renewal
###############################################################################
ip link set dev "$INTERFACE" down 2>/dev/null
sleep 2
ip link set dev "$INTERFACE" up   2>/dev/null

###############################################################################
# Obtain IP address (with timeout)
###############################################################################
INTERFACE_IP=$(wait_for_ip "$INTERFACE" "$WAIT_IP_TIMEOUT")

if [ -z "$INTERFACE_IP" ]; then
    printf "ERROR: Failed to acquire IP for %s within %s seconds\n" \
           "$INTERFACE" "$WAIT_IP_TIMEOUT"
    exit 2
fi

###############################################################################
# Execute login according to client type
###############################################################################
if [ "$CLIENT_TYPE" = "ct" ]; then
    LOGIN_OUTPUT=$("$AUTH_BIN" \
        -name "$USERNAME" -passwd "$PASSWORD" \
        -host "$HOST" -localip "$INTERFACE_IP" 2>&1)

    echo "$LOGIN_OUTPUT" | grep -qi "Successfully"
    [ $? -eq 0 ] && RETURN_CODE=0 || RETURN_CODE=3

else  # srun
    # let AUTH_BIN handle the host & auth_mode validation
    LOGIN_OUTPUT=$("$AUTH_BIN" \
        -ip "$INTERFACE_IP" -n "$USERNAME" -p "$PASSWORD" \
        -s "$HOST" -t "$AUTH_MODE" -d 2>&1)

    echo "$LOGIN_OUTPUT" | grep -qi "success"
    [ $? -eq 0 ] && RETURN_CODE=0 || RETURN_CODE=3
fi

###############################################################################
# Output result for caller and exit
###############################################################################
printf "%s\n" "$LOGIN_OUTPUT"
exit "$RETURN_CODE"
