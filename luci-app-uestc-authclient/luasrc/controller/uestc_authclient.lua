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
end

function action_get_log()
    local fs = require "nixio.fs"
    local http = require "luci.http"
    local log_content = fs.readfile("/tmp/uestc_authclient.log") or translate("No logs available")

    http.prepare_content("text/plain; charset=utf-8")
    http.header("Cache-Control", "no-cache")
    http.write(log_content)
end
