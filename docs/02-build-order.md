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

- [x] **Create `data` pool — mirror, 2× 2TB SATA SSD** (ZFS until 2026-10-19,
      **btrfs RAID1 since**, see D14 and the entry below)
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

- [x] **Docker on an xfs vDisk** (D5, changed 2026-10-19 from the directory
      data-root). From the shell: `DOCKER_ENABLED="no"` in
      `/boot/config/docker.cfg` + `emcmd cmdStatus=Apply` stops Docker and
      unmounts `/var/lib/docker`; set `DOCKER_IMAGE_TYPE="xfs"`,
      `DOCKER_IMAGE_FILE="/mnt/user/system/docker/docker-xfs.img"`,
      `DOCKER_IMAGE_SIZE="40"`, `DOCKER_ENABLED="yes"` + Apply again and emhttpd
      runs `mount_image` (creates + mkfs + loop-mounts) and `rc.docker start`.
      Everything in the old data-root is gone: images were re-loaded one at a
      time (`skopeo copy` to a tar on fastpi, `pv -L 8m | ssh tower-direct docker load`)
      and the stack recreated from `up.sh`. The old layer datasets
      (`data/system/<hash>`) were destroyed afterwards.
      *Verified:* `docker info` → `Storage Driver: overlay2`, `Backing Filesystem: xfs`;
      `mount` shows the image on `/var/lib/docker`; no layer datasets left;
      no ZFS oops in `dmesg`; scrub 0 errors after the change.
