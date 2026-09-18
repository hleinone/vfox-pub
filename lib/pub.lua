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

-- pub writes a POSIX sh launcher on Linux and macOS and a .bat launcher on Windows.
local function pin_line(first_line, pub_cache)
    if first_line:match("^#!") then
        return 'export PUB_CACHE="' .. pub_cache .. '"'
    end
    if first_line:lower():match("^@echo off%s*$") then
        return 'set "PUB_CACHE=' .. pub_cache .. '"'
    end
    return nil
end

function M.pin_pub_cache(launcher, pub_cache)
    local content = file.read(launcher)
    local first, rest = content:match("^([^\n]*)\n(.*)$")
    if not first then
        return
    end
    local eol = first:match("\r$") and "\r\n" or "\n"
    local line = pin_line(first:gsub("\r$", ""), pub_cache)
    if not line then
        return
    end
    local out = assert(io.open(launcher, "wb"))
    out:write(first, "\n", line, eol, rest)
    out:close()
end

return M
