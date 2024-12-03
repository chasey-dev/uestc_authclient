local m, s, o
local uci = require "luci.model.uci".cursor()
local net = require "luci.model.network".init()
local sys = require "luci.sys"

m = Map("uestc_authclient", translate("UESTC Authentication Client"))

-- Add description
m.description = translate("This page is used to configure the UESTC authentication client. Please fill in your username and password, and adjust other settings as needed.")

s = m:section(TypedSection, "authclient", translate("Settings"))
s.anonymous = true

-- Enable on startup
o = s:option(Flag, "enabled", translate("Enable on startup"))
o.default = "0"
o.rmempty = false
o.description = translate("Check to run the service automatically at system startup.")

-- Client type selection
o = s:option(ListValue, "client_type", translate("Authentication method"))
o.default = "ct"
o.description = translate("Select the authentication method. New dormitories and teaching areas use the Srun authentication method.")
o:value("ct", translate("CT authentication method (qsh-telecom-autologin)"))
o:value("srun", translate("Srun authentication method (go-nd-portal)"))
o.rmempty = false

-- CT client settings
-- Username
o = s:option(Value, "ct_client_username", translate("CT authentication username"))
o.datatype = "string"
o.description = translate("Your CT authentication username.")
o.placeholder = translate("Required")
o.rmempty = true
o:depends("client_type", "ct")

function o.validate(self, value, section)
    local client_type = m:get(section, "client_type")
    if client_type == "ct" then
        if value == nil or value == "" then
            return nil, translate("Username cannot be empty.")
        end
    end
    return value
end

-- Password
o = s:option(Value, "ct_client_password", translate("CT authentication password"))
o.datatype = "string"
o.password = true
o.description = translate("Your CT authentication password.")
o.placeholder = translate("Required")
o.rmempty = true
o:depends("client_type", "ct")

function o.validate(self, value, section)
    local client_type = m:get(section, "client_type")
    if client_type == "ct" then
        if value == nil or value == "" then
            return nil, translate("Password cannot be empty.")
        end
    end
    return value
end

-- Host
o = s:option(Value, "ct_client_host", translate("CT authentication host"))
o.datatype = "host"
o.default = "172.25.249.64"
o.description = translate("CT authentication server address, usually no need to modify.")
o.placeholder = "172.25.249.64"
o:depends("client_type", "ct")

-- Srun client settings
-- Username
o = s:option(Value, "srun_client_username", translate("Srun authentication username"))
o.datatype = "string"
o.description = translate("Your Srun authentication username.")
o.placeholder = translate("Required")
o.rmempty = true
o:depends("client_type", "srun")

function o.validate(self, value, section)
    local client_type = m:get(section, "client_type")
    if client_type == "srun" then
        if value == nil or value == "" then
            return nil, translate("Username cannot be empty.")
        end
    end
    return value
end

-- Password
o = s:option(Value, "srun_client_password", translate("Srun authentication password"))
o.datatype = "string"
o.password = true
o.description = translate("Your Srun authentication password.")
o.placeholder = translate("Required")
o.rmempty = true
o:depends("client_type", "srun")

function o.validate(self, value, section)
    local client_type = m:get(section, "client_type")
    if client_type == "srun" then
        if value == nil or value == "" then
            return nil, translate("Password cannot be empty.")
        end
    end
    return value
end

-- Authentication mode
o = s:option(ListValue, "srun_client_auth_mode", translate("Srun authentication mode"))
o.default = "dx"
o:value("dx", translate("China Telecom"))
o:value("edu", translate("Campus Network"))
o.description = translate("Select the authentication mode for the Srun client.")
o:depends("client_type", "srun")

-- Host
o = s:option(Value, "srun_client_host", translate("Srun authentication host"))
o.datatype = "ipaddr"
o.default = "10.253.0.237"
o.description = translate("Srun authentication server address, modify according to your area.")
o.placeholder = "10.253.0.237"
o:depends("client_type", "srun")

-- General settings
-- Network interface
o = s:option(ListValue, "interface", translate("Network interface"))
o.default = "wan"
o.description = translate("Select the network interface for authentication.")
o.placeholder = "wan"

-- Get network interface list
local netlist = net:get_networks()
for _, iface in ipairs(netlist) do
    local name = iface:name()
    if name and name ~= "loopback" then
        o:value(name)
    end
end

-- Heartbeat hosts (support multiple)
o = s:option(DynamicList, "heartbeat_hosts", translate("Heartbeat hosts"))
o.datatype = "host"
o.default = {"223.5.5.5", "119.29.29.29"}
o.description = translate("Host addresses used to check network connectivity; you can add multiple addresses.")

-- Check interval
o = s:option(Value, "check_interval", translate("Check interval (seconds)"))
o.datatype = "uinteger"
o.default = "30"
o.description = translate("Time interval for checking network status, in seconds.")
o.placeholder = "30"

-- Log retention days
o = s:option(Value, "log_retention_days", translate("Log retention days"))
o.datatype = "uinteger"
o.default = "7"
o.description = translate("Specify the number of days to retain log files; logs exceeding this period will be cleared.")
o.placeholder = "7"

-- Scheduled disconnection feature
o = s:option(Flag, "scheduled_disconnect_enabled", translate("Enable scheduled disconnection"))
o.default = "1"
o.rmempty = false
o.description = translate("Check to disconnect the network during specified time periods.")

-- Scheduled disconnect start time
o = s:option(ListValue, "scheduled_disconnect_start", translate("Disconnection start time (hour)"))
for i = 0, 23 do
    o:value(i, string.format("%02d:00", i))
end
o.default = "3"
o:depends("scheduled_disconnect_enabled", "1")

-- Scheduled disconnect end time
o = s:option(ListValue, "scheduled_disconnect_end", translate("Disconnection end time (hour)"))
for i = 0, 23 do
    o:value(i, string.format("%02d:00", i))
end
o.default = "4"
o:depends("scheduled_disconnect_enabled", "1")

-- Validate time range
function o.validate(self, value, section)
    local enabled = m:get(section, "scheduled_disconnect_enabled")
    if enabled == "1" then
        local start_time = tonumber(m:get(section, "scheduled_disconnect_start"))
        local end_time = tonumber(value)
        if start_time and end_time and start_time == end_time then
            return nil, translate("Disconnection start time and end time cannot be the same!")
        end
    end
    return value
end

-- Add on_commit function to restart the service after applying configuration
function m.on_commit(self)
    sys.call("/etc/init.d/uestc_authclient restart >/dev/null 2>&1 &")
end

return m
