local pub = require("pub")

function PLUGIN:BackendListVersions(ctx)
    local package = pub.package(pub.validate_tool(ctx.tool))
    local versions = {}
    for _, v in ipairs(package.versions or {}) do
        if not v.retracted then
            table.insert(versions, v.version)
        end
    end
    return { versions = versions }
end
