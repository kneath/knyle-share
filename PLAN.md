# Knyle Share Rails App Plan

## Summary

Build a conventional Rails app in the repository root that turns the current shaping docs and `prototype/` screens into a working product.

The implementation should prioritize:

- a cheap default deployment on Render with SQLite on a persistent disk
- private bundle storage in S3
- server-rendered admin views that match the existing prototype
- a public bundle delivery layer that supports password access and signed links
- a small private API that will support the CLI after the web app is stable

`prototype/` is the visual source of truth for the admin UI. The Rails app should preserve that look and flow while replacing the static pages with real routes, data, and actions.

## Foundation Decisions

### Rails Stack

- Generate the app in the repo root with a standard Rails structure.
- Use the current Rails stable generator with:
  - SQLite
  - importmap
  - Turbo + Stimulus
  - no CSS framework
  - Minitest and system tests intact
  - no Action Text, Action Mailbox, or Jbuilder
  - no Active Storage
- Keep `shaping/`, `prototype/`, `TECHNICAL_PREFERENCES.md`, and `PLAN.md` in the repo as product/design references.

### Gems and Libraries

Add only the dependencies needed for v1:

- `omniauth-github`
- `omniauth-rails_csrf_protection`
- `aws-sdk-s3`
- `commonmarker`
- `rack-attack`

Do not add Tailwind, ViewComponent, React, or an admin framework.

### Hosting and Delivery Strategy

- Use one Rails app to serve both the public host and the admin host.
- Use host-constrained routing:
  - admin routes only answer on the admin host
  - public bundle routes only answer on the public host
- Keep the S3 bucket private.
- Serve bundle bytes through Rails in v1 so access control, origin separation, and relative paths remain simple.
- Treat upload ingestion as a custom S3-backed pipeline, not an Active Storage problem.

### Visual Source of Truth

Use these prototype files as the initial UI reference:

- `prototype/login.html`
- `prototype/setup.html`
- `prototype/bundles.html`
- `prototype/bundle.html`
- `prototype/link.html`

The first admin implementation should feel like these pages with real data, not a redesign.

## Application Shape

### Core Models

Use these models and keep the relationships stable:

- `Installation`
  - singleton row
  - stores claimed admin GitHub identity
  - fields: `admin_github_uid`, `admin_github_login`, `admin_github_name`, `admin_github_avatar_url`, `admin_claimed_at`
- `Bundle`
  - one row per slug
  - replacement updates the same row so analytics and access sessions survive
  - fields: `slug`, `title`, `source_kind`, `presentation_kind`, `status`, `access_mode`, `password_digest`, `password_session_ttl_seconds`, `entry_path`, `byte_size`, `asset_count`, `content_revision`, `last_viewed_at`, `last_replaced_at`, `total_views_count`, `unique_protected_viewers_count`
- `BundleAsset`
  - one row per stored file in a bundle
  - fields: `bundle_id`, `path`, `storage_key`, `content_type`, `byte_size`, `checksum`
- `ViewerSession`
  - bundle-scoped authenticated viewer session for password access
  - fields: `bundle_id`, `token_digest`, `expires_at`, `last_seen_at`
- `BundleView`
  - lightweight analytics event
  - fields: `bundle_id`, `viewer_session_id`, `access_method`, `request_path`, `viewed_at`
- `ApiToken`
  - for the later private CLI API
  - fields: `label`, `token_digest`, `last_used_at`, `revoked_at`
- `BundleUpload`
  - staging record for API uploads
  - fields: `slug`, `source_kind`, `original_filename`, `access_mode`, `password_digest`, `replace_existing`, `ingest_key`, `status`, `error_message`, `byte_size`

### Bundle Semantics

- `Bundle` remains stable across replacement.
- Replacement increments `content_revision`, swaps the asset set, updates `last_replaced_at`, and keeps:
  - analytics
  - password sessions
  - signed-link validity
- Delete is destructive:
  - remove the bundle row
  - remove assets from S3
  - remove sessions and analytics rows
  - free the slug for future reuse
- Disabled bundles stay in the database, disappear from public delivery, and render an unavailable page.

### Presentation Classification

Use this classification service and keep it deterministic:

