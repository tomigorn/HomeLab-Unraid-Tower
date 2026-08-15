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

- [ ] **Create `scratch` pool — XFS, single NVMe**
      Device: `nvme-ShiJi_128GB_M.2-NVMe_AA00000000035`

- [ ] **Assign 6TB as array Disk 1, XFS**
      Device: `ata-WDC_WD60EFAX-68JH4N0_WD-WX42D80C4RAP`
      No parity disk (see D3).

- [ ] **Start array**

---

## Phase 2 — Shares

All exclusive (Secondary storage = none) — see D4.

- [ ] `photos` → `data`
- [ ] `appdata` → `data`
- [ ] `system` → `data`
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

## Phase 7 — BIOS

See `00-hardware.md`.

- [ ] Restore on AC Power Loss → Power On
- [ ] Wake-on-LAN enabled
