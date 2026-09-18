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

local function sh_quote(s)
    return "'" .. s:gsub("'", "'\\''") .. "'"
end

-- Inside `set "..."` cmd still expands `%`.
local function bat_literal(s)
    return (s:gsub("%%", "%%%%"))
end

-- With delayed expansion on, cmd also expands `!var!` and treats `^` as an escape.
local function bat_delayed_literal(s)
    return (bat_literal(s):gsub("%^", "^^"):gsub("!", "^!"))
end

-- pub rewrites its own launchers whenever it rebuilds a snapshot, so the PUB_CACHE
-- setting lives in a wrapper under <install_path>/bin that pub never touches.
-- pub writes .bat launchers on Windows and sh launchers elsewhere.
--
-- The .bat wrapper hands over to pub's launcher without CALL, because CALL expands
-- percent signs a second time, in the path and in the arguments. A user can enable
-- delayed expansion by default, and `endlocal` would restore that state before a
-- `set` on the same line runs, so the wrapper probes the mode with `"!" == ""` and
-- uses the escapes that mode needs.
local function wrapper(name, pub_cache)
    if name:match("%.bat$") then
        return table.concat({
            "@echo off",
            'if not "!" == "" goto plain',
            'set "PUB_CACHE=' .. bat_delayed_literal(pub_cache) .. '"',
            '"!PUB_CACHE!\\bin\\' .. bat_delayed_literal(name) .. '" %*',
            ":plain",
            'set "PUB_CACHE=' .. bat_literal(pub_cache) .. '"',
            '"%PUB_CACHE%\\bin\\' .. bat_literal(name) .. '" %*',
            "",
        }, "\r\n")
    end
    return table.concat({
        "#!/usr/bin/env sh",
        "export PUB_CACHE=" .. sh_quote(pub_cache),
        'exec "$PUB_CACHE/bin/"' .. sh_quote(name) .. ' "$@"',
        "",
    }, "\n")
end

function M.write_wrapper(install_path, launcher)
    local name = launcher:match("[^/\\]+$")
    local bin = file.join_path(install_path, "bin")
    -- Relative names with cwd keep the install path out of shell command text.
    if not file.exists(bin) then
        cmd.exec("mkdir bin", { cwd = install_path })
    end
    local path = file.join_path(bin, name)
    local out = assert(io.open(path, "wb"))
    out:write(wrapper(name, M.pub_cache(install_path)))
    out:close()
    if not name:match("%.bat$") then
        cmd.exec("chmod +x " .. sh_quote(name), { cwd = bin })
    end
end

return M
