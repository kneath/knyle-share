# Knyle Share application audit

September 28, 2026

Implementation follow-up: see [IMPLEMENTATION_NOTES.md](IMPLEMENTATION_NOTES.md) for the completed code changes, verification, and deployment requirements. The findings below describe the pre-change application.

The app has a good foundation: small server-rendered pages, restrained typography, content-focused public viewers, protected uploads by default, and a useful CLI. Its largest usability gaps sit around the central job: **publish something, confidently share it, and manage it later**. Finish that loop before expanding the feature set.

**Scope and evidence**

Reviewed the application’s routes, templates, styles, JavaScript, controllers, upload/storage services, CLI, and existing tests. Exercised an isolated local copy with a temporary database, mocked GitHub authentication, and in-memory object storage. Inspected desktop and 390 × 844 mobile layouts, the empty library, file selection, protected publishing, sharing, Markdown, audio, image, password errors, directory listing, and token onboarding.

The existing test suite passed: **138 tests / 855 assertions**. Existing browser system tests also passed: **5 tests / 19 assertions**. Additional request/model probes confirmed malformed upload errors return HTML, 70-character slugs pass model validation, and the password throttle’s path expression does not match `/access`.

“Observed” below means reproduced in the local browser or a focused probe. “Source-confirmed” means supported by implementation inspection. “Validate in deployment” identifies risks that require real hosting/browser measurements. Production latency, actual S3 CORS configuration, large media, real GitHub OAuth, native mobile browsers, and dark-mode rendering were not measured. PDF/video behavior was reviewed in source; sample audio/image/Markdown were exercised locally. This is a product and implementation audit, not a penetration test.

Effort is relative: **S** = contained change, **M** = multi-component work, **L** = substantial workflow or delivery change. Priorities indicate recommended sequence, not a commitment to delivery dates.

**First: repair broken behavior and trust gaps**

1. **P1 · Show the generated password after publishing. Effort M. Observed.**

   The default browser upload generates a password, sends it to the server, then redirects to a detail page that never displays it. The user has a protected bundle but cannot give someone its original password. They must replace the password or discover expiring links.

   Add a clear “Ready to share” result with the URL, one-time password, Copy link, Copy password, and Copy sharing details. Keep plaintext out of URLs and persistent storage. Explain that the password cannot be retrieved later.

   Evidence: [upload controller](/Users/kneath/code/kneath/knyle-share/app/javascript/controllers/upload_controller.js:100), [detail password block](/Users/kneath/code/kneath/knyle-share/app/views/admin/bundles/show.html.erb:104).

   Acceptance: a user can complete the default upload and give a recipient everything needed without resetting anything.

2. **P1 · Repair the access controls and their accessibility. Effort S. Observed.**

   Selecting Public sets the password group’s `hidden` attribute, but `.field-group { display: grid }` overrides its visual hiding. The password choices remain visible for a public upload. Separately, all four radio inputs use `hidden`, removing the actual controls from keyboard and accessibility navigation; the browser tree exposes their labels as plain text.

   Use properly labeled native radios in fieldsets, visually conceal them without removing focusability if retaining the pill styling, and give hidden panels reliable CSS. Add selected/focus states and an accessible custom-password label.

   Evidence: [upload form](/Users/kneath/code/kneath/knyle-share/app/views/admin/uploads/new.html.erb:40), [field styling](/Users/kneath/code/kneath/knyle-share/app/assets/stylesheets/admin.css:284).

   Acceptance: keyboard users can choose all modes; Public removes all password controls visually and semantically.

3. **P1 · Make destructive confirmations work. Effort S–M. Source-confirmed.**

   Delete bundle and Revoke token depend on `data-turbo-confirm`, but the application imports only Stimulus controllers and has no Turbo import-map entry. Those attributes currently have no confirmation behavior. The existing revoke system test submits without handling a dialog and passes.

   Add a real confirmation mechanism naming the affected bundle/token. If enabling Turbo, verify its effect on navigation, upload-controller reconnects, and the homepage’s `DOMContentLoaded` script. A focused confirmation controller is another small option. Consider recoverable deletion later.

   Evidence: [application entry point](/Users/kneath/code/kneath/knyle-share/app/javascript/application.js:2), [import map](/Users/kneath/code/kneath/knyle-share/config/importmap.rb:3), [delete button](/Users/kneath/code/kneath/knyle-share/app/views/admin/bundles/show.html.erb:144), [revoke button](/Users/kneath/code/kneath/knyle-share/app/views/admin/api_tokens/index.html.erb:79).

   Acceptance: cancel sends no mutation; confirm performs exactly one mutation. Cover both with browser tests.

