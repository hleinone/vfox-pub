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

-- Inside `set "..."` cmd still expands `%`; `!` is literal because delayed expansion is off.
local function bat_literal(s)
    return (s:gsub("%%", "%%%%"))
end

-- pub writes the bin/ script that an executable maps to into every launcher header.
local function script_name(launcher)
    local content = file.read(launcher)
    local script = content:match("\n#%s*Script:%s*([^\r\n]+)") or content:match("\nrem%s+Script:%s*([^\r\n]+)")
    if not script then
        error("cannot read the script name from " .. launcher)
    end
    script = script:gsub("%s+$", "")
    if not script:match("^[%w_%-%.]+$") then
        error("unsupported script name '" .. script .. "' in " .. launcher)
    end
    return script
end

-- The wrapper runs `dart pub global run` itself instead of pub's launcher: pub rewrites
-- its launchers whenever it rebuilds a snapshot, and it embeds the cache path in them
-- without quoting. pub finds and rebuilds the snapshot on its own.
--
-- In the .bat variant, setlocal keeps PUB_CACHE out of the calling cmd session and
-- fixes the expansion mode. dart may be a .cmd shim, and a batch file run without CALL
-- would end this file and its setlocal scope, so CALL is required. CALL expands percent
-- signs in the arguments a second time; pub's own launcher has the same behaviour.
local function wrapper(tool, script, pub_cache, bat)
    local target = tool .. ":" .. script
    if bat then
        return table.concat({
            "@echo off",
            "setlocal DisableDelayedExpansion",
            'set "PUB_CACHE=' .. bat_literal(pub_cache) .. '"',
            "call dart pub global run " .. target .. " %*",
            "exit /b %errorlevel%",
            "",
        }, "\r\n")
    end
    return table.concat({
        "#!/usr/bin/env sh",
        "export PUB_CACHE=" .. sh_quote(pub_cache),
        "exec dart pub global run " .. sh_quote(target) .. ' "$@"',
        "",
    }, "\n")
end

function M.write_wrapper(install_path, tool, launcher)
    local name = launcher:match("[^/\\]+$")
    local bat = name:match("%.bat$") ~= nil
    local bin = file.join_path(install_path, "bin")
    -- Relative names with cwd keep the install path out of shell command text.
    if not file.exists(bin) then
        cmd.exec("mkdir bin", { cwd = install_path })
    end
    local path = file.join_path(bin, name)
    local out = assert(io.open(path, "wb"))
    out:write(wrapper(tool, script_name(launcher), M.pub_cache(install_path), bat))
    out:close()
    if not bat then
        cmd.exec("chmod +x " .. sh_quote(name), { cwd = bin })
    end
end

return M
