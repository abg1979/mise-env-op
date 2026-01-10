local cmd = require("cmd")

function PLUGIN:MiseEnv(ctx)
    local secrets = ctx.options.secrets or {}
    local env = {}

    for key, ref in pairs(secrets) do
        -- Let errors propagate (fail loudly) so user knows to run `op signin`
        local value = cmd.exec("op read " .. ref)
        table.insert(env, {key = key, value = value:gsub("%s+$", "")})
    end

    return env
end
