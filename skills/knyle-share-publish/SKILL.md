---
name: knyle-share-publish
description: Delegate Knyle Share bundle publishing to the repo's CLI. Use when a user wants to share, publish, upload, or replace a local file or folder through Knyle Share, or when they want a share URL or expiring link for uploaded content.
---

# Knyle Share Publish

Use the repo's CLI instead of reimplementing upload logic or calling the private API directly.

## Workflow

1. Resolve the target path from the user's request or the current working directory.
2. If the target path is ambiguous or missing, ask a short clarifying question.
3. Run [`scripts/publish.sh`](./scripts/publish.sh) so the CLI handles slug validation, upload creation, direct S3 upload, publish, and link generation.
4. Prefer explicit CLI flags when the user already supplied enough information.
5. Use the CLI interactively when the user has not supplied enough information for access mode, replacement, or password choices.
6. Report the resulting share URL, generated password, and expiring link when applicable.

## Operating Rules

- Do not call the private upload API yourself when this skill applies.
- Do not duplicate slug validation, replacement checks, password generation, or signed-link creation in the prompt.
- If the CLI is not configured yet, run `bin/knyle-share login` through the wrapper script or ask the user for the missing admin URL and API token.
- If the user explicitly wants machine-readable output, add `--json` and return the parsed result.
- If the user already specified public vs protected access, use `--public` or `--protected`.
- If the user already supplied a password, use `--password`.
- If the user asked for a generated password, use `--generate-password`.
- If the user explicitly wants replacement without an interactive confirmation, use `--replace`.
- If the user asks for an expiring link after upload, use `--link-expiration` with one of `1_day`, `1_week`, or `1_month`.

## Command Pattern

Run the wrapper script from this skill:

```bash
./scripts/publish.sh <path> [flags...]
```

Use a TTY when interactive prompts are expected. Use a non-interactive command when all required details are already known.

Read [references/cli-usage.md](./references/cli-usage.md) when you need the flag mapping or example commands.
