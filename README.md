# Knyle Share

Knyle Share is a Rails app for publishing private or public bundles on a public host while keeping administration on a separate admin host.

Current implemented slice:

- admin/public host split with host-constrained routing
- first-run setup validation
- GitHub OAuth admin claim and sign-in
- real admin bundle management
- public bundle delivery with password and signed-link access
- upload processing and publish pipeline
- private API and local CLI publishing flow

## Requirements

- Ruby `3.4.2`
- Bundler
- SQLite 3
- An AWS S3 bucket for setup validation
- A GitHub OAuth app for admin sign-in

Node is not required for local development. The app currently uses importmap and server-rendered Rails views.

## Local Setup

### 1. Create the GitHub OAuth app

For local development, configure the GitHub OAuth app with:

- Homepage URL: `http://admin.lvh.me:3000`
- Authorization callback URL: `http://admin.lvh.me:3000/auth/github/callback`
- Leave `Enable Device Flow` unchecked. Knyle Share uses the standard web OAuth redirect flow, not GitHub's device flow.

If you run Rails on a different port, update the callback URL to match.

### 2. Create the S3 bucket and AWS credentials

Create:

- a private S3 bucket for Knyle Share
- an IAM user or IAM access key pair the app can use

When creating the bucket:

- Leave `Block all public access` enabled.
- Do not configure the bucket for static website hosting.

Knyle Share is designed to keep the S3 bucket private and serve content through the application, not directly from a public S3 bucket.

For the IAM setup, the simplest path is:

1. Open IAM in AWS.
2. Create a customer-managed policy with this JSON, replacing `YOUR_BUCKET_NAME`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "BucketAccess",
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket",
        "s3:GetBucketLocation"
      ],
      "Resource": "arn:aws:s3:::YOUR_BUCKET_NAME"
    },
    {
      "Sid": "ObjectAccess",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject"
      ],
      "Resource": "arn:aws:s3:::YOUR_BUCKET_NAME/*"
    }
  ]
}
```

3. Create an IAM user for Knyle Share.
4. Leave console access disabled for that user.
5. On the permissions step, choose `Attach policies directly`.
6. Attach only the customer-managed policy you just created for the Knyle Share bucket.
7. Do not add the user to an existing broad-access group like backups, and do not grant `AmazonS3FullAccess`.
8. After the user is created, open the user and create an access key.
9. On the access key use-case screen, choose `Application running outside AWS`. Knyle Share runs outside AWS, and this is the closest match. `Local code` is also fine for local-only development. This choice does not change the IAM permissions on the key.
10. Save the access key ID and secret access key immediately. AWS only shows the secret once.

Do not create or use root account access keys for this app.

The current setup validator needs S3 permissions to:

- check bucket access
- upload an object
- read that object back
- delete that object

At minimum, make sure the credentials can perform `s3:ListBucket`, `s3:GetObject`, `s3:PutObject`, and `s3:DeleteObject` for the configured bucket.

### 3. Create your local env file

Copy the template:

```sh
cp .env.example .env
```

Then fill in the GitHub and AWS values in `.env`.

The app now loads `.env` automatically in development and test via `dotenv-rails`, so you do not need to export these variables manually in your shell.

### 4. Configure environment variables

Your local `.env` should contain:

```sh
ADMIN_HOST=admin.lvh.me
PUBLIC_HOST=share.lvh.me
AWS_ACCESS_KEY_ID=your-access-key-id
AWS_SECRET_ACCESS_KEY=your-secret-access-key
AWS_REGION=us-west-2
S3_BUCKET=your-bucket-name
PUBLIC_ASSET_REDIRECT_TTL_SECONDS=300
INLINE_MARKDOWN_RENDER_MAX_BYTES=1048576
GITHUB_CLIENT_ID=your-github-oauth-client-id
GITHUB_CLIENT_SECRET=your-github-oauth-client-secret
```

For the AWS S3 values:

- `AWS_ACCESS_KEY_ID`
  Use the access key ID created for the Knyle Share IAM user.
- `AWS_SECRET_ACCESS_KEY`
  Use the secret access key created at the same time as the access key ID. AWS only shows this once.
- `AWS_REGION`
  Use the AWS region where your bucket lives, for example `us-west-2`. This must match the bucket's region exactly or setup validation will fail with a bucket region mismatch.
- `S3_BUCKET`
  Use the bucket name only, for example `knyle-share-files`. Do not use an S3 URL, ARN, or `s3://` prefix.
