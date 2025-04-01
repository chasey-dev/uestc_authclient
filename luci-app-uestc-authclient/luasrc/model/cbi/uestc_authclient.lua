local sys   = require "luci.sys"
local uci   = require "luci.model.uci".cursor()
local net  = require "luci.model.network".init()

-- Create the Map referencing /etc/config/uestc_authclient
local m = Map("uestc_authclient", translate("UESTC Authentication Client"),
    translate("This page is used to configure the UESTC authentication client. Please fill in your username and password, and adjust other settings as needed.")
)

------------------------------------------------------------------------------
-- 1) Basic Settings: config system 'basic'
------------------------------------------------------------------------------
local sBasic = m:section(NamedSection, "basic", "system", translate("Basic Settings"))
sBasic.anonymous = true

-- Enable on startup
local o = sBasic:option(Flag, "enabled", translate("Enable on startup"))
o.default = "0"
o.rmempty = false
o.description = translate("Check to run the service automatically at system startup.")


-- Limited monitoring
o = sBasic:option(Flag, "limited_monitoring", translate("Limited Monitoring"))
o.default = "1"
o.rmempty = false
o.description = translate("Check to limit monitoring and reconnection attempts to within 10 minutes around the last login time.")


------------------------------------------------------------------------------
-- 2) Authentication Settings: config auth 'auth'
------------------------------------------------------------------------------
-- Use one TypedSection, so we can do option:depends(...) for real-time toggling
local sAuth = m:section(TypedSection, "auth", translate("Authentication Settings"))
sAuth.anonymous = true

-- Authentication method
local ctype = sAuth:option(ListValue, "auth_type", translate("Authentication method"))
ctype.default = "ct"
ctype.rmempty = false
ctype:value("ct", translate("CT authentication method (qsh-telecom-autologin)"))
ctype:value("srun", translate("Srun authentication method (go-nd-portal)"))
ctype.description = translate("Select the authentication method. New dormitories and teaching areas use the Srun authentication method.")

----------------------[ CT fields ]----------------------

local oCTUser = sAuth:option(Value, "ct_username", translate("CT authentication username"))
oCTUser.datatype = "string"
oCTUser.description = translate("Your CT authentication username.")
oCTUser.placeholder = translate("Required")
oCTUser:depends("auth_type", "ct")

function oCTUser.validate(self, value, section)
    local val = value and value:trim()
    if sAuth:cfgvalue(section, "auth_type") == "ct" then
        if not val or val == "" then
            return nil, translate("Username cannot be empty.")
        end
    end
    return val
end

local oCTPass = sAuth:option(Value, "ct_password", translate("CT authentication password"))
oCTPass.datatype = "string"
oCTPass.password = true
oCTPass.description = translate("Your CT authentication password.")
oCTPass.placeholder = translate("Required")
oCTPass:depends("auth_type", "ct")

function oCTPass.validate(self, value, section)
    local val = value and value:trim()
    if sAuth:cfgvalue(section, "auth_type") == "ct" then
        if not val or val == "" then
            return nil, translate("Password cannot be empty.")
        end
    end
    return val
end

local oCTHost = sAuth:option(Value, "ct_host", translate("CT authentication host"))
oCTHost.datatype = "host"
oCTHost.default = "172.25.249.64"
oCTHost.description = translate("CT authentication server address, usually no need to modify.")
oCTHost:depends("auth_type", "ct")

----------------------[ Srun fields ]----------------------

local oSrunUser = sAuth:option(Value, "srun_username", translate("Srun authentication username"))
oSrunUser.datatype = "string"
oSrunUser.placeholder = translate("Required")
oSrunUser.description = translate("Your Srun authentication username.")
oSrunUser:depends("auth_type", "srun")

function oSrunUser.validate(self, value, section)
    local val = value and value:trim()
    if sAuth:cfgvalue(section, "auth_type") == "srun" then
        if not val or val == "" then
            return nil, translate("Username cannot be empty.")
        end
    end
    return val
end

local oSrunPass = sAuth:option(Value, "srun_password", translate("Srun authentication password"))
oSrunPass.datatype = "string"
oSrunPass.password = true
oSrunPass.placeholder = translate("Required")
oSrunPass.description = translate("Your Srun authentication password.")
oSrunPass:depends("auth_type", "srun")

