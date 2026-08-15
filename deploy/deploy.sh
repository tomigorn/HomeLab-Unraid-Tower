#!/usr/bin/env bash
#
# Push this repo's config and scripts to the Unraid server.
#
# Unraid runs from RAM and rebuilds itself from the flash on every boot, so the
# only durable destination is /boot/config/... Anything written elsewhere is gone
# at next power-on. See docs/02-build-order.md.
#
# Usage:  ./deploy/deploy.sh [--dry-run]

set -euo pipefail

HOST="${UNRAID_HOST:-tower}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

DRY=""
[[ "${1:-}" == "--dry-run" ]] && DRY="--dry-run" && echo ">>> DRY RUN — nothing will be written"

echo ">>> target: ${HOST}"

if ! ssh -o BatchMode=yes -o ConnectTimeout=5 "$HOST" true 2>/dev/null; then
  echo "!! cannot reach ${HOST} over SSH with key auth" >&2
  exit 1
fi

# User Scripts plugin reads its jobs from here; it persists because it is on the flash.
USER_SCRIPTS_DIR="/boot/config/plugins/user.scripts/scripts"

echo ">>> deploying user scripts -> ${USER_SCRIPTS_DIR}"
if [[ -d "${REPO_ROOT}/scripts/user-scripts" ]]; then
  ssh "$HOST" "mkdir -p '${USER_SCRIPTS_DIR}'"
  rsync -av --delete $DRY \
    -e ssh \
    "${REPO_ROOT}/scripts/user-scripts/" \
    "${HOST}:${USER_SCRIPTS_DIR}/"
fi

echo ">>> deploying shared libs -> /boot/config/scripts/lib"
if [[ -d "${REPO_ROOT}/scripts/lib" ]]; then
  ssh "$HOST" "mkdir -p /boot/config/scripts/lib"
  rsync -av $DRY -e ssh \
    "${REPO_ROOT}/scripts/lib/" \
    "${HOST}:/boot/config/scripts/lib/"
fi

# Shares are only pushed deliberately: overwriting a live share .cfg with a stale
# copy can silently change where data is written. Requires DEPLOY_SHARES=1.
if [[ "${DEPLOY_SHARES:-0}" == "1" && -d "${REPO_ROOT}/config/shares" ]]; then
  echo ">>> deploying share configs -> /boot/config/shares"
  rsync -av $DRY -e ssh \
    "${REPO_ROOT}/config/shares/" \
    "${HOST}:/boot/config/shares/"
else
  echo ">>> skipping share configs (set DEPLOY_SHARES=1 to include)"
fi

echo ">>> making scripts executable"
[[ -z "$DRY" ]] && ssh "$HOST" "find '${USER_SCRIPTS_DIR}' /boot/config/scripts -name '*.sh' -exec chmod +x {} + 2>/dev/null || true"

echo ">>> done"
echo
echo "Note: /boot is vfat, so unix permissions on the flash are not meaningful."
echo "Scripts are chmod'ed where they are executed from, not on the flash itself."
