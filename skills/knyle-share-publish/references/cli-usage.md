# CLI Usage

```bash
knyle-share <path> [flags...]
```

## Login

Run this when the CLI has not been configured yet:

```bash
knyle-share login
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
knyle-share ./site --public
```

Protected markdown file with generated password:

```bash
knyle-share "./Summer in the Sierra.md" --protected --generate-password
```

Replace an existing slug and mint a one-week link:

```bash
knyle-share ./site --slug poke-recipes --replace --protected --generate-password --link-expiration 1_week
```