4. **P1 · Validate the address before transferring the file. Effort M. Observed and source-confirmed.**

   The slug field has a pattern, but it is outside a real form and Upload invokes JavaScript directly, so native validation does not run. A malformed slug returned **422 HTML** to the JSON client in a probe, producing generic “Upload failed.” Existing-name conflicts are detected only after transfer, during processing. A 70-character slug also passes validation even though the slug becomes a DNS label.

   Rename “Slug” to “Link address,” show the resulting URL, enforce a maximum of 63 characters, validate blank/reserved/invalid names inline, and check availability before upload. Retain server-side race protection. Offer “Use another address” or an explicit replacement flow for collisions. Return structured JSON errors consistently.

   Evidence: [slug input](/Users/kneath/code/kneath/knyle-share/app/views/admin/uploads/new.html.erb:36), [upload create](/Users/kneath/code/kneath/knyle-share/app/controllers/admin/uploads_controller.rb:10), [late collision check](/Users/kneath/code/kneath/knyle-share/app/services/bundle_ingestor.rb:77), [slug validation](/Users/kneath/code/kneath/knyle-share/app/models/bundle.rb:30).

   Acceptance: invalid addresses and known collisions are explained before bytes transfer; emoji/non-Latin filenames receive a usable fallback or actionable prompt.

5. **P1 · Make “Protected” match the strength users expect. Effort M. Source-confirmed; route probe confirmed.**

   The browser generates three words from only 24 choices using `Math.random`: 13,824 possible phrases. The server generator also has a very small dictionary. The password throttle matches `/<slug>/access`, while current bundle hosts submit to `/access`, so the intended limiter does not cover the main flow.

   Use one cryptographically secure generation policy with a much larger dictionary or sufficiently strong random password. Apply throttling to canonical bundle-host access requests and return a helpful retry message. Keep tests for both canonical and legacy routes.

   Evidence: [browser generator](/Users/kneath/code/kneath/knyle-share/app/javascript/controllers/upload_controller.js:155), [server generator](/Users/kneath/code/kneath/knyle-share/app/services/generated_password.rb:1), [rate limiter](/Users/kneath/code/kneath/knyle-share/config/initializers/rack_attack.rb:8).

   Acceptance: generation has an explicit strength target and rate-limit tests exercise the routes recipients actually use.

6. **P1 · Make deletion fulfill its promise. Effort M. Source-confirmed.**

   The interface promises to delete “this bundle and all its files.” The action destroys database records; there is no storage-deletion callback or cleanup job on this path. Stored objects remain, and previously issued storage URLs may remain usable until their authorization expires.

   Capture object keys before destroying records, queue durable cleanup with retries, and expose a failure state if cleanup cannot complete. Explain any delay in removal. Include abandoned staged uploads in a separate cleanup policy.

   Evidence: [destroy action](/Users/kneath/code/kneath/knyle-share/app/controllers/admin/bundles_controller.rb:42), [bundle associations](/Users/kneath/code/kneath/knyle-share/app/models/bundle.rb:25), [asset model](/Users/kneath/code/kneath/knyle-share/app/models/bundle_asset.rb:1).

   Acceptance: deleting a fixture removes its storage objects as well as database records, including after a transient storage failure.

**Next: make the everyday workflow smoother**

7. **P2 · Put sharing at the top of bundle details. Effort M. Observed.**

   Four analytics cards and two metadata panels precede sharing controls. On mobile, “Generate expiring link” is far below the first screen. URLs, generated passwords, expiring links, and API tokens have no Copy button.

   Make the first card a compact sharing area: title, access/status, address, Copy link, Open preview, and protected-link options. Move analytics and infrequent management below it. Reuse one clipboard component with success/failure feedback and manual selection fallback. For protected bundles, distinguish copying the address from copying a password-free expiring link.

   Evidence: [bundle details](/Users/kneath/code/kneath/knyle-share/app/views/admin/bundles/show.html.erb:27), [link output](/Users/kneath/code/kneath/knyle-share/app/views/admin/bundle_links/new.html.erb:44).

   Acceptance: after publishing or reopening a bundle, its primary share action is visible without scrolling on mobile.