- `static_site`: directory with root `index.html`
- `markdown_document`: single Markdown file
- `single_download`: single non-Markdown file
- `file_listing`: directory without root `index.html`

Store the result on `Bundle.presentation_kind` during ingest. Do not classify on every request.

### Storage Rules

- Upload ingest objects land in S3 under an internal `uploads/` prefix.
- Published bundle assets live under `bundles/<bundle-id>/<content-revision>/...`.
- `BundleAsset.path` is always the bundle-relative path used by public routing.
- Checksums are stored so replacements and integrity issues are debuggable.

## Route and Controller Plan

### Admin Host

Use an `Admin` namespace and a dedicated admin layout.

- `GET /`
  - if no admin is claimed: redirect to setup
  - if admin is claimed and signed out: redirect to login
  - if signed in: redirect to bundles
- `GET /login`
- `GET /auth/github`
- `GET /auth/github/callback`
- `POST /logout`
- `GET /setup`
- `POST /setup/validate`
- `GET /bundles`
- `GET /bundles/:id`
- `PATCH /bundles/:id/status`
- `PATCH /bundles/:id/password`
- `DELETE /bundles/:id`
- `GET /bundles/:id/link/new`
- `POST /bundles/:id/link`

Admin page mapping to the prototype:

- `login` matches `prototype/login.html`
- `setup` matches `prototype/setup.html`
- `bundles#index` matches `prototype/bundles.html`
- `bundles#show` matches `prototype/bundle.html`
- `bundle_links#new` and `create` match `prototype/link.html`

### Public Host

Use a `Public` namespace with host constraint and reserved slug exclusion.

- `GET /:slug`
  - renders the bundle entry surface
- `POST /:slug/access`
  - validates a password and creates or refreshes the bundle-scoped viewer session
- `GET /:slug/raw`
  - raw Markdown source for `markdown_document`
- `GET /:slug/download`
  - download route for `markdown_document` and `single_download`
- `GET /:slug/*asset_path`
  - serves static-site assets, nested HTML pages, or file-listing content

Reserved top-level paths must stay blocked from slug claims:

- `api`
- `assets`
- `rails`
- `up`
- `health`

### Private API

Expose the CLI-facing API under `Admin::Api::V1` on the admin host.

- `GET /api/v1/bundles/availability`
  - checks slug availability and reserved names
- `POST /api/v1/uploads`
  - creates a `BundleUpload` and returns ingest metadata
- `PUT /api/v1/uploads/:id`
  - accepts the uploaded file or archive metadata as finalized
- `POST /api/v1/uploads/:id/process`
  - processes the staged upload into a published bundle
- `GET /api/v1/bundles/:slug`
  - returns bundle metadata for CLI output
- `POST /api/v1/bundles/:slug/links`
  - creates a signed-link response for the CLI

API auth uses `ApiToken`. The first web milestone can ship without token-management UI, but the API layer should still be built around token auth, not admin browser sessions.

## Build Sequence

### Phase 1: Bootstrap the Rails App

- Generate the Rails app in the repo root.
- Set up SQLite for development and a production database path on the Render disk.
- Add admin/public host config via environment variables:
  - `ADMIN_HOST`
  - `PUBLIC_HOST`
- Add AWS and GitHub env config:
  - `AWS_ACCESS_KEY_ID`
  - `AWS_SECRET_ACCESS_KEY`
  - `AWS_REGION`
  - `S3_BUCKET`
  - `GITHUB_CLIENT_ID`
  - `GITHUB_CLIENT_SECRET`
- Create the base application layout plus an `admin` layout.
- Port the prototype CSS into Rails assets as the starting admin stylesheet.

Acceptance:

- Rails boots locally.
- Admin host and public host route constraints are wired.
- The admin layout can render the prototype shell without real data yet.

### Phase 2: First-Run Validation and Admin Authentication

- Implement `Installation.current`.
- Implement `SetupValidation` as a service object that checks:
  - required environment variables
  - database connectivity
  - pending migrations
  - S3 configuration presence
  - S3 bucket reachability
  - S3 write/read/delete round trip
- Implement the setup page with rerun action and blocking state.
- Implement GitHub OAuth and signed-in admin sessions.
- Implement first-run claim behavior:
  - if no admin is claimed and setup validation passes, the first successful GitHub callback claims the installation
  - once claimed, later callbacks must match the stored GitHub UID
