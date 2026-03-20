# CLI Usage

Use the skill's wrapper script so the invocation stays tied to this repo:

```bash
./scripts/publish.sh <path> [flags...]
```

## Login

Run this when the CLI has not been configured yet:

```bash
./scripts/publish.sh login
```

The CLI stores its config in `~/.config/knyle-share/config.json` by default.

## Common Flags

- `--slug SLUG`: set the bundle slug explicitly
- `--replace`: replace an existing bundle without a replacement prompt
- `--public`: publish as a public bundle
- `--protected`: publish as a protected bundle
- `--password PASSWORD`: use a custom password for a protected bundle
- `--generate-password`: generate a three-word password
- `--link-expiration 1_day|1_week|1_month`: generate an expiring link after upload
- `--json`: print machine-readable JSON instead of interactive copy prompts

## Examples

Public folder:

```bash
./scripts/publish.sh ./site --public
```

Protected markdown file with generated password:

```bash
./scripts/publish.sh "./Summer in the Sierra.md" --protected --generate-password
```

Replace an existing slug and mint a one-week link:

```bash
./scripts/publish.sh ./site --slug poke-recipes --replace --protected --generate-password --link-expiration 1_week
```