8. **P2 · Give uploads honest progress, cancellation, and recovery. Effort M–L. Source-confirmed.**

   The bar measures transfer to Rails; Rails then writes to S3. It can reach 100% before that storage work is done. Processing is another synchronous request. There is no cancel, timeout UI, resumable processing action, navigation warning, or recovery after refresh. A processing failure sends the user back to a form whose next attempt uploads again.

   Distinguish Transferring, Saving, and Preparing preview. Show bytes/percentage only where meaningful; use an indeterminate state for unknown work. Preserve the upload ID so processing can be retried without retransmission. Add cancel and clear network/session-expired messages. Design retries to avoid duplicate publication.

   Evidence: [upload flow](/Users/kneath/code/kneath/knyle-share/app/javascript/controllers/upload_controller.js:100), [progress handling](/Users/kneath/code/kneath/knyle-share/app/javascript/controllers/upload_controller.js:183), [server upload](/Users/kneath/code/kneath/knyle-share/app/controllers/admin/uploads_controller.rb:18).

   Acceptance: disconnect, processing failure, and refresh each have a clear, recoverable outcome.

9. **P2 · Bring replacement and folder publishing into the browser. Effort L. Source-confirmed.**

   The backend/CLI support replacement and directories, but the browser always sends `source_kind=file` and `replace_existing=false`. Dragging several files silently selects only the first; uploading a tar archive does not turn it into a site through this flow.

   Add Replace files on bundle details with a summary of URL/access effects. Support folder selection or a clearly documented archive workflow. Show the selected file count and predicted presentation before publishing. Until supported, explain single-file limitations and reject multiple-file drops explicitly.

   Evidence: [drop handling](/Users/kneath/code/kneath/knyle-share/app/javascript/controllers/upload_controller.js:75), [fixed upload parameters](/Users/kneath/code/kneath/knyle-share/app/javascript/controllers/upload_controller.js:122), [archive routing](/Users/kneath/code/kneath/knyle-share/app/services/bundle_ingest/staged_object_lister.rb:49).

   Acceptance: users can update a shared bundle without learning the CLI or changing its URL, and no selected files are silently ignored.

10. **P2 · Give mobile layouts their own composition. Effort M. Observed.**

    At 390px, the brand, API Tokens, admin name, and Sign out wrap inside a fixed 56px header. The token-page heading and introductory paragraph are squeezed alongside each other; “API Tokens” breaks into two lines with its count below. Many actions are short touch targets, and metadata expands into very tall cards.

    Keep the brand on one line, group account actions in a menu, indicate active navigation, stack explanatory page headers, and use compact mobile metadata rows. Add long-title/URL/filename wrapping. Increase important touch areas, use 16px form text, and review focus indicators and dark-mode button contrast. Keep the current restrained aesthetic.

    Evidence: [header](/Users/kneath/code/kneath/knyle-share/app/views/admin/shared/_header.html.erb:1), [header CSS](/Users/kneath/code/kneath/knyle-share/app/assets/stylesheets/admin.css:5), [page-title CSS](/Users/kneath/code/kneath/knyle-share/app/assets/stylesheets/admin.css:90), [theme tokens](/Users/kneath/code/kneath/knyle-share/app/assets/stylesheets/application.css:41).

    Acceptance: check 320/390/768px widths, long content, keyboard navigation, zoom, and light/dark themes; nothing overlaps or requires page-level horizontal scrolling.

11. **P2 · Replace development-era onboarding copy. Effort S. Observed.**

    The empty library says there is “no upload flow yet” and tells users to seed the database while Milestone 3 is in progress. This contradicts the working New bundle action.

    Use “Share your first file,” a prominent upload action, a short list of supported formats, and a secondary CLI setup link. Explain Public versus Protected near the choice. Preserve the playful public homepage; add a discreet plain-language hint that visitors need a direct shared link, without creating a public directory.

    Evidence: [empty state](/Users/kneath/code/kneath/knyle-share/app/views/admin/bundles/index.html.erb:39), [public homepage](/Users/kneath/code/kneath/knyle-share/app/views/public/home/show.html.erb:1).

    Acceptance: a first-time user can understand what to upload, who can view it, and what happens next.