- Implement the login page for already-claimed installations.

Acceptance:

- Fresh install shows setup, not login.
- Failed setup keeps GitHub claim blocked.
- Passing setup allows first claim.
- Once claimed, only the stored GitHub account can sign in.

### Phase 3: Bundle Domain and Admin UI

- Add the `Bundle`, `BundleAsset`, `ViewerSession`, and `BundleView` models.
- Build the real admin pages from the prototype:
  - bundle list
  - bundle detail
  - expiring-link page
- Populate real bundle stats and states.
- Implement admin actions:
  - enable
  - disable
  - change password
  - delete
  - generate expiring link
- Keep the UI server-rendered with normal links and forms.
- Preserve light/dark support and responsive layouts from the prototype.

Acceptance:

- Admin can browse real bundle rows.
- Protected bundle detail works with real stats and actions.
- Disabled bundles read clearly as disabled.
- Signed-link page uses the 1 day / 1 week / 1 month presets.

### Phase 4: Upload Ingest and Replacement Pipeline

- Build `BundleUpload` plus an ingest service pipeline.
- The pipeline must support:
  - single file upload
  - directory archive upload using `.tar.gz`
  - classification into the four presentation kinds
  - replacement of an existing slug
- Processing rules:
  - write ingest object to S3
  - inspect and classify
  - upload published assets under the bundle revision path
  - swap bundle assets in a transaction
  - update bundle metadata and counters
  - purge old revision assets after the swap succeeds
- Replacement keeps analytics, sessions, and signed-link validity.

Acceptance:

- New bundle publish works for file and directory inputs.
- Replacement updates content without changing the slug.
- Old assets are no longer reachable after replacement.

### Phase 5: Public Delivery and Access Control

- Implement public bundle delivery per presentation kind.
- Use one controller layer for auth decisions and one renderer layer for presentation behavior.
- Access behavior:
  - public bundles render immediately
  - protected bundles show the password gate unless a valid signed link or viewer session exists
  - password success creates or refreshes a `ViewerSession`
  - signed links are stateless and built with `ActiveSupport::MessageVerifier`
- Counting rules:
  - count only successful document-level bundle views
  - do not count CSS, JS, image, or other asset requests as views
  - do not count admin traffic
  - count HTML requests within a static site as views
- Public rendering behavior:
  - `static_site`: serve HTML and asset paths under the bundle slug
  - `markdown_document`: rendered page, raw source route, download route
  - `single_download`: landing page plus download action
  - `file_listing`: directory listing UI plus file download paths

Acceptance:

- Password gate works and creates bundle-scoped access for 24 hours.
- Signed links bypass the password form until expiry.
- Markdown, single-download, static-site, and file-listing bundles all render correctly.
- Disabled bundles render unavailable.

### Phase 6: Private API for the CLI

- Implement token auth with `ApiToken`.
- Build the v1 upload and metadata endpoints.
- Keep responses explicit JSON, no serializer framework.
- Return enough metadata for the future CLI to:
  - confirm slug usage
  - upload content
  - confirm replacement behavior
  - print the final share URL
  - request a signed link

Acceptance:

- The API can publish a new bundle without the admin browser UI.
- The API can replace an existing bundle when explicitly requested.
- The API can mint signed links using the same presets as the admin UI.

### Phase 7: Deployment and Shared-App Documentation

- Add `render.yaml`.
- Document:
  - required env vars
  - Render disk setup
  - custom domains for admin and public hosts
  - AWS S3 bucket setup
  - first-run validation and claim flow
- Add production config for HTTPS, host authorization, and the health endpoint.

Acceptance:

- Another developer can deploy with a Render account and AWS account using the repo alone.
- The first-run validation screen becomes the main deployment sanity check.

## Execution Order

### Recommended Working Style

- Work serially through Phases 1, 2, and the model/routing portion of Phase 3.
- Do not split work across subagents until the Rails skeleton, host routing, auth flow, and core bundle schema are in place.
- Start parallel work only after the admin shell is rendering real data and the bundle interfaces are stable.

