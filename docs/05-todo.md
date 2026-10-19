# Open items

Single place to see what is left. Ordered by risk, not by effort.

Last audited against the live system: 2026-08-16.

---

## Review of 2026-08-16 (unattended)

A full review was run across the live system and every script. Everything the
docs claim was cross-checked against reality: `startArray=yes`, spin-down 1h on
disk1, `powersave` governor, Docker data-root `folder`, Nextcloud retention
`30, 365`, background jobs `cron`, SSH key persisted on the flash. **No drift
found.**

Health at review time: array `STARTED`, ZFS mirror `ONLINE` with a `mirror-0`
vdev and zero errors, all three containers up with Postgres healthy, 4 snapshots
present, no stray `@backup-` snapshots left behind, and the auto power-off pause
switch correctly absent.

### Fixed during the review

- **`thin_dated` rewritten to use a sorted glob instead of parsing `ls`.** This
  function calls `rm -rf` on backup trees, so a mis-parsed path is the worst
  kind of bug it could have. Re-verified against 400 synthetic dated
  directories: 27 kept, 373 removed, newest and oldest correct, and all 15
  recent days intact.
- **`--link-dest` target lookup rewritten** the same way. It decides what each
  nightly run hardlinks against, and a mis-parse would silently turn every
  backup into a full copy.
- **All scripts now pass `shellcheck -S warning` clean** (SC1090/SC1091 sourcing
  notices and SC2029 client-side-expansion notices excluded as intentional).
- Verified the `data/nextcloud` dataset does **not** grow on its own — 0 bytes
  over 3 minutes idle — so the upload-detection check cannot produce false
  "busy" readings that would block power-off forever.

### ⚠️ Known consequence of the current setup

**Auto power-off is on, and the fastpi orchestration does not exist yet.** So
scheduled jobs only run while the server happens to be awake. If you do not
touch the server for a week, there are no backups and no snapshots for that
week.

This is mostly self-limiting — if nothing is being used, nothing is changing, so
there is little to back up — but it stops being true the moment you upload
something and then leave the machine alone. The fix is the fastpi orchestration
in the Functionality section below.

---

## 🔒 Requires you — I could not do these unattended

These need the webGUI, a password prompt, an external account, or physical
access. None can be done over SSH by an agent.

| Task | Why I could not | Where |
|---|---|---|
| **Notifications** | Needs the GUI and an account/token | Settings → Notification Settings |
| **Offsite B2 backup** | Needs a Backblaze account and keys | backblaze.com, then `secrets/rclone-b2.env` |
| **HTTPS for webGUI** | Editing `ident.cfg` and restarting the webGUI unattended risks losing access with nobody there to recover it | Settings → Management Access |
| **SSH password auth off** | Unraid regenerates `sshd_config` at boot; a mistake locks out remote access while you sleep, and I could not verify recovery | Settings → Management Access |
| **Strong root password** | GUI only | Users → root |
| **Non-root SMB user** | GUI only | Users → Add User |
| **Tailscale** | Plugin install plus an auth key | Apps → Tailscale |
| **BIOS: Restore on AC Power Loss** | Physical access | BIOS setup |
| **Remove the unused NVMe** | Physical access | inside the case |
| **Router: UPnP off, confirm no port forwards** | Router admin | router GUI |
| **Licence purchase** | Payment | Tools → Registration |

### Done since that list was written

- [x] **Repo pushed to GitHub** — `tomigorn/HomeLab-Unraid-Tower`, private.
      This closes the "only one copy exists" risk: the thing describing how to
      rebuild the NAS no longer lives solely on one workstation.
- [x] **Git identity and SSH commit signing** on bazzite; history rewritten so
      all commits are authored by tomigorn and signed.
- [x] **fastpi set up as a working machine** — SSH commit signing (it had a
      GitHub key but no signing at all), this repo cloned, its own key
      authorised on tower, and `deploy.sh` / `fetch.sh` / `wake-tower.sh` all
      verified working from there.
