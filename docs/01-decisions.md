# Design decisions and rationale

Each entry records what was decided and *why*, so a future reader (or a future
version of me) does not undo it for a plausible-sounding but wrong reason.

---

## D1 — `data` pool is a two-device **mirror** (btrfs RAID1, see D14)

**Devices:** WD Red SA500 2TB + Seagate IronWolf 125 2TB (both SATA SSD)

Holds photos, general NAS shares, **and `appdata` + `system`**.

**Why appdata lives here rather than on the NVMe:** `appdata` contains things like
Immich's Postgres database, which is exactly as valuable as the photo files it
indexes. Losing it means losing albums, faces, and metadata even if the JPEGs
survive. It belongs on redundant storage, not on a single unbranded NVMe.

**Verification requirement:** a two-device pool must be confirmed to be a
mirror, not a stripe. A stripe of two disks looks healthy and performs well
right up until either disk dies, at which point everything is lost.
`btrfs filesystem df /mnt/data` must show `RAID1` for Data, Metadata **and**
System (a `single` anywhere means that part is unprotected).

---

## D2 — `scratch` pool is single-device XFS on the NVMe

**Device:** ShiJi 128GB M.2 NVMe (unbranded)

**Status: DROPPED 2026-08-16. The NVMe is left unassigned.**

The original plan was a single-device XFS pool holding download temp and
transcode cache. That was dropped because **the workload it existed for does not
exist**: this server is a NAS / personal cloud only — no Plex, no Jellyfin, no
download client. Both justifications disappear with them.

What remained was marginal — Docker image layers (small and re-pullable) and
Immich's occasional video transcoding. Neither justifies a pool on its own,
because a pool that is not needed is still a pool that can fail, raise alerts,
and appear in every health check.

Two further reasons not to build a dependency on this disk:

- It is unbranded, and its serial (`AA00000000035`) follows a placeholder pattern
  typical of low-quality no-name drives. Acceptable for data you can afford to
  lose; not something to rely on.
- `appdata` was already excluded from it by D1, so its most valuable potential
  use was off the table anyway.

Nothing is lost by waiting — a pool can be added at any time without disturbing
existing pools or data.

**Revisit if:** a download client is added, or Immich video transcoding turns out
to cause meaningful write wear on the `data` mirror.

---

## D3 — 6TB SMR drive is a backup target, **not parity**

**Device:** WD60EFAX 6TB, SMR, 5400rpm → array Disk 1, XFS

SMR (shingled) drives rewrite overlapping tracks, so sustained random writes
collapse to a fraction of normal speed once the drive's CMR cache fills. A parity
rebuild is precisely that workload, for many hours. SMR parity disks are a
well-known way to turn a single disk failure into a failed rebuild.

There is no parity disk at all — there is only one HDD, and parity across a single
data disk would be pointless anyway.

This disk's job is: local backup target (backup tier 2 of 3) and bulk media.

---

## D4 — All shares are **exclusive** (Secondary storage = none)

Every share sets a single primary storage location and no secondary, so Mover
never migrates data between pools and array. This keeps data where it was put and
makes capacity reasoning simple.

| Share | Primary |
|---|---|
| `photos` | `data` |
| `appdata` | `data` |
| `system` | `data` |
| `backup` | Array |
| `media` | Array |

---

## D5 — Docker uses an **xfs vDisk** (`docker-xfs.img`), not a directory

**Superseded 2026-10-19.** The directory data-root (Docker's `zfs` storage
driver, one ZFS dataset per image layer under `data/system`) was the original
choice to avoid the "docker.img is full" failure mode. Three kernel oopses in
ZFS (2026-10-17/18) correlated with heavy container writes and layer churn on
that driver; a clean 8-pass memtest ruled out RAM. Docker now runs the standard
Unraid setup: a 40 GB sparse xfs image at `/mnt/user/system/docker/docker-xfs.img`
(`DOCKER_IMAGE_TYPE="xfs"` in `docker.cfg`), loop-mounted at `/var/lib/docker`,
storage driver `overlay2`. The pool sees one file instead of ~80 datasets.
Watch the image fill level (`df -h /var/lib/docker`); 40 GB is ~15× the
current use.

---

## D6 — Backups: 3-2-1, and a mirror is not a backup

A ZFS mirror protects against *disk failure*. It does not protect against
deletion, corruption propagated to both sides, ransomware, or the whole machine
being lost. Three tiers:

1. **Live copy** — btrfs mirror (`data` pool)
2. **Local backup** — nightly to the 6TB array disk (rsync from a read-only
   snapshot)