12. **P2 · Improve audio controls without downloading the whole recording for decoration. Effort M. Observed and source-confirmed.**

    The player offers Play and a mouse/touch canvas, with no keyboard seek, volume, speed, buffering state, or playback-error message. It starts a full-file fetch and decode immediately to draw the waveform, alongside the audio element’s media loading. Production S3 CORS may also prevent that fetch; the current fallback silently draws a flat line.

    Start with native audio controls or an accessible seek slider. Handle rejected `play()` promises and media error/waiting events. Generate waveform peaks during ingest, or load them lazily from a small sidecar. Cancel work on navigation.

    Evidence: [audio view](/Users/kneath/code/kneath/knyle-share/app/views/public/bundles/audio_display.html.erb:8), [play handling](/Users/kneath/code/kneath/knyle-share/app/javascript/controllers/audio_player_controller.js:37), [full-file waveform fetch](/Users/kneath/code/kneath/knyle-share/app/javascript/controllers/audio_player_controller.js:80).

    Acceptance: opening a long recording does not eagerly fetch/decode its entire body for the waveform; keyboard seeking and clear error recovery work. Validate actual storage CORS separately.

13. **P2 · Keep media usable after an idle tab or late seek. Effort M. Validate in deployment.**

    Media source URLs are presigned with a five-minute default expiry. Public document HTML is also cacheable for five minutes with additional stale reuse. The page can therefore contain a URL older than the viewer realizes, and later range requests may fail after expiration. ETag time buckets do not refresh an already-open tab.

    Refresh media authorization on a relevant error while retaining playback position, or use a delivery scheme that remains usable for the viewing session. Align HTML cache lifetime with remaining media-URL validity. Keep protected authorization boundaries intact.

    Evidence: [inline media URL](/Users/kneath/code/kneath/knyle-share/app/controllers/public/bundles_controller.rb:249), [URL TTL](/Users/kneath/code/kneath/knyle-share/app/services/bundle_storage.rb:7), [document caching](/Users/kneath/code/kneath/knyle-share/app/controllers/public/base_controller.rb:141).

    Acceptance: verify play/seek after 10–15 minutes idle, a cached page near expiry, and expired protected access using real S3 responses.

14. **P2 · Make the library easy to find things in. Effort M. Source-confirmed.**

    The admin index renders all bundles ordered by `updated_at`, without search, filters, sorting controls, or pagination. Display badges classify images, audio, PDFs, and video as “Single Download,” hiding useful distinctions.

    Add title/address search, Public/Protected and Active/Disabled filters, a visible sort choice, and bounded pagination. Use recognizable media-type labels/icons. Offer quick Copy link and Open actions without nesting buttons inside the row link. Preserve filter/page state when returning from details.

    Evidence: [index query](/Users/kneath/code/kneath/knyle-share/app/controllers/admin/bundles_controller.rb:5), [library rows](/Users/kneath/code/kneath/knyle-share/app/views/admin/bundles/index.html.erb:15), [presentation labels](/Users/kneath/code/kneath/knyle-share/app/models/bundle.rb:7).

    Acceptance: a library of hundreds of bundles remains a small initial response and users can find a known item quickly.

15. **P2 · Add a few useful viewer affordances. Effort M, separable by format. Observed/source-confirmed.**

    Images are fit into the viewport with no original-size/zoom control; a detailed map or screenshot becomes hard to inspect on a phone. Directory rows repeat filename and path and only download files. PDF has an untitled iframe and no explicit open-in-browser fallback. Video lacks `playsinline` and runtime unsupported-codec guidance. Markdown is entirely monospace and wide tables have no dedicated overflow container.

    Add Fit/Actual size and open-original controls for images; preview/download distinctions and Download all for folders; an iframe title and PDF fallback; inline mobile video and useful error states. Keep Markdown’s personality if desired, but evaluate a proportional reading mode, locally scrolling tables, and copy-code actions.

    Evidence: [public viewer templates](/Users/kneath/code/kneath/knyle-share/app/views/public/bundles/image_display.html.erb:1), [directory view](/Users/kneath/code/kneath/knyle-share/app/views/public/bundles/file_listing.html.erb:35), [PDF view](/Users/kneath/code/kneath/knyle-share/app/views/public/bundles/pdf_display.html.erb:4), [video view](/Users/kneath/code/kneath/knyle-share/app/views/public/bundles/video_display.html.erb:5), [Markdown styles](/Users/kneath/code/kneath/knyle-share/app/assets/stylesheets/application.css:387).

    Acceptance: a recipient can inspect common content comfortably without downloading it merely to see detail. Test real iOS/Android PDF and video behavior before choosing heavier viewer libraries.