- [x] **`allowed_signers` now lists both machines' keys.** Without that, git
      reports the other machine's commits as `U` - a valid signature from an
      untrusted signer - so you cannot verify your own history across machines.

### Deliberately not done, though I could have

- **Monthly scrub and SMART schedules.** Writing and scheduling new jobs
  unattended at 03:30 without you able to see the first run is how bugs get in.
  The scripts are straightforward; they belong in a session where the first run
  can be watched. Note the SMART caveat below before writing them.
- **`photos` / `media` shares.** Listed in D4, but their purpose is now unclear:
  Nextcloud owns file access, and empty unused shares are clutter. Worth
  deciding what they are *for* before creating them.

---

## 🚨 URGENT — Wake-on-LAN stopped working (2026-08-16)

**Status 2026-08-16 (evening): the server is up and reachable. Two of the three
hypotheses below are now ruled out with hard evidence — see "Measured wake cycle"
at the end of this section. The remaining unknown is a several-minute window after
power-off during which magic packets are ignored.**

WoL worked three times earlier the same day, including once from a ~6 hour
overnight power-off (wake to array-mounted in 102 s). It then stopped. Evidence:

- 20 magic packets sent across `192.168.1.255` and `255.255.255.255`, ports 9
  and 7, over 5 rounds
- 90 s wait, then a full `/24` sweep
- MAC `60:be:b4:17:0d:e0` is **absent from the network entirely**
- The workstation's own networking is fine (gateway replies in 0.5 ms)

**The distinguishing factor:** every successful wake followed a power-off that
was issued manually and watched. This failure followed the first power-off
performed autonomously by the `idle-shutdown` job.

### Investigation so far (2026-08-16)

**Not reproducible on demand.** A controlled test — `powerdown` issued the same
way `idle-shutdown` issues it, then a wake — succeeded in 102 s, identical to
every successful run. So the fault is intermittent and is *not* caused by the
autonomous shutdown path specifically. This morning's wake, which followed an
autonomous overnight power-off, also worked.

**Ruled out.** The NIC is an **Intel I226-V [8086:125c] rev 04**, a family with
well-documented link-instability bugs. The two standard mitigations were
checked and are *already in place*:

- `EEE status: disabled` (Energy Efficient Ethernet — the usual culprit)
- `ASPM: Disabled` on the NIC, kernel policy `default`

**Current leading hypothesis: the machine wakes but is slow or stalled in early
boot.** This fits the reported symptom — it started, but the ethernet was not
blinking. Supporting evidence from the very first inspection of this machine:

```
[   4.365] ata2: SATA link down
[ 245.943] ata2: SATA link up 6.0 Gbps    <- 245 seconds
```

The 6TB SMR drive has previously taken over four minutes to appear. During that
window the machine is powered on but has not finished initialising, which is
indistinguishable from a failed wake. The wake script's timeout was 180 s,
shorter than that observed delay — so a slow boot would be *reported* as a
failed wake.

**Changes made in response:**
- Wake timeout raised 180 s → 300 s (normal cold boot to mounted array is 102 s)
- On timeout the script now sweeps the LAN for the MAC, which distinguishes
  "never powered on" from "powered on but not reachable"
- Syslog is now mirrored to `/boot/logs/syslog`, so the next failure has a
  shutdown and boot record to inspect

### First captured shutdown (2026-08-16 12:35) — known-good baseline

Persistent logging worked: Unraid rotates the flash syslog on boot, so the
previous boot survives as `/boot/logs/syslog-previous`. **This shutdown was
followed by a successful wake**, so it is a baseline to diff against the next
failure.

What the teardown does:

```
rc.inet1: ip link set eth0 nomaster
bond0 (slave eth0): Releasing backup interface
rc.inet1: ip link del bond0
rc.inet1: ip link set lo down
rc.0:     Sending all processes the SIGTERM signal
```

