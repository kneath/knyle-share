# Technical Preferences

This document captures the default technical preferences for this repository. It is a starting point, not a rigid rulebook. If the codebase teaches us a better pattern later, we should update this document instead of letting conventions drift silently.

## General Shape

- Prefer boring, conventional Rails over clever architecture
- Optimize for a small app that is easy to understand, deploy, and maintain
- Favor built-in Rails features before adding gems or custom frameworks
- Keep the system approachable for someone self-hosting on Render with AWS S3

## Rails Defaults

- Start with a standard Rails app structure
- Prefer ERB, Rails controllers, Active Record, and regular Rails routing conventions
- Keep controllers thin and focused on HTTP concerns
- Keep models responsible for domain behavior and invariants
- Introduce POROs or service objects only when the workflow clearly crosses multiple models or external systems
- Avoid creating application-specific abstractions before they pay for themselves

## Frontend Approach

- Default to server-rendered HTML
- Prefer Turbo and Stimulus for interactivity instead of building a separate SPA
- Keep JavaScript small, purposeful, and close to the UI behavior it supports
- Prefer straightforward CSS over heavy frontend tooling unless a clear need appears
- Every view should work well on both mobile and desktop layouts
- Every view should support both light and dark color schemes
- Use real `<a>` elements for navigation and links, even when JavaScript enhances the interaction

## CSS Preferences

- Prefer semantic HTML structure before adding classes
- Prefer styling elements like `h1`, `h2`, `p`, `ul`, and `button` when the styling is truly tied to the element's role
- Prefer class names that describe a reusable pattern or interface role over one-off visual declarations
- Semantic visual names like `box`, `panel`, `notice`, or `large-group` are fine when they describe a recurring UI concept
- Avoid Tailwind-like utility naming such as `font-xxl`, `mt-12`, or `text-center` as the primary styling approach
- Avoid class names that just restate a single CSS declaration
- Use classes when a component or pattern needs a stable hook, not as a substitute for document structure
- Keep typography decisions centralized so headings and body text read consistently across the app

## Database and Persistence

- Default to SQLite for development and the cheapest production deployment path
- Keep the schema compatible with Postgres so larger deployments can upgrade cleanly
- Avoid database-specific features unless they are isolated and justified
- Favor clear migrations over clever migration code
- Treat bundle files as object storage concerns, not database blobs

## Background Work

- Keep request paths responsive
- Move upload processing, bundle classification, and other heavier work out of the request when needed
- Prefer Rails-native job infrastructure before reaching for external queue systems
- Design background workflows so failures are visible and recoverable

## API Design

- Keep the API small and purpose-built for the CLI and admin flows
- Prefer explicit JSON responses over heavy serializer layers
- Keep route design conventional and easy to inspect
- Avoid turning internal app concepts into public API surface unless necessary

## Dependencies

- Add as few gems as possible
- Every dependency should remove meaningful work or risk
- Prefer mature, widely used gems over fashionable ones
- If Rails already solves the problem well enough, use Rails

## Testing

- Write tests for behavior that matters
- Prefer integration and system tests for important user flows
- Test uploads, authentication, and bundle access the way a real user experiences them
- Keep lower-level tests fast and focused
- Avoid over-mocking Rails internals or external boundaries

## Code Style

- Favor clarity over terseness
- Prefer explicit names over comments when possible
- Keep methods and classes small enough to understand in one pass
- Avoid unnecessary metaprogramming
- Prefer plain Ruby objects and straightforward conditionals over indirection
- Add comments when they explain intent or a non-obvious constraint, not when they restate the code

## Operational Preferences

- Design for failure and partial outages
- Keep configuration driven by environment variables
- Make first-run setup easy to validate
- Prefer deployment choices that keep the app cheap and easy to host
- Treat uploaded bundle content as untrusted input everywhere

## Product-Specific Leanings

- Public and admin surfaces should stay clearly separated
- Authentication should be simple for viewers and strict for admins
- CLI workflows should minimize friction without hiding important decisions
- Analytics should stay lightweight and answer practical questions, not become a reporting platform

## Decision Bias

When multiple implementation options are reasonable, prefer the option that is:

- More conventional in Rails
- Easier to explain to another developer
- Easier to self-host on Render
- Less dependent on third-party infrastructure
- Simpler to test end-to-end