- [x] **Pool converted ZFS → btrfs RAID1 (2026-10-19)**, from the CLI, the
      way the GUI does it. Full copy of the pool to fastpi first
      (`~/backups/tower-pool-2026-10-19/`: rsync of appdata + nextcloud incl.
      the `*.old-2026-10-18` dirs, `trivy-cache`, `docker.old-folder`, pg_dump
      + globals, flash cfgs, image tars). Then: containers stopped,
      `DOCKER_ENABLED="no"` + `emcmd cmdStatus=Apply`, `emcmd cmdStop=Stop`
      (pool exported), `zpool labelclear` + `wipefs -a` on both partitions
      (partition table kept — Unraid's own `MBR: 1MiB-aligned` layout),
      `pools/data.cfg` → `diskFsType="btrfs"`, `diskFsProfile="raid1"`,
      `diskUUID=""`, `emcmd cmdStart=Start` (pool shows *Unmountable: wrong or
      no file system*, `fsUnmountableMask` in `var.ini`), then
      `emcmd "cmdFormat=Format&unmountable_mask=<mask>"` — emhttpd ran
      `mkfs.btrfs -K -f -d raid1 -m raid1`, mounted, and wrote the new UUID
      into `data.cfg` itself. Subvolumes created for the three shares,
      data restored throttled (`rsync --bwlimit=8000`), Docker re-enabled
      (fresh `docker-xfs.img`, `NOCOW`), images loaded via `pv -L 8m`,
      `up.sh` + `configure.sh`. Only the live dirs came back; the old
      `*.old-2026-10-18`, `trivy-cache` and `docker.old-folder-2026-10-19`
      exist only in the fastpi backup now.
      *Verified:* `btrfs filesystem df` → Data/Metadata/System all `RAID1`;
      `btrfs scrub start -B` → `no errors found`; `btrfs device stats` all 0;
      mount options `compress=zstd:3,discard=async,space_cache=v2`; `occ status`
      installed 34.0.5, `occ setupchecks` clean; `status.php` through Traefik
      `installed:true`, `/login` → 302 to user_oidc; Prometheus
      `probe_success{job="blackbox-tower-nextcloud"}` = 1; no kernel oops.
- [x] `appdata` confirmed on `data` pool
- [x] **Nextcloud reinstalled fresh 2026-10-19** (34.0.5, Holy Grail login
      only). Old state renamed to `*.old-2026-10-18` next to the new dirs
      (`/mnt/user/appdata/nextcloud{,-db,-redis}`, `/mnt/user/nextcloud/data`);
      DB dump + config.php of the old install are on fastpi
      (`~/backups/decommissioned/nextcloud-2026-10-18/`). Steps: `up.sh`
      (pre-copies the code with a throttled rsync, see the script) →
      `occ maintenance:install` with the postgres container →
      `configure.sh` (trusted domains, proxy settings, cron mode,
      `user_oidc` 8.11.0 from the app store, provider `authentik`,
      `allow_multiple_user_backends=0`, indices, repair).
      *Verified:* `status.php` installed:true through Traefik;
      `GET /login` → 302 `/apps/user_oidc/login/1` → 303 to
      `sso.holy-grail.ch/application/o/authorize`; `/login?direct=1` and
      `POST /login` → 403 publicly; Prometheus `blackbox-tower-nextcloud`
      probe_success 1; `occ setupchecks` clean once the first cron run was in.
      Still to do by hand: first OIDC login as the owner, then
      `occ user:disable admin` (shell `occ` stays as recovery).

- [x] **Cup agent (2026-10-19)**: tower's images in fastpi's Cup (`https://cup.holy-grail.ch`, fastpi `Docker/Cup/cup.json` → `"tower": "http://192.168.1.101:8000"`). Same layout as beefy's `Cup-Agent`.

      | What | Where |
      |---|---|
      | Containers | `cup-socket-proxy-ro` (read-only, `POST=0`) → `cup-socket-proxy-unix` (socat) → `cup-agent` (`ghcr.io/sergi0g/cup:v3.5.1`, `"agent": true`) |
      | Config | `/boot/config/scripts/stacks/cup-agent/cup.json` (mounted read-only) |
      | Start / stop | `bash /boot/config/scripts/stacks/cup-agent/up.sh` / `down.sh`; Docker restarts them at array start (`--restart unless-stopped`) |
      | Port | `192.168.1.101:8000`, fastpi only |
      | Firewall | `firewall.sh`, run from `go` before Docker starts and from `up.sh`: `iptables -I DOCKER-USER -i br0 ! -s 192.168.1.2/32 -p tcp --dport 8000 -j DROP` (idempotent) |

      Images loaded the throttled way (skopeo `--override-arch amd64` on fastpi → tar → `pv -L 8m` → `docker load`). `docker load` sets no registry digest, and Cup skips images without one: only `cup` itself (pulled once afterwards, layers already present, nothing downloaded) shows up so far. Others appear after one `docker pull <image>` on tower, which only fetches the manifest while the tag still matches the loaded image.
      *Verified:* `iptables -L DOCKER-USER -n` shows the DROP; from fastpi `curl http://192.168.1.101:8000/api/v3/json` → JSON, from beefy → timeout (dropped); fastpi Cup lists server `tower`. Agent down during a Cup refresh → `Failed to refresh server` in `docker logs Cup`, tower left out until the next refresh.

- [x] **ClamAV (2026-10-19)**: daily scan of new/changed files on the pool, same `scan.sh` as fastpi and beefy (verbatim copy of fastpi's `Docker/antivirus/clamav/scan.sh`; modes, metrics, quarantine format: fastpi's `Docker/antivirus/README.md`).

      | What | Where |
      |---|---|
      | Container | `clamav` (`clamav-local:latest`, alpine 3 + ClamAV 1.4.6), runs the freshclam daemon |
      | Start / stop | `bash /boot/config/scripts/stacks/clamav/up.sh` / `down.sh`; Docker restarts it at array start |
      | Image | built on fastpi without emulation: `bin/clamav-image.sh` (amd64 rootfs + `apk --arch x86_64`, `pv -L 8m` → `docker import`) |
      | Scan roots | `/mnt/data/nextcloud` → `/scan/nextcloud`, `/mnt/data/appdata` → `/scan/appdata`; `/` → `/host` (ro, `all` only) |
      | Quarantine | `/mnt/data/appdata/clamav/quarantine/` + `index.txt` (date, original path, signature) |
      | State, metrics | `/mnt/data/system/clamav/state/` (`last-run`, `last-infected.txt`, `last-<mode>.log`, `allow.txt`; outside the scan roots, else `new` lists its own temp files), `/mnt/data/appdata/clamav/textfile/clamav.prom` (pulled by fastpi over `ssh tower-direct`) |
      | Signatures | docker volume `clamav_db` on the vDisk (rebuildable, not in snapshots/backups); first DB copied from fastpi at 8 MB/s |
      | Daily run | User Script `clamav-scan`, `45 * * * *`, acts on the first awake tick after 03:00 (marker `/boot/config/plugins/user.scripts/clamav-scan.last`); `notify_alert` on hits (exit 1) and errors (exit 2) |
      | By hand | `docker exec clamav /scan.sh all` (pool + host root, report only), `docker exec clamav /scan.sh /scan/nextcloud/data/<user>/files/<x>`, false positive: `docker exec clamav /scan.sh restore '<file in quarantine>'` |
      | Tests | `docker run --rm --entrypoint sh -v /boot/config/scripts/stacks/clamav:/src:ro clamav-local:latest /src/tests/test_scan.sh` |

      - `find` mode (ctime/mtime), not `SCAN_BTRFS=1`: `btrfs subvolume find-new` needs `CAP_SYS_ADMIN`, too much for the process that parses hostile files.
      - `nextcloud` and `appdata` are separate subvolumes: a hit in Nextcloud is copied to the quarantine, not renamed. Nextcloud does not notice: `occ files:scan --all` afterwards.
      - `idle-shutdown` counts a running `clamscan` as busy.
      - Rebuild after a `scan.sh` change: `bin/clamav-image.sh`, then `up.sh`.

      *Verified 2026-10-19:* tests `PASS 91 FAIL 0` in the image on tower; first `new` (last 24 h, fresh Nextcloud install) `listed=29777 scanned=29370 infected=0 errors=0` in 14.5 min; EICAR in `/mnt/data/nextcloud/clamav-test/` → path run exit 1, moved to the quarantine, `index.txt` line; EICAR under appdata + User Script → exit 1 and Unraid alert "ClamAV: malware found on tower"; test state wiped, `clamav.prom` back to 0.
      During the test one bit of the cached `main.cvd` flipped in RAM (`N`→`n`, disk copy fine after `drop_caches`) and clamscan segfaulted twice: more evidence for the RAM suspicion.

---

## Phase 5 — Backups and health

- [x] Hourly read-only btrfs snapshots of `nextcloud` + `appdata`
      (`pool-snapshot`, GFS thinning). *Verified 2026-10-19:* run by hand,
      `btrfs subvolume list -r /mnt/data` lists both snapshots.
- [ ] Nightly local backup `data` → 6TB
- [ ] Offsite encrypted backup → Backblaze B2
- [ ] Appdata Backup plugin → `backup` share, nightly
- [x] Monthly btrfs scrub + hourly device-error check (`pool-scrub`, runs the
      first awake hour of each month, marker on the flash). *Verified
      2026-10-19:* first run scrubbed with `no errors found`.
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
      `STARTED` at ~85 s → mirror healthy with 0 errors, both mounts
      present. `Wake-on: g` re-enabled by the driver on cold boot, so no `go`
      file entry is required.

- [x] **Idle auto power-off watchdog** — `scripts/user-scripts/idle-shutdown/`
      Powers off after **30 minutes** with no SSH/SMB/NFS connections, console
      logins, running data jobs (rsync/rclone/restic/duplicacy/syncoid), array
      resync, btrfs scrub/balance, SMART self-test, or disk writes. Runs `*/5`, and is
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
