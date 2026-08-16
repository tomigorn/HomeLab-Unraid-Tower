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

**The server is currently unreachable and will not wake. It needs to be checked
physically.**

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

Two hypotheses, and they need different fixes:

1. **The shutdown did not complete.** A hung `powerdown` leaves the machine
   neither running nor in S5, so the NIC never arms for WoL. Symptom would be
   fans still spinning with no video and no network.
2. **The board drops NIC standby power** after some period or under some
   condition (ErP/EuP behaviour), disarming WoL despite `Wake-on: g` being set
   at runtime.

### ⚠️ Until this is understood, autonomous power-off is not safe here

A headless server in a closet that cannot be woken remotely is worse than one
that stays powered on. **Consider creating `/boot/config/no-autoshutdown` to
pause auto power-off** until the cause is found.

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
the ZFS mirror and the 6TB in the *same machine*. Fire, theft, a lightning
surge, or ransomware that reaches the array takes all of it.

Credential template already committed at `secrets/rclone-b2.env.example`.

⚠️ The B2 credentials must also live in your password manager, not only on the
NAS — otherwise the event that destroys the NAS also destroys your access to
the backups.

### 3. ~~No restore has ever been tested~~ — **DRILL COMPLETED 2026-08-16**

- [x] restore a file from a ZFS snapshot — valid 500x500 PNG recovered
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

- [ ] Monthly ZFS scrub (`zpool scrub data`)
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
- [ ] fastpi + Traefik wake-on-request proxy for the public URL
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
