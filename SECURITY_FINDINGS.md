# Security Findings

This document records the current internet-deployment security review for Knyle Share.

## Need to Address

### 2. Shared-Origin Static Sites Can Exfiltrate Protected Bundles

Any uploaded `static_site` bundle can run arbitrary JavaScript on the shared public origin. Because protected-bundle access is enforced with path-scoped cookies, a malicious public bundle can make same-origin requests to other bundle paths and read responses for visitors who have already unlocked those bundles.

Relevant code:
- [app/services/bundle_ingest/classifier.rb#L32](/Users/kneath/code/kneath/knyle-share/app/services/bundle_ingest/classifier.rb#L32)
- [app/controllers/public/base_controller.rb#L61](/Users/kneath/code/kneath/knyle-share/app/controllers/public/base_controller.rb#L61)
- [app/services/public_viewer_session_manager.rb#L57](/Users/kneath/code/kneath/knyle-share/app/services/public_viewer_session_manager.rb#L57)
- [app/services/public_bundle_access.rb#L13](/Users/kneath/code/kneath/knyle-share/app/services/public_bundle_access.rb#L13)
- [config/initializers/content_security_policy.rb#L7](/Users/kneath/code/kneath/knyle-share/config/initializers/content_security_policy.rb#L7)

Current disposition:
- Must be fixed before treating `static_site` bundles as safe on a public deployment.
- Mitigation implemented: all bundles now use isolated `slug.PUBLIC_HOST` subdomains, and protected nested asset requests are restricted to same-origin fetches.

### 4. Password Rotation Does Not Revoke Existing Access

Changing a protected bundle password updates the password digest, but it does not invalidate active viewer sessions or previously issued signed links. Bundle replacement also explicitly preserves those access paths.

Relevant code:
- [app/controllers/admin/bundles_controller.rb#L19](/Users/kneath/code/kneath/knyle-share/app/controllers/admin/bundles_controller.rb#L19)
- [app/models/bundle.rb#L90](/Users/kneath/code/kneath/knyle-share/app/models/bundle.rb#L90)
- [app/services/public_bundle_access.rb#L13](/Users/kneath/code/kneath/knyle-share/app/services/public_bundle_access.rb#L13)
- [app/services/bundle_access_link.rb#L9](/Users/kneath/code/kneath/knyle-share/app/services/bundle_access_link.rb#L9)
- [app/services/bundle_ingest/replacement_planner.rb#L19](/Users/kneath/code/kneath/knyle-share/app/services/bundle_ingest/replacement_planner.rb#L19)

Current disposition:
- Must be fixed so password rotation and replacement can function as real revocation boundaries.

### 5. Public Delivery Is Vulnerable to Memory/Availability DoS

Public requests fully buffer S3 objects into Ruby memory before responding. On the documented single-process Render deployment, repeated requests to large public bundles can exhaust memory or tie up the app. View analytics also take a database lock on every request.

Relevant code:
- [app/services/bundle_storage.rb#L12](/Users/kneath/code/kneath/knyle-share/app/services/bundle_storage.rb#L12)
- [app/controllers/public/base_controller.rb#L52](/Users/kneath/code/kneath/knyle-share/app/controllers/public/base_controller.rb#L52)
- [app/controllers/public/base_controller.rb#L64](/Users/kneath/code/kneath/knyle-share/app/controllers/public/base_controller.rb#L64)
- [app/services/public_bundle_analytics.rb#L5](/Users/kneath/code/kneath/knyle-share/app/services/public_bundle_analytics.rb#L5)
- [render.yaml#L17](/Users/kneath/code/kneath/knyle-share/render.yaml#L17)

Current disposition:
- Must be fixed before assuming the service is resilient on the open internet.

## Will Not Address

### 1. Fresh Deployments Are First-Visitor Claimable

The first GitHub user to complete OAuth on an unclaimed deployment becomes the permanent admin. This is a real deployment risk, but it is currently accepted as part of the first-run ownership model.

Relevant code:
- [app/controllers/admin/sessions_controller.rb#L30](/Users/kneath/code/kneath/knyle-share/app/controllers/admin/sessions_controller.rb#L30)
- [app/models/installation.rb#L18](/Users/kneath/code/kneath/knyle-share/app/models/installation.rb#L18)
- [app/views/admin/setup/show.html.erb#L31](/Users/kneath/code/kneath/knyle-share/app/views/admin/setup/show.html.erb#L31)
- [render.yaml#L24](/Users/kneath/code/kneath/knyle-share/render.yaml#L24)

Current disposition:
- Accepted for now as a product decision. Deployment owners need to claim fresh installs immediately.

### 3. Generated Passwords Are Trivially Brute-Forceable

The built-in generated-password scheme uses only three words from a 31-word list, which produces about 30,000 possible passwords. This is weak for internet-facing protected content, but it is currently accepted.

Relevant code:
- [app/services/generated_password.rb#L2](/Users/kneath/code/kneath/knyle-share/app/services/generated_password.rb#L2)
- [lib/knyle_share/password_generator.rb#L5](/Users/kneath/code/kneath/knyle-share/lib/knyle_share/password_generator.rb#L5)
- [config/initializers/rack_attack.rb#L8](/Users/kneath/code/kneath/knyle-share/config/initializers/rack_attack.rb#L8)

Current disposition:
- Accepted for now as a usability decision, despite the security tradeoff.
