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
PRUNE=""
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY="--dry-run"; echo ">>> DRY RUN — nothing will be written" ;;
    --prune)   PRUNE="--delete";  echo ">>> PRUNE — remote files not in the repo will be DELETED" ;;
  esac
done

# /boot is vfat: it cannot store unix ownership or permissions, so plain `-a`
# (which implies -p -o -g) fails with "chown ... Operation not permitted" on
# every file. Sync contents and timestamps only.
RSYNC_OPTS=(-rltv --no-perms --no-owner --no-group --exclude='.gitkeep' --prune-empty-dirs)

# --delete is NOT the default. The User Scripts directory also holds jobs the
# plugin ships and jobs created through the webGUI; deleting anything merely
# absent from this repo would silently destroy them. Opt in with --prune only
# when you actually intend the repo to be authoritative.

echo ">>> target: ${HOST}"

# The server powers itself off when idle (D10), so being unreachable is its
# normal resting state rather than an error. Wake it and wait for the array,
# otherwise every deploy/fetch would need a manual wake first.
ensure_awake() {
  local wake="${REPO_ROOT}/scripts/wake-tower.sh"
  if ssh -o BatchMode=yes -o ConnectTimeout=5 "$HOST" true 2>/dev/null; then
    return 0
  fi
  echo ">>> ${HOST} is not responding - waking it"
  [[ -x "$wake" ]] || { echo "!! ${wake} not found" >&2; return 1; }
  "$wake" || return 1
  ssh -o BatchMode=yes -o ConnectTimeout=5 "$HOST" true 2>/dev/null
}

if ! ensure_awake; then
  echo "!! cannot reach ${HOST} over SSH with key auth" >&2
  exit 1
fi

# User Scripts plugin reads its jobs from here; it persists because it is on the flash.
USER_SCRIPTS_DIR="/boot/config/plugins/user.scripts/scripts"

echo ">>> deploying user scripts -> ${USER_SCRIPTS_DIR}"
if [[ -d "${REPO_ROOT}/scripts/user-scripts" ]]; then
  ssh "$HOST" "mkdir -p '${USER_SCRIPTS_DIR}'"
  rsync "${RSYNC_OPTS[@]}" $PRUNE $DRY \
    -e ssh \
    "${REPO_ROOT}/scripts/user-scripts/" \
    "${HOST}:${USER_SCRIPTS_DIR}/"
fi

echo ">>> deploying shared libs -> /boot/config/scripts/lib"
if [[ -d "${REPO_ROOT}/scripts/lib" ]]; then
  ssh "$HOST" "mkdir -p /boot/config/scripts/lib"
  rsync "${RSYNC_OPTS[@]}" $DRY -e ssh \
    "${REPO_ROOT}/scripts/lib/" \
    "${HOST}:/boot/config/scripts/lib/"
fi

# User Scripts stores job schedules in a single schedule.json, NOT in the job
# directories. Deploying the scripts without it restores jobs that never run -
# a silent failure, since a job with no schedule looks identical to a healthy
# one until you notice it has produced nothing. It is a single shared file
# covering every job, so pushing a stale copy would drop schedules for jobs
# created through the webGUI. Opt in with DEPLOY_SCHEDULES=1.
SCHEDULE_JSON="/boot/config/plugins/user.scripts/schedule.json"
if [[ "${DEPLOY_SCHEDULES:-0}" == "1" && -f "${REPO_ROOT}/config/user-scripts/schedule.json" ]]; then
  echo ">>> deploying User Scripts schedules -> ${SCHEDULE_JSON}"
  if [[ -z "$DRY" ]]; then
    ssh "$HOST" "cp -f '${SCHEDULE_JSON}' '${SCHEDULE_JSON}.bak' 2>/dev/null || true"
    scp -q "${REPO_ROOT}/config/user-scripts/schedule.json" "${HOST}:${SCHEDULE_JSON}"
    echo "    NOTE: schedules are re-read on array start or plugin page save."
  fi
else
  echo ">>> skipping User Scripts schedules (set DEPLOY_SCHEDULES=1 to include)"
fi

# Shares are only pushed deliberately: overwriting a live share .cfg with a stale
# copy can silently change where data is written. Requires DEPLOY_SHARES=1.
if [[ "${DEPLOY_SHARES:-0}" == "1" && -d "${REPO_ROOT}/config/shares" ]]; then
  echo ">>> deploying share configs -> /boot/config/shares"
  rsync "${RSYNC_OPTS[@]}" $DRY -e ssh \
    "${REPO_ROOT}/config/shares/" \
    "${HOST}:/boot/config/shares/"
else
  echo ">>> skipping share configs (set DEPLOY_SHARES=1 to include)"
fi

echo ">>> making scripts executable"
# User Scripts names its job files `script` with no extension, so match both.
[[ -z "$DRY" ]] && ssh "$HOST" "find '${USER_SCRIPTS_DIR}' /boot/config/scripts \\( -name '*.sh' -o -name 'script' \\) -exec chmod +x {} + 2>/dev/null || true"

echo ">>> done"
echo
echo "Note: /boot is vfat, so unix permissions on the flash are not meaningful."
echo "Scripts are chmod'ed where they are executed from, not on the flash itself."
