# Deployment

This is the production deployment runbook for Knyle Share as the application exists today.

The default and documented production target is Render, using the checked-in [render.yaml](/Users/kneath/code/kneath/knyle-share/render.yaml) Blueprint. The app is built around:

- one Render Ruby web service
- one persistent disk mounted at `/var/data`
- SQLite stored at `/var/data/production.sqlite3`
- private S3 object storage for bundle contents
- GitHub OAuth for the admin sign-in flow
- host-based routing with separate admin and public hosts
- wildcard public subdomains for bundle delivery

If you follow this document in order, you should end with a working deployment that can accept uploads and serve bundles publicly.

## Deployment Model

| Piece | Current production shape |
| --- | --- |
| App server | Rails 8 on Puma |
| Ruby version | `3.4.2` |
| Database | SQLite on a Render persistent disk |
| Object storage | Private Amazon S3 bucket |
| Admin auth | GitHub OAuth app |
| Admin host | `ADMIN_HOST`, for example `admin.example.com` |
| Public root host | `PUBLIC_HOST`, for example `share.example.com` |
| Bundle hosts | `slug.PUBLIC_HOST`, for example `docs.share.example.com` |
| Health check | `/up` |

Important constraints:

- `ADMIN_HOST` and `PUBLIC_HOST` must be different hostnames.
- `PUBLIC_HOST` must support wildcard subdomains because every bundle is served from `slug.PUBLIC_HOST`.
- The deployment is intentionally single-instance today. Do not scale this service horizontally while it uses SQLite on one disk.
- A persistent disk disables zero-downtime deploys on Render. A deploy will briefly replace the running instance.

## 1. Preflight Checklist

Before touching production, make sure you have:

- a Git repo containing this project pushed to GitHub, GitLab, or Bitbucket
- a Render workspace
- a domain you control in DNS
- an AWS account that can create an S3 bucket and IAM credentials
- a GitHub account or organization where you can create an OAuth app
- local access to this repo so you can run verification commands and the CLI

Run the app test suite from the repo root before deploying:

```sh
bundle install
bundle exec rails test
```

Render-specific prerequisite:

- This app needs three custom domains on one web service: `ADMIN_HOST`, `PUBLIC_HOST`, and `*.PUBLIC_HOST`.
- Render's current docs say Hobby workspaces support only two custom domains total, while Professional and higher support unlimited custom domains.
- Use a Render workspace tier that can accommodate all three domains.

## 2. Pick Your Production Hostnames

Choose final production values before creating the OAuth app and custom domains.

Recommended shape:

- `ADMIN_HOST=admin.example.com`
- `PUBLIC_HOST=share.example.com`
- bundle hosts will be `*.share.example.com`

Replace `example.com` throughout this guide with your real domain.

Rules:

- Keep the admin surface on its own hostname.
- Keep the public landing host on its own hostname.
- Do not point `ADMIN_HOST` and `PUBLIC_HOST` at the same hostname.
- Do not use the Render `onrender.com` hostname as your real application URL. The app's production host authorization only allows `ADMIN_HOST`, `PUBLIC_HOST`, and `*.PUBLIC_HOST`.

## 3. Create the S3 Bucket and IAM Credentials

Knyle Share stores uploaded bundle contents in S3. The bucket should stay private.

### 3.1 Create the bucket

In AWS S3:

1. Create a new general-purpose bucket.
2. Pick the final AWS region now. You cannot change the bucket region later.
3. Leave Block Public Access enabled.
4. Do not enable static website hosting.
5. Record the bucket name and region.

Use the bucket name only for configuration, not an ARN or `s3://` URL.

### 3.2 Create a least-privilege IAM policy

Create a customer-managed IAM policy for the bucket, replacing `YOUR_BUCKET_NAME`:

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

The setup validator performs a real S3 round trip, so the credentials must be able to:

- list the bucket
- read objects
- write objects
- delete objects

### 3.3 Create an IAM user or access key

