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
- Clean shutdown must use `/usr/local/sbin/powerdown`, which stops the array,
  unmounts, and exports the ZFS pool. Never `poweroff` directly.

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