- `PUBLIC_ASSET_REDIRECT_TTL_SECONDS`
  Optional. How long public asset and download redirects stay valid, in seconds. The default is `300`.
- `INLINE_MARKDOWN_RENDER_MAX_BYTES`
  Optional. Markdown files larger than this stay downloadable, but the app stops rendering them inline. The default is `1048576` bytes.

Notes:

- `lvh.me` resolves to `127.0.0.1`, so you do not need to edit `/etc/hosts`.
- Every bundle is served from its own subdomain like `my-bundle.share.lvh.me`. The base `PUBLIC_HOST` stays reserved for the public root threshold page.
- `lvh.me` resolves to `127.0.0.1` and supports wildcard subdomains automatically, so this works locally without extra DNS setup.
- Setup validation will fail until all of the variables above are present.
- Setup validation also performs a real S3 write, read, and delete cycle. Use credentials and a bucket that allow those operations.

### 5. Run the app setup

```sh
bin/setup
```

`bin/setup` will:

- install gems
- prepare the database
- clear old logs and temp files
- start the Rails server
- copy `.env.example` to `.env` first if you have not created `.env` yet

The development database lives at [storage/development.sqlite3](/Users/kneath/code/kneath/knyle-share/storage/development.sqlite3).

Then open:

- Admin: [http://admin.lvh.me:3000](http://admin.lvh.me:3000)
- Public host: [http://share.lvh.me:3000](http://share.lvh.me:3000)

## First-Run Flow

1. Visit the admin host.
2. The app should redirect to `/setup`.
3. Run setup validation.
4. Once all checks pass, sign in with GitHub.
5. The first successful GitHub login claims the installation admin.
6. After claim, only that same GitHub identity can sign in again.

The setup validator currently checks:

- required environment variables
- database connectivity
- pending migrations
- S3 configuration presence
- S3 bucket reachability
- S3 write/read/delete round trip

## Running Tests

Run the full suite with:

```sh
bundle exec rails test
```

The current tests cover:

- `Installation`
- `SetupValidation`
- admin auth and bundle management
- public bundle delivery
- upload ingest and replacement
- private API token auth and upload processing

## Useful Endpoints

- Admin root: `/` on `ADMIN_HOST`
- Public root: `/` on `PUBLIC_HOST`
- All bundles: `/` on `slug.PUBLIC_HOST`
- Health check: `/up`

## Production Notes

Production is currently set up for SQLite on a persistent disk plus S3 object storage.

Relevant production env vars:

- `SECRET_KEY_BASE`
- `ADMIN_HOST`
- `PUBLIC_HOST`
- `DATABASE_PATH` optional, defaults to `storage/production.sqlite3`
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `AWS_REGION`
- `S3_BUCKET`
- `PUBLIC_ASSET_REDIRECT_TTL_SECONDS` optional, defaults to `300`
- `INLINE_MARKDOWN_RENDER_MAX_BYTES` optional, defaults to `1048576`
- `GITHUB_CLIENT_ID`
- `GITHUB_CLIENT_SECRET`

The current implementation expects the S3 bucket to be reachable from the app and the GitHub OAuth callback to point at the admin host.
Public downloads and nested assets are served by short-lived presigned S3 URLs after the app authorizes access, so the bucket stays private while large asset bodies stay off the Rails process.
`PUBLIC_HOST` is the base public domain, not the domain of an individual bundle. Every bundle is served from `slug.PUBLIC_HOST`, so production deployments need wildcard DNS and TLS coverage for `*.PUBLIC_HOST`.

For production, keep using real environment variables in Render rather than a repo-local `.env` file.

### Public DNS

Knyle Share now expects three public DNS entry points:

- `ADMIN_HOST`
  Example: `admin.example.com`
- `PUBLIC_HOST`
  Example: `share.example.com`
- `*.PUBLIC_HOST`
  Example: `*.share.example.com`

There are no extra environment variables for bundle subdomains. The app derives each bundle host from the bundle slug plus `PUBLIC_HOST`.

At the DNS provider, point all three names at the same Render service:

- `admin.example.com`
- `share.example.com`
- `*.share.example.com`

How you do that depends on your DNS provider:

- If Render gives you a hostname target, use `CNAME` or the provider's `ALIAS`/`ANAME` equivalent where appropriate.
- If your DNS provider requires explicit records for wildcard coverage, create both the base public host and the wildcard public host.

TLS must also cover both the base public host and the wildcard bundle hosts.

## Render Deploy

This repo now includes [render.yaml](/Users/kneath/code/kneath/knyle-share/render.yaml) for the default deployment shape:

- one Ruby web service
- one persistent disk mounted at `/var/data`
- SQLite at `/var/data/production.sqlite3`
- one Puma process
- `/up` as the health check

Recommended deploy flow:

1. Create the AWS S3 bucket and IAM credentials.
2. Create the GitHub OAuth app.
3. In Render, create a new Blueprint service from this repo.
4. Set the required env vars:
   - `ADMIN_HOST`
   - `PUBLIC_HOST`
   - `AWS_ACCESS_KEY_ID`
   - `AWS_SECRET_ACCESS_KEY`
   - `AWS_REGION`
   - `S3_BUCKET`
   - `GITHUB_CLIENT_ID`
   - `GITHUB_CLIENT_SECRET`
5. Attach the persistent disk.
6. Add public domains to the same Render service:
   - one admin domain, for example `admin.example.com`
   - one public domain, for example `share.example.com`
   - wildcard public subdomains for bundle hosts, for example `*.share.example.com`
7. Make sure `admin.example.com`, `share.example.com`, and `*.share.example.com` all point at the same Render service and have working TLS.
8. Update the GitHub OAuth app to use the production admin domain:
   - Homepage URL: `https://ADMIN_HOST`
   - Callback URL: `https://ADMIN_HOST/auth/github/callback`
9. Deploy.
10. Visit the admin host and run the first-run setup validation before claiming the admin account.

Notes:

- `SECRET_KEY_BASE` is generated automatically by `render.yaml`.
- Keep `WEB_CONCURRENCY=1` with SQLite on a single Render disk.
- The admin domain, `PUBLIC_HOST`, and `*.PUBLIC_HOST` should all point at the same Render web service. Host-constrained routes split admin, the threshold page, and bundle delivery inside the app.

## API Tokens

The private API uses Bearer tokens, not admin browser sessions.

Create a token from the admin UI:

1. Sign in on the admin host.
2. Open `API Tokens`.
3. Create a token with a descriptive label.
4. Copy the plaintext token immediately. It is shown only once.

If you lose the plaintext token, revoke it and create a new one. Only the digest is saved in the database.

## CLI

The repo now includes a local CLI at [bin/knyle-share](/Users/kneath/code/kneath/knyle-share/bin/knyle-share).

First, save your admin host and token:

```sh
bin/knyle-share login
```

That writes a local CLI config file under `~/.config/knyle-share/config.json` by default. You can also override configuration with:

- `KNYLE_SHARE_ADMIN_URL`
- `KNYLE_SHARE_API_TOKEN`

Basic usage:

```sh
bin/knyle-share ./site --public
bin/knyle-share "./Summer in the Sierra.md" --protected --generate-password
bin/knyle-share ./site --slug poke-recipes --replace --public
```

Useful flags:

- `--slug SLUG`
- `--replace`
- `--public`
- `--protected`
- `--password PASSWORD`
- `--generate-password`
- `--link-expiration 1_day|1_week|1_month`
- `--json`

For directory uploads, the CLI automatically creates a `.tar.gz` archive before uploading it to the API.

Use it like this:

```sh
curl \
  -H "Authorization: Bearer YOUR_TOKEN" \
  "https://ADMIN_HOST/api/v1/bundles/availability?slug=example-bundle"
```
