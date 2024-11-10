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
local netm = require "luci.model.network".init()
local netlist = netm:get_networks()

for _, iface in ipairs(netlist) do
    local name = iface:name()
    if name and name ~= "loopback" then
        o:value(name)
    end
end

-- 心跳检测地址
o = s:option(Value, "heartbeat_host", translate("心跳检测地址"))
o.datatype = "host"
o.default = "223.5.5.5"
o.description = translate("用于检测网络连通性的主机地址。")
o.placeholder = "223.5.5.5"

-- 心跳检测间隔
o = s:option(Value, "check_interval", translate("心跳检测间隔（秒）"))
o.datatype = "uinteger"
o.default = "60"
o.description = translate("检测网络状态的时间间隔，单位为秒。")
o.placeholder = "60"

-- 恢复 on_commit 函数
function m.on_commit(self)
    luci.sys.call("/etc/init.d/uestc_ct_authclient restart >/dev/null 2>&1 &")
end

return m