function oSrunPass.validate(self, value, section)
    local val = value and value:trim()
    if sAuth:cfgvalue(section, "auth_type") == "srun" then
        if not val or val == "" then
            return nil, translate("Password cannot be empty.")
        end
    end
    return val
end

local oSrunMode = sAuth:option(ListValue, "srun_auth_mode", translate("Srun authentication mode"))
oSrunMode:value("dx", translate("China Telecom"))
oSrunMode:value("edu", translate("Campus Network"))
oSrunMode.default = "dx"
oSrunMode.description = translate("Select the authentication mode for the Srun client.")
oSrunMode:depends("auth_type", "srun")

local oSrunHost = sAuth:option(Value, "srun_host", translate("Srun authentication host"))
oSrunHost.datatype = "ipaddr"
oSrunHost.default = "10.253.0.237"
oSrunHost.description = translate("Srun authentication server address, modify according to your area.")
oSrunHost:depends("auth_type", "srun")


------------------------------------------------------------------------------
-- 3) Network Settings: config system 'listening'
------------------------------------------------------------------------------
local sNet = m:section(NamedSection, "listening", "system", translate("Network Settings"))
sNet.anonymous = true

local oIf = sNet:option(ListValue, "interface", translate("Interface"))
oIf.default = "wan"
oIf.description = translate("Select the interface for authentication. (Linux Interface, Refers to device in Openwrt.)")

local seen_devices = {}

for _, iface in ipairs(net:get_interfaces()) do
    local ifn = iface:name()
    if ifn and ifn ~= "lo" then
        seen_devices[ifn] = true
    end
end

for devname, _ in pairs(seen_devices) do
    oIf:value(devname)
end

local oHb = sNet:option(DynamicList, "heartbeat_hosts", translate("Heartbeat hosts"))
oHb.datatype = "host"
oHb.description = translate("Host addresses used to check network connectivity; you can add multiple addresses.")

local oCheck = sNet:option(Value, "check_interval", translate("Check interval (seconds)"))
oCheck.datatype = "uinteger"
oCheck.default = "30"
oCheck.description = translate("Time interval for checking network status, in seconds.")


------------------------------------------------------------------------------
-- 4) Logging Settings: config system 'logging'
------------------------------------------------------------------------------
local sLog = m:section(NamedSection, "logging", "system", translate("Logging Settings"))
sLog.anonymous = true

local oRet = sLog:option(Value, "retention_days", translate("Log retention days"))
oRet.datatype = "uinteger"
oRet.default = "7"
oRet.description = translate("Specify the number of days to retain log files; logs exceeding this period will be cleared.")


------------------------------------------------------------------------------
-- 5) Scheduled Disconnection: config system 'schedule'
------------------------------------------------------------------------------
local sSched = m:section(NamedSection, "schedule", "system", translate("Scheduled Disconnection"))
sSched.anonymous = true

local oEn = sSched:option(Flag, "enabled", translate("Enable scheduled disconnection"))
oEn.default = "1"
oEn.rmempty = false
oEn.description = translate("Check to disconnect the network during specified time periods.")

local st = sSched:option(ListValue, "disconnect_start", translate("Disconnection start time (hour)"))
for i = 0, 23 do
    st:value(i, string.format("%02d:00", i))
end
st.default = "3"
st:depends("enabled", "1")

local et = sSched:option(ListValue, "disconnect_end", translate("Disconnection end time (hour)"))
for i = 0, 23 do
    et:value(i, string.format("%02d:00", i))
end
et.default = "4"
et:depends("enabled", "1")

function et.validate(self, value, section)
    local en = uci:get("uestc_authclient", "schedule", "enabled")
    if en == "1" then
        local start_val = uci:get("uestc_authclient", "schedule", "disconnect_start")
        if tostring(value) == tostring(start_val) then
            return nil, translate("Disconnection start time and end time cannot be the same!")
        end
    end
    return value
end


------------------------------------------------------------------------------
-- on_commit: save & restart
------------------------------------------------------------------------------
function m.on_commit(self)
    -- restart the service
    sys.call("/etc/init.d/uestc_authclient restart >/dev/null 2>&1 &")
end

return m
