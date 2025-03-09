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

    entry({"admin", "services", "uestc_authclient", "get_log"},
        call("action_get_log")).leaf = true
        
    entry({"admin", "services", "uestc_authclient", "status"},
        call("action_status")).leaf = true
end

function action_get_log()
    local fs = require "nixio.fs"
    local http = require "luci.http"
    local log_content = fs.readfile("/tmp/uestc_authclient.log") or translate("No logs available")

    http.prepare_content("text/plain; charset=utf-8")
    http.header("Cache-Control", "no-cache")
    http.write(log_content)
end

-- Function to get service status in JSON format for AJAX updates
function action_status()
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
        -- Check network connectivity
        network_status = "disconnected"
        for _, host in ipairs(heartbeat_hosts) do
            if sys.call("ping -c 1 -W 1 " .. host .. " >/dev/null 2>&1") == 0 then
                network_status = "connected"
                break
            end
        end
    else
        network_status = "not_running"
    end
    
    -- Get last login time
    local fs = require "nixio.fs"
    local last_login = fs.readfile("/tmp/uestc_authclient_last_login") or "none"
    
    -- Prepare JSON response
    local result = {
        running = is_running,
        network_status = network_status,
        last_login = last_login
    }
    
    http.prepare_content("application/json")
    http.write(json.stringify(result))
end
