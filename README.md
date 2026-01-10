# mise-env-op

A [mise](https://mise.jdx.dev/) environment plugin that fetches secrets from 1Password at shell activation time. Secrets are loaded directly into environment variables and never written to disk.

## Features

- Secrets stay in memory, never touch disk
- Single `op inject` call for all secrets (fast)
- Skips fetch if env var already set (nested shells are instant)
- Per-environment secrets (development, production, etc.)
- Multi-account 1Password support

## Requirements

- [mise](https://mise.jdx.dev/) with environment plugin support
- [1Password CLI](https://developer.1password.com/docs/cli/) (`op`) installed and authenticated

## Installation

```bash
mise plugin install mise-env-op https://github.com/kennyp/mise-env-op
```

## Configuration

### Basic usage

```toml
[env._.mise-env-op.secrets]
MY_API_KEY = "op://vault/item/field"
DATABASE_URL = "op://vault/database/connection_string"
```

### Multi-account 1Password

```toml
[env._.mise-env-op]
account = "my.1password.com"

[env._.mise-env-op.secrets]
MY_API_KEY = "op://vault/item/field"
```

### Per-environment secrets

Secrets can vary by `MISE_ENV`. Falls back to `default` if the current environment isn't found.

```toml
[env._.mise-env-op.secrets.default]
LOG_LEVEL = "op://vault/config/log_level"

[env._.mise-env-op.secrets.development]
API_KEY = "op://dev-vault/api/key"
DATABASE_URL = "op://dev-vault/db/url"

[env._.mise-env-op.secrets.production]
API_KEY = "op://prod-vault/api/key"
DATABASE_URL = "op://prod-vault/db/url"
```

## Performance

- All secrets are fetched in a single `op inject` call
- If an env var is already set (e.g., in a parent shell), the fetch is skipped
- Nested shells, tmux panes, and subshells reuse existing values instantly

## Error Handling

If your 1Password session has expired:

```
[mise-env-op] op inject failed - are you signed in? Try: op signin
```

If a secret reference is invalid:

```
[mise-env-op] failed to resolve: MY_KEY (op://vault/bad/path)
```

## License

MIT
