#!/bin/sh

# Shared logging utility functions for UESTC Authentication Client

# Source the internationalization support if not already sourced
if [ -z "$MSG_SERVICE_STARTED" ]; then
    . /usr/lib/uestc_authclient/i18n.sh
fi

# Log domain - defaults to "global"
LOG_DOMAIN="global"
# Base directory for all logs
LOG_BASE_DIR="/tmp/uestc_authclient"
# Log directory path (domain-specific)
LOG_DIR="$LOG_BASE_DIR/$LOG_DOMAIN/logs"
# Current log file path (generated daily)
LOG_FILE=""
# Last log cleanup timestamp file (domain-specific)
LOG_CLEANUP_TIMESTAMP_FILE="$LOG_DIR/last_cleanup"

#######################################
# Set the log domain and update paths
# Arguments:
#   $1 - Log domain name
#######################################
set_log_domain() {
    local new_domain="$1"
    if [ -z "$new_domain" ]; then
        return 1
    fi
    
    LOG_DOMAIN="$new_domain"
    LOG_DIR="$LOG_BASE_DIR/$LOG_DOMAIN/logs"
    LOG_CLEANUP_TIMESTAMP_FILE="$LOG_DIR/last_cleanup"
    
    # Re-initialize logging with the new domain
    log_init
    return 0
}

#######################################
# Get the current log domain
# Returns:
#   Current log domain name
#######################################
get_log_domain() {
    echo "$LOG_DOMAIN"
}

#######################################
# Initialize logging
# Arguments:
#   $1 - (Optional) Custom log directory path
#######################################
log_init() {
    if [ -n "$1" ]; then
        LOG_DIR="$1"
        # Update cleanup timestamp file path if using custom directory
        LOG_CLEANUP_TIMESTAMP_FILE="$LOG_DIR/last_cleanup"
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
    fi
    
    # Check if the log file exists, create it if it doesn't
    # This handles both new date and external deletion cases
    if [ ! -f "$LOG_FILE" ]; then
        touch "$LOG_FILE"
        echo "$(date): $MSG_LOG_INITIALIZED $LOG_FILE" >> "$LOG_FILE"
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
get_logs_all() {
    # Get logs from all domains
    for domain in $(list_log_domains); do
        get_logs_by_domain "$domain"
    done
}

#######################################
# Get all log content from a specific domain without changing the current domain
# Arguments:
#   $1 - Domain name (optional, defaults to current domain)
# Returns:
#   All log content from all available log files in the specified domain
#######################################
get_logs_by_domain() {
    local domain="${1:-$LOG_DOMAIN}"
    local domain_log_dir="$LOG_BASE_DIR/$domain/logs"
    
    # Check if log directory exists
    if [ ! -d "$domain_log_dir" ]; then
        echo "$MSG_NO_LOGS_AVAILABLE"
        return
    fi
    
    # Find all log files and sort them by name (which is by date)
    local log_files=$(find "$domain_log_dir" -name "*.log" | sort)
    
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
        echo "=== $domain - $file_date ==="
        cat "$log_file"
        echo "" # Add empty line between log files
    done
}

#######################################
# List all available log domains
# Returns:
#   List of all log domains that have logs
#######################################
list_log_domains() {
    # Check if base directory exists
    if [ ! -d "$LOG_BASE_DIR" ]; then
        echo "$MSG_NO_LOGS_AVAILABLE"
        return
    fi
    
    # Find all directories in the base directory that have logs
    for domain_dir in "$LOG_BASE_DIR"/*; do
        [ -d "$domain_dir" ] || continue
        local domain=$(basename "$domain_dir")
        
        # Check if logs directory exists
        if [ -d "$domain_dir/logs" ] && [ -n "$(find "$domain_dir/logs" -name "*.log" 2>/dev/null)" ]; then
            echo "$domain"
        fi
    done
}

#######################################
# Delete all logs for a specific domain
# Arguments:
#   $1 - Domain name (optional, defaults to current domain)
# Returns:
#   0 if successful, 1 if domain logs directory doesn't exist
#######################################
delete_logs_by_domain() {
    local domain="${1:-$LOG_DOMAIN}"
    local domain_log_dir="$LOG_BASE_DIR/$domain/logs"
    
    # Check if log directory exists
    if [ ! -d "$domain_log_dir" ]; then
        echo "$MSG_NO_LOGS_AVAILABLE"
        return 1
    fi
    
    # Remove all log files but keep the directory structure
    rm -f "$domain_log_dir"/*.log
    
    # Reset the cleanup timestamp file
    local current_time=$(date +%s)
    echo "$current_time" > "$domain_log_dir/last_cleanup"
    
    return 0
}

#######################################
# Delete all logs for all domains
# Returns:
#   0 if successful
#######################################
delete_logs_all() {
    local success=0
    
    # Get all domains
    for domain in $(list_log_domains); do
        delete_logs_by_domain "$domain" >/dev/null
        success=0
    done
    
    return $success
}

# Auto-initialize logging when this script is sourced
log_init
