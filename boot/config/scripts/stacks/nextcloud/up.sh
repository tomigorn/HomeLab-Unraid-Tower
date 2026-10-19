#!/usr/bin/env bash
#
# Bring up the Nextcloud stack: PostgreSQL + Redis + Nextcloud.
#
# Unraid ships no `docker compose`, so this is plain `docker run`. It is
# idempotent: re-running recreates the containers from these definitions. All
# state lives in bind mounts on the ZFS pool, so recreating a container loses
# nothing - that is the point. To change a setting, edit here and re-run.
#
# Run ON THE SERVER:  /boot/config/scripts/stacks/nextcloud/up.sh
# Or from the repo:   ssh tower '/boot/config/scripts/stacks/nextcloud/up.sh'

set -euo pipefail

SECRETS="/boot/config/secrets/nextcloud.env"
[[ -r "$SECRETS" ]] || { echo "!! missing $SECRETS" >&2; exit 1; }
set -a; . "$SECRETS"; set +a

NET="nextcloud"
APPDATA="/mnt/user/appdata"
# User files. NOTE the /data subdirectory - this is deliberate and load-bearing.
#
# Unraid's emhttpd runs `chmod 0777` + `chown nobody:users` on every user share
# root at each array start:
#     emhttpd: shcmd: chmod 0777 '/mnt/user/nextcloud'
# Nextcloud requires its data directory to be 0770 and refuses to start or run
# occ if it is world-readable ("Environment not properly prepared"), so pointing
# the datadir at the share root breaks Nextcloud on EVERY reboot - which on this
# server means daily, since it powers itself off when idle.
#
# The reset is not recursive, so a subdirectory keeps its own permissions.
NC_DATA="/mnt/user/nextcloud/data"
HTTP_PORT="8080"                    # host port; reverse proxy will front this later

PG_IMAGE="postgres:16-alpine"
REDIS_IMAGE="redis:7-alpine"
NC_IMAGE="nextcloud:stable-apache"

# Hostnames Nextcloud will accept. Nextcloud refuses to serve a domain that is
# not in this list. cloud.holy-grail.ch is the public name (Traefik on fastpi).
TRUSTED_DOMAINS="${NEXTCLOUD_TRUSTED_DOMAINS:-} cloud.holy-grail.ch tower tower.galaxus.box 192.168.1.101:${HTTP_PORT} localhost:${HTTP_PORT}"
PUBLIC_URL="https://cloud.holy-grail.ch"
# Traefik on fastpi reaches Nextcloud from these addresses (tunnel + LAN).
TRUSTED_PROXIES="172.24.0.1 192.168.1.2"
# Nextcloud must reach the IdP on fastpi; on this LAN sso.holy-grail.ch resolves
# through Cloudflare, so pin it to fastpi.
SSO_HOST="sso.holy-grail.ch:192.168.1.2"
TRUSTED_DOMAINS="$(echo "$TRUSTED_DOMAINS" | xargs)"   # trim

log() { echo ">>> $*"; }

docker network inspect "$NET" >/dev/null 2>&1 || {
  log "creating network $NET"; docker network create "$NET" >/dev/null
}

mkdir -p "${APPDATA}/nextcloud-db" "${APPDATA}/nextcloud-redis" "${APPDATA}/nextcloud" "${NC_DATA}"

# Re-assert the datadir mode. Harmless if already correct, and it repairs the
# state after anything has reset it. www-data is uid/gid 33 in the container.
chown 33:33 "${NC_DATA}" 2>/dev/null || true
chmod 770   "${NC_DATA}" 2>/dev/null || true

recreate() { # recreate <name>  - remove an existing container so config changes apply
  docker rm -f "$1" >/dev/null 2>&1 && log "removed old container: $1" || true
}

