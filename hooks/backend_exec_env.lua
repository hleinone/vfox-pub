local file = require("file")

function PLUGIN:BackendExecEnv(ctx)
    return {
        env_vars = {
            { key = "PATH", value = file.join_path(ctx.install_path, "bin") },
        },
    }
end
