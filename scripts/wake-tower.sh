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

if ssh -o BatchMode=yes -o ConnectTimeout=3 "$HOST" true 2>/dev/null; then
  echo "${HOST} is already up"
  exit 0
fi

echo "waking ${HOST} (${MAC})..."
send_magic_packet || exit 1

[[ "${1:-}" == "--no-wait" ]] && exit 0

echo "waiting up to ${TIMEOUT}s for SSH..."
start=$SECONDS
while (( SECONDS - start < TIMEOUT )); do
  if ssh -o BatchMode=yes -o ConnectTimeout=3 "$HOST" true 2>/dev/null; then
    echo "${HOST} is up after $(( SECONDS - start ))s"
    exit 0
  fi
  sleep 5
done

echo "!! ${HOST} did not come up within ${TIMEOUT}s" >&2
echo "   check: BIOS ErP/EuP disabled, PCIe Power On enabled, 'ethtool eth0' shows Wake-on: g" >&2
exit 1
