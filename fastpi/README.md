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

## Read before starting

`PROMPT.md` in this directory is a complete brief for continuing this work on
fastpi, including the facts that were measured rather than assumed.
