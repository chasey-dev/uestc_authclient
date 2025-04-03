#!/bin/sh

# Shared logging utility functions for UESTC Authentication Client

# Source the internationalization support if not already sourced
if [ -z "$MSG_SERVICE_STARTED" ]; then
    . /usr/lib/uestc_authclient/i18n.sh
fi

# Log directory path
LOG_DIR="/tmp/uestc_authclient_logs"
# Current log file path (generated daily)
LOG_FILE=""
# Last log cleanup timestamp file
LOG_CLEANUP_TIMESTAMP_FILE="/tmp/uestc_authclient_last_cleanup"

#######################################
# Initialize logging
# Arguments:
#   $1 - (Optional) Custom log directory path
#######################################
log_init() {
    if [ -n "$1" ]; then
        LOG_DIR="$1"
    fi
    
    # Ensure log directory exists
    if [ ! -d "$LOG_DIR" ]; then
        mkdir -p "$LOG_DIR"
    fi
    
    # Get current date for the log file name
    local current_date=$(date +"%Y-%m-%d")
    LOG_FILE="${LOG_DIR}/${current_date}.log"
    
    # Create log file if it doesn't exist
    if [ ! -f "$LOG_FILE" ]; then
        touch "$LOG_FILE"
        echo "$(date): $MSG_LOG_INITIALIZED $LOG_FILE" >> "$LOG_FILE"
    fi
}

#######################################
# Get the current log file path, creating a new one if date changed
#######################################
get_current_log_file() {
    # Get current date
    local current_date=$(date +"%Y-%m-%d")
    local current_log_file="${LOG_DIR}/${current_date}.log"
    
    # Check if we need to use a new log file (date changed)
    if [ "$LOG_FILE" != "$current_log_file" ]; then
        LOG_FILE="$current_log_file"
        
        # Create new log file if it doesn't exist
        if [ ! -f "$LOG_FILE" ]; then
            touch "$LOG_FILE"
            echo "$(date): $MSG_LOG_INITIALIZED $LOG_FILE" >> "$LOG_FILE"
        fi
    fi
    
    echo "$LOG_FILE"
}

#######################################
# Log a message to the log file with timestamp
# Arguments:
#   $1 - Message to log
#######################################
log_message() {
    # Get current log file
    local current_log_file=$(get_current_log_file)
    
    # Log the message
    echo "$(date): $1" >> "$current_log_file"
}

#######################################
# Log a formatted message to the log file with timestamp
# Arguments:
#   $1 - Format string
#   $2... - Format arguments
#######################################
log_printf() {
    # Get the format string
    local format="$1"
    shift
    # Format the message
    local message=$(printf "$format" "$@")
    # Log the formatted message
    log_message "$message"
}

#######################################
# Check if log cleanup should be performed based on time interval
# Arguments:
#   $1 - Interval in hours (default: 24)
# Returns:
#   0 if cleanup should be performed, 1 otherwise
#######################################
should_cleanup_log() {
    local interval_hours=${1:-24}
    local interval_seconds=$((interval_hours * 3600))
    local current_time=$(date +%s)
    
    # Check if timestamp file exists
    if [ ! -f "$LOG_CLEANUP_TIMESTAMP_FILE" ]; then
        # No timestamp file, create it and return true (should cleanup)
        echo "$current_time" > "$LOG_CLEANUP_TIMESTAMP_FILE"
        return 0
    fi
    
    # Read last cleanup timestamp
    local last_cleanup=$(cat "$LOG_CLEANUP_TIMESTAMP_FILE" 2>/dev/null)
    if [ -z "$last_cleanup" ] || ! expr "$last_cleanup" : '[0-9]\+$' >/dev/null 2>&1; then
        # Invalid timestamp, update and return true
        echo "$current_time" > "$LOG_CLEANUP_TIMESTAMP_FILE"
        return 0
    fi
    
    # Check if enough time has elapsed
    local elapsed_time=$((current_time - last_cleanup))
    if [ $elapsed_time -ge $interval_seconds ]; then
        # Enough time elapsed, update timestamp and return true
        echo "$current_time" > "$LOG_CLEANUP_TIMESTAMP_FILE"
        return 0
    fi
    
    # Not enough time elapsed
    return 1
}

#######################################
# Clean logs older than retention period
# Arguments:
#   $1 - Log retention days (default: 7)
#   $2 - Cleanup interval in hours (default: 24)
# Returns:
#   0 if cleanup was performed, 1 if skipped due to time interval
#######################################
log_clean() {
    local log_retention_days=${1:-7}
    local cleanup_interval_hours=${2:-24}
    
    # Check if cleanup should be performed based on interval
    should_cleanup_log "$cleanup_interval_hours"
    if [ $? -ne 0 ]; then
        # Not time to cleanup yet
        return 1
    fi
    
    # Check if log directory exists
    if [ ! -d "$LOG_DIR" ]; then
        return 0
    fi

    # Get current timestamp
    local current_timestamp=$(date +%s)
    local retention_seconds=$((log_retention_days * 86400))
    local cutoff_timestamp=$((current_timestamp - retention_seconds))
    local deleted_count=0
    local total_count=0
    
    # Process each log file in the directory
    for log_file in "$LOG_DIR"/*.log; do
        [ -f "$log_file" ] || continue
        total_count=$((total_count + 1))
        
        # Extract date from filename (format: YYYY-MM-DD.log)
        local file_date=$(basename "$log_file" .log)
        local file_timestamp=$(date -d "$file_date" +%s 2>/dev/null)
        
        # If date parsing failed or file is older than retention period, delete it
        if [ -n "$file_timestamp" ] && [ $file_timestamp -lt $cutoff_timestamp ]; then
            rm -f "$log_file"
            deleted_count=$((deleted_count + 1))
        fi
    done
    
    # Log the cleanup results to the current log file
    if [ $deleted_count -gt 0 ]; then
        log_printf "$MSG_LOG_CLEANUP_COMPLETED" "$deleted_count" "$total_count" "$log_retention_days"
    fi
    
    return 0
}

#######################################
# Get all log content in chronological order
# Returns:
#   All log content from all available log files
#######################################
get_all_logs() {
    # Check if log directory exists
    if [ ! -d "$LOG_DIR" ]; then
        echo "$MSG_NO_LOGS_AVAILABLE"
        return
    fi
    
    # Find all log files and sort them by name (which is by date)
    local log_files=$(find "$LOG_DIR" -name "*.log" | sort)
    
    # If no log files, return message
    if [ -z "$log_files" ]; then
        echo "$MSG_NO_LOGS_AVAILABLE"
        return
    fi
    
    # Output the content of all log files
    for log_file in $log_files; do
        # Get the date from the filename
        local file_date=$(basename "$log_file" .log)
        
        # Add a header for each log file
        echo "=== $file_date ==="
        cat "$log_file"
        echo "" # Add empty line between log files
    done
}

# Auto-initialize logging when this script is sourced
log_init

# Add any additional functions or commands here 