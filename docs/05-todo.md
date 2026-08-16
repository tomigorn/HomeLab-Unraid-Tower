# Open items

Single place to see what is left. Ordered by risk, not by effort.

Last audited against the live system: 2026-08-16.

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

- [ ] **Remove `/boot/config/no-autoshutdown`** — auto power-off is currently
      inhibited while building. Power saving does not resume until this is gone
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
