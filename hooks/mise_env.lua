local cmd = require("cmd")

local log = {
    enabled = false,
}

function log.debug(msg)
    if log.enabled then
        io.stderr:write("[mise-env-op][debug] " .. msg .. "\n")
    end
end

local function ref_key(key)
    return "_MISE_ENV_OP_REF_" .. key
end

local function make_tempfile()
    local base = os.getenv("TEMP") or os.getenv("TMP") or "."
    local name = "mise-env-op-" .. tostring(os.time()) .. "-" .. tostring(math.random(10000, 99999)) .. ".tmpl"
    -- Ensure backslash separator on Windows
    return base .. "\\" .. name
end

function PLUGIN:MiseEnv(ctx)
    -- Enable debug logging from env var or config
    local env_debug = os.getenv("MISE_ENV_OP_DEBUG")
    local config_debug = ctx.options and ctx.options.debug
    log.enabled = (env_debug == "1" or env_debug == "true") or (config_debug == true or config_debug == "true")

    log.debug("start MiseEnv")

    -- Validate options
    if not ctx.options then
        log.debug("missing ctx.options")
        error("[mise-env-op] no options configured in mise.toml")
    end
    if not ctx.options.secrets then
        log.debug("missing ctx.options.secrets")
        error("[mise-env-op] 'secrets' is required in mise.toml configuration")
    end
    if type(ctx.options.secrets) ~= "table" then
        log.debug("ctx.options.secrets not a table")
        error("[mise-env-op] 'secrets' must be a table")
    end

    local secrets = ctx.options.secrets

    -- Optional account for multi-account 1Password setups
    local account = ctx.options.account
    if account then
        log.debug("using account: " .. tostring(account))
    else
        log.debug("no account specified")
    end

    local env = {}
    local expected = {}
    local needs_fetch = {}

    -- Build template, but skip secrets already in environment with same ref
    local template_lines = {}
    for key, ref in pairs(secrets) do
        log.debug("processing key: " .. tostring(key))

        -- Respect false: explicitly unset this key and its ref tracker
        if ref == false then
            log.debug("key set to false; unsetting: " .. tostring(key))
            table.insert(env, {key = key, value = ""})
            table.insert(env, {key = ref_key(key), value = ""})
        else
            local existing_val = os.getenv(key)
            local existing_ref = os.getenv(ref_key(key))

            log.debug("existing_val for " .. tostring(key) .. ": " .. tostring(existing_val))
            log.debug("existing_ref for " .. tostring(key) .. ": " .. tostring(existing_ref))

            -- Treat "false" string as unset (mise convention)
            if existing_val == "false" then
                log.debug("existing_val is 'false'; treating as unset for " .. tostring(key))
                existing_val = nil
            end

            if existing_val and existing_val ~= "" and existing_ref == ref then
                -- Already set with same ref, reuse it
                log.debug("reuse existing value for " .. tostring(key))
                table.insert(env, {key = key, value = existing_val})
                table.insert(env, {key = ref_key(key), value = ref})
            else
                log.debug("will fetch via op inject: " .. tostring(key) .. " -> " .. tostring(ref))
                expected[key] = ref
                needs_fetch[key] = true
                table.insert(template_lines, key .. "={{ " .. ref .. " }}")
            end
        end
    end

    if #template_lines == 0 then
        log.debug("no template lines; returning env")
        return env
    end

    -- Single op inject call for all secrets
    local template = table.concat(template_lines, "\n")
    log.debug("template built with " .. tostring(#template_lines) .. " lines")

    -- Cross-platform: write template to temp file and use op inject -i
    local tmp = make_tempfile()
    log.debug("writing template to temp file: " .. tostring(tmp))
    local f = assert(io.open(tmp, "w"))
    f:write(template)
    f:close()

    -- Normalize path for shell execution
    local tmp_arg = tmp:gsub("\\", "/")
    local op_cmd = "op inject -i " .. tmp_arg .. ""
    if account then
        op_cmd = op_cmd .. " --account " .. account
    end
    log.debug("executing op inject command - " .. tostring(op_cmd))

    local success, output = pcall(cmd.exec, op_cmd)

    -- Best-effort cleanup
    os.remove(tmp)

    if not success then
        log.debug("op inject failed\n" .. tostring(output))
        error("[mise-env-op] op inject failed - are you signed in? Try: op signin" ..
              (account and (" --account " .. account) or ""))
    end
    log.debug("op inject success; output length: " .. tostring(#output))

    -- Parse output: KEY=value
    local found = {}
    for line in output:gmatch("[^\n]+") do
        log.debug("parsing line: " .. line)
        local k, v = line:match("^([^=]+)=(.*)$")
        if k and v and needs_fetch[k] then
            found[k] = true
            log.debug("found key in output: " .. tostring(k))
            -- Check for unresolved template (op inject leaves {{ }} on error)
            if v:match("^{{.*}}$") then
                log.debug("failed to resolve: " .. k .. " (" .. expected[k] .. ")")
            else
                table.insert(env, {key = k, value = v})
                -- Store the ref so we can detect changes in child directories
                table.insert(env, {key = ref_key(k), value = expected[k]})
                log.debug("stored env for key: " .. tostring(k))
            end
        end
    end

    -- Warn about completely missing keys
    for key, ref in pairs(expected) do
        if not found[key] then
            log.debug("missing from output: " .. key .. " (" .. ref .. ")")
        end
    end

    log.debug("done MiseEnv; returning env entries: " .. tostring(#env))
    return env
end