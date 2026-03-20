# Frontend Performance Review

Date: 2026-03-20

## Executive Summary

Knyle Share is already in a good place on JavaScript weight. There is effectively no shipped JS bundle today, and the app shell is server-rendered. The biggest performance risks are not framework overhead. They are cacheability, request-path work, and oversized HTML responses when bundles get large.

The highest-value fixes are:

- Make public bundle assets cacheable across repeat visits instead of minting fresh presigned redirect targets on every request.
- Stop fetching and rendering public HTML and markdown documents from S3 on every page view.
- Put bounds on file-listing HTML so large bundles do not become multi-hundred-kilobyte documents on mobile networks.
- Split the shared stylesheet so admin-only and threshold-homepage CSS do not block first paint on every route.

Current measured artifact sizes:

- `app/assets/stylesheets/application.css`: 16,966 bytes raw.
- Threshold-page CSS inside that shared stylesheet: about 4,168 bytes raw.
- `public/icon.png`: 4,166 bytes.

The app should stay simple. Do not add a heavier frontend stack to chase performance here. Fix delivery semantics first.

When performance and security point in different directions, security wins. Public content can be cached aggressively because it is already meant to be public. Protected content cannot be treated like public content just to save a round-trip.

## Prioritized Findings

### P1. Bundle sub-assets are delivered in a way that undermines repeat-view caching

Evidence:

- `app/controllers/public/base_controller.rb:72-74` answers bundle asset requests with a redirect.
- `app/services/bundle_storage.rb:29-37` generates a new presigned S3 URL per request, with a short default TTL.
- `app/services/bundle_ingestor.rb:91-100` and `app/services/bundle_ingest/replacement_planner.rb:13-25` already version bundle content with `content_revision`, which means immutable caching is safe for unchanged content.
- `app/services/bundle_ingest/object_store.rb:44-63` copies and writes S3 objects without setting `cache_control`.

Why this matters:

- A static site's `/assets/app.css`, `/assets/app.js`, images, and fonts are requested through stable same-origin URLs, but the app converts each of those requests into a fresh presigned destination URL.
- That pattern makes it much harder for the browser to reuse cached bytes across visits and reloads, because the final asset URL changes even when the content does not.
- On slow cellular networks, that adds an avoidable round-trip through Rails before the browser can even start the real asset transfer.
- Because object keys already include `content_revision`, the system is leaving safe immutable caching on the table.

Judgment:

- Pursue this aggressively for public bundles.
- Do not pursue the same strategy for protected bundles unless the cache behavior is explicitly bound to current authorization state. Security wins here.

Actionable fix:

1. Separate public and protected bundle delivery strategies.
2. For public bundles, serve stable immutable asset URLs keyed by `content_revision`, ideally through a CDN or object-storage host, with `Cache-Control: public, max-age=31536000, immutable`.
3. For protected bundles, keep the request URL stable and either proxy bytes through Rails with `ETag` plus `Cache-Control: private, max-age=...`, or make the redirect response itself explicitly cacheable for a short TTL keyed to `access_revision`.
4. Do not make protected-bundle redirect responses cacheable unless the cache key is explicitly bound to the current auth state. A cached 302 that points at a bearer-style presigned URL can accidentally bypass the access check for later requests.
5. If presigned redirects remain for public bundles, add `response_cache_control` in `BundleStorage#download_url` and explicit cache headers on the 302 response. Right now the response only sets `Referrer-Policy`.
6. For protected bundles, prefer non-cacheable redirects or a private proxy path over a cacheable redirect response.
7. Add tests that assert repeat requests for unchanged public assets reuse cacheable URLs or cacheable redirect responses without changing protected-bundle authorization semantics.

### P1. Public HTML and markdown pages pay full origin cost on every request

Evidence:

- `app/controllers/public/base_controller.rb:60-69` fetches HTML from storage and renders it inline for every HTML page request.
- `app/controllers/public/bundles_controller.rb:17-31` reads markdown from storage and runs `Commonmarker.to_html` plus sanitization on every inline markdown request.
- `app/services/bundle_storage.rb:14-27` always performs a fresh S3 `get_object` before the controller can respond.
- `app/controllers/public/bundles_controller.rb:19-24` and `app/services/public_bundle_analytics.rb:2-17` perform synchronous analytics writes on the same request path that serves the page.

Why this matters:

- Public HTML and markdown document delivery is currently bound to S3 latency, app CPU, and database writes on every view.
- Warm repeat views do not have a strong document revalidation strategy based on `content_revision` and asset checksum.
- On a starter deployment with one web process (`render.yaml:5-21`), synchronous document work directly increases tail latency under load.
- On phones and slower networks, lower TTFB is often more important than shaving a few kilobytes off the client payload. This path is spending time before the first byte.

Judgment:

- Pre-rendering and revalidation are worth doing for public documents.
- Protected documents may use private conditional caching, but only with validators tied to revocation state. Any shortcut that lets stale authorization live longer than intended should be rejected.

Actionable fix:

1. Pre-render sanitized markdown at ingest time and store the rendered HTML alongside the source asset, or persist it in the database keyed by asset checksum plus an explicit sanitizer/renderer version so tightened policies can invalidate old renders.
2. Serve public HTML and markdown with `fresh_when` or `stale?` using `bundle.id`, `bundle.content_revision`, `asset.checksum`, and `last_replaced_at`.
3. For public documents, add explicit cache semantics that allow CDN and browser revalidation, for example `public, s-maxage=...` plus `stale-while-revalidate`.
4. For protected documents, use `private` caching with conditional requests so returning viewers can get 304s without bypassing access control.
5. Any protected-document validator must include revocation state such as `access_revision`, `access_mode`, and disabled status in addition to content identity. Content-only validators are not enough once password rotation and disablement are revocation boundaries.
6. Move analytics recording off the critical response path for document views, or at minimum batch the counter updates asynchronously.

### P2. File listings render the entire bundle in one HTML response

Evidence:

- `app/controllers/public/bundles_controller.rb:41-49` loads every asset in path order.
- `app/views/public/bundles/file_listing.html.erb:10-25` renders every asset row into one list with no pagination, filtering, or chunking.

Why this matters:

- A bundle with hundreds or thousands of files will produce large HTML payloads, large DOM trees, longer server render times, and slower mobile scrolling.
- File-listing bundles are exactly the kind of content that can grow without warning.
- This gets worse on poor cell coverage because the user pays for every file row before they can interact with the page.

Judgment:

- This is a clear performance win with no meaningful security downside. It should stay in scope.

Actionable fix:

1. Paginate file listings. A first page of 50 to 100 items is a safer baseline.
2. Add server-side search or prefix filtering so users can narrow a large directory instead of downloading the full listing.
3. Select only the columns needed for the list view instead of loading full asset records.
4. Consider a directory-tree presentation for nested content so the initial response only includes top-level paths.
5. Add tests that cover large listings and enforce a bounded first response size.

### P2. One render-blocking stylesheet serves every surface

Evidence:

- `app/views/layouts/application.html.erb:20` loads `application.css` for public pages.
- `app/views/layouts/admin.html.erb:10` loads the same stylesheet for admin pages.
- `app/assets/stylesheets/application.css:703-921` contains threshold-homepage-only styles and animations inside the shared file.

Why this matters:

- CSS is render-blocking. Every page pays for styles it does not use.
- The threshold homepage section alone is roughly one quarter of the current stylesheet, yet those bytes are also shipped to admin pages, password gates, download pages, and file listings.
- The total stylesheet is still modest today, but the structure is wrong for growth. This will get worse as the app accumulates more surface-specific styling.

Judgment:

- This is worth doing after the cache and TTFB work. It improves first paint without creating a security tradeoff.

Actionable fix:

1. Split the stylesheet into at least `core.css`, `admin.css`, `public_bundle.css`, and `public_home.css`.
2. Keep only shared tokens and generic primitives in the global sheet.
3. Load route-specific CSS from the layout or via `content_for :head`.

## Delivery Recommendations

These are not separate code findings, but they matter if the goal is fast delivery under both strong and weak network conditions.

- Put the public bundle host behind a CDN or edge cache for public bundle traffic, but explicitly bypass caching for protected responses, password-gate pages, signed-link flows, and auth-sensitive redirects. `config/environments/production.rb:28-29` leaves `config.asset_host` unused, and public document delivery currently depends heavily on origin performance.
- Verify Brotli or gzip for HTML, CSS, and JS at the edge. Do not assume the hosting platform is doing the right thing without measurement.
- Expose server timing for S3 fetch time, markdown render time, and analytics write time so regressions are visible in the browser.
- Keep the public path simple. The current architecture is light on JS, which is good. Preserve that advantage while improving cache behavior.

## Recommended Implementation Order

1. Fix cacheability for bundle assets and public documents.
2. Remove synchronous markdown rendering from the request path.
3. Paginate public file listings.
4. Split the shared stylesheet by surface.

## Verification Checklist

- A warm repeat visit to a public static site should transfer zero new CSS, JS, font, and image bytes unless the bundle changed.
- A warm repeat visit to a public markdown or HTML document should produce a 304 or CDN hit instead of a full re-render.
- The initial HTML response for a file listing should stay bounded even when the bundle contains thousands of files.
- Public password-gate and single-download pages should need only one small HTML request and one small CSS request before becoming interactive.
- Mobile and desktop runs should both be tested with real throttling, including a slow-4G profile.

## Will Not Address

- Shared CDN caching or cacheable protected redirects for protected bundles or protected documents. The performance win is not worth weakening the access boundary.
- Moving the public homepage inline script into a separate asset purely for performance. Revisit only if CSP hardening work already makes that change convenient.
- Admin pagination right now. Revisit when actual bundle counts or admin traces show this page has become materially slow.
- Inlining tiny critical CSS for the password gate and single-download shells. The simpler win is splitting the shared stylesheet; critical-CSS hand tuning is not worth the maintenance cost yet.
- Micro-optimizing the existing tiny icon files or inline text before cacheability and TTFB are fixed.
- Adding a client-heavy frontend framework to chase performance here.