16. **P2 · Make errors explain the next step and preserve the destination. Effort M. Observed/source-confirmed.**

    Incorrect passwords reload the gate with unassociated error text; missing assets/directories often return plain text. After session expiry, access redirects to the bundle root and successful password entry also returns there, losing a requested nested file/download. Admin login likewise returns to the library rather than the original page.

    Provide consistent expired, disabled, missing-file, and offline states with actionable wording. Associate password errors with the input, focus the field on failure, add a show-password control, and announce upload status/errors. Preserve a validated same-origin return path across authentication.

    Evidence: [public access controller](/Users/kneath/code/kneath/knyle-share/app/controllers/public/access_controller.rb:17), [access redirect](/Users/kneath/code/kneath/knyle-share/app/controllers/public/base_controller.rb:45), [plain-text errors](/Users/kneath/code/kneath/knyle-share/app/controllers/public/bundles_controller.rb:117), [admin login destination](/Users/kneath/code/kneath/knyle-share/app/controllers/admin/sessions_controller.rb:49).

    Acceptance: a recipient opening a nested file returns to that exact file after unlocking it; errors are understandable with a screen reader.

17. **P2 · Clarify expiring-link behavior and access changes. Effort S–M. Observed/source-confirmed.**

    Expiration presets look like selection pills but submit immediately; the default 1 week looks selected before any link exists. Generated links occupy a large wall of text on mobile. Expiration uses server time without identifying the timezone. Password replacement invalidates prior links/sessions through `access_revision`, but the form does not explain that consequence. Disabled bundles still offer link generation.

    Use a duration selector plus explicit Create link and Copy actions, display relative and timezone-qualified expiry, and explain which access is invalidated by a password change. Warn or disable sharing while the bundle is disabled. A later “Revoke all links” action can reuse the access revision; individual revocation requires separately tracked links.

    Evidence: [link form](/Users/kneath/code/kneath/knyle-share/app/views/admin/bundle_links/new.html.erb:23), [password rotation](/Users/kneath/code/kneath/knyle-share/app/models/bundle.rb:90), [signed-link verification](/Users/kneath/code/kneath/knyle-share/app/services/public_bundle_access.rb:17).

    Acceptance: users can predict when a link stops working and what a password reset affects.

18. **P2 · Let owners edit the things recipients see. Effort M. Source-confirmed.**

    Titles are generated by title-casing the slug and cannot be edited through the admin. Public/protected status also cannot be changed through this UI. Descriptive titles should not require changing a shared URL.

    Add Edit details for title and, where appropriate, description. Add an explicit access-change flow that handles password creation and session/link invalidation. Keep the existing URL stable by default. Show recipient-facing previews and add useful share metadata for public content; protected metadata should stay minimal.

    Evidence: [title derivation](/Users/kneath/code/kneath/knyle-share/app/services/bundle_ingestor.rb:153), [available routes](/Users/kneath/code/kneath/knyle-share/config/routes.rb:34), [public layout metadata](/Users/kneath/code/kneath/knyle-share/app/views/layouts/application.html.erb:1).

    Acceptance: owners can correct a title without reuploading and can understand the consequences of changing visibility.

19. **P2 · Make analytics labels honest about what is counted. Effort S–M. Source-confirmed.**

    “Unique Viewers” counts protected viewer sessions, not distinct people; public bundles show n/a. Conditional-cache hits return before recording a view, and browser/CDN cache hits do not reach Rails. The current counters therefore do not represent all opens. Async jobs also use the in-process adapter in production, making counts best-effort around restarts.

    Use modest wording such as Recorded views and Authorized sessions, explain public limitations, remove the redundant “0 / 0 views,” and reduce analytics’ visual prominence. Decide whether approximate counts are enough before introducing durable analytics delivery or client-side counting.

    Evidence: [detail stats](/Users/kneath/code/kneath/knyle-share/app/views/admin/bundles/show.html.erb:27), [unique labels](/Users/kneath/code/kneath/knyle-share/app/helpers/admin/bundles_helper.rb:28), [analytics service](/Users/kneath/code/kneath/knyle-share/app/services/public_bundle_analytics.rb:1), [production job adapter](/Users/kneath/code/kneath/knyle-share/config/environments/production.rb:58).

    Acceptance: labels and help text accurately describe counters under refreshes, new sessions, and cache hits.

