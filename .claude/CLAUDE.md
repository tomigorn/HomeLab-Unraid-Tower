# unraid-nas

These instructions apply **on top of** the global config at
`~/.claude/CLAUDE.md` (both are loaded together).

The global file owns the environment (Bazzite, Distrobox, host bridging) and the
**commit rules** — short messages, and never any mention of AI or a
Co-Authored-By trailer. Those apply here too.

---

## What this repo is

Configuration-as-code for the Unraid NAS `tower`. The repo is the source of
truth; the server is deployed *from* it.

Start at `docs/05-todo.md` for what is open, `docs/02-build-order.md` for what is
done and **how it was verified**.

## Layout

`boot/` mirrors `/boot` on the server exactly — what you see is where it lands.
`bin/` is tooling that runs on the workstation, not the server.

```bash
./deploy/deploy.sh              # boot/ -> tower:/boot/
./deploy/fetch.sh && git diff   # pull live state, see drift
./bin/wake-tower.sh             # ~102s to a mounted array
```

## Things that will catch you out

- **The server is usually powered off.** It shuts down after 30 minutes idle and
  is woken by Wake-on-LAN. `deploy.sh` and `fetch.sh` wake it automatically.
- **`/boot` is vfat.** No symlinks, no exec bits. Scripts are invoked as
  `bash <path>`. This is why deployment copies rather than linking.
- **Only `/boot/config/...` survives a reboot.** Unraid runs from RAM. Anything
  written to `/root`, `/etc` or `/usr` is gone at next power-on.
- **SSH answers ~20s before the array is mounted.** Anything touching `/mnt`
  must wait for `mdState=STARTED`, or it runs against empty mountpoints and
  reports success having copied nothing.
- **Unraid resets share root permissions to 0777 on every array start.** This is
  why Nextcloud's data directory lives in a *subdirectory* of its share (D11).
- **Verify against the live system rather than assuming.** Unraid has
  version-specific quirks; several assumptions in this repo were wrong until
  checked. Prefer reading the actual config or running the actual command.

## Secrets

Real values live at `/boot/config/secrets/*.env` on the server and never enter
git. Only `*.example` templates are committed.
