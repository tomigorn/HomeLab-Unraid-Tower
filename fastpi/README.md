# fastpi artifacts

Files in this directory belong on **fastpi**, not on tower. They are kept here
because they exist to serve tower, and because this repo was where the
measurements behind them were taken.

Nothing here is deployed by `deploy/deploy.sh` — that only ever writes to
tower's flash. Copy these by hand into the `HomeLab-FastPi` repo.

| Here | Destination on fastpi |
|---|---|
| `traefik/dynamic/tower-wake.yml` | `Docker/Traefik/traefik/dynamic/` |
| `traefik/dynamic/tower-wol.yml` | `Docker/Traefik/traefik/dynamic/` |
| `tower-waker/.env.example` | `Docker/Tower-Waker/.env` |

## What this achieves

tower powers itself off after 30 minutes idle (D10). That saves roughly €57/yr
but makes anything it hosts unreachable. A wake-on-request gate in front of it
fixes that: a request arrives, the gate finds tower asleep, fires a magic
packet, and holds the caller on a refreshing page until tower answers.

This mirrors the existing **Beefy-Waker**, which already does exactly this for
beefy — so the work is a second instance, not a new design.

## The three differences from beefy, and why

1. **Probe port 8080, not 22.** On Unraid, SSH answers about **21 seconds
   before the array is mounted**. A port-22 probe therefore reports ready while
   every share is still missing. Nextcloud on 8080 cannot answer until Docker
   started, which cannot happen until the array mounted — so the service port
   is a strictly better readiness signal, and removes any need for
   Unraid-specific logic in the waker.

2. **`WAKE_COUNTDOWN=120`, not 60.** Measured cold boot to a mounted array is
   **102 s**.

3. **A rate limit in front of the gate.** Beefy's services are internal;
   Nextcloud is meant to be public. Without a limit, any internet request —
   including a bot scanning the tunnel — powers the server on. That both
   defeats the power saving and hands a stranger a power switch.

## Status: deployed and verified 2026-08-16

Live on fastpi. `Tower-Waker` runs on port 9002 alongside `Beefy-Waker` on 9001.

Verified end to end rather than assumed:

| Check | Result |
|---|---|
| `/status`, tower up | `{"up": true}` |
| `/status`, tower asleep | `{"up": false}` |
| `/gate`, tower up | `200` - traffic proxied through |
| `/gate`, tower asleep | `503` + refresh page, **and it woke tower in ~60 s** |
| Wake page via Traefik | `200`, title `Wake tower` |
| `beefy-waker` afterwards | still healthy, untouched |

### How it was built

A **self-contained copy** of Beefy-Waker rather than a shared image. The app's
target env vars were `BEEFY_*`; in the copy they are renamed `TARGET_*`, and the
user-facing strings say tower. Beefy's own files were not modified, and that was
checked afterwards: zero renamed references leaked into it.

**Consolidating both onto one generalised image is the obvious follow-up.** It
was left undone deliberately, because it means editing a service that already
works.

### Not done: no Nextcloud route exists yet

The wake middleware is defined but **attached to nothing**, because Nextcloud is
not yet exposed through Traefik. An unattached middleware does nothing and says
nothing about it, so remember to attach `tower-wake-public` (rate limit, then
gate) when that route is created.

### `/history` does not work for tower

Beefy's `/history` shells out to `journalctl --list-boots`. Unraid is not
systemd and has no journal, so that endpoint will fail. The SSH key mounts were
dropped from the compose file accordingly.

### On fastpi

| Path | What |
|---|---|
| `~/Projects/Docker/Tower-Waker/` | the service |
| `~/Projects/Docker/Traefik/traefik/dynamic/tower-*.yml` | routing |
| `~/.ssh/config` | `Match host tower exec ... /wake`, so plain `ssh tower` wakes it |
| `~/HomeLab-Unraid-Tower/` | this repo |
