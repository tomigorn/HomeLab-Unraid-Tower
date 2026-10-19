#!/usr/bin/env bash
#
# Push the repo onto the Unraid server.
#
# The repo's boot/ directory MIRRORS /boot on the server exactly, so deployment
# is a single tree copy and the mapping is visible in the filesystem rather than
# hidden in this script:
#
#     boot/config/go                                  -> /boot/config/go
#     boot/config/scripts/lib/notify.sh               -> /boot/config/scripts/lib/notify.sh
#     boot/config/plugins/user.scripts/scripts/<job>  -> same path on the server
#
# Why copies and not symlinks (the dotfiles approach):
#   /boot is VFAT and cannot represent a symlink at all - `ln -s` there fails
#   with "Operation not permitted". And /boot/config is the ONLY location that
#   survives an Unraid reboot, since the OS runs from RAM. Cloning this repo
#   onto the pool and symlinking from there would not work either: the pool
#   is not mounted at boot, which is exactly when Unraid reads its config.
#
# Usage:
#   ./deploy/deploy.sh                 push (safe defaults)
#   ./deploy/deploy.sh --dry-run       show what would change
#   ./deploy/deploy.sh --prune         also delete remote files absent here
#   DEPLOY_SHARES=1     ./deploy/deploy.sh    include share .cfg files
#   DEPLOY_SCHEDULES=1  ./deploy/deploy.sh    include User Scripts schedule.json

set -euo pipefail

HOST="${UNRAID_HOST:-tower}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="${REPO_ROOT}/boot/"

DRY=""; PRUNE=""
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY="--dry-run"; echo ">>> DRY RUN - nothing will be written" ;;
    --prune)   PRUNE="--delete"; echo ">>> PRUNE - remote files not in the repo will be DELETED" ;;
  esac
done

# /boot is vfat: it stores no unix ownership or permissions, so plain -a (which
# implies -p -o -g) fails with "chown ... Operation not permitted" on every file.
RSYNC_OPTS=(-rltv --no-perms --no-owner --no-group)

# Excluded by default because they are destructive to get wrong:
#
#  shares/*.cfg    decide where data physically lives; pushing a stale copy can
#                  silently redirect writes to the wrong disk.
#  schedule.json   one shared file covering EVERY User Scripts job, including any
#                  created through the webGUI. A stale copy silently unschedules
#                  them, and a job that never runs looks identical to a healthy one.
EXCLUDES=(--exclude '.gitkeep')
[[ "${DEPLOY_SHARES:-0}"    == "1" ]] || EXCLUDES+=(--exclude 'config/shares/')
[[ "${DEPLOY_SCHEDULES:-0}" == "1" ]] || EXCLUDES+=(--exclude 'config/plugins/user.scripts/schedule.json')

echo ">>> target: ${HOST}:/boot/"

# The server powers itself off when idle (D10), so being unreachable is its
# normal resting state rather than an error.
ensure_awake() {
  ssh -o BatchMode=yes -o ConnectTimeout=5 "$HOST" true 2>/dev/null && return 0
  echo ">>> ${HOST} is not responding - waking it"
  "${REPO_ROOT}/bin/wake-tower.sh" || return 1
  ssh -o BatchMode=yes -o ConnectTimeout=5 "$HOST" true 2>/dev/null
}
ensure_awake || { echo "!! cannot reach ${HOST} over SSH with key auth" >&2; exit 1; }

# The go file runs at every boot; a bad copy stops the server booting correctly.
if [[ -z "$DRY" && -f "${SRC}config/go" ]]; then
  ssh "$HOST" "cp -f /boot/config/go /boot/config/go.bak 2>/dev/null || true"
fi

rsync "${RSYNC_OPTS[@]}" "${EXCLUDES[@]}" $PRUNE $DRY -e ssh "$SRC" "${HOST}:/boot/"

[[ "${DEPLOY_SHARES:-0}"    == "1" ]] || echo ">>> skipped share configs   (DEPLOY_SHARES=1 to include)"
[[ "${DEPLOY_SCHEDULES:-0}" == "1" ]] || echo ">>> skipped schedule.json   (DEPLOY_SCHEDULES=1 to include)"

echo ">>> done"
echo
echo "Note: /boot is vfat, so exec bits do not persist there. Scripts are invoked"
echo "as 'bash <path>'; User Scripts does this itself."
