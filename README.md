# Prospero

A **reverse weather forecaster**. Instead of asking "what will the weather be next Tuesday?", Prospero answers "when in the next two weeks will the weather be right for *this activity*?"

You define **activity patterns** — a set of conditions like "4 hours, 60–80°F, humidity below 70%, wind under 10 knots, not at low tide" — and Prospero scans the upcoming forecast to find windows that qualify, ranked by how well they match.

## Why

Boat projects, fiberglassing, painting, sailing, hiking — many outdoor activities have narrow weather requirements that rarely all line up. Rather than mentally cross-referencing a hourly forecast, you describe the activity once and let the forecaster find the windows for you.

## Features

- **Passkey sign-in** (WebAuthn) — no passwords
- **Per-user patterns** with color-coded identity (OKLCH hues auto-spaced for visual distinction)
- **14-day calendar view** showing qualifying windows as colored bars across each day; chroma modulates with match quality (marginal windows fade toward grey, excellent matches are vibrant)
- **Hover / tap info cards** showing the time range, best sub-window, and the weather conditions that qualified it
- **Weather** from [Open-Meteo](https://open-meteo.com/) (free, no API key)
- **Tides** from [NOAA CO-OPS](https://tidesandcurrents.noaa.gov/) harmonic predictions
- **Admin & invitations** — invitation-only registration, admin user management, masquerade for support
- **Multi-app deployable** — session cookies are path-scoped so Prospero can share a domain with other apps behind a reverse proxy

## Stack

- **Swift 6.2** + **Hummingbird 2** (web framework)
- **Fluent** ORM over **PostgreSQL** (production) or **SQLite** (dev)
- **Plot** (HTML DSL) + **HTMX** (progressive enhancement)
- **swift-webauthn** for passkey ceremonies
- Shared library [`hummingbird-auth`](https://github.com/samalone/hummingbird-auth) — the passkey / session / invitation / admin layer
- Shared library [`plot-htmx`](https://github.com/samalone/plot-htmx) — HTMX attribute helpers for Plot

## Running locally

```sh
# First run: apply migrations and start
swift run prospero serve --auto-migrate

# Generate an invitation to create the first user (first user is auto-admin)
swift run prospero invite --email you@example.com
```

Then open http://localhost:8080 and follow the invitation URL to register a passkey.

By default Prospero uses SQLite at `./prospero.sqlite`. Set `DATABASE_URL` to use PostgreSQL.

### Environment

| Variable             | Purpose                                                         |
| -------------------- | --------------------------------------------------------------- |
| `DATABASE_URL`       | PostgreSQL URL. If unset, SQLite is used.                       |
| `DATA_DIR`           | Directory for the SQLite file (default: `.`).                   |
| `WEBAUTHN_RP_ID`     | Relying-party ID (domain). Default `localhost`.                 |
| `WEBAUTHN_RP_ORIGIN` | Origin URL including scheme. Default `http://localhost:<port>`. |
| `BASE_URL`           | Canonical base URL for invite links.                            |

## Subcommands

- `serve` — run the web server
- `migrate` — apply (or `--revert`) database migrations
- `invite` — generate an invitation URL from the command line

## License

MIT.
