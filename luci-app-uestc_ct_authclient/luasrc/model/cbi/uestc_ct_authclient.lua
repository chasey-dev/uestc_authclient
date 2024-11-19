local m, s, o
local uci = require "luci.model.uci".cursor()
local net = require "luci.model.network".init()
local sys = require "luci.sys"

m = Map("uestc_ct_authclient", translate("清水河电信认证"))

-- 添加描述文字
m.description = translate("该页面用于配置清水河电信认证客户端。请填写您的校园网用户名和密码，并根据需要调整其他设置。")

s = m:section(TypedSection, "authclient", translate("设置"))
s.anonymous = true

-- 开机自动运行
o = s:option(Flag, "enabled", translate("开机自动运行"))
o.default = "0"
o.rmempty = false
o.description = translate("勾选后，服务将在系统启动时自动运行。")

-- 用户名
o = s:option(Value, "username", translate("用户名"))
o.datatype = "string"
o.description = translate("您的校园网用户名。")
o.placeholder = translate("必填")
o.rmempty = false

function o.validate(self, value, section)
    if value == nil or value == "" then
        return nil, translate("用户名不能为空。")
    end
    return value
end

-- 密码
o = s:option(Value, "password", translate("密码"))
o.datatype = "string"
o.password = true
o.description = translate("您的校园网密码。")
o.placeholder = translate("必填")
o.rmempty = false

function o.validate(self, value, section)
    if value == nil or value == "" then
        return nil, translate("密码不能为空。")
    end
    return value
end

-- 登录主机
o = s:option(Value, "host", translate("登录主机"))
o.datatype = "host"
o.default = "172.25.249.64"
o.description = translate("认证服务器地址，通常无需修改。")
o.placeholder = "172.25.249.64"

-- 监听接口
o = s:option(ListValue, "interface", translate("监听接口"))
o.default = "wan"
o.description = translate("选择用于认证的网络接口。")
o.placeholder = "wan"

-- 获取网络接口列表
local netlist = net:get_networks()
for _, iface in ipairs(netlist) do
    local name = iface:name()
    if name and name ~= "loopback" then
        o:value(name)
    end
end

-- 心跳检测地址（支持多个）
o = s:option(DynamicList, "heartbeat_hosts", translate("心跳检测地址"))
o.datatype = "host"
o.default = {"223.5.5.5", "119.29.29.29"}
o.description = translate("用于检测网络连通性的主机地址，可以添加多个地址。")

-- 心跳检测间隔
o = s:option(Value, "check_interval", translate("心跳检测间隔（秒）"))
o.datatype = "uinteger"
o.default = "30"
o.description = translate("检测网络状态的时间间隔，单位为秒。")
o.placeholder = "30"

-- 日志保留天数
o = s:option(Value, "log_retention_days", translate("日志保留天数"))
o.datatype = "uinteger"
o.default = "7"
o.description = translate("指定日志文件的保留天数，超过天数的日志将被清除。")
o.placeholder = "7"

-- 定时断网功能
o = s:option(Flag, "scheduled_disconnect_enabled", translate("启用定时断网"))
o.default = "1"
o.rmempty = false
o.description = translate("勾选后，系统将在指定时间段内断开网络连接。")

-- 定时断网开始时间
o = s:option(ListValue, "scheduled_disconnect_start", translate("断网开始时间（小时）"))
for i = 0, 23 do
    o:value(i, string.format("%02d:00", i))
end
o.default = "3"
o:depends("scheduled_disconnect_enabled", "1")

-- 定时断网结束时间
o = s:option(ListValue, "scheduled_disconnect_end", translate("断网结束时间（小时）"))
for i = 0, 23 do
    o:value(i, string.format("%02d:00", i))
end
o.default = "4"
o:depends("scheduled_disconnect_enabled", "1")

-- 校验时间段
function o.validate(self, value, section)
    local start_time = tonumber(m:get(section, "scheduled_disconnect_start"))
    local end_time = tonumber(value)
    if start_time and end_time and start_time == end_time then
        return nil, translate("断网开始时间和结束时间不能相同！")
    end
    return value
end

-- 添加 on_commit 函数，在配置应用后重启服务
function m.on_commit(self)
    sys.call("/etc/init.d/uestc_ct_authclient restart >/dev/null 2>&1 &")
end

return m
