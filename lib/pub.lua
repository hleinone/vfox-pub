local cmd = require("cmd")
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

function M.pub_cache(install_path)
    return file.join_path(install_path, "pub-cache")
end

-- pub rewrites its own launchers whenever it rebuilds a snapshot, so the PUB_CACHE
-- setting lives in a wrapper under <install_path>/bin that pub never touches.
-- pub writes .bat launchers on Windows and sh launchers elsewhere.
local function wrapper(name, pub_cache)
    if name:match("%.bat$") then
        return table.concat({
            "@echo off",
            'set "PUB_CACHE=' .. pub_cache .. '"',
            'call "%PUB_CACHE%\\bin\\' .. name .. '" %*',
            "exit /b %errorlevel%",
            "",
        }, "\r\n")
    end
    return table.concat({
        "#!/usr/bin/env sh",
        'export PUB_CACHE="' .. pub_cache .. '"',
        'exec "$PUB_CACHE/bin/' .. name .. '" "$@"',
        "",
    }, "\n")
end

function M.write_wrapper(install_path, launcher)
    local name = launcher:match("[^/\\]+$")
    local bin = file.join_path(install_path, "bin")
    if not file.exists(bin) then
        cmd.exec('mkdir "' .. bin .. '"')
    end
    local path = file.join_path(bin, name)
    local out = assert(io.open(path, "wb"))
    out:write(wrapper(name, M.pub_cache(install_path)))
    out:close()
    if not name:match("%.bat$") then
        cmd.exec('chmod +x "' .. path .. '"')
    end
end

return M
