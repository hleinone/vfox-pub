local file = require("file")

local M = {}

function M.validate_tool(tool)
    if type(tool) ~= "string" or not tool:match("^[a-z_][a-z0-9_]*$") then
        error("invalid pub package name: " .. tostring(tool))
    end
    return tool
end

function M.validate_version(version)
    if type(version) ~= "string" or not version:match("^[%w%.%+%-]+$") then
        error("invalid pub package version: " .. tostring(version))
    end
    return version
end

function M.pin_pub_cache(launcher, pub_cache)
    local content = file.read(launcher)
    local shebang, rest = content:match("^(#![^\n]*)\n(.*)$")
    if not shebang then
        return
    end
    local out = assert(io.open(launcher, "w"))
    out:write(shebang, "\n", 'export PUB_CACHE="', pub_cache, '"\n', rest)
    out:close()
end

return M