In AWS IAM:

1. Create a dedicated IAM user for Knyle Share.
2. Do not give it console access.
3. Attach only the bucket policy above.
4. Create an access key.
5. Save the access key ID and secret access key immediately.

You will need:

- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `AWS_REGION`
- `S3_BUCKET`

## 4. Create the GitHub OAuth App

Knyle Share uses a GitHub OAuth app for the admin sign-in flow.

Create the app in GitHub:

1. Open GitHub.
2. Go to `Settings`.
3. Open `Developer settings`.
4. Open `OAuth Apps`.
5. Click `New OAuth App`.

Use values shaped like this:

- Application name: `Knyle Share Production`
- Homepage URL: `https://admin.example.com`
- Authorization callback URL: `https://admin.example.com/auth/github/callback`
- Enable Device Flow: leave unchecked

Record:

- `GITHUB_CLIENT_ID`
- `GITHUB_CLIENT_SECRET`

Important notes:

- GitHub OAuth apps support only one callback URL, so use the final production admin hostname here.
- If you also run the app locally, keep a separate local OAuth app for `admin.lvh.me`.

## 5. Create the Render Blueprint

This repository already includes [render.yaml](/Users/kneath/code/kneath/knyle-share/render.yaml), so the intended setup path is a Blueprint deploy.

In Render:

1. Open `New`.
2. Choose `Blueprint`.
3. Connect the repo that contains this project.
4. Select the branch you want to deploy.
5. Review the Blueprint and create it.

The current Blueprint defines:

- service name `knyle-share`
- runtime `ruby`
- plan `starter`
- build command `bundle install && bundle exec rails assets:precompile`
- start command `bundle exec rails db:prepare && bundle exec puma -C config/puma.rb`
- health check path `/up`
- a persistent disk mounted at `/var/data`
- generated `SECRET_KEY_BASE`

## 6. Set the Environment Variables

Render will prompt for the variables marked `sync: false` in the Blueprint. Set them before the first real deploy.

### 6.1 Required values you must provide

| Variable | Example | Notes |
| --- | --- | --- |
| `ADMIN_HOST` | `admin.example.com` | Exact admin hostname |
| `PUBLIC_HOST` | `share.example.com` | Base public hostname, not a bundle hostname |
| `AWS_ACCESS_KEY_ID` | `AKIA...` | S3 access key |
| `AWS_SECRET_ACCESS_KEY` | `...` | S3 secret key |
| `AWS_REGION` | `us-west-2` | Must match the bucket's actual region |
| `S3_BUCKET` | `knyle-share-files` | Bucket name only |
| `GITHUB_CLIENT_ID` | `Iv1....` | From the OAuth app |
| `GITHUB_CLIENT_SECRET` | `...` | From the OAuth app |

### 6.2 Optional values you can provide

| Variable | Default | Meaning |
| --- | --- | --- |
| `PUBLIC_ASSET_REDIRECT_TTL_SECONDS` | `300` | Presigned redirect lifetime for download-style asset access |
| `INLINE_MARKDOWN_RENDER_MAX_BYTES` | `1048576` | Maximum markdown size rendered inline before download-only fallback |
| `RAILS_LOG_LEVEL` | `info` | Standard Rails production log level override |

### 6.3 Values already handled by the Blueprint

| Variable | Current value |
| --- | --- |
| `RAILS_ENV` | `production` |
| `DATABASE_PATH` | `/var/data/production.sqlite3` |
| `WEB_CONCURRENCY` | `1` |
| `RAILS_MAX_THREADS` | `3` |
| `SECRET_KEY_BASE` | generated by Render |

Operational notes:

- Keep `WEB_CONCURRENCY=1` while the app uses SQLite on a single disk.
- Do not store production secrets in a repo-local `.env` file.
- The app does not currently require `RAILS_MASTER_KEY` in production. If you later move production settings into Rails encrypted credentials, revisit that.