# On an empty html volume the image entrypoint copies ~600 MB of code at full
# speed. The ZFS pool has crashed under such write bursts (2026-10-17), so lay
# the code first with a throttled rsync; version.php present makes the
# entrypoint skip its own copy.
preseed() {
  [[ -f "${APPDATA}/nextcloud/version.php" ]] && return 0
  log "pre-copying Nextcloud code into ${APPDATA}/nextcloud (throttled)"
  docker run --rm -v "${APPDATA}/nextcloud:/var/www/html" --entrypoint rsync "$NC_IMAGE" \
    -rlDog --chown www-data:root --bwlimit=8000 /usr/src/nextcloud/ /var/www/html/
}

# ------------------------------------------------------------------ PostgreSQL
recreate nextcloud-db
log "starting nextcloud-db (${PG_IMAGE})"
docker run -d \
  --name nextcloud-db \
  --network "$NET" \
  --restart unless-stopped \
  -v "${APPDATA}/nextcloud-db:/var/lib/postgresql/data" \
  -e POSTGRES_DB="$POSTGRES_DB" \
  -e POSTGRES_USER="$POSTGRES_USER" \
  -e POSTGRES_PASSWORD="$POSTGRES_PASSWORD" \
  --health-cmd="pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}" \
  --health-interval=10s --health-retries=12 \
  "$PG_IMAGE" >/dev/null

# ----------------------------------------------------------------------- Redis
# Nextcloud uses Redis for file locking and as a memory cache. Without it
# Nextcloud logs a warning and concurrent access is noticeably slower.
recreate nextcloud-redis
log "starting nextcloud-redis (${REDIS_IMAGE})"
docker run -d \
  --name nextcloud-redis \
  --network "$NET" \
  --restart unless-stopped \
  -v "${APPDATA}/nextcloud-redis:/data" \
  "$REDIS_IMAGE" redis-server --save 60 1 --loglevel warning >/dev/null

# ------------------------------------------------------- wait for the database
log "waiting for postgres to accept connections..."
for i in $(seq 1 30); do
  if [[ "$(docker inspect -f '{{.State.Health.Status}}' nextcloud-db 2>/dev/null)" == "healthy" ]]; then
    log "postgres healthy after $((i*3))s"; break
  fi
  sleep 3
  (( i == 30 )) && { echo "!! postgres did not become healthy" >&2; docker logs --tail 30 nextcloud-db; exit 1; }
done

# ------------------------------------------------------------------- Nextcloud
recreate nextcloud
preseed
log "starting nextcloud (${NC_IMAGE})"
docker run -d \
  --name nextcloud \
  --network "$NET" \
  --restart unless-stopped \
  --add-host "$SSO_HOST" \
  -p "${HTTP_PORT}:80" \
  -v "${APPDATA}/nextcloud:/var/www/html" \
  -v "${NC_DATA}:/var/www/html/data" \
  -e POSTGRES_HOST="nextcloud-db" \
  -e POSTGRES_DB="$POSTGRES_DB" \
  -e POSTGRES_USER="$POSTGRES_USER" \
  -e POSTGRES_PASSWORD="$POSTGRES_PASSWORD" \
  -e REDIS_HOST="nextcloud-redis" \
  -e NEXTCLOUD_ADMIN_USER="$NEXTCLOUD_ADMIN_USER" \
  -e NEXTCLOUD_ADMIN_PASSWORD="$NEXTCLOUD_ADMIN_PASSWORD" \
  -e NEXTCLOUD_TRUSTED_DOMAINS="$TRUSTED_DOMAINS" \
  -e NEXTCLOUD_DATA_DIR="/var/www/html/data" \
  -e OVERWRITEPROTOCOL="https" \
  -e OVERWRITECLIURL="$PUBLIC_URL" \
  -e TRUSTED_PROXIES="$TRUSTED_PROXIES" \
  "$NC_IMAGE" >/dev/null

log "done. containers:"
docker ps --filter "network=${NET}" --format "  {{.Names}}\t{{.Status}}\t{{.Image}}"
echo
log "Nextcloud will take a minute to initialise on first run."
log "Then: ${PUBLIC_URL} (Holy Grail login) or http://192.168.1.101:${HTTP_PORT}/login?direct=1"
log "First install: bash /boot/config/scripts/stacks/nextcloud/configure.sh"
