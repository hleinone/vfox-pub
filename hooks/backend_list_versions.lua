local http = require("http")
local json = require("json")
local pub = require("pub")

function PLUGIN:BackendListVersions(ctx)
    local tool = pub.validate_tool(ctx.tool)
    local resp, err = http.get({
        url = "https://pub.dev/api/packages/" .. tool,
        headers = { Accept = "application/vnd.pub.v2+json", ["User-Agent"] = "vfox-pub" },
    })
    if err then
        error("pub.dev request failed for " .. tool .. ": " .. tostring(err))
    end
    if resp.status_code == 404 then
        error("package '" .. tool .. "' was not found on pub.dev")
    end
    if resp.status_code ~= 200 then
        error("pub.dev returned status " .. resp.status_code .. " for " .. tool)
    end

    local versions = {}
    for _, v in ipairs(json.decode(resp.body).versions) do
        if not v.retracted then
            table.insert(versions, v.version)
        end
    end
    return { versions = versions }
end