## 7. Verify the Persistent Disk Settings

The Blueprint already defines the disk, but verify it in the Render dashboard after creation.

The disk must be:

- attached to the `knyle-share` web service
- mounted at `/var/data`
- large enough for the SQLite database and any future operational files

Current repo defaults:

- mount path: `/var/data`
- SQLite file path: `/var/data/production.sqlite3`
- size: `1 GB`

Do not change the mount path unless you also change `DATABASE_PATH`.

Remember:

- only files written under `/var/data` persist across deploys and restarts
- the disk is only available to the running service, not to the build step
- a disk-backed service cannot be safely scaled to multiple instances

## 8. Add Custom Domains and DNS

This app is not correctly deployed until all three public entry points are working on the same Render service.

### 8.1 Add the domains in Render

Add all of these as custom domains on the same web service:

- `admin.example.com`
- `share.example.com`
- `*.share.example.com`

Do not skip the wildcard entry. Public bundle hosts depend on it.

### 8.2 Create the DNS records with your DNS provider

For `admin.example.com` and `share.example.com`, Render will provide the CNAME target to use.

For `*.share.example.com`, Render's current wildcard-domain flow requires three `CNAME` records:

- `*`
- `_acme-challenge`
- `_cf-custom-hostname`

Use the exact values Render shows for your service when you add the wildcard domain.

Important DNS notes:

- The wildcard record does not replace the base `share.example.com` record. You need both.
- If Render domain verification stalls, check for conflicting `AAAA` records and remove them.
- Wait until Render verifies each domain and finishes TLS certificate issuance before testing OAuth.

### 8.3 Point everything at the same Render service

At the end of DNS setup, all of these names must reach the same web service:

- `admin.example.com`
- `share.example.com`
- `anything.share.example.com`

## 9. Trigger and Watch the First Deploy

If the Blueprint has not already deployed after creation, trigger a deploy manually.

Expected behavior:

- Render runs `bundle install`
- Render precompiles assets
- Render boots the app with `bundle exec rails db:prepare`
- Rails creates or migrates `/var/data/production.sqlite3`
- Puma starts using `config/puma.rb`
- Render begins checking `/up`

Before moving on, confirm:

- the deploy finished successfully
- the service is healthy
- `https://admin.example.com/up` responds
- `https://share.example.com/up` responds

## 10. Complete First-Run Setup and Claim the Admin

The first admin account is claimed through the app itself.

Do this immediately after the deploy is live.

1. Visit `https://admin.example.com/`.
2. You should be redirected to `/setup`.
3. Click `Re-run checks`.
4. Wait for all five checks to pass:
   - environment variables configured
   - database reachable and migrated
   - S3 configuration present
   - S3 bucket reachable
   - S3 read/write/delete cycle
5. Click `Sign in with GitHub`.
6. Complete GitHub OAuth with the intended admin account.
7. After success, verify you land on the admin bundles page.

Important:

- The first GitHub user to sign in after setup validation passes becomes the permanent admin for the installation.
- Do not share the admin URL or leave the deployment unclaimed once the checks pass.

## 11. Run a Real End-to-End Smoke Test

A green deploy is not enough. Test the app the same way a real user will use it.

### 11.1 Confirm the admin and public shells

Check these first:

- `https://admin.example.com/` loads the signed-in admin flow
- `https://share.example.com/` loads the public home page

### 11.2 Create an API token

From the admin UI:

1. Open `API Tokens`.
2. Create a token with a descriptive label.
3. Copy the plaintext token immediately. It is shown only once.

### 11.3 Configure the local CLI

From your local checkout:

```sh
bin/knyle-share login
```

Provide:

- admin URL: `https://admin.example.com`
- API token: the token you just created

### 11.4 Publish a real test bundle

Publish a small markdown file:

```sh
bin/knyle-share README.md --protected --generate-password
```

Verify all of the following:

- the CLI upload succeeds
- the app returns a share URL on a bundle subdomain
- the password gate works
- the document renders after access is granted
- download or raw routes work when appropriate

