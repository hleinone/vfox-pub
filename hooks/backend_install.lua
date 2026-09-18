local cmd = require("cmd")
local pub = require("pub")

function PLUGIN:BackendInstall(ctx)
    local tool = pub.validate_tool(ctx.tool)
    local version = pub.validate_version(ctx.version)
    local executables = pub.executables(pub.package(tool), tool, version)

    cmd.exec(
        "dart pub global activate --no-executables " .. tool .. " " .. version,
        { env = { PUB_CACHE = pub.pub_cache(ctx.install_path) } }
    )
    for exe, script in pairs(executables) do
        pub.write_wrapper(ctx.install_path, tool, exe, script)
    end
    return {}
end
