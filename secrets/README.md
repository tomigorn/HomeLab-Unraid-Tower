# Secrets

**Nothing real in this directory is ever committed.** `.gitignore` allows only
`*.example` files and this README.

## The pattern (decision D9)

Real values live on the server at `/boot/config/secrets/*.env`:

- `/boot/config/…` is on the flash, so it survives the reboot that wipes RAM
- root-readable only
- never enters git

This repo commits an `*.env.example` for each one, documenting every variable a
script expects. When a script needs credentials it sources the env file:

```bash
set -a; . /boot/config/secrets/rclone-b2.env; set +a
```

## Setting one up

```bash
ssh tower 'mkdir -p /boot/config/secrets && chmod 700 /boot/config/secrets'
scp secrets/rclone-b2.env.example tower:/boot/config/secrets/rclone-b2.env
ssh tower 'vi /boot/config/secrets/rclone-b2.env'
```

`/boot` is vfat, so unix permissions on the flash are advisory at best. Anyone
with physical access to the USB stick can read these. That is an accepted
limitation — the mitigation is physical security of the server plus the fact that
B2 application keys can be scoped and revoked.

## Keep a copy elsewhere

⚠️ **Offsite backup credentials must also exist in your password manager.**

If the only copy of the B2 key is on the NAS, then any event that destroys the
NAS also destroys your ability to reach the backup — which defeats the purpose of
having an offsite backup at all.
