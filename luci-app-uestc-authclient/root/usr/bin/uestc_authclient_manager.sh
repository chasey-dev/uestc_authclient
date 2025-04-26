#!/bin/sh

# uestc_authclient_manager.sh
# Session manager daemon that manages multiple authentication client monitoring instances
# Each session runs in its own process, controlled by this manager

# Source shared utilities
. /usr/lib/uestc_authclient/log_utils.sh
. /usr/lib/uestc_authclient/i18n.sh
. /usr/share/libubox/jshn.sh
. /lib/functions.sh

# load configuration in one call
config_load uestc_authclient
ALL_SESSIONS=$(config_foreach 'echo "$1"' session)

# Monitor script path
MONITOR_SCRIPT="/usr/bin/uestc_authclient_monitor.sh"
PIDFILE_DIR="/var/run/uestc_authclient"
STATE_DIR="/tmp/uestc_authclient"

# Lock path for interfaces
LOCK_DIR="$STATE_DIR/lock"
IFACE_LOCK_DIR="$LOCK_DIR/interface"

# Get global logging settings
LOG_RETENTION_DAYS=7
config_get LOG_RETENTION_DAYS "global" log_rdays 7

# Ensure directories exist
mkdir -p "$PIDFILE_DIR" "$STATE_DIR" "$IFACE_LOCK_DIR" 2>/dev/null

# Set log domain to globalex
set_log_domain "global"

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
            # Release the lock if exists
            unlock_iface "$sid"
        fi
    fi
    return 1
}


#######################################
# Helper: Lock interface by sid
# Arguments:
#   $1 - Session ID
# Output: 0 - success
#         1 - fail  
#######################################
tryLock_iface() {
    local sid="$1"
    local interface
    config_get interface "$sid" listen_interface ""
    local iface_lock="$IFACE_LOCK_DIR/$interface.lock"
    # Check if the lock file exists
    if [ -e "$iface_lock" ]; then
        # If the lock file exists, check if it's locked by another session
        local locked_by
        locked_by=$(cat "$iface_lock")  # Read the session ID currently holding the lock
        
        if [ "$locked_by" != "$sid" ]; then
            return 1  # Exit if the lock is held by another session
        fi
    fi
    
    # Lock the interface by writing the current session ID into the lock file
    echo "$sid" > "$iface_lock"
    return 0
}

#######################################
# Helper: Unlock interface by sid
# Arguments:
#   $1 - Session ID
#######################################
unlock_iface() {
    local sid="$1"
    local interface
    local iface_lock

    # get iface by session id
    config_get interface "$sid" listen_interface ""
    iface_lock="$IFACE_LOCK_DIR/$interface.lock"

    # Remove iface locked by current session
    if [ -e "$iface_lock" ]; then
        local locked_by
        locked_by=$(cat "$iface_lock")
        if [ "$locked_by" == "$sid" ]; then
            rm -f "$iface_lock"
        fi
    fi
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
    local enabled
    config_get enabled "$sid" enabled 0
    if [ "$enabled" != "1" ]; then
        log_printf "$MSG_SESSION_DISABLED" "$sid"
        return 1
    fi
    
    tryLock_iface "$sid"
    if [ "$?" -eq 1 ]; then
        local interface
        config_get interface "$sid" listen_interface ""

        log_printf "$MSG_INTERFACE_LOCKED" "$interface" "$sid"
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
    local exit_code=0

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

        log_printf "$MSG_SESSION_STOPPED" "$sid" "$pid"
        exit_code=0
    else
        log_printf "$MSG_SESSION_NOT_RUNNING" "$sid"
        exit_code=1
    fi
        
    # Remove PID file
    rm -f "$PIDFILE_DIR/$sid.pid"

    # Remove network status file
    rm -f "$STATE_DIR/$sid/network_status"

    # Release the iface locked by current session
    unlock_iface "$sid"

    return $exit_code
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
    local network_status_file="$STATE_DIR/$sid/network_status"
    local last_login=0
    local last_login_file="$STATE_DIR/$sid/last_login"
    
    # load last_login if present
    [ -f "$last_login_file" ] && last_login=$(cat "$last_login_file")

    # check running state
    if pid=$(get_session_pid "$sid"); then
        running=1
        # check if network is up by file
        [ -f "$network_status_file" ] && read -r network_up <"$network_status_file"
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
    
    for sid in $ALL_SESSIONS; do
        start_session "$sid"
    done
}

#######################################
# Stop all running sessions
#######################################
stop_all_sessions() {
    log_message "$MSG_STOPPING_ALL_SESSIONS"
    
    for sid in $ALL_SESSIONS; do
        if get_session_pid "$sid" >/dev/null; then
            stop_session "$sid"
        fi
    done
}

#######################################
# Main command handler
#######################################
usage() {
    echo "Usage: $0 {start|stop|restart|status|log} [session_id]"
    echo "$0 {clean} [log|all] [session_id]"
    exit 1
}

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
        for sid in $ALL_SESSIONS; do
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
        get_logs_by_domain "$2"
        ;;

    clean)
        case "$2" in
            log)
                delete_logs_by_domain "$3"
                ;;
            all)
                if [ -n "$3" ]; then
                    # calling clean all may affect network connection display in UI
                    rm -rf "$STATE_DIR/$3"
                else
                    rm -rf "$STATE_DIR/global"
                fi
                ;;
            *)
                usage
                ;;
        esac
        ;;
    *)
        usage
        ;;
        
esac

exit 0 