**Unraid removes the NIC from `bond0` and deletes the bond, and nothing re-arms
Wake-on-LAN afterwards.** WoL must be armed at the instant power is cut, so an
interface teardown is a plausible route to losing it intermittently. The log
ends at the SIGTERM broadcast, because rsyslog is itself killed there — the
final moments are still not visible.

**Mitigation applied (unproven):** `idle-shutdown` now runs
`ethtool -s eth0 wol g` and logs the resulting state immediately before calling
`powerdown`. Cheap insurance; it does not prove the diagnosis.

**Next failure, do this:** compare `/boot/logs/syslog-previous` against the
baseline above. Specifically check whether the last logged `Wake-on:` value was
`g`, and whether the teardown sequence differs.

**Wake attempts since the failure: 4 consecutive successes** (109 s, 102 s,
102 s, 102 s to a mounted array).

**Still possible, not yet excluded:**
1. The shutdown does not always complete, leaving the NIC unarmed.
2. The board intermittently drops NIC standby power.
3. Marginal SATA/power on the 6TB stalls the boot — note this drive already
   needed its cables reseated once for exactly this reason.

### Measured wake cycle (2026-08-16 evening) — two hypotheses eliminated

A full cycle was instrumented from `fastpi`. Times below are UTC; tower logs in
CEST (UTC+2).

| UTC | Event | Source |
|---|---|---|
| 20:50:01 | `idle-shutdown` fires, logs `wol before powerdown: pumbg⏎g` | `syslog-previous` |
| 20:50:24 | last shutdown line (`killall5 -15`), flash unmounts after this | `syslog-previous` |
| 20:54:10 / 20:56:12 / 20:56:56 | 3 magic packets — **ignored** | waker log |
| 20:59:22 | 4th packet — **wakes it** | waker log + tcpdump |
| 21:00:12 | kernel starts (**50 s POST**) | `uptime -s` |
| 21:01:09 | `emhttpd` up | syslog |
| 21:01:24 | array mounting | syslog |
| **21:01:30** | **"Containers started."** | syslog |

**Ruled out — the packets are fine.** Captured on the wire with `tcpdump`: L2
broadcast to `ff:ff:ff:ff:ff:ff`, UDP/9, 102-byte payload of `6×0xff` followed by
`60be b417 0de0` repeated exactly 16 times. Textbook-correct, correct MAC.

**Ruled out — WoL was armed.** The mitigation added earlier that logs `Wake-on:`
immediately before `powerdown` did its job: `pumbg` / `g`. So "the shutdown left
the NIC unarmed" (hypothesis 1) did not happen on this occasion.

**Ruled out — the boot is not slow.** Magic packet to fully-booted with containers
running was **128 s**; kernel to containers was **78 s**. That matches the known
102 s baseline. The "slow SATA link on the 6TB SMR drive stalls the boot"
explanation (hypothesis 3) does not apply to this failure.

**What is left.** Three packets spanning 20:54→20:57 did nothing; one at 20:59
worked instantly. So there is a window of roughly 4–9 minutes after `powerdown`
during which the NIC does not respond. It is **not a fixed delay** — an earlier
cycle the same day woke from the first packet in ~34 s. Most likely candidates,
neither yet proven:

- the unlogged tail of shutdown after the flash unmounts (pool unmount, disk
  spin-down, final ACPI power-off) taking variable time, with the busier
  1-hour-uptime session flushing more than a short one
- the NIC renegotiating link at low power after the board drops to standby

**Next failure, capture this:** the wattage at the wall during the dead window. A
draw well above standby means the machine is still winding down and the packets
are simply arriving too early — which would settle it. Note that on this occasion
29.2 W was observed and misread as "stuck"; against the measured baseline
(beefy: boot peak 41 W → ~28 W running → ~0 W off) that reading meant *already
running*, not stalled.

### ⚠️ Autonomous power-off: kept on, deliberately

A headless server that cannot be woken remotely is worse than one that stays
powered on, and `/boot/config/no-autoshutdown` exists to pause auto power-off.
**The owner decided on 2026-08-16 to keep autonomous power-off enabled** rather
than pause it, accepting the occasional multi-minute wake. Do not create the
inhibit file without asking.

