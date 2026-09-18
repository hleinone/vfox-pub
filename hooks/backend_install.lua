local cmd = require("cmd")
local file = require("file")
local pub = require("pub")

function PLUGIN:BackendInstall(ctx)
    local tool = pub.validate_tool(ctx.tool)
    local version = pub.validate_version(ctx.version)
    local pub_cache = pub.pub_cache(ctx.install_path)

    cmd.exec("dart pub global activate " .. tool .. " " .. version, { env = { PUB_CACHE = pub_cache } })

    local launchers = file.join_path(pub_cache, "bin")
    if not file.exists(launchers) then
        error("package '" .. tool .. "' has no executables")
    end
    for _, launcher in ipairs(file.list(launchers)) do
        pub.write_wrapper(ctx.install_path, launcher)
    end
    return {}
end
