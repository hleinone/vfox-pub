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

-- dart percent-decodes the script argument and the --packages value, so a `%` in a path
-- has to be sent as `%25`.
local function dart_arg(path)
    return (path:gsub("%%", "%%25"))
end

-- The wrapper runs a kernel snapshot that the plugin compiles itself, not pub's launcher
-- and not `dart pub global run`: pub prints status text to stdout while it rebuilds a
-- snapshot, which corrupts the output of tools such as protoc plugins. The compile step
-- writes to stderr only. With VFOX_PUB_COMPILE set, the wrapper compiles and exits, which
-- the install hook uses so that the first run is fast and compile errors surface early.
--
-- Every run passes --packages: the snapshot does not sit below a .dart_tool directory,
-- and without the flag Isolate.resolvePackageUri returns null for package assets.
--
-- The sh wrapper rebuilds when the VM rejects the snapshot with exit code 253, which it
-- does before it reads stdin.
local function sh_wrapper(install_path, tool, version, script)
    local pkg = "pub-cache/global_packages/" .. tool .. "/.dart_tool/package_config.json"
    local src = "pub-cache/hosted/pub.dev/" .. tool .. "-" .. version .. "/bin/" .. script .. ".dart"
    local encoded = dart_arg(install_path)
    return table.concat({
        "#!/usr/bin/env sh",
        "install=" .. sh_quote(install_path),
        'snapshot="$install/snapshots/' .. script .. '.dill"',
        "snapshot_arg=" .. sh_quote(encoded .. "/snapshots/" .. script .. ".dill"),
        "packages_arg=" .. sh_quote(encoded .. "/" .. pkg),
        'if [ -z "${VFOX_PUB_COMPILE:-}" ] && [ -f "$snapshot" ]; then',
        '    dart --packages="$packages_arg" "$snapshot_arg" "$@"',
        "    code=$?",
        '    [ "$code" -ne 253 ] && exit "$code"',
        "fi",
        'mkdir -p "$install/snapshots" || exit $?',
        'dart compile kernel --packages="$install/'
            .. pkg
            .. '" -o "$snapshot.$$" "$install/'
            .. src
            .. '" 1>&2 || exit $?',
        'mv -f "$snapshot.$$" "$snapshot" || exit $?',
        '[ -n "${VFOX_PUB_COMPILE:-}" ] && exit 0',
        'exec dart --packages="$packages_arg" "$snapshot_arg" "$@"',
        "",
    }, "\n")
end

-- The .bat wrapper derives every path from its own location, so it is pure ASCII and
-- cmd never decodes a path in a legacy code page. It contains no CALL, because CALL
-- expands percent signs a second time. dart may be a batch file (Flutter ships dart.bat),
-- and a batch file run without CALL ends this file, so the wrapper cannot act on dart's
-- exit code. It compares a stored SDK version instead and runs dart as its last line.
-- The compile runs through PowerShell, which passes the paths in environment variables
-- without a second cmd parse. setlocal keeps the variables out of the calling session.
--
-- Replacing `%` needs delayed expansion. The `endlocal & set` line carries the results
-- back into the scope where delayed expansion is off, which keeps `!` in the paths intact.
local function bat_wrapper(tool, version, script)
    local pkg = "pub-cache\\global_packages\\" .. tool .. "\\.dart_tool\\package_config.json"
    local src = "pub-cache\\hosted\\pub.dev\\" .. tool .. "-" .. version .. "\\bin\\" .. script .. ".dart"
    return table.concat({
        "@echo off",
        "setlocal DisableDelayedExpansion",
        'for %%I in ("%~dp0..") do set "VFOX_PUB_INSTALL=%%~fI"',
        'set "VFOX_PUB_SNAPSHOT=%VFOX_PUB_INSTALL%\\snapshots\\' .. script .. '.dill"',
        'set "VFOX_PUB_PACKAGES=%VFOX_PUB_INSTALL%\\' .. pkg .. '"',
        "setlocal EnableDelayedExpansion",
        'set "VFOX_PUB_ARG=!VFOX_PUB_SNAPSHOT:%%=%%25!"',
        'set "VFOX_PUB_PACKAGES_ARG=!VFOX_PUB_PACKAGES:%%=%%25!"',
        'endlocal & set "VFOX_PUB_ARG=%VFOX_PUB_ARG%" & set "VFOX_PUB_PACKAGES_ARG=%VFOX_PUB_PACKAGES_ARG%"',
        'for /f "tokens=1-4" %%A in (\'dart --version 2^>^&1\') do set "VFOX_PUB_SDK=%%A %%B %%C %%D"',
        'set "VFOX_PUB_BUILT="',
        'if exist "%VFOX_PUB_SNAPSHOT%.sdk" set /p VFOX_PUB_BUILT=<"%VFOX_PUB_SNAPSHOT%.sdk"',
        "if defined VFOX_PUB_COMPILE goto compile",
        'if not exist "%VFOX_PUB_SNAPSHOT%" goto compile',
        'if "%VFOX_PUB_BUILT%" == "%VFOX_PUB_SDK%" goto run',
        ":compile",
        'if not exist "%VFOX_PUB_INSTALL%\\snapshots" mkdir "%VFOX_PUB_INSTALL%\\snapshots"',
        'set "VFOX_PUB_SCRIPT=%VFOX_PUB_INSTALL%\\' .. src .. '"',
        'set "VFOX_PUB_TMP=%VFOX_PUB_SNAPSHOT%.%RANDOM%"',
        'powershell -NoProfile -NonInteractive -Command "& dart compile kernel --packages $env:VFOX_PUB_PACKAGES -o $env:VFOX_PUB_TMP $env:VFOX_PUB_SCRIPT; exit $LASTEXITCODE" 1>&2',
        "if %errorlevel% neq 0 exit /b %errorlevel%",
        'move /y "%VFOX_PUB_TMP%" "%VFOX_PUB_SNAPSHOT%" >nul || exit /b 1',
        '>"%VFOX_PUB_SNAPSHOT%.sdk" echo %VFOX_PUB_SDK%',
        "if defined VFOX_PUB_COMPILE exit /b 0",
        ":run",
        'dart --packages="%VFOX_PUB_PACKAGES_ARG%" "%VFOX_PUB_ARG%" %*',
        "",
    }, "\r\n")
end

-- The shell writes the wrapper, with name and content passed as environment variables:
-- no path or content goes through shell quoting, and Lua's io library, which opens
-- paths in the ANSI code page on Windows, is not involved.
local function write_wrapper(bin, name, content)
    local env = { VFOX_PUB_NAME = name, VFOX_PUB_CONTENT = content }
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

function M.install_executable(install_path, tool, version, exe, script)
    local bin = file.join_path(install_path, "bin")
    if not file.exists(bin) then
        cmd.exec("mkdir bin", { cwd = install_path })
    end
    local name = WINDOWS and exe .. ".bat" or exe
    local content = WINDOWS and bat_wrapper(tool, version, script) or sh_wrapper(install_path, tool, version, script)
    write_wrapper(bin, name, content)
    cmd.exec(WINDOWS and name or sh_quote("./" .. name), { cwd = bin, env = { VFOX_PUB_COMPILE = "1" } })
end

return M