This validates the full production chain:

- admin authentication
- API token auth
- upload processing
- S3 write access
- bundle routing on wildcard domains
- protected public delivery

## 12. Ongoing Deploys

After the first deployment:

- pushing changes to the linked branch will trigger new deploys unless auto-deploy is disabled
- startup will continue to run `db:prepare`, so committed migrations apply on boot
- the SQLite database remains on the persistent disk across deploys

If you change any of these, update all related systems together:

- `ADMIN_HOST`
- `PUBLIC_HOST`
- custom domains in Render
- DNS records
- GitHub OAuth callback URL

## 13. Common Failure Modes

### Setup says required environment variables are missing

Cause:

- one or more required Render env vars were not set, were misspelled, or were saved on the wrong service

Fix:

- compare the Render environment page against the required list in this document
- redeploy after correcting the values

### Setup says the database is not migrated

Cause:

- boot did not finish `db:prepare`
- the app cannot write to the configured database path

Fix:

- check deploy logs
- confirm the disk is mounted at `/var/data`
- confirm `DATABASE_PATH=/var/data/production.sqlite3`

### Setup says the S3 bucket is unreachable

Cause:

- wrong bucket name
- wrong AWS credentials
- IAM policy missing required actions

Fix:

- verify `S3_BUCKET`
- verify the access key pair
- verify the IAM policy includes `s3:ListBucket`, `s3:GetBucketLocation`, `s3:GetObject`, `s3:PutObject`, and `s3:DeleteObject`

### Setup says the bucket region is wrong

Cause:

- `AWS_REGION` does not match the bucket's actual region

Fix:

- update `AWS_REGION` to the real bucket region and redeploy

### GitHub sign-in fails

Cause:

- incorrect `GITHUB_CLIENT_ID` or `GITHUB_CLIENT_SECRET`
- callback URL in GitHub does not exactly match `https://ADMIN_HOST/auth/github/callback`
- DNS or TLS for `ADMIN_HOST` is not fully ready

Fix:

- verify the GitHub OAuth app settings
- verify the Render custom domain is active and serving HTTPS

### The admin or public site works, but bundle subdomains do not

Cause:

- wildcard custom domain was not added in Render
- wildcard DNS records were not created
- TLS for the wildcard domain has not finished issuing

Fix:

- add `*.PUBLIC_HOST` as a custom domain
- create all Render-required wildcard CNAME records
- wait for verification and TLS completion

### Deploys briefly interrupt traffic

Cause:

- expected behavior for a Render service with a persistent disk

Fix:

- none for the current architecture
- if you need zero-downtime deploys or multiple instances, plan a move away from SQLite-on-disk

## References

Repo references:

- [render.yaml](/Users/kneath/code/kneath/knyle-share/render.yaml)
- [README.md](/Users/kneath/code/kneath/knyle-share/README.md)
- [config/environments/production.rb](/Users/kneath/code/kneath/knyle-share/config/environments/production.rb)
- [config/routes.rb](/Users/kneath/code/kneath/knyle-share/config/routes.rb)
- [app/services/setup_validation.rb](/Users/kneath/code/kneath/knyle-share/app/services/setup_validation.rb)

Official docs:

- [Render Blueprints](https://render.com/docs/infrastructure-as-code)
- [Render Blueprint YAML Reference](https://render.com/docs/blueprint-spec)
- [Render Custom Domains](https://render.com/docs/custom-domains)
- [Render Persistent Disks](https://render.com/docs/disks)
- [GitHub: Creating an OAuth app](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/creating-an-oauth-app)
- [AWS S3: Creating a general purpose bucket](https://docs.aws.amazon.com/AmazonS3/latest/userguide/create-bucket-overview.html)
- [AWS S3: Block public access settings](https://docs.aws.amazon.com/AmazonS3/latest/userguide/configuring-block-public-access-bucket.html)