The reason for this split is simple: early Rails app work touches the same files and decisions at once. Parallelizing too early creates conflicts in `config/`, routes, base layouts, auth, and migrations. Once those contracts are real, work can divide cleanly.

### Milestone 0: Repo Bootstrap

Task list:

- [x] Generate Rails in the root
- [x] Preserve `prototype/`, `shaping/`, `TECHNICAL_PREFERENCES.md`, and `PLAN.md`
- [ ] Commit the generated baseline before product-specific work starts

Goal:

- Turn the repo into a working Rails app without losing the existing planning and prototype artifacts.

Work:

- Generate Rails in the root.
- Preserve `prototype/`, `shaping/`, `TECHNICAL_PREFERENCES.md`, and `PLAN.md`.
- Commit the generated baseline before product-specific work starts.

Definition of done:

- `bin/rails` commands run.
- The app boots locally.
- The repo has a clean baseline commit for the generated app.

### Milestone 1: App Skeleton and Hosts

Task list:

- [x] Configure SQLite, environment variables, and host constraints
- [x] Add the admin layout and shared styles translated from the prototype
- [x] Wire empty root, login, setup, and bundle index routes with placeholder content

Goal:

- Establish the real application shell and the deployment assumptions.

Work:

- Configure SQLite, environment variables, and host constraints.
- Add the admin layout and shared styles translated from the prototype.
- Wire empty root, login, setup, and bundle index routes with placeholder content.

Definition of done:

- Admin and public hosts are recognized correctly.
- The admin shell renders with Rails layouts and assets.
- The app can be started locally with documented env vars.

### Milestone 2: Setup Validation and Admin Claim

Task list:

- [x] Implement `Installation`
- [x] Implement `SetupValidation`
- [x] Implement GitHub OAuth and admin session handling
- [x] Implement fresh-install setup, blocked validation state, successful claim, and later login behavior

Goal:

- Complete the first-run experience and lock authentication behavior.

Work:

- Implement `Installation`.
- Implement `SetupValidation`.
- Implement GitHub OAuth and admin session handling.
- Implement fresh-install setup, blocked validation state, successful claim, and later login behavior.

Definition of done:

- Fresh installations land on setup.
- Failed setup keeps claim blocked.
- Successful validation allows first claim.
- After claim, only the stored GitHub identity can sign in.

### Milestone 3: Core Bundle Models and Admin Screens

Task list:

- [x] Add `Bundle`, `BundleAsset`, `ViewerSession`, and `BundleView`
- [x] Build the real bundle list, detail page, and signed-link screen
- [x] Implement enable/disable, password change, delete, and expiring-link generation

Goal:

- Replace the static prototype with working Rails admin pages backed by real models.

Work:

- Add `Bundle`, `BundleAsset`, `ViewerSession`, and `BundleView`.
- Build the real bundle list, detail page, and signed-link screen.
- Implement enable/disable, password change, delete, and expiring-link generation.

Definition of done:

- The prototype screens exist as working Rails pages.
- Admin actions mutate real data.
- Signed links are generated by the app.
- At this point the project is ready for safe parallelization.

### Parallel Split Point

After Milestone 3, split work into parallel tracks with disjoint ownership.

Recommended tracks:

- Main thread: own migrations, shared domain contracts, and integration decisions.
- Worker 1: public bundle delivery and access control.
- Worker 2: upload ingest and replacement pipeline.
- Worker 3: private API and token auth.
- Worker 4, optional: deployment docs, `render.yaml`, seeds, and system test expansion.

Rules:

- The main thread keeps ownership of `config/routes.rb`, shared models, and cross-cutting services.
- Parallel workers can add to those surfaces, but the main thread should integrate final shape changes.
- Do not let multiple workers simultaneously redesign the same controller namespace or migration chain.

### Milestone 4: Public Delivery Track

Task list:

- [x] Build the public host controllers
- [x] Implement password gating, viewer sessions, signed-link verification, and presentation-specific rendering
- [x] Record analytics for document-level views only

Goal:

- Make public bundle URLs work end to end.

Work:

- Build the public host controllers.
- Implement password gating, viewer sessions, signed-link verification, and presentation-specific rendering.
- Record analytics for document-level views only.

Definition of done:

