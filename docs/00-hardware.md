# Hardware inventory

All values below were read off the live system, not from a spec sheet.
Last verified: 2026-08-16.

## Server

| Item | Value |
|---|---|
| Hostname | `Tower` (Unraid default; description also default `Media server`) |
| Unraid version | 7.3.2 |
| IP | 192.168.1.101 (DHCP lease) |
| MAC | `60:BE:B4:17:0D:E0` |
| CPU | Intel Celeron N5105 @ 2.00 GHz, 4 cores |
| RAM | 16 GiB DDR4 (board max 32) |
| Licence | 30-day Trial (`/boot/config/Trial.key`) — tier not yet purchased |

## Storage

**Always address disks by `/dev/disk/by-id/…`, never `sdX`.**
Device letters are assigned in SATA link-up order and *do* move between boots —
this was observed directly: after one reboot, three of four drives changed letter.
A destructive command written against `sdX` will eventually hit the wrong disk.

| Role | Model | Serial | `by-id` path |
|---|---|---|---|
| Boot flash | Silicon Power 16GB USB 3.0 | `P200269507010A7E92DDC045` | `usb-UFD_3.0_Silicon-Power16G_P200269507010A7E92DDC045-0:0` |
| Pool `data` | WD Red SA500 2TB SATA SSD | `234542800604` | `ata-WDC_WDS200T1R0A-68A4W0_234542800604` |
| Pool `data` | Seagate IronWolf 125 2TB SATA SSD | `70W003LZ` | `ata-Seagate_IronWolf_ZA2000NM10002-3R1103_70W003LZ` |
| Pool `scratch` | ShiJi 128GB M.2 NVMe (unbranded) | `AA00000000035` | `nvme-ShiJi_128GB_M.2-NVMe_AA00000000035` |
| Array Disk 1 | WD Red 6TB **SMR**, 5400rpm | `WD-WX42D80C4RAP` | `ata-WDC_WD60EFAX-68JH4N0_WD-WX42D80C4RAP` |

### Note on the 6TB

The original build plan listed this as a *4TB* WD Red. It is in fact a **6TB
WD60EFAX**, and `smartctl` confirms the model family as **"Western Digital Red
(SMR)"**. The SMR reasoning in `01-decisions.md` therefore still holds — it is
simply 6TB of backup target rather than 4TB.

SMART overall health at inventory time: **PASSED**.

## Known hardware quirks

**Marginal SATA connection on the 6TB.** On first inspection this drive's SATA
link came up **245 seconds after boot** rather than at ~4s, so Unraid — which
enumerates disks at boot — did not see it at all. Reseating the SATA data and
power leads fixed it; it now links at 4.4s like the other drives.

If this drive ever "disappears" again, check `dmesg | grep ata` for the link-up
timestamp before assuming a disk failure.

**Faulty ethernet cable.** An intermittent cable caused a total network dropout
that presented as a dead server (`Interface - Ethernet Port 0 is down. Check
cable!` on the local console). Replaced. The faulty cable should be destroyed,
not returned to the spares box.

**Do not disable NICs in BIOS.** Unraid pins interface names to MAC addresses in
`/boot/config/network-rules.cfg`. Disabling the NIC that is `eth0` leaves `bond0`
referencing a member that no longer exists, and the server loses all networking
with no console error beyond the link-down banner. Recovery is either to re-enable
the port in BIOS, or to `rm /boot/config/network-rules.cfg` and reboot so Unraid
re-enumerates.

## Power management — VERIFIED WORKING

Wake-on-LAN from a full power-off (S5) is **tested and working**. This is the
foundation of D10, so it was proven before anything was built on top of it.

Measured cycle, 2026-08-16:

| Stage | Result |
|---|---|
| Clean shutdown (`/usr/local/sbin/powerdown`) | array stopped, pool unmounted |
| Full power-off confirmed | 45 s of no ping response |
| Magic packet → SSH reachable | **80 s** |
| Magic packet → array `STARTED` | **~85 s** |
| Mirror after cold boot | healthy, 0 errors (was ZFS; btrfs RAID1 since 2026-10-19) |
| Both mounts present | `/mnt/data`, `/mnt/disk1` |

Settings that survived the cold boot, all confirmed:

- `ethtool eth0` → `Wake-on: g` — **the driver re-enables this by default, so no
  `/boot/config/go` entry is needed.** Re-check after any Unraid upgrade.
- `startArray="yes"` — array auto-starts unattended
- `diskSpindownDelay.1="1"` — 1 hour on the HDD
- `UDMA_CRC_Error_Count` still 0 after the power cycle
- `Start_Stop_Count` 263 → 265 (+2 for the cycle; irrelevant against the drive's
  rating)

Wake command: `./scripts/wake-tower.sh` — sends the magic packet as a UDP
broadcast and waits for SSH.

**Budget ~90 seconds from magic packet to a usable, fully mounted server.**

### BIOS

- [x] Wake-from-off enabled (exact menu labels vary by board; the settings were
      located and applied, and the behaviour is verified above, which is what
      matters). If WoL ever stops working, suspect **ErP / EuP mode** having been
      re-enabled — it cuts NIC standby power and silently breaks wake-from-off.
- [ ] **Restore on AC Power Loss → Power On** — still worth setting so a power
      cut does not leave the machine dark. Note this is *independent* of WoL:
      WoL wakes it on demand, but only this brings it back by itself after an
      outage.
