local cmd = require("cmd")
local file = require("file")
local http = require("http")
local json = require("json")

local WINDOWS = RUNTIME.osType == "windows"

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

local function validate_name(kind, name, tool)
    if type(name) ~= "string" or not name:match("^[%w_%-%.]+$") then
        error("unsupported " .. kind .. " name '" .. tostring(name) .. "' in package '" .. tool .. "'")
    end
    return name
end

function M.package(tool)
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
    return json.decode(resp.body)
end

-- Maps each executable of one version to its bin/ script. A JSON null script, which
-- decodes to a non-string sentinel, means the script has the executable's name.
function M.executables(package, tool, version)
    for _, v in ipairs(package.versions or {}) do
        if v.version == version then
            local declared = v.pubspec and v.pubspec.executables
            if type(declared) ~= "table" or next(declared) == nil then
                error("package '" .. tool .. "' " .. version .. " declares no executables")
            end
            local map = {}
            for exe, script in pairs(declared) do
                if type(script) ~= "string" then
                    script = exe
                end
                map[validate_name("executable", exe, tool)] = validate_name("script", script, tool)
            end
            return map
        end
    end
    error("version " .. version .. " of package '" .. tool .. "' was not found on pub.dev")
end

function M.pub_cache(install_path)
    return file.join_path(install_path, "pub-cache")
end

local function sh_quote(s)
    return "'" .. s:gsub("'", "'\\''") .. "'"
end

-- The wrapper runs `dart pub global run` itself instead of pub's launcher: pub rewrites
-- its launchers whenever it rebuilds a snapshot, and it embeds the cache path in them
-- without quoting. pub finds and rebuilds the snapshot on its own.
--
-- The .bat variant derives the cache path from its own location. pub, cmd and Lua
-- disagree about the encoding of a non-ASCII path, and `%~dp0` never leaves cmd.
-- setlocal keeps PUB_CACHE out of the calling cmd session and fixes the parse mode.
-- dart may be a .cmd shim, and a batch file run without CALL would end this file and
-- its setlocal scope, so CALL is required. CALL expands percent signs in the arguments
-- a second time; pub's own launcher has the same behaviour.
local function wrapper(target, pub_cache)
    if WINDOWS then
        return table.concat({
            "@echo off",
            "setlocal DisableDelayedExpansion",
            'for %%I in ("%~dp0..") do set "PUB_CACHE=%%~fI\\pub-cache"',
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

-- The shell writes the wrapper, with name and content passed as environment variables:
-- no path or content goes through shell quoting, and Lua's io library, which opens
-- paths in the ANSI code page on Windows, is not involved.
function M.write_wrapper(install_path, tool, exe, script)
    local bin = file.join_path(install_path, "bin")
    if not file.exists(bin) then
        cmd.exec("mkdir bin", { cwd = install_path })
    end
    local env = {
        VFOX_PUB_NAME = WINDOWS and exe .. ".bat" or exe,
        VFOX_PUB_CONTENT = wrapper(tool .. ":" .. script, M.pub_cache(install_path)),
    }
    if WINDOWS then
        cmd.exec(
            'powershell -NoProfile -NonInteractive -Command "[IO.File]::WriteAllText($env:VFOX_PUB_NAME, $env:VFOX_PUB_CONTENT, [Text.Encoding]::ASCII)"',
            { cwd = bin, env = env }
        )
    else
        cmd.exec(
            'printf "%s" "$VFOX_PUB_CONTENT" > "$VFOX_PUB_NAME" && chmod +x "$VFOX_PUB_NAME"',
            { cwd = bin, env = env }
        )
    end
end

return M
