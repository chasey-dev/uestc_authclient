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
        MSG_UNKNOWN_CLIENT_TYPE="未知的客户端类型："
        MSG_USERNAME_PASSWORD_NOT_SET="用户名或密码未设置，无法启动。"
        
        # Monitor script messages
        MSG_MONITOR_SCRIPT_STARTED="监控脚本已启动。"
        MSG_NETWORK_REACHABLE="网络已恢复正常。"
        MSG_NETWORK_UNREACHABLE="网络连通性检查失败 (%s/%s)"
        MSG_TRY_RELOGIN="连续 %s 次网络不可达，尝试重新登录..."
        MSG_INTERFACE_NO_IP="接口 %s 没有获取到IP地址，等待下一次检查。"
        MSG_DISCONNECT_TIME="达到计划断网时间，断开网络连接。"
        MSG_RECONNECT_TIME="计划断网时间结束，恢复网络连接。"
        MSG_SERVICE_DISABLED="服务在配置中被禁用，不启动服务。"
        MSG_LIMITED_MONITORING_ENABLED="限时监控已启用。"
        MSG_LIMITED_MONITORING_DISABLED="限时监控已禁用。"
        MSG_LAST_LOGIN_UNKNOWN="上次登录时间未知。"
        MSG_MONITOR_WINDOW_ACTIVE="当前处于监控时间窗口内，进行网络监控和重连。"
        MSG_MONITOR_WINDOW_INACTIVE="当前不在监控时间窗口内，暂停网络监控和重连。"
        
        # Service messages
        MSG_SERVICE_STARTED="服务已启动。"
        MSG_SERVICE_STOPPED="服务已停止。"
        
        # Auth client common messages
        MSG_RELEASE_DHCP="释放接口 %s 的 DHCP..."
        MSG_RENEW_IP="重新获取接口 %s 的 IP 地址..."
        MSG_GOT_IP="接口 %s 已获取到 IP 地址：%s"
        MSG_WAIT_IP_TIMEOUT="等待 %s 秒后，接口 %s 仍未获取到 IP 地址，放弃登录。"
        MSG_LOGIN_OUTPUT="登录输出：%s"
        
        # CT auth client specific messages
        MSG_CT_EXECUTE_LOGIN="执行电信登录程序..."
        MSG_CT_LOGIN_SUCCESS="登录成功，更新上次登录时间。"
        MSG_CT_LOGIN_FAILURE="登录失败，未更新上次登录时间。"
        
        # Srun auth client specific messages
        MSG_SRUN_EXECUTE_LOGIN="执行 Srun 认证方式登录程序..."
        MSG_SRUN_LOGIN_SUCCESS="Srun 认证方式登录成功，更新上次登录时间。"
        MSG_SRUN_LOGIN_FAILURE="Srun 认证方式登录失败，未更新上次登录时间。"
        MSG_SRUN_USERNAME_PASSWORD_NOT_SET="Srun 认证方式的用户名或密码未设置，无法登录。"
        
        # Logging messages
        MSG_LOG_INITIALIZED="日志初始化完成。日志文件创建于"
        MSG_LOG_ROTATION_COMPLETED="日志轮转完成。已保留 %s/%s 行记录（保留期限：%s 天）"
        MSG_LOG_FILE_CLEARED="日志文件已清空（保留期限：%s 天）"
    else
        # English message dictionary (default)
        MSG_UNKNOWN_CLIENT_TYPE="Unknown client type:"
        MSG_USERNAME_PASSWORD_NOT_SET="Username or password not set, cannot start."
        
        # Monitor script messages
        MSG_MONITOR_SCRIPT_STARTED="Monitor script started."
        MSG_NETWORK_REACHABLE="Network has recovered."
        MSG_NETWORK_UNREACHABLE="Network connectivity check failed (%s/%s)"
        MSG_TRY_RELOGIN="Network unreachable for %s times, attempting to re-login..."
        MSG_INTERFACE_NO_IP="Interface %s has no IP address, waiting for the next check."
        MSG_DISCONNECT_TIME="Reached scheduled disconnect time, disconnecting network."
        MSG_RECONNECT_TIME="Scheduled disconnect time ended, restoring network connection."
        MSG_SERVICE_DISABLED="Service is disabled in the configuration, not starting."
        MSG_LIMITED_MONITORING_ENABLED="Limited monitoring enabled."
        MSG_LIMITED_MONITORING_DISABLED="Limited monitoring disabled."
        MSG_LAST_LOGIN_UNKNOWN="Last login time unknown."
        MSG_MONITOR_WINDOW_ACTIVE="Within monitoring time window, performing network monitoring and reconnection."
        MSG_MONITOR_WINDOW_INACTIVE="Outside monitoring time window, pausing network monitoring and reconnection."
        
        # Service messages
        MSG_SERVICE_STARTED="Service started."
        MSG_SERVICE_STOPPED="Service stopped."
        
        # Auth client common messages
        MSG_RELEASE_DHCP="Releasing DHCP on interface %s..."
        MSG_RENEW_IP="Renewing IP address on interface %s..."
        MSG_GOT_IP="Interface %s obtained IP address: %s"
        MSG_WAIT_IP_TIMEOUT="After waiting %s seconds, interface %s still has no IP address, aborting login."
        MSG_LOGIN_OUTPUT="Login output: %s"
        
        # CT auth client specific messages
        MSG_CT_EXECUTE_LOGIN="Executing CT login script..."
        MSG_CT_LOGIN_SUCCESS="Login successful, updated last login time."
        MSG_CT_LOGIN_FAILURE="Login failed, did not update last login time."
        
        # Srun auth client specific messages
        MSG_SRUN_EXECUTE_LOGIN="Executing Srun authentication login script..."
        MSG_SRUN_LOGIN_SUCCESS="Srun authentication login successful, updated last login time."
        MSG_SRUN_LOGIN_FAILURE="Srun authentication login failed, did not update last login time."
        MSG_SRUN_USERNAME_PASSWORD_NOT_SET="Username or password for Srun authentication is not set, cannot login."
        
        # Logging messages
        MSG_LOG_INITIALIZED="Logging initialized. Log file created at"
        MSG_LOG_ROTATION_COMPLETED="Log rotation completed. Retained %s/%s lines (retention: %s days)"
        MSG_LOG_FILE_CLEARED="Log file cleared (retention: %s days)"
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