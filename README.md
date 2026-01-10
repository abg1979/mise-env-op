# mise-env-op

A [mise](https://mise.jdx.dev/) environment plugin that fetches secrets from 1Password at shell activation time. Secrets are loaded directly into environment variables and never written to disk.

## Requirements

- [mise](https://mise.jdx.dev/) with environment plugin support
- [1Password CLI](https://developer.1password.com/docs/cli/) (`op`) installed and authenticated

## Installation

```bash
mise plugin install mise-env-op https://github.com/kennyp/mise-env-op
```

## Configuration

In your `mise.toml`:

```toml
[env._.mise-env-op.secrets]
MY_API_KEY = "op://vault/item/field"
DATABASE_URL = "op://vault/database/connection_string"
```

The `secrets` table maps environment variable names to 1Password secret references.

## Usage

Once configured, secrets are automatically loaded when mise activates your environment:

```bash
cd my-project
echo $MY_API_KEY  # fetched from 1Password
```

## Error Handling

If your 1Password session has expired, the plugin will fail loudly so you know to re-authenticate:

```bash
op signin
```

## License

MIT
