#!/usr/bin/env bash
#
# Wake the Unraid server with a Wake-on-LAN magic packet, then wait for SSH.
#
# A magic packet is 6x 0xFF followed by the target MAC repeated 16 times, sent
# as a UDP broadcast. That needs no raw sockets and no root - which matters here,
# because the Distrobox container is denied CAP_NET_RAW and tools like `arping`
# and `etherwake` cannot run inside it at all.
#
# Usage:
#   ./scripts/wake-tower.sh              # wake and wait for SSH (default)
#   ./scripts/wake-tower.sh --no-wait    # send the packet and return immediately
#
# Env overrides: TOWER_MAC, TOWER_HOST, TOWER_BCAST, WAKE_TIMEOUT

set -uo pipefail

MAC="${TOWER_MAC:-60:be:b4:17:0d:e0}"
HOST="${TOWER_HOST:-tower}"
# Readiness is polled by IP, never by hostname. When the server is off the
# router drops its DNS entry as the DHCP lease expires, so `tower` stops
# resolving - precisely when this script runs. Polling the name would then fail
# even though the wake itself succeeded (observed: the machine was up and
# serving while this script reported "did not come up within 180s").
IP="${TOWER_IP:-192.168.1.101}"
BCAST="${TOWER_BCAST:-192.168.1.255}"
TIMEOUT="${WAKE_TIMEOUT:-180}"

send_magic_packet() {
  python3 - "$MAC" "$BCAST" <<'PY'
import socket, sys
mac, bcast = sys.argv[1], sys.argv[2]
raw = bytes.fromhex(mac.replace(":", "").replace("-", ""))
if len(raw) != 6:
    sys.exit(f"bad MAC: {mac}")
packet = b"\xff" * 6 + raw * 16
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
# Port 9 (discard) is the convention; 7 also works on some NICs.
for port in (9, 7):
    s.sendto(packet, (bcast, port))
s.close()
print(f"magic packet sent to {mac} via {bcast}:9,7")
PY
}

# Cheap layer-3 check first - no DNS, no SSH keys, no host-key prompts.
if ping -c1 -W2 "$IP" >/dev/null 2>&1; then
  echo "${HOST} (${IP}) is already up"
  exit 0
fi

echo "waking ${HOST} (${MAC})..."
send_magic_packet || exit 1

[[ "${1:-}" == "--no-wait" ]] && exit 0

start=$SECONDS

echo "waiting for network (up to ${TIMEOUT}s)..."
until ping -c1 -W2 "$IP" >/dev/null 2>&1; do
  (( SECONDS - start >= TIMEOUT )) && {
    echo "!! ${IP} did not respond within ${TIMEOUT}s" >&2
    echo "   check: BIOS ErP/EuP disabled, PCIe Power On enabled," >&2
    echo "          and 'ethtool eth0' reporting Wake-on: g" >&2
    exit 1
  }
  sleep 5
done
echo "  network up after $(( SECONDS - start ))s"

echo "waiting for SSH..."
until (ping -c1 -W2 "$IP" >/dev/null 2>&1 && \
       ssh -o BatchMode=yes -o ConnectTimeout=4 -o StrictHostKeyChecking=accept-new \
           -i ~/.ssh/tower -o IdentitiesOnly=yes "root@${IP}" true 2>/dev/null); do
  (( SECONDS - start >= TIMEOUT )) && { echo "!! SSH never came up" >&2; exit 1; }
  sleep 5
done
echo "  ssh up after $(( SECONDS - start ))s"

# SSH answers roughly 5s BEFORE the array finishes mounting. Anything that runs
# a job against /mnt must wait for this, or it operates on empty mountpoints and
# reports success having copied nothing.
echo "waiting for the array to mount..."
until ssh -o BatchMode=yes -o ConnectTimeout=4 -i ~/.ssh/tower -o IdentitiesOnly=yes \
        "root@${IP}" 'grep -q "mdState=\"STARTED\"" /var/local/emhttp/var.ini' 2>/dev/null; do
  (( SECONDS - start >= TIMEOUT )) && { echo "!! array did not start within ${TIMEOUT}s" >&2; exit 1; }
  sleep 5
done

echo "${HOST} ready after $(( SECONDS - start ))s (array STARTED, mounts available)"