3. **Offsite, encrypted** — Backblaze B2 via rclone or Duplicacy

Plus **read-only btrfs snapshots** of the `nextcloud` and `appdata` subvolumes
(hourly, GFS retention, `pool-snapshot` user script) as an undo buffer and a
ransomware speed bump — snapshots are read-only and survive a compromise of
the live filesystem.

Plus **Appdata Backup plugin** nightly to the `backup` share.

**Not OneDrive.** An existing large OneDrive account is near Microsoft's ~300k
object soft limit. A photo library would blow straight through it.

---

## D7 — Health monitoring must be noisy

Monthly btrfs scrub + hourly `btrfs device stats` check (`pool-scrub` user
script) + monthly SMART extended self-test, with notifications actually
configured. Unmonitored redundancy is indistinguishable from no redundancy: the
mirror silently degrades, and you discover it when the second disk fails.

---

## D8 — Security posture: nothing admin-facing is exposed

Unraid runs everything as root; exposed instances get scanned and ransomwared.

- **Never port-forward the webGUI or SSH.**
- Remote admin via **Tailscale** only.
- If a service must be public (e.g. a photo app for family), expose **that
  container only**, via Cloudflare Tunnel or a reverse proxy with TLS and its own
  auth.
- UPnP off. HTTPS on for the local webGUI. SSH key-only, password auth disabled.
- Strong root password; separate non-root user for SMB. No Public shares.

See `04-security.md` for the implementation detail.

---

## D9 — Secrets: plain env files on the flash, templates in git

Real values live in `/boot/config/secrets/*.env` on the server — root-readable
only, persists across reboots, never enters git. The repo commits `*.env.example`
templates documenting every required variable.

**Rejected alternative:** sops + age, which would allow encrypted secrets to live
in the repo and make a from-git rebuild fully self-contained. Better in principle,
but it adds an age key that itself must be backed up and managed. For a single
home server the simpler scheme wins. Revisit if this ever grows to several hosts.

---

## D10 — Power: full shutdown + Wake-on-LAN, orchestrated by `fastpi`

The server is **powered off by default** and woken on demand with a WoL magic
packet. `fastpi` — an always-on Raspberry Pi already on the LAN — owns the
schedule and acts as the orchestrator: it wakes the server, runs the job over
SSH, and powers it back down.

This moves the always-on power budget from the x86 box to a ~2 W Pi.

### Measured power, not estimated

**Idle draw at the wall: 25.1 W** (measured 2026-08-16, HDD not yet spun down).
An earlier estimate of ~15 W was wrong — the real figure is roughly 65% higher,
which makes the case for powering off considerably stronger.

| Scenario | Annual | At €0.30/kWh |
|---|---|---|
| Always on @ 25.1 W | 220 kWh | **~€66/yr** |
| Off by default, ~2 h/day awake | ~30 kWh | **~€9/yr** |
| **Saving** | **~190 kWh** | **~€57/yr** |

Two further reductions available on top, both independent of the wake/sleep
design:

- **HDD spin-down** (D3 / `00-hardware.md`) — roughly 3 W while parked, so idle
  should fall to ~22 W once the one-hour delay is in effect.
- **CPU governor** is currently `performance`, which pins clocks high for no
  benefit on a NAS. `powersave` should recover another 1–3 W.

Re-measure after both are applied; the always-on baseline is the number the
whole calculation hangs on.

### Why not sleep, and why not hibernate

**Hibernation is architecturally impossible on Unraid.** The root filesystem runs
entirely in RAM and there is no swap device; `/sys/power/disk` reports no
hibernation target. There is nowhere to write a memory image. Not a config gap.

**S3 suspend-to-RAM was rejected.** The kernel does offer it (`/sys/power/state`
= `freeze mem`), but Unraid's S3 support is historically unreliable, and this
machine's NIC is `igc` (Intel I225/I226), a family with a track record of
suspend/resume and link-negotiation quirks. A clean shutdown and cold boot has no
resume state to corrupt. This matches prior experience on the `beefy` host, where
shutdown proved more reliable than sleep.

### Why the scheduler must live off-box

Unraid's cron does not run while the machine is off, and does **not** catch up
missed jobs on next boot. A backup schedule owned by the server itself would
therefore fail silently the moment power saving is enabled — the exact class of
invisible failure D7 exists to prevent. Putting the schedule on `fastpi` makes
"the server was off" a condition the scheduler can detect and alert on.

### Prerequisites

- **Array auto-start must be enabled.** Default is `startArray="no"`, meaning the
  array does not mount after a cold boot — every woken backup would find no
  filesystem. This is the single most important prerequisite.
