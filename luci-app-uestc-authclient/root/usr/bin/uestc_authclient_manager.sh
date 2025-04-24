#!/bin/sh

# uestc_authclient_manager.sh
# Session manager daemon that manages multiple authentication client monitoring instances
# Each session runs in its own process, controlled by this manager

# Source shared utilities
. /usr/lib/uestc_authclient/log_utils.sh
. /usr/lib/uestc_authclient/i18n.sh
. /usr/share/libubox/jshn.sh

# Monitor script path
MONITOR_SCRIPT="/usr/bin/uestc_authclient_monitor.sh"
PIDFILE_DIR="/var/run/uestc_authclient"
STATE_DIR="/tmp/uestc_authclient"

# Get global logging settings
LOG_RETENTION_DAYS=$(uci -q get "uestc_authclient.global.log_rdays")
[ -z "$LOG_RETENTION_DAYS" ] && LOG_RETENTION_DAYS=7

# Ensure directories exist
mkdir -p "$PIDFILE_DIR" "$STATE_DIR" 2>/dev/null

# Set log domain to global
set_log_domain "global"

#######################################
# Helper: Get all session IDs from config
# Output: List of session IDs
#######################################
get_all_sessions() {
    local idx=0
    local sid
    
    while true; do
        sid=$(uci -q get "uestc_authclient.@session[$idx].sid")
        if [ -z "$sid" ]; then
            break
        fi
        echo "$sid"
        idx=$((idx + 1))
    done
}

#######################################
# Helper: Get active process ID for session
# Arguments:
#   $1 - Session ID
# Output: PID or empty if not running
#######################################
get_session_pid() {
    local sid="$1"
    local pidfile="$PIDFILE_DIR/$sid.pid"
    
    if [ -f "$pidfile" ]; then
        local pid=$(cat "$pidfile" 2>/dev/null)
        # Check if process is still running
        if kill -0 "$pid" 2>/dev/null; then
            echo "$pid"
            return 0
        else
            # Clean up stale PID file
            rm -f "$pidfile"
        fi
    fi
    return 1
}

#######################################
# Start a specific session monitor
# Arguments:
#   $1 - Session ID
# Returns:
#   0 if started successfully, 1 otherwise
#######################################
start_session() {
    local sid="$1"
    
    # Check if session is already running
    if pid=$(get_session_pid "$sid"); then
        log_printf "$MSG_SESSION_ALREADY_RUNNING" "$sid" "$pid"
        return 1
    fi
    
    # Check if session is enabled
    local enabled=$(uci -q get "uestc_authclient.$sid.enabled")
    if [ "$enabled" != "1" ]; then
        log_printf "$MSG_SESSION_DISABLED" "$sid"
        return 1
    fi
    
    # Start the monitor process in background
    "$MONITOR_SCRIPT" "$sid" >/dev/null 2>&1 &
    local pid=$!

    # Save PID to file
    echo "$pid" > "$PIDFILE_DIR/$sid.pid"
    log_printf "$MSG_SESSION_STARTED" "$sid" "$pid"
    
    return 0
}

#######################################
# Stop a specific session monitor
# Arguments:
#   $1 - Session ID
# Returns:
#   0 if stopped successfully, 1 otherwise
#######################################
stop_session() {
    local sid="$1"
    local pid
    
    if pid=$(get_session_pid "$sid"); then
        # Kill the process
        kill "$pid" 2>/dev/null
        # Give it a moment to terminate gracefully
        sleep 1
        
        # Force kill if still running
        if kill -0 "$pid" 2>/dev/null; then
            kill -9 "$pid" 2>/dev/null
            sleep 1
        fi
        
        # Remove PID file
        rm -f "$PIDFILE_DIR/$sid.pid"
        log_printf "$MSG_SESSION_STOPPED" "$sid" "$pid"
        return 0
    else
        log_printf "$MSG_SESSION_NOT_RUNNING" "$sid"
        return 1
    fi
}

#######################################
# Validate if session exists
# Arguments:
#   $1 - Session ID
# Output: 1 - exist
#         0 - not exist
#######################################
validate_session() {
    local sid="$1"
    local enabled=$(uci -q get "uestc_authclient.$sid.enabled")

    if [ -z "$enabled" ]; then
        return 0
    else
        return 1
    fi
}

