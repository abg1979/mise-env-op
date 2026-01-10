local cmd = require("cmd")

local function get_secrets_for_env(secrets_config)
    if not secrets_config then
        return nil
    end

    -- Check if secrets_config is a flat table (key = "op://...") or nested by environment
    local has_env_keys = false
    local has_op_refs = false
    for key, val in pairs(secrets_config) do
        if type(val) == "table" then
            has_env_keys = true
        elseif type(val) == "string" and val:match("^op://") then
            has_op_refs = true
        end
    end

    -- Flat structure: { KEY = "op://..." }
    if has_op_refs and not has_env_keys then
        return secrets_config
    end

    -- Nested structure: { development = { KEY = "op://..." }, production = { ... } }
    if has_env_keys then
        local mise_env = os.getenv("MISE_ENV") or "development"
        local env_secrets = secrets_config[mise_env]
        if env_secrets then
            return env_secrets
        end
        -- Fall back to "default" if current env not found
        if secrets_config["default"] then
            return secrets_config["default"]
        end
        io.stderr:write("[mise-env-op] no secrets for MISE_ENV=" .. mise_env .. " (and no 'default' fallback)\n")
        return nil
    end

    return nil
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

    -- Get secrets for current environment
    local secrets = get_secrets_for_env(ctx.options.secrets)
    if not secrets then
        return {}
    end

    -- Optional account for multi-account 1Password setups
    local account = ctx.options.account

    local env = {}
    local expected = {}
    local needs_fetch = {}

    -- Build template, but skip secrets already in environment
    local template_lines = {}
    for key, ref in pairs(secrets) do
        local existing = os.getenv(key)
        if existing and existing ~= "" then
            -- Already set, reuse it
            table.insert(env, {key = key, value = existing})
        else
            expected[key] = ref
            needs_fetch[key] = true
            table.insert(template_lines, key .. "={{ " .. ref .. " }}")
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
