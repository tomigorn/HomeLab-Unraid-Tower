# unraid-nas

Configuration-as-code for a home Unraid NAS (`Tower`, Unraid 7.3.2).

The point of this repo: the server's setup lives here as reviewable files, not as
undocumented clicks in a web UI. If the flash drive dies, this repo plus a backup
of `/boot/config` is enough to rebuild.

## Layout

**`boot/` mirrors `/boot` on the server exactly.** What you see here is where it
lands there — no translation table, no mapping buried in a script:

```
boot/config/go                                     -> /boot/config/go
boot/config/scripts/lib/notify.sh                  -> /boot/config/scripts/lib/notify.sh
boot/config/scripts/stacks/nextcloud/up.sh         -> /boot/config/scripts/stacks/nextcloud/up.sh
boot/config/plugins/user.scripts/scripts/<job>/    -> same path on the server
boot/config/shares/*.cfg                           -> /boot/config/shares/
```

| Path | Contents |
|---|---|
| `boot/` | Mirror of the server's flash. Deployment is a straight tree copy |
| `bin/` | Tools that run **here**, on the workstation (e.g. `wake-tower.sh`) |
| `docs/` | Runbook, decisions and why, recovery procedures, open items |
| `deploy/` | Push repo → server, and pull server → repo for drift checks |
| `secrets/` | `*.env.example` templates only — real values never committed |

### Why copies and not symlinks

A dotfiles-style symlink farm is not possible on Unraid, for two independent
reasons:

1. **`/boot` is VFAT and cannot represent a symlink.** `ln -s` there fails with
   `Operation not permitted`. It is not a permissions problem — the filesystem
   has no such concept.
2. **`/boot/config` is the only location that survives a reboot.** Unraid runs
   from RAM and rebuilds itself from the flash at every boot. Cloning this repo
   onto the pool and symlinking from there fails too: the pool is not
   mounted at boot, which is precisely when Unraid reads its config.

So the repo is the source of truth and `deploy.sh` copies from it, while
`fetch.sh` pulls the live state back so any divergence shows up in `git diff`.

## Usage

```bash
./deploy/deploy.sh                      # push boot/ -> server:/boot/
./deploy/deploy.sh --dry-run            # show what would change
./deploy/fetch.sh && git diff           # pull live state back, see any drift

DEPLOY_SHARES=1    ./deploy/deploy.sh   # also push share .cfg files
DEPLOY_SCHEDULES=1 ./deploy/deploy.sh   # also push User Scripts schedules

./bin/wake-tower.sh                     # wake the server (~102s to a mounted array)
```

Share configs and `schedule.json` are excluded by default because getting them
wrong is silent: a stale share config redirects where data physically lands, and
a stale `schedule.json` unschedules jobs — and a job that never runs looks
exactly like a healthy one.

Both deploy and fetch **wake the server automatically** if it is asleep, which
is its normal resting state (D10).

Both use the `tower` SSH host alias. See `docs/04-security.md` for the SSH setup.

## Status

Build is in progress.

- **`docs/05-todo.md`** — what is still open, ordered by risk. Start here.
- **`docs/02-build-order.md`** — the live checklist, recording what is done and
  *how it was verified*.

Working today: btrfs RAID1 mirror, 6TB array disk, Wake-on-LAN, idle auto
power-off, Nextcloud with version history, hourly btrfs snapshots, and a local
backup to the 6TB.

Not yet working: **notifications** (so failures are currently silent) and the
**offsite backup**. See the TODO.

Restores *have* been tested — a drill found and fixed a defect that would have
made the Nextcloud database unrestorable (`docs/03-recovery.md`, S4b).

Work continues on **fastpi**: see `fastpi/PROMPT.md`.
