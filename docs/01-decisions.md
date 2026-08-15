# Design decisions and rationale

Each entry records what was decided and *why*, so a future reader (or a future
version of me) does not undo it for a plausible-sounding but wrong reason.

---

## D1 — `data` pool is a two-device ZFS **mirror**

**Devices:** WD Red SA500 2TB + Seagate IronWolf 125 2TB (both SATA SSD)

Holds photos, general NAS shares, **and `appdata` + `system`**.

**Why appdata lives here rather than on the NVMe:** `appdata` contains things like
Immich's Postgres database, which is exactly as valuable as the photo files it
indexes. Losing it means losing albums, faces, and metadata even if the JPEGs
survive. It belongs on redundant storage, not on a single unbranded NVMe.

**Verification requirement:** a two-device ZFS pool must be confirmed to be a
`mirror`, not a `stripe`. A stripe of two disks looks healthy and performs well
right up until either disk dies, at which point everything is lost. `zpool status`
must show a `mirror-0` vdev containing both devices.

---

## D2 — `scratch` pool is single-device XFS on the NVMe

**Device:** ShiJi 128GB M.2 NVMe (unbranded)

Holds only rebuildable data: download temp, transcode cache. No redundancy,
because nothing on it is worth protecting. If it dies, nothing is lost — replace
the disk and recreate the shares.

Deliberately *not* used for appdata (see D1) and deliberately not part of the
`data` mirror (mixing an unbranded NVMe into the pool holding the photos would
put the pool's reliability at the mercy of its weakest member).

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

## D5 — Docker uses a **directory** data-root, not a fixed-size vdisk

Avoids the classic "docker.img is full" failure mode and the need to guess a size
up front. A directory grows with the pool and is easier to inspect and back up.

---

## D6 — Backups: 3-2-1, and a mirror is not a backup

A ZFS mirror protects against *disk failure*. It does not protect against
deletion, corruption propagated to both sides, ransomware, or the whole machine
being lost. Three tiers:

1. **Live copy** — ZFS mirror (`data` pool)
2. **Local backup** — nightly to the 6TB array disk (rsync, or `zfs send`/syncoid
   if the 6TB is made ZFS)
3. **Offsite, encrypted** — Backblaze B2 via rclone or Duplicacy

Plus **ZFS snapshots** on the photo dataset (hourly/daily/weekly retention) as an
undo buffer and a ransomware speed bump — snapshots are read-only and survive
a compromise of the live filesystem.

Plus **Appdata Backup plugin** nightly to the `backup` share.

**Not OneDrive.** An existing large OneDrive account is near Microsoft's ~300k
object soft limit. A photo library would blow straight through it.

---

## D7 — Health monitoring must be noisy

Monthly ZFS scrub + monthly SMART extended self-test, with notifications actually
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
