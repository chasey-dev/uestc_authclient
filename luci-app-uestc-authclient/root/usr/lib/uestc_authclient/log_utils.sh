#!/bin/sh

# Shared logging utility functions for UESTC Authentication Client

# Default log file path
LOG_FILE="/tmp/uestc_authclient.log"
# Last log cleanup timestamp file
LOG_CLEANUP_TIMESTAMP_FILE="/tmp/uestc_authclient_last_cleanup"

#######################################
# Initialize logging
# Arguments:
#   $1 - (Optional) Custom log file path
#######################################
log_init() {
    if [ -n "$1" ]; then
        LOG_FILE="$1"
    fi
    
    # Ensure log directory exists
    local log_dir=$(dirname "$LOG_FILE")
    if [ ! -d "$log_dir" ]; then
        mkdir -p "$log_dir"
    fi
    
    # Create log file if it doesn't exist
    if [ ! -f "$LOG_FILE" ]; then
        touch "$LOG_FILE"
        echo "$(date): Logging initialized. Log file created at $LOG_FILE" >> "$LOG_FILE"
    fi
}

#######################################
# Log a message to the log file with timestamp
# Arguments:
#   $1 - Message to log
#######################################
log_message() {
    echo "$(date): $1" >> "$LOG_FILE"
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
    
    # Check if log file exists
    if [ ! -f "$LOG_FILE" ]; then
        return 0
    fi

    # Get current timestamp
    local current_timestamp=$(date +%s)
    local retention_seconds=$((log_retention_days * 86400))
    local cutoff_timestamp=$((current_timestamp - retention_seconds))
    
    # Create a temporary file for the filtered logs
    local temp_log_file="${LOG_FILE}.tmp"
    > "$temp_log_file"  # Ensure temporary file exists and is empty
    
    # Count of processed and retained lines for logging
    local total_lines=0
    local retained_lines=0
    
    while read -r line; do
        total_lines=$((total_lines + 1))
        
        # Extract the date and time from the log line
        local log_date=$(echo "$line" | awk '{print $1" "$2" "$3}')
        local log_timestamp=$(date -d "$log_date" +%s 2>/dev/null)
        
        if [ -z "$log_timestamp" ] || [ $log_timestamp -ge $cutoff_timestamp ]; then
            # Keep line if timestamp can't be parsed or if it's within retention period
            echo "$line" >> "$temp_log_file"
            retained_lines=$((retained_lines + 1))
        fi
    done < "$LOG_FILE"
    
    # Check if temporary file exists and has content
    if [ -s "$temp_log_file" ]; then
        # Add a log rotation message
        echo "$(date): Log rotation completed. Retained $retained_lines/$total_lines lines (retention: $log_retention_days days)" >> "$temp_log_file"
        # Replace the old log with the new one
        mv "$temp_log_file" "$LOG_FILE"
    else
        # Create empty log with header if no lines were retained
        echo "$(date): Log file cleared (retention: $log_retention_days days)" > "$LOG_FILE"
        rm -f "$temp_log_file"
    fi
    
    return 0
}

# Auto-initialize logging when this script is sourced
log_init

# Add any additional functions or commands here 