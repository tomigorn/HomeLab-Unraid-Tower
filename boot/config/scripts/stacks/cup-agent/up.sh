#!/usr/bin/env bash
#
# Bring up the Cup agent: tower's containers in fastpi's Cup dashboard
# (https://cup.holy-grail.ch, fastpi's Docker/Cup/cup.json -> servers.tower).
# Agent mode serves only the JSON API, no web UI. Same layout as beefy's
# Cup-Agent: read-only socket proxy -> socat unix bridge -> Cup.
#
# Plain `docker run`, idempotent: re-running recreates the containers. Docker
# restarts them at every array start (--restart unless-stopped).
#
# Run ON THE SERVER:  bash /boot/config/scripts/stacks/cup-agent/up.sh
# Images are not pulled here: load them throttled from fastpi (docs/02-build-order.md).

set -euo pipefail

HERE="/boot/config/scripts/stacks/cup-agent"
SOCK_NET="cup_socket"             # internal: proxy and bridge only
OUT_NET="cup-agent"               # agent's way out to the registries
BRIDGE_VOL="cup_socket_bridge"
HOST_IP="192.168.1.101"
PORT="8000"                       # also in firewall.sh; change both together

CUP_IMAGE="ghcr.io/sergi0g/cup:v3.5.1"   # keep in step with fastpi's Cup
PROXY_IMAGE="ghcr.io/tecnativa/docker-socket-proxy:0.3.0"
SOCAT_IMAGE="alpine/socat:latest"

log() { echo ">>> $*"; }

for img in "$CUP_IMAGE" "$PROXY_IMAGE" "$SOCAT_IMAGE"; do
  docker image inspect "$img" >/dev/null 2>&1 || { echo "!! image missing: $img (load it from fastpi)" >&2; exit 1; }
done

# Firewall first: the agent port must never be open to the whole LAN.
CUP_AGENT_PORT="$PORT" bash "${HERE}/firewall.sh"
log "DOCKER-USER:"; iptables -S DOCKER-USER | sed 's/^/    /'

docker network inspect "$SOCK_NET" >/dev/null 2>&1 || { log "creating network $SOCK_NET"; docker network create --internal "$SOCK_NET" >/dev/null; }
docker network inspect "$OUT_NET"  >/dev/null 2>&1 || { log "creating network $OUT_NET";  docker network create "$OUT_NET" >/dev/null; }
docker volume inspect "$BRIDGE_VOL" >/dev/null 2>&1 || docker volume create "$BRIDGE_VOL" >/dev/null

recreate() { docker rm -f "$1" >/dev/null 2>&1 && log "removed old container: $1" || true; }

# ------------------------------------------------------ read-only socket proxy
# POST=0: no create/start/stop/exec. Mounting docker.sock :ro into Cup would
# protect the socket file, not the API behind it.
recreate cup-socket-proxy-ro
log "starting cup-socket-proxy-ro"
docker run -d \
  --name cup-socket-proxy-ro \
  --network "$SOCK_NET" \
  --restart unless-stopped \
  -e CONTAINERS=1 -e IMAGES=1 -e INFO=1 -e VERSION=1 -e POST=0 \
  -v /var/run/docker.sock:/var/run/docker.sock:ro \
  --cap-drop ALL --cap-add CHOWN --cap-add SETUID --cap-add SETGID --cap-add DAC_OVERRIDE \
  --security-opt no-new-privileges:true \
  --memory 64m \
  "$PROXY_IMAGE" >/dev/null

# ------------------------------------------------------------ unix bridge
# Cup only takes a unix socket and ignores DOCKER_HOST.
recreate cup-socket-proxy-unix
log "starting cup-socket-proxy-unix"
docker run -d \
  --name cup-socket-proxy-unix \
  --network "$SOCK_NET" \
  --restart unless-stopped \
  -v "${BRIDGE_VOL}:/sock" \
  --cap-drop ALL \
  --security-opt no-new-privileges:true \
  --memory 32m \
  "$SOCAT_IMAGE" \
  UNIX-LISTEN:/sock/docker.sock,fork,unlink-early,mode=666 TCP:cup-socket-proxy-ro:2375 >/dev/null

# ---------------------------------------------------------------- Cup agent
# Bridge mounted at Cup's default /var/run: its -s flag fails with this socket.
# The socket comes through the volume, so the agent needs only the outbound network.
recreate cup-agent
log "starting cup-agent"
docker run -d \
  --name cup-agent \
  --network "$OUT_NET" \
  --restart unless-stopped \
  -p "${HOST_IP}:${PORT}:8000" \
  -v "${BRIDGE_VOL}:/var/run" \
  -v "${HERE}/cup.json:/config/cup.json:ro" \
  --security-opt no-new-privileges:true \
  --memory 128m \
  "$CUP_IMAGE" -c /config/cup.json serve >/dev/null

log "done. containers:"
docker ps --filter "name=cup-" --format "  {{.Names}}\t{{.Status}}\t{{.Image}}"
log "check: curl -s http://${HOST_IP}:${PORT}/api/v3/json   (from fastpi only)"
