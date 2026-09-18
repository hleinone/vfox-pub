local cmd = require("cmd")
local file = require("file")
local pub = require("pub")

function PLUGIN:BackendInstall(ctx)
    local tool = pub.validate_tool(ctx.tool)
    local version = pub.validate_version(ctx.version)
    local install_path = ctx.install_path

    cmd.exec("dart pub global activate " .. tool .. " " .. version, { env = { PUB_CACHE = install_path } })

    local bin_dir = file.join_path(install_path, "bin")
    if not file.exists(bin_dir) then
        error("package '" .. tool .. "' has no executables")
    end
    -- pub launchers fall back to `dart pub global run` when the Dart SDK changes (exit 253).
    -- That fallback reads PUB_CACHE from the environment, so pin it inside each launcher.
    for _, launcher in ipairs(file.list(bin_dir)) do
        pub.pin_pub_cache(launcher, install_path)
    end
    return {}
end
