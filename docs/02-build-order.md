# Build order / runbook

Live checklist. Each step records how it was **verified**, not just that it was
done — "I clicked the button" is not evidence that the result is correct.

Legend: `[x]` done and verified · `[~]` done, verification pending · `[ ]` not started

---

## Phase 0 — Access and clean slate

- [x] **SSH key access from workstation**
      Key: `~/.ssh/tower` (ed25519). Host alias `tower` in `~/.ssh/config`.
      *Verified:* `ssh tower` authenticates via publickey, no password.

- [x] **Key persists across reboot**
      Unraid 7.x stores it at **`/boot/config/ssh/root/authorized_keys`**.
      Note: this is *not* `/boot/config/ssh/root.pubkeys`, which is the older
      path and does not exist on 7.3.2.
      *Verified:* file present on the flash, 109 bytes, contains the public key.

- [x] **Confirm flash config is factory**
      `mdState="STOPPED"`, `mdNumDisks="0"`, no parity, no shares, `docker.cfg`
      at defaults (`DOCKER_ENABLED="no"`). Hostname `Tower` and description
      `Media server` are Unraid **defaults**, not leftovers from a prior install.
      `Trial.key` present and intact.

- [x] **Wipe previous filesystems off all four data drives**
      Found: btrfs mirror pair on the two 2TB SSDs, btrfs on the NVMe, and an
      unimportable 4-device striped ZFS pool `media-pool` on the 6TB (two members
      missing → `UNAVAIL`, `insufficient replicas`, data already unrecoverable).
      Cleared with `zpool labelclear` + `wipefs -a` + `sgdisk --zap-all`, all
      addressed by `by-id` path, with a guard refusing to touch the flash.
      *Verified:* `lsblk` shows no partitions on any of the four; `blkid` returns
      nothing for them; `zpool import` → *no pools available*; flash `sda1` still
      `vfat`/`UNRAID`.

---

## Phase 1 — Pools

