# CLAUDE.md — Notes for Claude working in this repo

This file captures context that isn't obvious from the code: architectural choices, where the seams are, conventions to preserve, and things that have burned us before. Read this before making non-trivial changes.

## What Prospero is

A reverse weather forecaster. Users define **activity patterns** (a set of weather + tide + time-of-day constraints plus a duration). Prospero scans a 14-day forecast and reports windows that satisfy the pattern, each tagged with a quality score 0–1. The calendar view renders these as colored bars — one track per day, hours across.

See `README.md` for the user-facing overview.

## Stack

- Swift 6.2, strict concurrency
- Hummingbird 2 + Plot (HTML DSL) + HTMX
- Fluent ORM — PostgreSQL in prod, SQLite in dev
- `hummingbird-auth` (passkeys, sessions, invitations, admin, masquerade) — sibling repo at `/Volumes/Campfire/Projects/hummingbird-auth`
- `plot-htmx` (HTMX attributes for Plot) — sibling repo

## Code layout

```
Sources/Prospero/
  Application.swift            — @main, subcommands (serve/migrate/invite), DI wiring
  AppRequestContext.swift      — conforms to AuthRequestContextProtocol
  ErrorLoggingMiddleware.swift
  Models/
    ProsperoUser.swift         — conforms to AuthUser
    ActivityPattern.swift      — the core domain model
  Migrations/                  — app-owned schema (auth migrations come from the library)
  Routes/
    PatternRoutes.swift        — CRUD for activity patterns
    ForecastRoutes.swift       — ad-hoc forecast (legacy / single-pattern)
    CalendarRoutes.swift       — /calendar, multi-pattern 14-day view
  Services/
    OpenMeteoClient.swift      — hourly forecast fetch
    TideClient.swift           — NOAA CO-OPS 6-minute harmonic predictions
    PatternMatcher.swift       — sliding-window scoring algorithm
    ForecastAssembler.swift    — orchestrates weather + tide + matcher
    HuePlacer.swift            — OKLCH color assignment + quality-modulated chroma
    PatternHueService.swift    — re-balances hues when the pattern set changes
  Views/                       — Plot components; PageLayout is the outer shell
  Static/                      — CSS, static JS (htmx.min.js)
```

## Architectural seams

### Auth is a library, not app code

All passkey / session / invitation / admin / masquerade logic lives in `hummingbird-auth`. This app:

1. Defines `ProsperoUser : AuthUser` (Fluent model)
2. Defines `AppRequestContext : AuthRequestContextProtocol`
3. Calls `installAuthRoutes`, `installProfileRoutes`, `installAdminRoutes` in `Application.swift`
4. Wraps library Views in `PageLayout` (the shared Plot component)

**Don't** reach into the auth library to special-case Prospero. If a feature needs an app-level hook, add it to the library's callbacks / configuration, not a Prospero-specific branch. Life Balance also consumes this library.

### Context hierarchy

- `AppRequestContext` — base request context. `user` is optional.
- `AuthenticatedContext<AppRequestContext>` — used for the `authed` route group. `user` is non-optional.
- `AdminContext<AppRequestContext>` — used for admin routes. `user` is non-optional and `isAdmin`.

Route groups pick the right context; handlers just read `context.user`.

### View layer

`PageLayout` conforms to `ResponseGenerator`, so handlers can `return PageLayout(...) { … }` directly — no explicit `.html.render()` call. Library views (`LoginView`, `RegistrationView`, `ProfileView`, `AdminUsersView`, `AdminInvitationsView`) are embedded inside Prospero's `PageLayout` via closure callbacks passed to the library's route installers.

## Data flow: calendar view

1. `CalendarRoutes` loads the user's patterns.
2. For each pattern, concurrently (`TaskGroup`) fetch Open-Meteo hourly forecast + NOAA tide series.
3. `PatternMatcher` slides a window of `durationHours` across the series, scoring each position 0–1.
4. Connected qualifying hours are merged into `CalendarWindow`s.
5. `CalendarView` renders 14 day rows, bars positioned by start/end fraction within the day, color = `HuePlacer.goalColor(hue:quality:)` (OKLCH, chroma scaled quadratically by quality).
6. Info cards show on hover **and** `:focus` / `:focus-within` (bars have `tabindex="0"` so touch devices can tap to focus).

## Color system (HuePlacer)

Each pattern gets a hue angle (0..<360). Hues are re-balanced when patterns are added/removed to maximize angular separation (binary search + greedy). A user can pin a pattern's hue via `isHueFixed`.

Colors are **OKLCH**:
- Legend / bar base: `goalColor(hue:)` — 65% L, 0.18 chroma
- Quality-modulated bar: `goalColor(hue:quality:)` — 85% L, chroma ramps quadratically `0.01 → 0.18`

