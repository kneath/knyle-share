# Knyle Share

Knyle Share is a little app designed to share bundles to the internet — markdown files, images, audio files, videos, or even small static sites. You can upload them from your computer with a CLI, the included LLM Skill, or from the web admin panel. 

It's an easy way to get things off your computer onto the internet, hosted by you on your servers and your domains.

Here are a couple of examples:

- I had this markdown file on my computer called [`Principles of Adult Behavior.md`](https://principles-of-adult-behavior.share.warpspire.com/) and I wanted to share it to a friend.
- I also wanted to show you how I uploaded it, so I [uploaded a screenshot](https://principles-terminal-screen.share.warpspire.com/) with a password `principled` so it wasn't publicly accessible.

It was mostly written by robots. It started with [an idea](shaping/Idea.md), which I used to get the robots to write out a [spec](shaping/Spec.md). I also got the robots to write a [technical preferences](TECHNICAL_PREFERENCES.md) doc based on the way I like to write web apps. They made a [plan](sausage/PLAN.md) and built the app with my guidance. Along the way, I've had the robots document their [performance](sausage/PERFORMANCE_FINDINGS.md) and [security](sausage/SECURITY_FINDINGS.md) findings.

I mostly built this for me, but maybe you'll find it interesting too.

## Requirements

- Ruby `3.4.2`
- Bundler
- SQLite 3
- An AWS S3 bucket for setup validation
- A GitHub OAuth app for admin sign-in

## Local Setup

### 1. Create the GitHub OAuth app

For local development, configure the GitHub OAuth app with:

- Homepage URL: `http://admin.lvh.me:3000`
- Authorization callback URL: `http://admin.lvh.me:3000/auth/github/callback`
- Leave `Enable Device Flow` unchecked. Knyle Share uses the standard web OAuth redirect flow, not GitHub's device flow.

If you run Rails on a different port, update the callback URL to match.

### 2. Create the S3 bucket and AWS credentials

Create:

- A private S3 bucket for Knyle Share
- An IAM user or IAM access key pair the app can use

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

- Check bucket access
- Upload an object
- Read that object back
- Delete that object

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

- Install gems
- Prepare the database
- Clear old logs and temp files
- Start the Rails server
- Copy `.env.example` to `.env` first if you have not created `.env` yet

The development database lives at `storage/development.sqlite3`.

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

- Required environment variables
- Database connectivity
- Pending migrations
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
- Admin auth and bundle management
- Public bundle delivery
- Upload ingest and replacement
- Private API token auth and upload processing

## Deployment Runbook

For detailed instructions on how to deploy this application, refer to the **[Deployment Runbook](docs/Deployment.md)**

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
- `SENTRY_DSN` optional, enables Sentry exception reporting
- `SENTRY_TRACES_SAMPLE_RATE` optional, defaults to `0`

Public downloads and nested assets are served by short-lived presigned S3 URLs after the app authorizes access, so the bucket stays private while large asset bodies stay off the Rails process.

`PUBLIC_HOST` is the base public domain, not the domain of an individual bundle. Every bundle is served from `slug.PUBLIC_HOST`, so production deployments need wildcard DNS and TLS coverage for `*.PUBLIC_HOST`.

### Public DNS

Knyle Share expects three public DNS entry points:

- `ADMIN_HOST`
  Example: `admin.example.com`
- `PUBLIC_HOST`
  Example: `share.example.com`
- `*.PUBLIC_HOST`
  Example: `*.share.example.com`

TLS must also cover both the base public host and the wildcard bundle hosts.

## API Tokens

The private API uses Bearer tokens, not admin browser sessions.

Create a token from the admin UI:

1. Sign in on the admin host.
2. Open `API Tokens`.
3. Create a token with a descriptive label.
4. Copy the plaintext token immediately. It is shown only once.

If you lose the plaintext token, revoke it and create a new one. Only the digest is saved in the database.

## CLI

The repo includes a local CLI at `bin/knyle-share`

To install it into `/usr/local/bin` as a symlink back to this repo:

```sh
sudo bin/install-cli
```

That installs `/usr/local/bin/knyle-share` and keeps it pointed at your current checkout, so pulling new code updates the installed CLI too.

You can also choose a different destination:

```sh
bin/install-cli --bin-dir "$HOME/.local/bin"
```

First, save your admin host and token:

```sh
knyle-share login
```

That writes a local CLI config file under `~/.config/knyle-share/config.json` by default. You can also override configuration with:

- `KNYLE_SHARE_ADMIN_URL`
- `KNYLE_SHARE_API_TOKEN`

Basic usage:

```sh
knyle-share ./site --public
knyle-share "./Summer in the Sierra.md" --protected --generate-password
knyle-share ./site --slug poke-recipes --replace --public
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
