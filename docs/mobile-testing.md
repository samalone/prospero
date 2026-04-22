# Mobile testing

Prospero relies on passkeys, which require a real HTTPS origin with a stable
hostname — so mobile testing can't just hit the dev server on `localhost`
or a LAN IP. `scripts/tailscale-dev.sh` publishes the local dev server
over Tailscale Serve at an HTTPS URL derived from the Mac's tailnet
FQDN, using a Let's Encrypt cert.

## Current state

- **Mac-side fidelity**: works. You can curl the dev URL from Apsara
  via the tailnet and get back the usual Prospero responses.
- **iPhone (iOS 26.4.1) reachability**: **broken** — not by the
  script, but by upstream Tailscale iOS bugs (see below). The phone
  can see Apsara in its Tailscale peer list and even transfer files
  via the Tailscale app, but system-level networking (Safari,
  Shortcuts/`NSURLSession`) can't push HTTPS traffic through the
  Network Extension to a serve endpoint. Symptom: requests time out
  with no packets reaching the Mac.

The script was left pointed at `tailscale serve` (tailnet-only, the
safer default). It's ready to use the moment the upstream bug is
fixed.

## Known upstream issues

Both are open against Tailscale, neither has a fix at time of writing:

- [tailscale/tailscale#16491 — iOS 26 Beta 3 breaks Tailscale](https://github.com/tailscale/tailscale/issues/16491) —
  Safari and browser apps fail to connect to `tailscale serve`
  endpoints, while the same server works fine from earlier iOS.
- [tailscale/tailscale#18889 — Tailscale connectivity fails on iOS 26.4 shortly after connecting](https://github.com/tailscale/tailscale/issues/18889) —
  VPN shows connected, peer list populates, but system apps can't
  actually push traffic through. Reconnecting gives a few seconds
  of working state.

The Tailscale app's own in-app traffic uses a code path that bypasses
the iOS TCP/IP stack, which is why file transfer works while Safari
does not. Same hostname, different code paths.

## Options for the future

In rough order of effort:

1. **Wait for the Tailscale fix** and use the script as-is. No code
   change needed — just retry once upstream ships a patched iOS
   client.
2. **Switch to `tailscale funnel`** (public internet egress, not
   tailnet). The phone bypasses the broken NetExt entirely because
   traffic reaches Tailscale's edge from the public internet rather
   than the tailnet. Smallest script change (swap `serve` for
   `funnel`, and enable the `funnel` attribute for Apsara in the
   admin ACL). Downside: dev URL is publicly reachable by anyone who
   knows it. Mitigations: only enable during testing, tear down with
   `tailscale funnel reset` immediately after, rely on the fact that
   registration requires an invitation token.
3. **Cloudflared Tunnel / ngrok with a reserved hostname.** Publishes
   over a public HTTPS URL independent of Tailscale, so the phone
   bug doesn't apply. More setup (account + reserved hostname) but
   durable regardless of Tailscale state.

Option 2 is the quickest path if mobile testing becomes urgent —
and the invitation-token requirement means unauthenticated scanners
can't do much beyond hitting the login page.

## Usage once the blocker clears

Prerequisites (one-time):

1. Enable **MagicDNS** and **HTTPS Certificates** in the
   [Tailscale DNS admin console](https://login.tailscale.com/admin/dns).
2. Install Tailscale on the phone, sign in to the same tailnet.

To start a session:

```
./scripts/tailscale-dev.sh
```

On first run (fresh `~/.prospero-dev/prospero.sqlite`) the script
runs migrations, generates an invitation for
`samalone@llamagraphics.com`, and copies the invite URL to the Mac
clipboard so it crosses to the phone via Universal Clipboard. On
subsequent runs both are skipped; sign in with the staging passkey.

The script serves on `https://<mac>.<tailnet>.ts.net:8443`. Port
8443 sidesteps the port-443 conflict with Docker Desktop's nginx
ingress when the dev k8s overlay is running. WebAuthn handles
non-default ports transparently because the RP origin is computed
from the URL the browser actually sees.

To stop a session:

- `Ctrl-C` the server.
- `tailscale serve reset` to tear down the proxy.
