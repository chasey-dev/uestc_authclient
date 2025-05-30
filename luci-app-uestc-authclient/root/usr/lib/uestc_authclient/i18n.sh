#!/bin/sh

# Centralized internationalization support for UESTC Authentication Client
# This file contains all messages used across different scripts in both Chinese and English

# Get the system language (default to English if not specified)
CURRENT_LANG=$(uci get luci.main.lang 2>/dev/null)
[ -z "$CURRENT_LANG" ] && CURRENT_LANG="en"

#######################################
# Initialize message dictionary
#######################################
init_i18n() {
    # Common messages used across multiple scripts
    if [ "$CURRENT_LANG" = "zh_cn" ]; then
        # Chinese message dictionary
        MSG_UNKNOWN_CLIENT_TYPE="未知的客户端类型 (%s)。"
        MSG_USERNAME_PASSWORD_NOT_SET="认证所需的必要参数未设置，无法启动。"
        
        # Monitor script messages
        MSG_MONITOR_SCRIPT_STARTED="监控脚本已启动。"
        MSG_MONITOR_SCRIPT_EXIT="监控脚本已终止。"
        MSG_NETWORK_REACHABLE="网络已恢复正常。"
        MSG_NETWORK_UNREACHABLE="网络连通性检查失败 (%s/%s)"
        MSG_TRY_RELOGIN="连续 %s 次网络不可达，尝试重新登录..."
        MSG_TRY_RELOGIN_BACKOFF="退避模式中，再次尝试重新登录..."
        MSG_DISCONNECT_TIME="达到计划断网时间，断开网络连接。"
        MSG_RECONNECT_TIME="计划断网时间结束，恢复网络连接。"
        MSG_LIMITED_MONITORING_ENABLED="限时监控已启用。"
        MSG_LIMITED_MONITORING_DISABLED="限时监控已禁用。"
        MSG_LAST_LOGIN_UNKNOWN="上次登录时间未知。"
        MSG_MONITOR_WINDOW_ACTIVE="当前处于监控时间窗口内，进行网络监控和重连。"
        MSG_MONITOR_WINDOW_INACTIVE="当前不在监控时间窗口内，暂停网络监控和重连。"
        MSG_INTERFACE_NO_IP="接口 %s 没有获取到IP地址，退出限时监控。"

        # Backoff mechanism messages
        MSG_BACKOFF_APPLIED="应用退避策略，将检测间隔增加到 %s 秒。"
        MSG_BACKOFF_RESET="网络已恢复，重置检测间隔为 %s 秒。"
        MSG_BACKOFF_RESET_AFTER_SCHEDULE="达到计划断网时间，重置退避状态。"
        MSG_BACKOFF_DISCONNECT="进入退避模式，断开网络连接。"
        MSG_BACKOFF_RECONNECT="退避间隔结束，恢复网络连接。"
        MSG_LIMITED_MONITORING_BYPASSED="正处于退避模式，忽略限时监控。"
        MSG_AUTH_FAILED_NETWORK_STILL_DOWN="认证尝试后网络仍不可达。"
        
        # Service messages
        MSG_SERVICE_STARTED="服务已启动。"
        MSG_SERVICE_STOPPED="服务已停止。"
        MSG_SERVICE_DISABLED="服务在配置中被禁用，不启动服务。"
        MSG_NO_ENABLED_SESSION="无可用配置。"
        
        # Auth client common messages
        MSG_RELEASE_DHCP="释放接口 %s 的 DHCP..."
        MSG_RENEW_IP="重新获取接口 %s 的 IP 地址..."
        MSG_GOT_IP="接口 %s 已获取到 IP 地址：%s"
        MSG_WAIT_IP_TIMEOUT="等待 %s 秒后，接口 %s 仍未获取到 IP 地址，放弃登录。"
        MSG_EXECUTE_LOGIN="执行 %s 方式登录程序..."
        MSG_LOGIN_SUCCESS="%s 方式登录成功，更新上次登录时间。"
        MSG_LOGIN_FAILURE="%s 方式登录失败，未更新上次登录时间。"
        MSG_LOGIN_OUTPUT="登录输出：%s"
        MSG_AUTH_PARAM_ERROR="认证脚本传入参数错误，放弃登录。"

        # Logging messages
        MSG_LOG_INITIALIZED="日志初始化完成。日志文件创建于"
        MSG_LOG_FILE_CLEARED="日志文件已清空（保留期限：%s 天）"
        MSG_NO_LOGS_AVAILABLE="没有可用的日志"
        MSG_LOG_CLEANUP_COMPLETED="日志清理完成。已删除 %s/%s 个日志文件（保留期限：%s 天）"

        # Session manager messages
        MSG_SESSION_STARTED="配置 %s 已启动 (PID: %s)"
        MSG_SESSION_STOPPED="配置 %s 已停止 (PID: %s)"
        MSG_SESSION_ALREADY_RUNNING="配置 %s 已在运行 (PID: %s)"
        MSG_SESSION_NOT_RUNNING="配置 %s 未运行"
        MSG_SESSION_DISABLED="配置 %s 已禁用"
        MSG_STARTING_ALL_SESSIONS="正在启动所有已启用的配置。"
        MSG_STOPPING_ALL_SESSIONS="正在停止所有正在运行的配置。"
        MSG_INTERFACE_LOCKED="接口 %s 已经被使用。配置 %s 无法启动。"

    else
        # English message dictionary (default)
        MSG_UNKNOWN_CLIENT_TYPE="Unknown client type (%s)."
        MSG_USERNAME_PASSWORD_NOT_SET="Necessary parameter for auth not set, cannot start."
        
        # Monitor script messages
        MSG_MONITOR_SCRIPT_STARTED="Monitor script started."
        MSG_MONITOR_SCRIPT_EXIT="Monitor script stopped."
        MSG_NETWORK_REACHABLE="Network has recovered."
        MSG_NETWORK_UNREACHABLE="Network connectivity check failed (%s/%s)"
        MSG_TRY_RELOGIN="Network unreachable for %s times, attempting to re-login..."
        MSG_TRY_RELOGIN_BACKOFF="Backoff mode, attempting to re-login again..."
        MSG_DISCONNECT_TIME="Reached scheduled disconnect time, disconnecting network."
        MSG_RECONNECT_TIME="Scheduled disconnect time ended, restoring network connection."
        MSG_LIMITED_MONITORING_ENABLED="Limited monitoring enabled."
        MSG_LIMITED_MONITORING_DISABLED="Limited monitoring disabled."
        MSG_LAST_LOGIN_UNKNOWN="Last login time unknown."
        MSG_MONITOR_WINDOW_ACTIVE="Within monitoring time window, performing network monitoring and reconnection."
        MSG_MONITOR_WINDOW_INACTIVE="Outside monitoring time window, pausing network monitoring and reconnection."
        MSG_INTERFACE_NO_IP="Interface %s has no IP address, exiting limited monitoring."

        # Backoff mechanism messages
        MSG_BACKOFF_APPLIED="Applied backoff policy, increased check interval to %s seconds."
        MSG_BACKOFF_RESET="Network recovered, reset check interval to %s seconds."
        MSG_BACKOFF_RESET_AFTER_SCHEDULE="Reached scheduled disconnect time, resetting backoff state."
        MSG_BACKOFF_DISCONNECT="Entering backoff mode, disconnecting network."
        MSG_BACKOFF_RECONNECT="Backoff period ended, restoring network connection."
        MSG_LIMITED_MONITORING_BYPASSED="In backoff mode, bypassing limited monitoring."
        MSG_AUTH_FAILED_NETWORK_STILL_DOWN="Network still unreachable after authentication attempt."
        
        # Service messages
        MSG_SERVICE_STARTED="Service started."
        MSG_SERVICE_STOPPED="Service stopped."
        MSG_SERVICE_DISABLED="Service is disabled in the configuration, not starting."
        MSG_NO_ENABLED_SESSION="No enabled session."
        
        # Auth client messages
        MSG_RELEASE_DHCP="Releasing DHCP on interface %s..."
        MSG_RENEW_IP="Renewing IP address on interface %s..."
        MSG_GOT_IP="Interface %s obtained IP address: %s"
        MSG_WAIT_IP_TIMEOUT="After waiting %s seconds, interface %s still has no IP address, aborting login."
        MSG_EXECUTE_LOGIN="Executing %s login script..."
        MSG_LOGIN_SUCCESS="%s login successful, updated last login time."
        MSG_LOGIN_FAILURE="%s login failed, did not update last login time."
        MSG_LOGIN_OUTPUT="Login output: %s"
        MSG_AUTH_PARAM_ERROR="Parameter parsed to login script is illegal, aborting login."
        
        # Logging messages
        MSG_LOG_INITIALIZED="Log initialized. Log file created at"
        MSG_LOG_FILE_CLEARED="Log file cleared (retention period: %s days)"
        MSG_NO_LOGS_AVAILABLE="No logs available"
        MSG_LOG_CLEANUP_COMPLETED="Log cleanup completed. Deleted %s/%s log files (retention period: %s days)"

        # Session manager messages
        MSG_SESSION_STARTED="Session %s started (PID: %s)"
        MSG_SESSION_STOPPED="Session %s stopped (PID: %s)"
        MSG_SESSION_ALREADY_RUNNING="Session %s is already running (PID: %s)"
        MSG_SESSION_NOT_RUNNING="Session %s is not running"
        MSG_SESSION_DISABLED="Session %s is disabled"
        MSG_STARTING_ALL_SESSIONS="Starting all enabled sessions"
        MSG_STOPPING_ALL_SESSIONS="Stopping all running sessions"
        MSG_INTERFACE_LOCKED="Interface %s is already in use. Stopping session %s ..."
    
    fi
}

#######################################
# Get a translated message
# Arguments:
#   $1 - Message key (e.g., MSG_SERVICE_STARTED)
# Returns:
#   The translated message text
#######################################
get_message() {
    local msg_key="$1"
    local msg_value=""
    
    # Use eval to get the value of the variable whose name is in msg_key
    eval "msg_value=\$$msg_key"
    
    echo "$msg_value"
}

# Initialize messages
init_i18n 