- A published bundle can be viewed on the public host.
- Protected access works through both passwords and signed links.
- Disabled bundles are unavailable publicly.

### Milestone 5: Upload Ingest Track

Task list:

- [x] Implement `BundleUpload`
- [ ] Implement S3 ingest flow, archive processing, classification, and replacement
- [ ] Persist published asset records and revision changes

Goal:

- Make bundles publishable through the internal pipeline.

Work:

- Implement `BundleUpload`, S3 ingest flow, archive processing, classification, and replacement.
- Persist published asset records and revision changes.

Definition of done:

- New bundles publish successfully.
- Existing slugs replace successfully when requested.
- Replacements preserve analytics and sessions.

### Milestone 6: Private API Track

Task list:

- [ ] Add `ApiToken`
- [ ] Implement upload, metadata, slug check, and signed-link endpoints
- [ ] Lock down token auth and rate limiting

Goal:

- Expose the internal capability needed by the future CLI.

Work:

- Add `ApiToken`.
- Implement upload, metadata, slug check, and signed-link endpoints.
- Lock down token auth and rate limiting.

Definition of done:

- An authenticated API client can publish and replace bundles.
- The API returns enough metadata for future CLI output and follow-up actions.

### Milestone 7: Deployment and Hardening

Task list:

- [ ] Add `render.yaml`
- [ ] Document env vars, Render disk setup, custom domains, AWS S3 setup, and first-run claim flow
- [ ] Add production config for HTTPS, host authorization, and the health endpoint
- [ ] Expand system tests for the highest-risk deploy and auth flows

Goal:

- Make the app straightforward for someone else to deploy.

Work:

- Add `render.yaml`.
- Document S3, Render, hosts, and first-run claim flow.
- Tighten production config, health checks, and host authorization.
- Expand system tests for the highest-risk flows.

Definition of done:

- A new operator can deploy the app with Render and AWS using the repo docs alone.
- The documented setup flow matches the actual first-run behavior.

## Implementation Notes

### UI Translation

- Keep the bundle list as the card-based layout shown in `prototype/bundles.html`.
- Keep the bundle detail as a focused stats-and-actions page shown in `prototype/bundle.html`.
- Keep the setup and login pages centered and quiet as shown in the prototype.
- Use the prototype CSS as a starting asset, then refactor it into maintainable Rails stylesheets without changing the visual direction.

### Services and Boundaries

Create plain Ruby objects for the parts that truly cross boundaries:

- `SetupValidation`
- `BundleClassifier`
- `BundleIngestor`
- `SignedLink`
- `ViewerSessionIssuer`
- `BundleAnalyticsRecorder`
- `StorageClient`

Do not introduce service objects for simple CRUD controller actions.

### Security Rules

- Use `has_secure_password` on `Bundle` for protected passwords.
- Rate-limit password attempts and token-auth API requests with `rack-attack`.
- Keep bundle content treated as untrusted input.
- Sanitize Markdown output before rendering.
- Reject path traversal during archive extraction.

## Test Plan

### Automated

- Model tests:
  - bundle classification
  - slug reservation
  - signed-link verification
  - viewer session expiry
  - setup validation result aggregation
- Request tests:
  - admin auth redirects
  - public access gating
  - raw/download routes
  - API token auth
- System tests:
  - first-run validation and admin claim flow
  - admin login after claim
  - bundle list and detail screens
  - signed-link generation screen
  - password-protected public access flow
- Integration tests:
  - publish a single file bundle
  - publish a directory bundle
  - replace an existing slug while preserving analytics

### Manual

- Compare Rails admin pages against the current prototype at mobile and desktop widths.
- Verify both light and dark schemes across login, setup, list, detail, and link generation.
- Verify all navigation remains real links or real forms.
- Verify a static-site bundle can load nested assets under the public slug.

## Assumptions and Defaults

- Use Minitest, not RSpec.
- Use SQLite in development and default production.
- Use GitHub OAuth for admin auth from day one.
- Use synchronous upload processing in v1, but isolate ingest behind `BundleIngestor` and `BundleUpload` so it can move to background jobs later.
- Use `.tar.gz` as the directory-upload format for the future CLI.
- Keep API token management minimal in the first app iteration; if needed, add a small admin settings screen after the core admin flows are stable.