- [x] **Create `data` pool — ZFS mirror, 2× 2TB SATA SSD**
      Devices: `ata-WDC_WDS200T1R0A-68A4W0_234542800604` +
      `ata-Seagate_IronWolf_ZA2000NM10002-3R1103_70W003LZ`

      Pre-format intent is recorded by Unraid 7.x in `/boot/config/pools/data.cfg`
      (`diskFsProfile="mirror"`, `diskFsWidth="2"`) — worth checking *before*
      formatting, since the topology is committed at format time.

      *Verified (see D1), two independent ways:*
      1. `zpool status data` shows a `mirror-0` vdev with **both devices nested
         under it**. A stripe lists devices flat, directly beneath the pool name.
      2. `zpool list data` reports `SIZE 1.81T` from 2× 2TB. A stripe would show
         ~3.6T — half the raw capacity is the redundancy.

      Pool properties confirmed: `compression=on` (lz4), `autotrim=on`,
      `atime=off`, `ONLINE` with no errors, mounted at `/mnt/data`.

      Compression was enabled **before** formatting deliberately: ZFS only
      compresses data written after the setting is applied, so enabling it later
      would leave everything written before then uncompressed. Matters here
      because this pool holds `appdata` (Immich's Postgres), which compresses
      well; photos are already-compressed and lz4 early-aborts on them.

- [x] ~~**Create `scratch` pool — XFS, single NVMe**~~ — **dropped, see D2**
      The NVMe (`nvme-ShiJi_128GB_M.2-NVMe_AA00000000035`) is left **unassigned**.
      No media server and no download client means the pool had no workload to
      justify it. Can be added later without disturbing anything.

- [x] **Assign 6TB as array Disk 1, XFS**
      Device: `ata-WDC_WD60EFAX-68JH4N0_WD-WX42D80C4RAP`
      No parity disk (see D3) — Parity and Parity 2 left `DISK_NP`.

      Note: Unraid's Array Devices **Slots** count includes the two parity
      positions, so the minimum selectable value is `3` (parity + parity2 +
      disk1). Empty slots are harmless and do not count toward the licence
      device limit, which counts attached devices.

      *Verified:* mounted `/dev/md1p1` as XFS at `/mnt/disk1`, 5.5T. The 108G
      `df` reports on the empty filesystem is XFS metadata (`agcount=6` with
      `rmapbt` and `reflink`), not data — `du` confirms it is empty.

- [x] **Start array** — `mdState="STARTED"`, `fsState="Started"`

---

## Phase 2 — Shares

All exclusive (Secondary storage = none) — see D4.

- [ ] `photos` → `data`
- [x] `appdata` → `data` — verified `shareUseCache="only"`, `shareCachePool="data"`,
      no secondary; physically present at `/mnt/data/appdata`
- [x] `system` → `data` — same, at `/mnt/data/system`
- [ ] `backup` → Array
- [ ] `media` → Array

---

## Phase 3 — Security

- [ ] Strong root password
- [ ] HTTPS on for local webGUI
- [ ] SSH password auth disabled (key-only)
- [ ] Separate non-root user for SMB; no Public shares
- [ ] UPnP off on the router
- [ ] Tailscale installed and verified as the only remote admin path
- [ ] Confirm **no** port-forward exists for webGUI or SSH

---

## Phase 4 — Docker

- [ ] Docker enabled with **directory** data-root (see D5)
- [ ] `appdata` confirmed on `data` pool

---

## Phase 5 — Backups and health

- [ ] ZFS snapshots on the photo dataset (hourly/daily/weekly retention)
- [ ] Nightly local backup `data` → 6TB
- [ ] Offsite encrypted backup → Backblaze B2
- [ ] Appdata Backup plugin → `backup` share, nightly
- [ ] Monthly ZFS scrub
- [ ] Monthly SMART extended self-test
- [ ] Notifications configured **and test-fired** — an alert path that has never
      delivered a message is not a working alert path

---

## Phase 6 — Licence

- [ ] Determine whether the boot flash counts toward the device limit
      (decides Starter vs Unleashed)
- [ ] Purchase before the 30-day trial expires

> Buy a good-quality USB 2.0 flash drive *before* purchasing a licence — the
> licence binds to the flash GUID, and that is the stick you are then committed
> to. Unraid recommends USB 2.0 for the boot device; USB 3 controllers cause
> intermittent dropouts on many boards.

---

## Phase 7 — Power management (D10)

See `00-hardware.md` for the measured wake cycle.

- [x] **Array auto-start enabled** (`startArray="yes"`)
      Prerequisite for everything else: without it a woken server boots with
      nothing mounted, and scheduled jobs would run against empty mountpoints
      and report success having copied nothing.

- [x] **HDD spin-down: 1 hour on Disk 1 only**
      Global default left at `never` so the SSDs are untouched.

- [x] **Wake-on-LAN from full power-off — TESTED END TO END**
      Clean shutdown → confirmed off → magic packet → SSH at 80 s → array
      `STARTED` at ~85 s → ZFS mirror `ONLINE` with 0 errors, both mounts
      present. `Wake-on: g` re-enabled by the driver on cold boot, so no `go`
      file entry is required.

- [x] **Idle auto power-off watchdog** — `scripts/user-scripts/idle-shutdown/`
      Powers off after **30 minutes** with no SSH/SMB/NFS connections, console
      logins, running data jobs (rsync/rclone/restic/duplicacy/syncoid), array
      resync, ZFS scrub, SMART self-test, or disk writes. Runs `*/5`, and is
      stateful — six consecutive idle checks are required, so a single quiet
      moment never triggers a shutdown.

      *Logic verified on the live system before scheduling:*
      - Detects an active admin SSH session (see the `who` bug below)
      - Detects an 8 MiB write to the SMR disk (16,480 sectors) and resets

      **Two design details that were bugs first:**

      1. **Sessions are counted with `ss`, not `who`.** A non-interactive
         `ssh host 'cmd'` allocates no PTY and creates no utmp entry, so `who`
         reported **0 while an admin was actively connected** — the first
         version would have powered the machine off underneath a live session.
      2. **HTTP (80/443) is deliberately not counted.** Browsers hold webGUI
         connections open on background tabs indefinitely; counting them would
         mean one forgotten tab silently disables all power saving.

      **SMR guard:** the HDD must show *exactly zero* sectors written for the
      full 30-minute window. After a write burst an SMR drive reorganises its
      CMR media cache into shingled zones during idle, and that work is not
      visible as host I/O. An interrupted reorganisation is not data loss (it
      resumes on next spin-up) but it costs write performance later.

      **Inhibit:** `touch /boot/config/no-autoshutdown` — on the flash, so it
      survives reboots until removed. Use during maintenance, long copies, or
      while working in the webGUI.

      - [x] User Scripts plugin installed
      - [x] Deployed via `./deploy/deploy.sh`, scheduled `*/5 * * * *`,
            cron entry confirmed in `/etc/cron.d/root`
      - [x] **Schedule captured in the repo** at
            `config/user-scripts/schedule.json` — User Scripts keeps schedules
            in one shared file, *not* in the job directories, so without this a
            rebuilt flash would restore jobs that silently never run

      *Observed running from cron and behaving correctly:*
      ```
      01:45:02  BUSY - sdb wrote 128 sectors (SMR settle)
      01:50:01  BUSY - 1 SSH connection(s)
      ```
      The 128-sector write was traced to XFS flushing metadata after a test
      file was created and deleted — **not** a recurring writer. Verified by
      sampling `/proc/diskstats` once a minute for six minutes with the system
      untouched: zero writes throughout. The strict zero-write SMR guard is
      therefore achievable in practice and does not need loosening.

- [ ] Restore on AC Power Loss → Power On (independent of WoL — this is what
      recovers the machine after a power cut with nobody present)

- [x] CPU governor `performance` → `powersave` (Tips and Tweaks plugin)
      All four cores were pinned at 2800 MHz while idle; now 799-1019 MHz.
      Persisted as `CPU_GOVERNOR="powersave"`.

- [x] Idle draw re-measured: **25.1 W → 23.4 W** (-1.7 W).
      Remaining idle-power tweaks have poor return: with the machine powered off
      most of the day, watts saved while idle barely register. The one item still
      worth doing is physically removing the unassigned NVMe (D2), which is
      enumerated and drawing power for nothing.

- [ ] **fastpi orchestration** — implement only after backups are proven working
      on an always-on machine (see D10 sequencing). fastpi wakes the server, runs
      the job over SSH, checks for active SMB/SSH sessions, then powers down.
      Must alert if the wake fails, or a missed backup is invisible.