**Then: improve delivery and supporting workflows**

20. **P2 · Target actual latency sources while retaining the small frontend. Effort L; measure before choosing infrastructure. Source-confirmed risks.**

    Browser uploads travel through Rails to S3, while the CLI already uses presigned direct uploads. Ingest performs object-store work inside a database transaction, potentially occupying a request worker and prolonging SQLite write contention. Public HTML still reads storage on a cold request; public sub-assets incur authorization/redirect hops. Existing Markdown prerendering, directory pagination, split CSS, and cache controls are useful work already in place.

    Reuse direct-upload plumbing for the browser, move lengthy preparation into a recoverable job, and keep the final database commit short. For popular public bundles, evaluate stable versioned asset delivery/cache improvements. Measure cold/warm requests, large uploads, and concurrent admin operations with real storage. Confirm edge compression instead of assuming it. Avoid a framework rewrite for these issues.

    Evidence: [browser transfer](/Users/kneath/code/kneath/knyle-share/app/controllers/admin/uploads_controller.rb:18), [ingest transaction](/Users/kneath/code/kneath/knyle-share/app/services/bundle_ingestor.rb:20), [asset redirects](/Users/kneath/code/kneath/knyle-share/app/controllers/public/base_controller.rb:92), [existing performance work](/Users/kneath/code/kneath/knyle-share/sausage/PERFORMANCE_FINDINGS.md:1).

    Acceptance: establish real baseline timings and response sizes, then show reductions in redundant transfer, worker occupancy, and repeat-view bytes without weakening protected access.

21. **P3 · Finish setup, token, and CLI onboarding. Effort S–M. Source-confirmed; token page observed.**

    Setup initially says Re-run checks before checks have run; failures expose low-level error details without linked remedies. Tokens can be created, but the UI does not lead directly into a ready-to-use CLI setup flow. The CLI has sensible validation and explicit phases, but large transfers have no byte progress or retry/resume workflow.

    Change the initial action to Run checks, show Checking feedback, and link failures to the relevant setup instructions. After token creation, offer Copy token and a short CLI configuration guide using the existing secret prompt. Keep raw tokens out of shell-history-oriented examples. Add terminal upload progress while preserving clean `--json` output; distinguish “published successfully, link creation failed” from total upload failure.

    Evidence: [setup view](/Users/kneath/code/kneath/knyle-share/app/views/admin/setup/show.html.erb:30), [token view](/Users/kneath/code/kneath/knyle-share/app/views/admin/api_tokens/index.html.erb:13), [CLI publishing](/Users/kneath/code/kneath/knyle-share/lib/knyle_share/cli.rb:96), [CLI transfer](/Users/kneath/code/kneath/knyle-share/lib/knyle_share/client.rb:77).

    Acceptance: a new owner can go from configuration to their first browser/CLI share using guidance available in the app.

**Suggested implementation order**

| Pass | Work | Intended result |
| --- | --- | --- |
| 1. Reliability | Findings 1–6, plus the false empty-state copy | Publishing, protection, validation, and deletion do what the interface promises. |
| 2. Sharing experience | Findings 7, 8, 10, 11, 16, 17 | First upload ends in a useful share result; repeat use feels fast and clear on a phone. |
| 3. Content and management | Findings 9, 12–15, 18, 19 | Owners can manage a growing collection and recipients can comfortably view its contents. |
| 4. Delivery and onboarding | Findings 20, 21, informed by measured usage | Larger files and self-hosting work smoothly without unnecessary complexity. |

**Regression coverage to add when implementing**

The passing tests do not cover several important browser behaviors. Add focused coverage for the default protected upload’s password handoff; keyboard-only access selection; Public hiding password fields; malformed/reserved/long/colliding slugs; cancellation of delete/revoke; retrying processing without retransmission; expired-session deep links; and media failure recovery. Add a small visual review matrix for mobile/desktop, long content, and light/dark mode. Test storage cleanup and canonical-route throttling at the service/integration boundary.

No application implementation changes were made during this audit. Test data, authentication mocks, and storage fixtures were confined to the temporary audit environment.
