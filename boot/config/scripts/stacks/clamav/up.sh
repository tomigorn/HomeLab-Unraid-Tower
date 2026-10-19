#!/usr/bin/env bash
#
# Bring up ClamAV: one container running the freshclam daemon; scans run in it
# via `docker exec clamav /scan.sh new|all|<path>` (User Script clamav-scan).
# scan.sh is a verbatim copy of fastpi's Docker/antivirus/clamav/scan.sh.
#
# Plain `docker run`, idempotent: re-running recreates the container. Docker
# restarts it at every array start (--restart unless-stopped).
#
# Run ON THE SERVER:  bash /boot/config/scripts/stacks/clamav/up.sh
# The image is built on fastpi and loaded throttled: bin/clamav-image.sh.

set -euo pipefail

IMAGE="clamav-local:latest"
BASE="/mnt/data/appdata/clamav"
STATE="/mnt/data/system/clamav/state"   # outside the scan roots: new would list its own temp files
DB_VOL="clamav_db"                # docker vDisk: rebuildable, kept out of snapshots and backups

log() { echo ">>> $*"; }

docker image inspect "$IMAGE" >/dev/null 2>&1 || { echo "!! image missing: $IMAGE (bin/clamav-image.sh on fastpi)" >&2; exit 1; }
mountpoint -q /mnt/data || { echo "!! /mnt/data not mounted" >&2; exit 1; }

mkdir -p "$STATE" "${BASE}/textfile" "${BASE}/quarantine"
chmod 700 "${BASE}/quarantine"
docker volume inspect "$DB_VOL" >/dev/null 2>&1 || docker volume create "$DB_VOL" >/dev/null

docker rm -f clamav >/dev/null 2>&1 && log "removed old container: clamav" || true
log "starting clamav"
# find mode, not SCAN_BTRFS=1: find-new needs CAP_SYS_ADMIN, too much for the process that parses hostile files.
docker run -d \
  --name clamav \
  --restart unless-stopped \
  -e HOST=tower \
  -e SCAN_ROOTS="/scan/nextcloud /scan/appdata" \
  -e QUARANTINE=/scan/appdata/clamav/quarantine \
  -v /mnt/data/nextcloud:/scan/nextcloud \
  -v /mnt/data/appdata:/scan/appdata \
  -v /:/host:ro \
  -v "${STATE}:/state" \
  -v "${BASE}/textfile:/textfile" \
  -v "${DB_VOL}:/var/lib/clamav" \
  --health-cmd 'pgrep freshclam >/dev/null || exit 1' \
  --health-interval 60s --health-timeout 10s --health-retries 3 --health-start-period 120s \
  --security-opt no-new-privileges:true \
  --memory 3g \
  "$IMAGE" >/dev/null

docker ps --filter name=^clamav$ --format "  {{.Names}}\t{{.Status}}\t{{.Image}}"
log "logs: docker logs clamav   scan: docker exec clamav /scan.sh new"