#######################################
# add_status_json_fields: add all the JSON fields for one session into the current context
# Arguments:
#   $1 - session ID
#######################################
add_status_json_fields() {
    local sid="$1"
    local running=0
    local pid=""
    local network_up=0
    local last_login=0
    local last_login_file="$STATE_DIR/$sid/last_login"

    # load last_login if present
    [ -f "$last_login_file" ] && last_login=$(cat "$last_login_file")

    # check running state
    if pid=$(get_session_pid "$sid"); then
        running=1

        # test network via heartbeat hosts
        local interface
        local hosts
        interface=$(uci -q get "uestc_authclient.$sid.listen_interface" || echo "wan")
        hosts=$(uci -q get "uestc_authclient.$sid.listen_hosts" \
                 | tr ' ' '\n' | xargs)  # split into lines

        for h in $hosts; do
          if ping -I "$interface" -c1 -W1 "$h" >/dev/null 2>&1; then
            network_up=1
            break
          fi
        done
    fi

    # Now add fields into JSON
    json_add_string  "sid"         "$sid"
    json_add_boolean "running"     "$running"
    json_add_int     "pid"         "$pid"
    json_add_boolean "network_up"  "$network_up"
    json_add_int     "last_login"  "$last_login"
}


#######################################
# Compose session status result as JSON
# Arguments:
#   $1 - Success
#   $2 - Session ID
#   $3 - Running status
#   $4 - PID
#   $5 - Network status
#   $6 - Last login timestamp
#######################################
compose_status_json() {
    json_init
    json_add_boolean "success" "$1"
    json_add_string "sid" "$2"
    json_add_boolean "running" "$3"
    json_add_int "pid" "$4"
    json_add_boolean "network_up" "$5"
    json_add_int "last_login" "$6"
    json_dump
}

#######################################
# Start all enabled sessions
#######################################
start_all_sessions() {
    log_message "$MSG_STARTING_ALL_SESSIONS"
    
    for sid in $(get_all_sessions); do
        local enabled=$(uci -q get "uestc_authclient.$sid.enabled")
        if [ "$enabled" = "1" ]; then
            start_session "$sid"
        fi
    done
}

#######################################
# Stop all running sessions
#######################################
stop_all_sessions() {
    log_message "$MSG_STOPPING_ALL_SESSIONS"
    
    for sid in $(get_all_sessions); do
        if get_session_pid "$sid" >/dev/null; then
            stop_session "$sid"
        fi
    done
}

#######################################
# Main command handler
#######################################
case "$1" in
    start)
        if [ -n "$2" ]; then
            start_session "$2"
        else
            start_all_sessions
        fi
        ;;
        
    stop)
        if [ -n "$2" ]; then
            stop_session "$2"
        else
            stop_all_sessions
        fi
        ;;
        
    restart)
        if [ -n "$2" ]; then
            stop_session "$2"
            sleep 1
            start_session "$2"
        else
            stop_all_sessions
            sleep 1
            start_all_sessions
        fi
        ;;

    status)
        # 1) start a fresh JSON context
        json_init

        if [ -n "$2" ]; then
        # 2a) single‐session mode: output one object
        add_status_json_fields "$2"

        else
        # 2b) all‐session mode: build an array of objects
        json_add_array "sessions"
        for sid in $(get_all_sessions); do
            # skip if the session name is invalid
            validate_session "$sid" && continue

            json_add_object      # open { … }
            add_status_json_fields "$sid"
            json_close_object   # close }
        done
        json_close_array     # close ]
        fi

        # 3) emit the complete JSON in one go
        json_dump
        ;;

    log)
        validate_session "$2"
        # get logs by domain or get global logs if no session id or "global"
        if [ $? -eq 1 ]; then
            get_logs_by_domain "$2"
        elif [ -z "$2" ] || [ "$2" = "global" ]; then
            # check if global log file needs to be cleaned
            log_clean "$LOG_RETENTION_DAYS" 24
            get_logs_by_domain "$2"
        fi
        ;;

    *)
        echo "Usage: $0 {start|stop|restart|status|log} [session_id]"
        exit 1
        ;;
esac

exit 0 