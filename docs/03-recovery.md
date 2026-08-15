# Recovery procedures

Written to be followed while stressed. Each scenario states what is lost, what is
safe, and the order of operations.

> **Before touching anything destructive:** disk letters (`sdb`, `sdc`, …) are
> assigned in link-up order and change between boots. Always confirm the target
> by serial via `/dev/disk/by-id/`. Cross-check against `docs/00-hardware.md`.

---

## S1 — The USB flash drive died

**Lost:** Unraid config only — array assignments, shares, plugins, Docker config.
**Safe:** all data on the pools and array disks. The disks are self-describing;
Unraid reads the pool from the disks, not from the flash.

1. Get a new USB 2.0 flash drive, ideally brand-name, 8–32GB.
2. Install Unraid with the USB Creator tool.
3. Restore `/boot/config` from the most recent flash backup (see "Flash backup"
   below), **except** the `*.key` licence file.
4. Transfer the licence to the new flash GUID via Unraid's key replacement flow
   (Tools → Registration). One free transfer is permitted; beyond that it needs
   a support request.
5. Boot. Verify array assignments match `docs/02-build-order.md` **before**
   starting the array. If a disk is assigned to the wrong slot, do not start —
   correct it first.
6. `./deploy/deploy.sh` from this repo to restore scripts and config.

### Flash backup

The flash is the single point of failure for configuration. Back it up:

- Unraid webGUI: **Main → Flash → Flash Backup** (downloads a zip), or
- `./deploy/fetch.sh` in this repo, which pulls the version-controllable parts
  into git.

Do both. The zip captures the licence key and binary blobs like `super.dat` that
git deliberately does not track.

---

## S2 — One SSD in the `data` mirror died

**Lost:** nothing. This is precisely what the mirror is for.
**Safe:** all data, still online, running degraded on the surviving disk.

⚠️ **The pool now has no redundancy.** A second failure loses everything. Treat
this as urgent, and note that a resilver stresses the surviving disk — the
riskiest moment is during recovery.

1. Confirm which disk failed — **by serial**:
   ```
   zpool status data
   ```
2. **Before replacing anything, verify the offsite backup is current.** If the
   surviving disk dies mid-resilver, the offsite copy is what is left.
3. Stop the array. Physically replace the failed disk.
4. Assign the new disk to the pool slot in the webGUI, start the array.
5. Watch the resilver:
   ```
   zpool status data
   ```
6. Confirm the pool returns to `ONLINE` with a `mirror-0` vdev containing **two**
   devices. A pool that comes back as a single-device vdev is not a mirror.

---

## S3 — The 6TB array disk died

**Lost:** the local backup tier and bulk media. **Not** the primary photo copy.
**Safe:** everything on the `data` pool, and the offsite backup.

There is no parity (see D3), so there is nothing to rebuild from — this disk is
a *copy*, not redundancy.

1. Replace the disk.
2. Assign as array Disk 1, format XFS.
3. Recreate the `backup` and `media` shares.
4. Re-run the local backup job to repopulate from `data`.
5. Re-copy media from wherever it originated.

---

## S4 — Restore photos from Backblaze B2

Use when both the `data` pool and the local 6TB copy are gone (fire, theft,
ransomware that reached both).

1. Install rclone on any machine with disk space and bandwidth.
2. Place the B2 credentials from your password manager into an rclone config —
   see `secrets/rclone-b2.env.example` for the required variables. **The offsite
   credentials must not live only on the NAS**, or a compromise of the NAS takes
   the backup with it.
3. Verify before restoring:
   ```
   rclone size b2:<bucket>/photos
   rclone lsd  b2:<bucket>/photos
   ```
   Compare against expected object count. A restore that starts from a truncated
   backup wastes hours before the problem is visible.
4. Restore:
   ```
   rclone copy b2:<bucket>/photos /path/to/restore --progress --transfers 8
   ```
5. Spot-check actual image files open correctly — not just that the file count
   matches.

---

## S5 — Ransomware / mass deletion, pool itself healthy

ZFS snapshots are read-only and are the fastest path back.

1. **Do not** run the backup jobs — they will happily replicate the damage
   offsite. Disable the User Scripts schedules first.
2. List snapshots:
   ```
   zfs list -t snapshot -r data/photos
   ```
3. Identify the last good one by timestamp.
4. Roll back:
   ```
   zfs rollback -r data/photos@<snapshot>
   ```
   ⚠️ `-r` destroys snapshots newer than the target. Confirm the chosen snapshot
   predates the incident before running it.
5. Only re-enable backup jobs once the filesystem is verified good.

---

## S6 — Server unreachable on the network

Worked example from this build, kept because the symptoms mislead.

`ping` fails and the ARP entry shows `INCOMPLETE`/`FAILED` → nothing is answering
at layer 2. A router's device list showing the server as "up" is **not** evidence
— consumer routers render that from the DHCP lease table, and "device uptime"
means lease age, not a heartbeat.

Check in this order:

1. **Is it powered on?** It will not restart itself after a power cut unless the
   BIOS `Restore on AC Power Loss` setting is enabled (see `00-hardware.md`).
2. **Cable.** A faulty cable caused exactly this during the build. The local
   console shows `Interface - Ethernet Port 0 is down. Check cable!`. Swap it.
3. **Did anyone change BIOS NIC settings?** Disabling the NIC that Unraid has
   pinned as `eth0` breaks `bond0` and kills all networking. Revert the BIOS
   change, or `rm /boot/config/network-rules.cfg` and reboot.
4. **Did it get a different IP?** Sweep the subnet and match on MAC prefix
   (`60:be:b4`, see `00-hardware.md`) rather than trusting DNS, which may be
   serving a stale lease.
5. Attach a monitor. The Unraid console prints the current IP and any boot
   failure directly.