The practical mitigation is therefore on the `fastpi` side: the waker currently
sends **one** packet per request, so a packet landing in the dead window is lost
with nothing to follow it up. Making the waker re-send every 20–30 s for a few
minutes would have made this entire incident invisible. Not yet implemented.

### To diagnose, at the machine

- [ ] Are the fans spinning and any LEDs lit? (fans + no network = hung shutdown,
      hypothesis 1)
- [ ] NIC link LEDs with the machine off — a WoL-armed NIC usually shows a link
      light even when the system is down. Dark means no standby power to the NIC
      (hypothesis 2)
- [ ] Press power, then check `dmesg` and `/var/log/syslog` for how the previous
      shutdown ended
- [ ] Re-check BIOS: **ErP / EuP must be DISABLED**, PCIe Power On / PME enabled
- [ ] Confirm `ethtool eth0 | grep Wake-on` still reports `g` after a cold boot
- [ ] Then reproduce deliberately: let `idle-shutdown` power it off unattended
      and try to wake it, rather than testing after a manual `powerdown`

---

## 🔴 Blocking — these make other work untrustworthy

### 1. Notifications — nothing is configured

**Deferred by choice 2026-08-16. Nothing else changes this: it stays the
highest-risk open item until done.**

No notification agent exists (`/boot/config/plugins/dynamix/notifications/agents/`
is absent). Every script in `scripts/user-scripts/` calls `notify_alert` on
failure, and those alerts currently reach Unraid's internal list and **nowhere
else**.

Why this matters more than it sounds: this server is powered off most of the
day and is not logged into. A backup that starts failing produces no visible
symptom. The realistic discovery time is *months*, and the realistic moment of
discovery is when you need a restore. That is precisely the failure mode D7
exists to prevent, and every monitoring script built so far assumes this is
solved.

Options considered: ntfy (no account, use a long random topic), Telegram (bot
token + chat id), email/SMTP (Unraid native, needs an app password), Discord
webhook.

**Also required:** test-fire it afterwards. An alert path that has never
delivered a message is not a working alert path.

### 2. Offsite backup — tier 3 of 3 does not exist

Backblaze B2 via rclone, encrypted. Currently the only copies of anything are
the btrfs mirror and the 6TB in the *same machine*. Fire, theft, a lightning
surge, or ransomware that reaches the array takes all of it.

Credential template already committed at `secrets/rclone-b2.env.example`.

⚠️ The B2 credentials must also live in your password manager, not only on the
NAS — otherwise the event that destroys the NAS also destroys your access to
the backups.

### 3. ~~No restore has ever been tested~~ — **DRILL COMPLETED 2026-08-16**

- [x] restore a file from a ZFS snapshot — valid 500x500 PNG recovered (pool is btrfs since 2026-10-19; redo with `/mnt/data/.snapshots/`)
- [x] restore a file from a dated tree on the 6TB
- [x] all three copies verified **bit-for-bit identical** by md5
- [x] Postgres dump restored into a scratch container — 0 errors, 102
      `oc_filecache` rows and the `admin` user matching live exactly

**The drill found a real defect and it is now fixed.** `pg_dump` dumps a
database, not the cluster's roles. Nextcloud creates and connects as its own
role `oc_admin`, so the original backup would have produced a database with
perfect data that Nextcloud could not log into. The backup now also runs
`pg_dumpall --globals-only`; restoring globals first takes the restore from
**235 errors to 0**, with table ownership matching live (`oc_admin | 131`).

Procedure documented at `03-recovery.md` (S4b).

Still untested:
- [ ] a *full* disaster restore onto empty disks, rather than component restores
- [ ] restore from the offsite copy (does not exist yet)

---

## 🟠 Security — currently open

- [ ] **HTTPS for the webGUI** — `USE_SSL="no"` today
- [ ] **SSH password auth disabled** — still enabled, `PermitRootLogin yes`.
      Key auth is confirmed working, so this is safe to turn off now
