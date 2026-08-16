# Continuing this work on fastpi

Paste this to Claude on fastpi after cloning
`git@github.com:tomigorn/HomeLab-Unraid-Tower.git`.

---

## Context

I have three machines:

- **fastpi** — Raspberry Pi, always on, `192.168.1.2`. Runs Traefik, Cloudflare
  Tunnel, and a fleet of Docker services. Repo: `HomeLab-FastPi`. **This is where
  you are, and where I mostly work.**
- **tower** — Unraid 7.3.2 NAS, `192.168.1.101`. Repo:
  `HomeLab-Unraid-Tower` (this one). Built over one session; storage, power
  management and Nextcloud all work.
- **bazzite-prime** — my desktop. Where tower was built from.

tower **powers itself off after 30 minutes idle** and is woken by Wake-on-LAN.
That saves ~€57/yr but makes anything it hosts unreachable while asleep.

fastpi already solves exactly this problem for **beefy** via
`Docker/Beefy-Waker` + Traefik `forwardAuth`. The job is to do the same for
tower — a second instance, not a new design.

## What I want

1. **Git identity on fastpi**, matching bazzite: SSH key, `~/.gitconfig` with no
   `[user]` block and `includeIf` per directory, SSH commit signing. Pattern is
   in `workstation/` in this repo, and in
   `tomigorn/Laptop-MacOs/multiple-git-accounts`.
2. **SSH access from fastpi to tower**, so `deploy/deploy.sh` and
   `bin/wake-tower.sh` work from here.
3. **A `Tower-Waker`** service, and the Traefik config to use it.
4. **Attach the wake gate** to whatever router fronts Nextcloud.

Config I have already written is in `fastpi/` in this repo — Traefik dynamic
files and a `.env.example`. Read `fastpi/README.md` first.

## Facts already measured — do not re-derive these

| Fact | Value |
|---|---|
| tower IP / MAC | `192.168.1.101` / `60:be:b4:17:0d:e0` |
| Cold boot: network up | 76 s |
| Cold boot: SSH answers | 81 s |
| Cold boot: **array mounted** | **102 s** |
| Nextcloud | `http://192.168.1.101:8080` |
| tower idle draw | 23.4 W (≈1 W off) |
| Idle shutdown threshold | 30 min |

**The single most important one:** on Unraid, **SSH answers ~21 seconds before
the array is mounted.** Anything that treats a successful SSH connection as
readiness will run against empty mountpoints and report success having copied
nothing. Probe the *service* port (8080), or check `mdState=STARTED` in
`/var/local/emhttp/var.ini`.

## Gotchas that cost time on tower

- **`/boot` is vfat.** No symlinks (`ln -s` fails outright), no exec bits.
  Scripts there must be run as `bash <path>`. This is why deployment copies
  rather than symlinking, and why a dotfiles-style setup is impossible on tower.
- **Only `/boot/config/…` survives a reboot.** Unraid runs from RAM.
- **Unraid `chmod 0777`s every share root at array start.** Nextcloud needs
  `0770` and refuses to run `occ` otherwise, which silently kills its cron. The
  data directory therefore lives in a *subdirectory* of the share (D11).
- **DNS for `tower` stops resolving while it is off** — the router drops the
  lease. Anything that polls it must use the IP.
- **Persistent connections keep the machine awake.** An idle Nextcloud browser
  tab polls ~7×/5min. `idle-shutdown` filters those specific endpoints. Your
  Beefy-Waker README documents the same behaviour for beefy.
- **Wake-on-LAN failed once, unexplained.** It has worked every time since (5+),
  but it is not closed out. `/boot/logs/syslog-previous` on tower now preserves
  the previous boot including its shutdown — compare against the known-good
  baseline in `docs/05-todo.md` if it recurs.

## Decisions to make, not assume

- **Generalising the waker.** Beefy-Waker's env vars are `BEEFY_*`. Running a
  second instance cleanly means renaming these to something generic
  (`TARGET_*`) once and running two containers off one image, rather than
  forking the code. My `.env.example` assumes that rename. Confirm with me
  before doing it — it touches a service that currently works.
- **Public exposure.** Nextcloud is meant to be reachable from outside. That
  means a public request can power my server on. I have written a `rateLimit`
  middleware and a `tower-wake-public` chain for this, but decide with me
  whether the public router gets the wake gate at all, or only the LAN/tailnet
  one.

## How I want you to work

- **Verify against the live system rather than assuming.** Several things in
  this repo were wrong until checked — the SSH persistence path, the readiness
  timing, the permission reset. Read the actual config, run the actual command.
- **One step at a time.** Tell me what to do, what I should see, and wait.
- **Flag anything destructive before running it.**
- **Commits:** short and clear, subject line only unless a body genuinely adds
  something. **Never mention AI, Claude, or a co-author.** See
  `~/.claude/CLAUDE.md` and `.claude/CLAUDE.md`.

## Where to read first

| File | Why |
|---|---|
| `docs/05-todo.md` | What is open, ordered by risk. **Start here** |
| `fastpi/README.md` | What the fastpi-side artifacts are and why they differ from beefy |
| `docs/01-decisions.md` | D10 (power), D11 (Nextcloud datadir) especially |
| `docs/00-hardware.md` | Serials, by-id paths, measured wake cycle |
| `bin/wake-tower.sh` | Existing CLI waker — keep it; it has no dependency on fastpi being up |

## Still open on tower, unrelated to this task

Highest risk first, all in `docs/05-todo.md`:

1. **No notification agent.** Every scheduled job alerts on failure, and those
   alerts currently reach nowhere. On a server that is off most of the day, a
   failing backup is invisible for months.
2. **No offsite backup.** Every copy of the data is still in one machine.
3. Security: HTTPS off, SSH password auth still enabled, no non-root SMB user.
4. Licence: trial expires ~2026-09-15.
