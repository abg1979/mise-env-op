local cmd = require("cmd")

local function ref_key(key)
    return "_MISE_ENV_OP_REF_" .. key
end

function PLUGIN:MiseEnv(ctx)
    -- Validate options
    if not ctx.options then
        error("[mise-env-op] no options configured in mise.toml")
    end
    if not ctx.options.secrets then
        error("[mise-env-op] 'secrets' is required in mise.toml configuration")
    end
    if type(ctx.options.secrets) ~= "table" then
        error("[mise-env-op] 'secrets' must be a table")
    end

    local secrets = ctx.options.secrets

    -- Optional account for multi-account 1Password setups
    local account = ctx.options.account

    local env = {}
    local expected = {}
    local needs_fetch = {}

    -- Build template, but skip secrets already in environment with same ref
    local template_lines = {}
    for key, ref in pairs(secrets) do
        -- Respect false: skip this key entirely
        if ref == false then
            -- Do nothing - don't set, don't fetch
        else
            local existing_val = os.getenv(key)
            local existing_ref = os.getenv(ref_key(key))

            if existing_val and existing_val ~= "" and existing_ref == ref then
                -- Already set with same ref, reuse it
                table.insert(env, {key = key, value = existing_val})
                table.insert(env, {key = ref_key(key), value = ref})
            else
                expected[key] = ref
                needs_fetch[key] = true
                table.insert(template_lines, key .. "={{ " .. ref .. " }}")
            end
        end
    end

    if #template_lines == 0 then
        return env
    end

    -- Single op inject call for all secrets
    local template = table.concat(template_lines, "\n")
    local op_cmd = "printf '%s' '" .. template:gsub("'", "'\\''") .. "' | op inject"
    if account then
        op_cmd = op_cmd .. " --account " .. account
    end

    local success, output = pcall(cmd.exec, op_cmd)
    if not success then
        error("[mise-env-op] op inject failed - are you signed in? Try: op signin" ..
              (account and (" --account " .. account) or ""))
    end

    -- Parse output: KEY=value
    local found = {}
    for line in output:gmatch("[^\n]+") do
        local k, v = line:match("^([^=]+)=(.*)$")
        if k and v and needs_fetch[k] then
            found[k] = true
            -- Check for unresolved template (op inject leaves {{ }} on error)
            if v:match("^{{.*}}$") then
                io.stderr:write("[mise-env-op] failed to resolve: " .. k .. " (" .. expected[k] .. ")\n")
            else
                table.insert(env, {key = k, value = v})
                -- Store the ref so we can detect changes in child directories
                table.insert(env, {key = ref_key(k), value = expected[k]})
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
