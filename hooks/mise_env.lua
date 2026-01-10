local cmd = require("cmd")

function PLUGIN:MiseEnv(ctx)
    local secrets = ctx.options.secrets or {}
    local env = {}
    local keys = {}

    -- Build template for op inject: KEY={{ op://ref }}
    local template_lines = {}
    for key, ref in pairs(secrets) do
        table.insert(keys, key)
        table.insert(template_lines, key .. "={{ " .. ref .. " }}")
    end

    if #keys == 0 then
        return env
    end

    -- Single op inject call for all secrets
    local template = table.concat(template_lines, "\n")
    local output = cmd.exec("printf '%s' '" .. template:gsub("'", "'\\''") .. "' | op inject")

    -- Parse output: KEY=value
    for line in output:gmatch("[^\n]+") do
        local k, v = line:match("^([^=]+)=(.*)$")
        if k and v then
            table.insert(env, {key = k, value = v})
        end
    end

    return env
end