The quadratic ramp + fixed 85% lightness was tuned so black text reads on every bar and the perceptible difference between Fair/Good/Excellent is visible. Don't switch to linear chroma without reconsidering text legibility.

## Conventions to preserve

- **Swift 6 strict concurrency** — no `Sendable` warnings. Library models are `@unchecked Sendable` where Fluent requires it.
- **Base64 normalization at storage boundaries.** `swift-webauthn` mixes base64 and base64url between registration and authentication. The library handles this; don't add new WebAuthn code without `normalizeToBase64URL()` at every field write.
- **CSRF tokens on state-changing library forms.** PageLayout's masquerade form already wires this from `PageContext`. New POST endpoints that mutate user state should follow the same pattern.
- **Cookie path scoping.** Prospero is designed to coexist with other apps on one domain behind a reverse proxy. `SessionConfiguration` uses the default path — don't harden it to `/` without thinking about collisions.
- **Empty form fields → nil, not 0.0.** Optional Doubles on `ActivityPattern` are decoded from `String?` and parsed manually. Don't change them to `Double?` with auto-decoding — empty strings crash the decoder.
- **No multi-statement switches in `@ComponentBuilder`.** Swift 6 generics can't handle it. Use ternaries or compute the value first.

## Things that have burned us

- **`AuthRedirectMiddleware` redirecting API calls.** It now checks `Accept: application/json` and `Content-Type: application/json` before redirecting. If you see JSON API calls getting 302'd to `/login`, that's the check.
- **SQLite ALTER TABLE.** Use it sparingly — SQLite's ALTER is restricted. For new columns on existing tables, prefer adding to the base `Create…` migration if the schema hasn't shipped yet; otherwise write a proper add-column migration.
- **Three-way info card anchoring.** Calendar bars near the left or right edge overflow the viewport. Thresholds (currently `< 0.2` → left, `>= 0.65` → right, else center) were tuned by eye against real forecast data. Adjust if you add wider cards.
- **Generic closures nesting Decodable types.** Swift 6 can't always infer them. Move the struct to module scope if you hit `generic parameter could not be inferred`.

## Subcommands

- `prospero serve [--auto-migrate] [--base-path /prospero]` — web server. `--base-path` (or `PROSPERO_BASE_PATH`) mounts the app under a path prefix for path-based reverse-proxy sharing; defaults to `/`.
- `prospero migrate [--revert]` — schema
- `prospero invite --email … --expires-days N --base-url …` — produce an invitation URL

## Mount-path mechanics

When `--base-path /prospero` is set:

- `normalizeMountPath` produces `""` for root or `"/prospero"` (leading slash, no trailing).
- The normalized path is written back to `PROSPERO_BASE_PATH` so `AppRequestContext.mountPath` — a computed property — reads it.
- All app routes are registered on `app = router.group(RouterPath(mountPath))`, so `/patterns` at root becomes `/prospero/patterns`.
- Library route installers compose automatically: `installAuthRoutes(on: app, …)` lands auth routes at `/prospero/auth/…` because Hummingbird's `RouterGroup` prepends the outer path. `installProfileRoutes` and `installAdminRoutes` do the same.
- Admin handlers' internal redirects use `context.mountPath` (which `AuthenticatedContext`/`AdminContext` copy through) to stay inside the app.
- `FileMiddleware` takes `urlBasePath: mountPath` so `/prospero/styles.css` resolves to the file named `styles.css` in the static bundle.
- `SessionConfiguration.cookiePath` is set to the mount path, scoping the session cookie so siblings on the same domain don't see it.
- `AuthConfiguration.pathPrefix` / `.loginPagePath` / `.invitePagePath` carry the mount path, so anything reading them (notably `AuthRedirectMiddleware`) produces full-path redirects.
- `/healthz` is **outside** the mount path — probes don't need to know where the app is mounted.
- Views use the top-level `mountURL(_:)` helper to build href/action attributes.

First registered user is automatically promoted to admin — this makes bootstrap painless. Don't "fix" it unless you also build a first-run admin setup flow.

## Sibling projects

- **Life Balance** (`/Volumes/Campfire/life-balance`) — older, more mature HB2+HTMX app; still the canonical reference for library patterns. Consumes the same `hummingbird-auth` library.
- **Looseleaf** — older, less mature. Don't model new work on it.

## Deployment

Target is Linode Kubernetes with a shared PostgreSQL pod (cost constraint — can't afford a per-app block-storage PG instance). Multiple apps sit behind Nginx with path-based routing, hence the cookie-scoping requirement. Deployment manifests aren't in this repo yet.

## Memory / user preferences

- Commit when a feature is done, not after every tweak.
- User tests on desktop; phone testing happens post-deploy.
- Focus on Swift-native idioms and Hummingbird 2 patterns; don't suggest Vapor-specific approaches.
