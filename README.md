# Knyle Share

Knyle Share is a Rails app for publishing private or public bundles on a public host while keeping administration on a separate admin host.

Current implemented slice:

- admin/public host split with host-constrained routing
- first-run setup validation
- GitHub OAuth admin claim and sign-in
- placeholder admin bundle screens based on the prototype

## Requirements

- Ruby `3.4.2`
- Bundler
- SQLite 3
- An AWS S3 bucket for setup validation
- A GitHub OAuth app for admin sign-in

Node is not required for local development. The app currently uses importmap and server-rendered Rails views.

## Local Setup

### 1. Create your local env file

Copy the template:

```sh
cp .env.example .env
```

Then fill in the GitHub and AWS values in `.env`.

The app now loads `.env` automatically in development and test via `dotenv-rails`, so you do not need to export these variables manually in your shell.

### 2. Install gems

```sh
bundle install
```

### 3. Configure environment variables

Your local `.env` should contain:

```sh
ADMIN_HOST=admin.lvh.me
PUBLIC_HOST=share.lvh.me
AWS_ACCESS_KEY_ID=your-access-key-id
AWS_SECRET_ACCESS_KEY=your-secret-access-key
AWS_REGION=us-west-2
S3_BUCKET=your-bucket-name
GITHUB_CLIENT_ID=your-github-oauth-client-id
GITHUB_CLIENT_SECRET=your-github-oauth-client-secret
```

Notes:

- `lvh.me` resolves to `127.0.0.1`, so you do not need to edit `/etc/hosts`.
- Setup validation will fail until all of the variables above are present.
- Setup validation also performs a real S3 write, read, and delete cycle. Use credentials and a bucket that allow those operations.

### 4. Create the GitHub OAuth app

For local development, configure the GitHub OAuth app with:

- Homepage URL: `http://admin.lvh.me:3000`
- Authorization callback URL: `http://admin.lvh.me:3000/auth/github/callback`

If you run Rails on a different port, update the callback URL to match.

### 5. Prepare the database

```sh
bin/rails db:prepare
```

This uses SQLite in development at [storage/development.sqlite3](/Users/kneath/code/kneath/knyle-share/storage/development.sqlite3).

### 6. Boot the app

```sh
bin/rails server
```

Then open:

- Admin: [http://admin.lvh.me:3000](http://admin.lvh.me:3000)
- Public host: [http://share.lvh.me:3000](http://share.lvh.me:3000)

You can also use:

```sh
bin/setup
```

That will copy `.env.example` to `.env` if needed, install gems, prepare the database, clear logs/tmp files, and start the server.

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
- the bootstrap and admin-claim flow

## Useful Endpoints

- Admin root: `/` on `ADMIN_HOST`
- Public root: `/` on `PUBLIC_HOST`
- Health check: `/up`

## Production Notes

Production is currently set up for SQLite on a persistent disk plus S3 object storage.

Relevant production env vars:

- `ADMIN_HOST`
- `PUBLIC_HOST`
- `DATABASE_PATH` optional, defaults to `storage/production.sqlite3`
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `AWS_REGION`
- `S3_BUCKET`
- `GITHUB_CLIENT_ID`
- `GITHUB_CLIENT_SECRET`

The current implementation expects the S3 bucket to be reachable from the app and the GitHub OAuth callback to point at the admin host.

For production, keep using real environment variables in Render rather than a repo-local `.env` file.
