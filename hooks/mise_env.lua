local cmd = require("cmd")

function PLUGIN:MiseEnv(ctx)
    local secrets = ctx.options.secrets or {}
    local env = {}
    local expected = {}

    -- Build template for op inject: KEY={{ op://ref }}
    local template_lines = {}
    for key, ref in pairs(secrets) do
        expected[key] = ref
        table.insert(template_lines, key .. "={{ " .. ref .. " }}")
    end

    if #template_lines == 0 then
        return env
    end

    -- Single op inject call for all secrets
    local template = table.concat(template_lines, "\n")
    local output = cmd.exec("printf '%s' '" .. template:gsub("'", "'\\''") .. "' | op inject")

    -- Parse output: KEY=value
    local found = {}
    for line in output:gmatch("[^\n]+") do
        local k, v = line:match("^([^=]+)=(.*)$")
        if k and v then
            found[k] = true
            -- Check for unresolved template (op inject leaves {{ }} on error)
            if v:match("^{{.*}}$") then
                io.stderr:write("[mise-env-op] failed to resolve: " .. k .. " (" .. expected[k] .. ")\n")
            else
                table.insert(env, {key = k, value = v})
            end
        end
    end

    -- Warn about completely missing keys
    for key, ref in pairs(expected) do
        if not found[key] then
            io.stderr:write("[mise-env-op] missing from output: " .. key .. " (" .. ref .. ")\n")
        end
    end

    return env
end
