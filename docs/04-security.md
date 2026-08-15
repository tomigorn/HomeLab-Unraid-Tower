# Security policy

Threat model in one line: **Unraid runs everything as root, so a compromise of
the webGUI or SSH is a total compromise of every photo on the machine.** The
posture follows from that.

See D8 in `01-decisions.md` for the decision record.

---

## Hard rules

1. **Never port-forward the Unraid webGUI (80/443) or SSH (22) to the internet.**
   Exposed Unraid instances are scanned for and ransomwared. There is no
   configuration of Unraid that makes this safe.
2. **UPnP off on the router.** Otherwise a container can quietly forward a port
   for itself and silently undo rule 1.
3. **No Public shares.** Every share requires authentication.
4. **Offsite backup credentials are not stored only on the NAS.** Keep a copy in
   a password manager, or an attacker who owns the NAS owns the backups too.

---

## Remote admin: Tailscale only

Tailscale gives a WireGuard mesh with no inbound firewall holes. Admin access to
the webGUI and SSH happens over the tailnet, never the public internet.

- [ ] Install the Tailscale plugin
- [ ] Enrol the server
- [ ] Verify the webGUI is reachable over the tailnet
- [ ] Verify from outside the LAN that `http://<public-ip>` reaches **nothing**
- [ ] Auth key stored per `secrets/tailscale.env.example`, never in git

---

## Exposing a service to family

If something genuinely must be public — e.g. a photo app for relatives — expose
**only that container**, never the host:

- **Cloudflare Tunnel** (preferred): no inbound ports at all, origin stays
  private, TLS terminated by Cloudflare.
- **Or** a reverse proxy with its own TLS and its own authentication layer.

Either way the container gets its own network path, and the Unraid host stays
unreachable from the internet.

---

## SSH

Key-only. Password auth disabled once key access is confirmed working from the
workstation — verify the key works *before* disabling passwords, or you lock
yourself out of a headless machine.

- Key: ed25519, `~/.ssh/tower` on the workstation
- Server-side persistent location (Unraid 7.x):
  **`/boot/config/ssh/root/authorized_keys`**
- Anything written to `/root/.ssh/` alone is lost at reboot — the RAM filesystem
  is rebuilt from the flash on every boot

Public keys are committed under `config/ssh/`. Private keys never are.

---

## Local webGUI

- [ ] HTTPS enabled
- [ ] Strong root password (password manager generated, not memorable)
- [ ] Separate non-root user for SMB access

---

## Verification

Security settings that were never tested are assumptions. Before considering this
phase done:

- [ ] From a network *outside* the LAN, confirm the public IP exposes no Unraid
      port (use an external port scanner, not a check from inside the LAN — from
      inside, everything looks closed or everything looks open for the wrong
      reasons)
- [ ] Confirm SSH rejects password auth
- [ ] Confirm no share is browsable without credentials
- [ ] Fire a test notification and confirm it actually arrives
