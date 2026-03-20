# Frontend Performance Review

Date: 2026-03-20

## Executive Summary

Knyle Share is already in a good place on JavaScript weight. There is effectively no shipped JS bundle today, and the app shell is server-rendered. The biggest performance risks are not framework overhead. They are cacheability, request-path work, and oversized HTML responses when bundles get large.

The highest-value fixes are:

- Make bundle assets cacheable across repeat visits instead of minting fresh presigned redirect targets on every request.
- Stop fetching and rendering public HTML and markdown documents from S3 on every page view.
- Put bounds on file-listing HTML so large bundles do not become multi-hundred-kilobyte documents on mobile networks.
- Split the shared stylesheet so admin-only and threshold-homepage CSS do not block first paint on every route.

Current measured artifact sizes:

- `app/assets/stylesheets/application.css`: 16,966 bytes raw.
- Threshold-page CSS inside that shared stylesheet: about 4,168 bytes raw.
- `public/icon.png`: 4,166 bytes.

The app should stay simple. Do not add a heavier frontend stack to chase performance here. Fix delivery semantics first.

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

Actionable fix:

1. Separate public and protected bundle delivery strategies.
2. For public bundles, serve stable immutable asset URLs keyed by `content_revision`, ideally through a CDN or object-storage host, with `Cache-Control: public, max-age=31536000, immutable`.
3. For protected bundles, keep the request URL stable and either proxy bytes through Rails with `ETag` plus `Cache-Control: private, max-age=...`, or make the redirect response itself explicitly cacheable for a short TTL keyed to `access_revision`.
4. If presigned redirects remain, add `response_cache_control` in `BundleStorage#download_url` and explicit cache headers on the 302 response. Right now the response only sets `Referrer-Policy`.
5. Add tests that assert repeat requests for unchanged assets reuse cacheable URLs or cacheable redirect responses.

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

Actionable fix:

1. Pre-render sanitized markdown at ingest time and store the rendered HTML alongside the source asset, or persist it in the database keyed by asset checksum.
2. Serve public HTML and markdown with `fresh_when` or `stale?` using `bundle.id`, `bundle.content_revision`, `asset.checksum`, and `last_replaced_at`.
3. For public documents, add explicit cache semantics that allow CDN and browser revalidation, for example `public, s-maxage=...` plus `stale-while-revalidate`.
4. For protected documents, use `private` caching with conditional requests so returning viewers can get 304s without bypassing access control.
5. Move analytics recording off the critical response path for document views, or at minimum batch the counter updates asynchronously.

### P2. File listings render the entire bundle in one HTML response

Evidence:

- `app/controllers/public/bundles_controller.rb:41-49` loads every asset in path order.
- `app/views/public/bundles/file_listing.html.erb:10-25` renders every asset row into one list with no pagination, filtering, or chunking.

Why this matters:

- A bundle with hundreds or thousands of files will produce large HTML payloads, large DOM trees, longer server render times, and slower mobile scrolling.
- File-listing bundles are exactly the kind of content that can grow without warning.
- This gets worse on poor cell coverage because the user pays for every file row before they can interact with the page.

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

Actionable fix:

1. Split the stylesheet into at least `core.css`, `admin.css`, `public_bundle.css`, and `public_home.css`.
2. Keep only shared tokens and generic primitives in the global sheet.
3. Load route-specific CSS from the layout or via `content_for :head`.
4. Consider inlining tiny critical CSS for the smallest shells, such as password-gated and single-download pages, if they remain visually simple.

### P3. The public homepage ships route-specific inline JS and forces layout during interaction

Evidence:

- `app/views/public/home/show.html.erb:28-75` embeds page-specific JavaScript inline instead of loading a cacheable route-specific asset.
- `app/views/public/home/show.html.erb:52-56` forces reflow with `el.offsetHeight` before restarting the animation.

Why this matters:

- This is not the biggest bottleneck in the app, but the code cannot be cached separately from the HTML document.
- Forced layout on interaction is unnecessary for a page that should stay lightweight.
- Inline behavior also makes it harder to tighten CSP later without allowances for inline scripts.

Actionable fix:

1. Move the homepage behavior into a route-scoped JS asset or Stimulus controller and only load it on the public home page.
2. Replace the forced-reflow animation reset with class toggles, `animationend`, or Web Animations API usage.
3. Respect `prefers-reduced-motion` for the threshold animations.

### P3. Admin list views will eventually hit the same scaling issue as public listings

Evidence:

- `app/controllers/admin/bundles_controller.rb:5-7` loads all bundles for the index.
- `app/views/admin/bundles/index.html.erb:11-30` renders all bundles in one pass.

Why this matters:

- Admin traffic is less performance-sensitive than public delivery, but people still use admin interfaces on phones and slower connections.
- If bundle count grows, the index page will become slower to render and slower to scroll.

Actionable fix:

1. Paginate bundles in the admin index.
2. Select only the fields needed by the list.
3. Apply the same treatment to API tokens and any future audit/event views before they grow large.

## Delivery Recommendations

These are not separate code findings, but they matter if the goal is fast delivery under both strong and weak network conditions.

- Put the public bundle host behind a CDN or edge cache. `config/environments/production.rb:28-29` leaves `config.asset_host` unused, and public document delivery currently depends heavily on origin performance.
- Verify Brotli or gzip for HTML, CSS, and JS at the edge. Do not assume the hosting platform is doing the right thing without measurement.
- Expose server timing for S3 fetch time, markdown render time, and analytics write time so regressions are visible in the browser.
- Keep the public path simple. The current architecture is light on JS, which is good. Preserve that advantage while improving cache behavior.

## Recommended Implementation Order

1. Fix cacheability for bundle assets and public documents.
2. Remove synchronous markdown rendering from the request path.
3. Paginate public file listings.
4. Split the shared stylesheet by surface.
5. Move the homepage script into a cacheable route-specific asset.
6. Add admin pagination as cleanup before the dataset grows.

## Verification Checklist

- A warm repeat visit to a public static site should transfer zero new CSS, JS, font, and image bytes unless the bundle changed.
- A warm repeat visit to a public markdown or HTML document should produce a 304 or CDN hit instead of a full re-render.
- The initial HTML response for a file listing should stay bounded even when the bundle contains thousands of files.
- Public password-gate and single-download pages should need only one small HTML request and one small CSS request before becoming interactive.
- Mobile and desktop runs should both be tested with real throttling, including a slow-4G profile.

## What Not To Do

- Do not add a client-heavy frontend framework to chase performance here.
- Do not spend time micro-optimizing the existing tiny icon files or inline text before the cache and TTFB issues are fixed.
- Do not keep expanding `application.css` as a global dumping ground. That pattern is cheap now and expensive later.
