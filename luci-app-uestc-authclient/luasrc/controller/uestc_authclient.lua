module("luci.controller.uestc_authclient", package.seeall)

function index()
    if not nixio.fs.access("/etc/config/uestc_authclient") then
        return
    end

    entry({"admin", "services", "uestc_authclient"},
        alias("admin", "services", "uestc_authclient", "overview"),
        _("UESTC Authentication"), 10).dependent = true

    entry({"admin", "services", "uestc_authclient", "overview"},
        template("uestc_authclient/overview"),
        _("Overview"), 1)

    entry({"admin", "services", "uestc_authclient", "config"},
        cbi("uestc_authclient"),
        _("Configuration"), 2).leaf = true

    entry({"admin", "services", "uestc_authclient", "actions", "start"},
        call("action_start")).leaf = true

    entry({"admin", "services", "uestc_authclient", "actions", "stop"},
        call("action_stop")).leaf = true
        
    entry({"admin", "services", "uestc_authclient", "actions", "clear_log"},
        call("action_clear_log")).leaf = true        

    entry({"admin", "services", "uestc_authclient", "actions", "get_log"},
        call("action_get_log")).leaf = true
        
    entry({"admin", "services", "uestc_authclient", "actions", "get_status"},
        call("action_get_status")).leaf = true

end

-- Function to get the current logs
function action_get_log()
    local fs = require "nixio.fs"
    local http = require "luci.http"
    local i18n = require "luci.i18n"
    local log_content = fs.readfile("/tmp/uestc_authclient.log") or i18n.translate("No logs available")

    http.prepare_content("text/plain; charset=utf-8")
    http.header("Cache-Control", "no-cache")
    http.write(log_content)
end

-- Function to get service status in JSON format for AJAX updates
function action_get_status()
    local sys = require "luci.sys"
    local uci = require "luci.model.uci".cursor()
    local http = require "luci.http"
    local json = require "luci.jsonc"
    
    -- Path to the service script
    local PROG = "/usr/bin/uestc_authclient_monitor.sh"
    
    -- Check if the service is running
    local is_running = (sys.call("pgrep -f '" .. PROG .. "' >/dev/null") == 0)
    
    -- Check network status
    local network_status = "not_running"
    if is_running then
        -- Get the list of heartbeat hosts
        local heartbeat_hosts = uci:get_list("uestc_authclient", "listening", "heartbeat_hosts") or {"223.5.5.5", "119.29.29.29"}
        local interface = uci:get("uestc_authclient", "listening", "interface")
        -- Check network connectivity
        network_status = "disconnected"
        for _, host in ipairs(heartbeat_hosts) do
            if sys.call("ping -I " .. interface .. " -c 1 -W 1 " .. host .. " >/dev/null 2>&1") == 0 then
                network_status = "connected"
                break
            end
        end
    else
        network_status = "not_running"
    end
    
    -- Get last login time
    local fs = require "nixio.fs"
    local i18n = require "luci.i18n"
    local last_login = fs.readfile("/tmp/uestc_authclient_last_login") or i18n.translate("None")
    
    -- Prepare JSON response
    local result = {
        running = is_running,
        network_status = network_status,
        last_login = last_login
    }
    
    http.prepare_content("application/json")
    http.write(json.stringify(result))
end

-- start the service
function action_start()
    local sys = require "luci.sys"

    -- Start the service
    sys.call("/etc/init.d/uestc_authclient start")

end

-- stop the service
function action_stop()
    local sys = require "luci.sys"

    -- Stop the service
    sys.call("/etc/init.d/uestc_authclient stop")

end

-- clear the logs
function action_clear_log()
    local fs = require "nixio.fs"

    -- Clear the log file
    fs.writefile("/tmp/uestc_authclient.log", "")

end
