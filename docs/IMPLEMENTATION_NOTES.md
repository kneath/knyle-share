# Audit implementation

The September 28 user-experience audit has been implemented across publishing,
sharing, administration, public viewers, and the CLI. The original audit records
the pre-change behavior; this document describes the resulting application.

| Audit findings | Implemented behavior |
| --- | --- |
| 1, 7 | Uploads finish on a Ready to share screen with the address, one-time password, and copyable sharing details. Bundle details lead with sharing controls. Reusable clipboard controls include manual-copy feedback. |
| 2, 10 | Native labeled access radios, reliable hidden panels, focus treatment, larger controls, mobile account navigation, wrapping long content, and corrected dark-mode button colors. |
| 3 | Delete/revoke confirmations identify their targets; cancel is covered by browser tests. Visibility changes explain access consequences. |
| 4 | Address preview, 63-character validation, preflight collision checks, structured JSON failures, and clear replacement entry points. |
| 5 | Browser, server, and CLI generate passwords from 128 random bits. Both canonical and legacy password routes are throttled. |
| 6 | Database-backed storage-cleanup records survive outages/restarts. Deletion, replaced files, canceled uploads, and expired staging data are cleaned up with retries. The library surfaces pending/failed cleanup. |
| 8, 20 | Direct-to-storage browser transfer with a same-origin fallback, honest transfer/preparation states, cancellation, persistent upload status, queued preparation, retry without retransmission, and idempotent publication. Storage IO is outside the final publication transaction. Controllers load on demand. |
| 9 | Browser replacement and `.tar.gz` / `.tgz` folder/site publishing, format guidance, explicit multiple-file drop errors, and replacement revision checks. |
| 11, 21 | Useful first-upload and CLI onboarding, a Run checks state, configuration guidance, and a plain-language hint on the public homepage. |
| 12, 13 | Native audio controls and playback speed replace eager waveform decoding. Audio/video/image previews can refresh expired source URLs after rechecking access. Media HTML is not cached with expiring credentials. PDFs offer a fresh direct-open fallback. |
| 14 | Search, access/status filters, sorting, 25-item pagination, real media-type labels, quick sharing actions, and library return paths. Entry-asset preloading avoids fetching entire bundles to label library rows. |
| 15 | Image Fit/Actual size and original-file actions; directory preview/download choices; prepared Download all archives; accessible PDF titles; inline mobile video; Markdown reading-font toggle, scrolling tables, and copy-code actions. |
| 16 | Associated password errors, show-password controls, useful missing-file states, live upload feedback, and validated return paths after authentication. |
| 17 | Explicit expiration selection/Create link flow, copy controls, UTC-qualified expiration, disabled-bundle guidance, and revoke-all-links/sessions action. |
| 18 | Editable titles/descriptions/visibility at stable addresses, access-revision changes, and public-only share metadata. |
| 19 | Recorded views and Authorized sessions labels explain the limits of cached visits and session-based counts. |
| 21, CLI | Interactive byte progress, a bounded transfer retry, `resume UPLOAD_ID`, and successful publication results with a warning when only link creation fails. JSON output stays machine-readable. |

## Deployment

Apply the two new migrations and use `bin/start`, which supervises Puma and the
publishing worker against the same persistent SQLite disk. The Render blueprint
has been updated. Other hosts can supervise `bin/publishing-worker` separately
on the same machine. Existing async analytics remain approximate; publishing
and deletion have persistent recovery records.

S3 CORS is optional for compatibility: without it, browser uploads fall back to
Rails. Configure the exact admin origin to benefit from direct transfers. See
[Deployment.md](Deployment.md) for the rule and recovery commands.

Generated passwords remain available in the upload page's memory only. Refresh
or navigation clears them; recovery can finish publishing but cannot recover a
lost plaintext password. Owners can reset it from bundle details.

Folder publishing accepts archives, rather than a native directory picker.
New/replaced directory bundles receive a prepared Download all archive. Older
bundles retain their existing objects; republishing adds that archive. Archives
are limited to 10,000 files and 256 MB uncompressed and assembled using temporary
disk space. A file transfer interrupted before staging restarts from the beginning;
preparation after staging can resume without resending bytes.

## Verification and remaining environment checks

Final local verification passed: 161 application tests with 974 assertions and
8 browser tests with 52 assertions, with no failures, errors, or skips.
`git diff --check` also passed. Tests used isolated temporary databases.

The regular suite covers authentication, storage/ingest, CLI/API compatibility,
address validation, upload idempotency/cancellation, stale replacement rejection,
cleanup recovery, search/pagination, protected deep links, media refresh, and
canonical password throttling. Browser coverage includes password handoff,
keyboard access choices, delete/revoke cancellation, and long-content layouts at
320, 390, and 768 pixels in light and dark themes. Desktop/mobile screenshots were
also reviewed manually in the local fixture environment.

These changes have not been deployed. Real S3 CORS, cold/warm hosting latency,
edge compression, idle media range requests, and native iOS/Android PDF/video
behavior still require the release checks documented in Deployment.md. No live
bucket settings, public CDN, or hosting configuration was changed remotely.
