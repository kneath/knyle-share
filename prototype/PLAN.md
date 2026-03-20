# Admin Area HTML Prototype Plan

## Design Direction

**Aesthetic**: Minimal & modern (Linear/Vercel style)
**Palette**: Monochrome + blue accent, with light and dark mode support
**Layout**: Stacked card list for bundles, clean detail pages
**Structure**: Multiple linked HTML files, one per screen

### Color Tokens

| Role       | Light            | Dark             |
|------------|------------------|------------------|
| Background | `#ffffff`        | `#0a0a0a`        |
| Surface    | `#fafafa`        | `#111111`        |
| Border     | `#e5e5e5`        | `#262626`        |
| Text       | `#171717`        | `#ededed`        |
| Muted      | `#737373`        | `#a3a3a3`        |
| Accent     | `#2563eb` (blue) | `#3b82f6` (blue) |
| Danger     | `#dc2626` (red)  | `#ef4444` (red)  |
| Success    | `#16a34a` (green)| `#22c55e` (green)|

### Typography

- System font stack (`-apple-system, BlinkMacSystemFont, "Segoe UI", ...`)
- Base size 15px, generous line height
- Headings in semibold, not bold

### Design Patterns (from references)

- **Plausible**: Stat row across top of detail pages, clean whitespace
- **Linear**: Dense but clean list rows, subtle borders, monochrome with minimal accent
- **Render**: Status badges with color coding, icon + name pattern
- **Fathom**: Simple name + number rows for data

---

## Screens to Build

### 1. `login.html` — Admin Login
- Centered card on a minimal page
- "Knyle Share" wordmark/title at top
- "Sign in with GitHub" button (accent colored)
- Subtle footer text about admin-only access

### 2. `setup.html` — First-Run Bootstrap
- Centered card, wider than login
- Title: "Set up Knyle Share"
- Validation checklist with pass/fail indicators:
  - Environment variables configured
  - Database reachable and migrated
  - S3 configuration present
  - S3 bucket reachable
  - S3 read/write/delete cycle
- Each item shows a check (green) or X (red) with a label
- "Re-run checks" button
- "Sign in with GitHub" button (enabled only when all checks pass)
- Clear messaging about first-login-claims-admin

### 3. `bundles.html` — Bundle List (main dashboard)
- **Header bar**: "Knyle Share" left, avatar + name + sign out right
- **Page title**: "Bundles" with a count badge (e.g., "7")
- **Stacked card list**, each card showing:
  - Bundle name (slug) as the primary text, linked to detail
  - Presentation type badge (Static Site, Markdown, Download, File Listing)
  - Second line: access mode (Public / Protected) · status (Active / Disabled)
  - Right side: view count + "last viewed X ago"
- Disabled bundles visually muted (lower opacity or muted text)
- Empty state for when there are no bundles yet
- Include sample data for 5-6 bundles covering all presentation types and states

### 4. `bundle.html` — Bundle Detail
- **Header bar**: same as bundle list, with back link to bundles
- **Bundle title section**: slug as h1, presentation type badge, URL shown below
- **Stat row** (Plausible-style): Total views | Unique viewers | Last viewed | Created
- **Status & access section**:
  - Status: Active/Disabled with toggle action button
  - Access: Public/Protected indicator
  - For protected: "Change password" action
- **Actions section**:
  - "Generate expiring link" button → links to `link.html`
  - "Disable bundle" / "Enable bundle" button
  - "Delete bundle" button (danger styled, at bottom)
- Show two states: one active+protected bundle, one disabled bundle (can be toggled via a class or shown as a second section)

### 5. `link.html` — Generate Expiring Link
- **Header bar**: same, with breadcrumb back to bundle detail
- **Page title**: "Generate expiring link" with bundle slug shown
- **Expiration presets**: Three buttons/pills for 1 day, 1 week, 1 month
- **Generated link display**: Shown in a monospace box with a "Copy" button
- Two states: before generation (pick expiry) and after generation (show link)

---

## File Structure

```
prototype/
├── shared.css          # All styles, light+dark mode via prefers-color-scheme
├── login.html
├── setup.html
├── bundles.html        # Bundle list / dashboard
├── bundle.html         # Bundle detail view
└── link.html           # Generate expiring link
```

One shared CSS file keeps styles consistent and makes iteration easy. Each HTML file links to it. No JavaScript needed — this is a static visual prototype. Dark mode handled purely via `prefers-color-scheme` media query.

---

## Build Order

1. **`shared.css`** — Set up reset, color tokens as CSS custom properties, typography, common components (buttons, badges, cards, header bar, stat row)
2. **`login.html`** — Simplest screen, validates the base styles
3. **`setup.html`** — Validation checklist, builds on login layout
4. **`bundles.html`** — Main screen, the heart of the prototype
5. **`bundle.html`** — Detail view with stats and actions
6. **`link.html`** — Small focused screen

After each screen, we'll review it in the browser preview tool and iterate before moving to the next.

---

## CSS Approach

Per the technical preferences:
- Semantic HTML first (use `h1`, `nav`, `main`, `article`, `button` etc.)
- Class names describe UI patterns: `.card`, `.badge`, `.stat-row`, `.header-bar`
- No utility classes
- CSS custom properties for the color palette, toggled by `prefers-color-scheme`
- Mobile-responsive from the start (single column, comfortable touch targets)
