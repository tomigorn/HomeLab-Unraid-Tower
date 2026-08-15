# unraid-nas

Configuration-as-code for a home Unraid NAS (`Tower`, Unraid 7.3.2).

The point of this repo: the server's setup lives here as reviewable files, not as
undocumented clicks in a web UI. If the flash drive dies, this repo plus a backup
of `/boot/config` is enough to rebuild.

## Layout

| Path | Contents |
|---|---|
| `docs/` | Runbook, decisions and why, recovery procedures |
| `config/` | Version-controlled copies of live `/boot/config/…` artifacts |
| `scripts/user-scripts/` | Jobs run by the User Scripts plugin (one dir each) |
| `scripts/lib/` | Shared helpers (notifications, guards) |
| `docker/` | Compose files / Unraid template XML per container |
| `deploy/` | Push repo → server, and pull server → repo for drift checks |
| `secrets/` | `*.env.example` templates only — real values never committed |

## The Unraid persistence quirk

Unraid runs from RAM and rebuilds itself from the USB flash drive on every boot.
**Only `/boot/config/…` (plus appdata on the pools) survives a reboot.** Anything
written to `/root`, `/etc` or `/usr` is gone at next power-on.

That is why deployment is "rsync into `/boot/config/`" rather than "install to the
filesystem". See `docs/02-build-order.md` and `deploy/deploy.sh`.

## Usage

```bash
./deploy/deploy.sh          # push config/ + scripts/ to the server
./deploy/fetch.sh           # pull live config back, then `git diff` to see drift
```

Both use the `tower` SSH host alias. See `docs/04-security.md` for the SSH setup.

## Status

Build is in progress. `docs/02-build-order.md` is the live checklist — it records
what is done, what is verified, and what is still pending.
