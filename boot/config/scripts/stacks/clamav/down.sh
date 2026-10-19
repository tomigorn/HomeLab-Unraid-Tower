#!/usr/bin/env bash
#
# Stop and remove the clamav container. Signatures (volume clamav_db), state and
# quarantine stay; up.sh brings it back.
#
# Run ON THE SERVER:  bash /boot/config/scripts/stacks/clamav/down.sh

set -euo pipefail

docker rm -f clamav >/dev/null 2>&1 && echo ">>> removed clamav" || true