- **BIOS: ErP / EuP mode must be DISABLED.** ErP cuts standby power to the NIC
  and breaks wake-from-off entirely. It is the most common reason WoL "doesn't
  work" after a full shutdown.
- **BIOS: PCIe Power On / PME must be ENABLED.**
- `ethtool eth0` must report `Wake-on: g` after a cold boot. It is currently the
  driver default; if a future update changes that, persist it via `/boot/config/go`.
- Clean shutdown must use `/usr/local/sbin/powerdown`, which stops the array
  and unmounts the pool. Never `poweroff` directly.

### Known trade-offs, accepted

- **Boot latency ~60–120 s.** Interactive access uses the same pattern already in
  use for `beefy`: an SSH `Match … exec` hook fires the wake, with
  `ConnectionAttempts` high enough to retry while the machine boots.
- **A web service cannot wake the box by being visited.** If a photo app is ever
  exposed for family, a request to a powered-off server simply fails. That would
  need an always-on reverse proxy on `fastpi` that fires the magic packet and
  then proxies once the host answers.
- **Shutdown must not interrupt an active user.** The power-down job has to check
  for live SMB and SSH sessions before pulling the plug, rather than shutting down
  on a fixed timer.
- **Extra start/stop cycles on the HDD.** Negligible: a few hundred per year
  against a drive rated for tens of thousands.

### Sequencing

Implement **after** backups are running and verified. Adding power management
first makes a missing backup ambiguous — broken script, or sleeping box? Prove
the jobs work on an always-on machine, then introduce the power saving.


---

## D11 — Nextcloud's data directory lives in a **subdirectory** of the share

**`/mnt/user/nextcloud/data`, never `/mnt/user/nextcloud` itself.**

Unraid's `emhttpd` re-applies its permission model to every user share root at
each array start:

```
emhttpd: shcmd (52): chmod 0777 '/mnt/user/nextcloud'
emhttpd: shcmd (53): chown nobody:users '/mnt/user/nextcloud'
```

Nextcloud requires its data directory to be `0770` and refuses to run when it is
world-readable, failing with:

```
Your data directory is readable by other people.
Exception: Environment not properly prepared.
```

Pointing the datadir at the share root therefore breaks Nextcloud **on every
boot** — and because this server powers itself off when idle (D10), that means
daily. The symptom is quiet and nasty: the web UI keeps working, but every `occ`
command fails, so `nextcloud-cron` dies on each run and **version expiry and
trash cleanup silently stop**.

The reset is **not recursive**, so a subdirectory keeps its own mode. Verified
across a real reboot: the share root came back `777 nobody:users` while
`data/` stayed `770 sshd:sshd` (uid 33 = `www-data` in the container), and `occ`
worked.

`up.sh` also re-asserts `chown 33:33` and `chmod 770` on the datadir each run,
so the state repairs itself if anything ever resets it.

**Do not "fix" this by setting `check_data_directory_permissions => false`.**
That silences the check while leaving the data world-readable, which matters
once a non-root SMB user exists.


---

## D12 — Wake-on-request is handled by fastpi, not by tower

tower powers itself off when idle (D10), which makes anything it hosts
unreachable. The gate that wakes it therefore has to live somewhere that is
always on: **fastpi**, in front of Traefik.

fastpi already does exactly this for `beefy` (`Docker/Beefy-Waker` plus a
`forwardAuth` middleware), so tower gets a second instance of a proven service
rather than a new design. Config is prepared in `fastpi/` in this repo.

**Probe the service port (8080), not SSH (22).** This is the one substantive
difference from the beefy setup. On Unraid, SSH answers about **21 seconds
before the array is mounted**, so a port-22 probe reports ready while every
share is still missing. Nextcloud cannot answer on 8080 until Docker started,
which cannot happen until the array mounted — so the service port is a strictly
better readiness signal, and it keeps all Unraid-specific knowledge out of the
waker.

**A rate limit sits in front of the public gate.** Beefy's services are
internal; Nextcloud is meant to be public. Without a limit, any internet request
— including a bot scanning the tunnel — powers the server on, which both defeats
the power saving and hands a stranger a power switch.

**`bin/wake-tower.sh` stays.** It is used by `deploy.sh` and `fetch.sh`, and
being a direct magic packet it has no dependency on fastpi being up. The waker
serves browsers; the script serves tooling. The Beefy-Waker README already notes
that the waker is a single point of failure, and keeping an out-of-band path is
the answer to that.

## D13 — Nextcloud login is Authentik OIDC; local passwords are LAN-only