- [ ] Strong root password (in a password manager)
- [ ] Separate non-root user for SMB; no Public shares
- [ ] Tailscale as the only remote admin path
- [ ] Confirm from outside the LAN that **no** Unraid port is reachable
- [ ] UPnP off on the router

---

## 🟡 Health monitoring

- [x] Monthly btrfs scrub + device-error check (`pool-scrub` user script, 2026-10-19)
- [ ] Monthly SMART extended self-test

  ⚠️ Measure the extended test first. The 6TB reports a **7-minute** extended
  self-test, which is not a plausible full surface scan of 6TB (~10–12 h
  expected). If it really finishes in 7 minutes it is not scanning the whole
  surface, and a periodic full read (`dd` scrub-read) is needed instead to find
  bad sectors *before* a restore does. See `00-hardware.md`.

---

## 🟢 Functionality

- [ ] `photos` and `media` shares (D4)
- [ ] Decide: is the Nextcloud **desktop sync client** important? It polls every
      ~30s, which keeps the server permanently awake and roughly halves the
      power saving. Browser + mobile alone would keep the full saving
- [x] **fastpi + Traefik wake-on-request proxy** (D12) — deployed and verified
      2026-08-16. `Tower-Waker` on port 9002; the gate woke tower from cold in
      ~60 s. See `fastpi/README.md`.
      - [ ] Attach `tower-wake-public` to the Nextcloud router **once that route
            exists**. The middleware is defined but attached to nothing, and an
            unattached middleware fails silently
      - [ ] Consolidate Beefy-Waker and Tower-Waker onto one generalised image
- [ ] fastpi orchestration of scheduled jobs (D10)

  Note for whoever writes it: SSH answers about **5 seconds before** the array
  finishes mounting. Jobs must wait for `mdState=STARTED`, not treat a
  successful SSH connection as readiness, or they run against empty mountpoints
  and report success having copied nothing.

- [ ] Consider Immich for photos specifically — Nextcloud's photo handling is
      weak, and both store originals as plain files so one backup strategy
      covers both. Weigh against the load on a 4-core Celeron

---

## 🔵 Housekeeping

- [ ] **After the 2026-10-19 reinstall:** log in once at
      `https://cloud.holy-grail.ch` with Holy Grail (user in `cloud-admins`),
      then `docker exec -u www-data nextcloud php occ user:disable admin`.
- [ ] Delete the old Nextcloud state once nothing is missed:
      `/mnt/user/appdata/{nextcloud,nextcloud-db,nextcloud-redis}.old-2026-10-18`,
      `/mnt/user/nextcloud/data.old-2026-10-18`,
      `/mnt/data/system/docker.old-folder-2026-10-19` (empty shell of the old
      Docker directory data-root), `/mnt/user/appdata/trivy-cache`.
- [ ] Watch the Docker vDisk fill level (`df -h /var/lib/docker`, 40 GB).

- [x] ~~Remove `/boot/config/no-autoshutdown`~~ — **done 2026-08-16.** Auto
      power-off is live. The file is a pause switch: recreate it with
      `ssh tower 'touch /boot/config/no-autoshutdown'` any time you need the
      server to stay up, and delete it to resume power saving.
- [ ] Physically remove the unassigned NVMe (D2) — powered, enumerated, doing
      nothing
- [ ] BIOS: `Restore on AC Power Loss → Power On` (independent of WoL; this is
      what recovers the machine after a power cut with nobody present)
- [ ] Re-measure idle draw. Last: **23.4 W** (was 25.1 W before the governor
      change)

---

## ⏳ Licence — has a deadline

- [ ] Determine whether the boot flash counts toward the device limit
      (decides Starter vs Unleashed)
- [ ] Purchase before the trial expires — **~29 days left as of 2026-08-16**

> Buy a good brand-name USB 2.0 flash drive *before* purchasing. The licence
> binds to the flash GUID, and that is the stick you are then committed to.