Nextcloud is published at `https://cloud.holy-grail.ch` (Cloudflare Tunnel →
Traefik on `fastpi` → `tower:8080`) and authenticates against the Authentik IdP
on `fastpi`, via the `user_oidc` app.

**Why OIDC and not LDAP.** LDAP was the original plan, but it has no native MFA:
Authentik's workaround is appending the TOTP code to the password
(`password;123456`), and the alternative is a bind flow that skips MFA entirely —
making Nextcloud, which holds all the files, the one service that bypasses an
otherwise mandatory-MFA IdP. OIDC applies the existing flows unchanged and needs
no LDAP outpost container on tower. Authentik's own documentation reserves LDAP
for deployments using server-side encryption with per-user keys, which this is
not.

**Access is decided in Authentik, not here.** Membership of `cloud-users` grants
access at all; `cloud-admins` additionally grants Nextcloud administrator rights.
Both are bound to the Authentik application, so a non-member is refused before
Nextcloud ever sees them and no account is provisioned. Nextcloud's hard-coded
`admin` group name is what the scope mapping emits for `cloud-admins` members.

**The local `admin` account is disabled after the first OIDC login**
(`occ user:disable admin`, since the 2026-10-19 reinstall); recovery is the
shell (`occ user:enable admin`, or `occ user:resetpassword`). While it exists it
is the only account not backed by Authentik. `user_oidc`'s `allow_multiple_user_backends=0` hides the
password form, and Traefik returns 403 for both `?direct=1` and `POST /login` on
the public hostname. So the local password login works **only over the LAN**:
`http://192.168.1.101:8080/login?direct=1`, or via VPN when remote.

An IP allowlist cannot express this. `cloudflared` reaches Traefik from inside
the LAN, and a LAN browser opening the public hostname still exits to Cloudflare
and returns through the same tunnel — so LAN and internet clients are
indistinguishable at the IP layer on that hostname. Hence a hard deny there plus
a LAN-only address here.

**Accepted residual risk.** `admin`'s password still authenticates against
WebDAV and OCS from the internet; those endpoints must stay public for sync
clients. Nextcloud's built-in brute-force protection (429 after 10 failures in
30 minutes) covers them, and it sees real client IPs because `trusted_proxies`
is set. Give `admin` a long random password and enable Nextcloud's own TOTP on
it.

**Dependency introduced:** Nextcloud login now requires `fastpi` to be up. If
`fastpi` is down, nobody can log in except via the LAN break-glass path above.

---

## D14 — `data` pool is **btrfs RAID1**, not ZFS

**Decided 2026-10-19.** The pool was created as a ZFS mirror (D1) and ran that
way from 2026-08-16. In three days it produced three kernel oopses in the ZFS
module (2026-10-17 01:17 and 08:58, 2026-10-18 20:07): a NULL dereference in
the txg sync thread and two general protection faults, each wedging every
write to the pool until a power-cycle. Writes lost in the wedge left 382 empty
files in a Nextcloud app and a 500 on every page for eight hours. An 8-pass
memtest86 was clean, so this is software: ZFS on Unraid is new (7.0+, module
2.4.3 on kernel 6.18), while a btrfs mirror is Unraid's long-standing pool
default with the GUI tooling (balance, scrub, device stats, replace) built
around it.

**How it is set up** — exactly what the GUI Format button does:
`pools/data.cfg` has `diskFsType="btrfs"`, `diskFsProfile="raid1"`; emhttpd
formatted with `mkfs.btrfs -K -f -d raid1 -m raid1 /dev/sdd1 /dev/sdc1` and
mounts with `noatime,space_cache=v2` + `discard=async` (Autotrim) +
`compress=zstd` (Compression) — both pool settings, not hand-edited options.
Each share is its own subvolume (`/mnt/data/{appdata,nextcloud,system}`) so
it can be snapshotted; snapshots live in `/mnt/data/.snapshots/<share>/`.
Docker keeps its xfs vDisk (D5), which `mount_image` marks `NOCOW` (`chattr +C`).

**Lost on purpose:** ZFS-only properties (per-dataset `used`, `.zfs/snapshot`,
`zfs send`). Replaced by `btrfs subvolume find-new` (upload detection in
`idle-shutdown`), `btrfs subvolume snapshot -r` (`pool-snapshot`,
`backup-local`) and `btrfs scrub` + `btrfs device stats` (`pool-scrub`).

**Check it:** `btrfs filesystem df /mnt/data` (all three `RAID1`),
`btrfs device stats /mnt/data` (all counters 0), `btrfs scrub status /mnt/data`.
