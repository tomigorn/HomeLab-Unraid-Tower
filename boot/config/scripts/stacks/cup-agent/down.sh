#!/usr/bin/env bash
#
# Stop and remove the Cup agent containers. Networks, volume and the
# DOCKER-USER rule stay; up.sh brings everything back.
#
# Run ON THE SERVER:  bash /boot/config/scripts/stacks/cup-agent/down.sh

set -euo pipefail

for c in cup-agent cup-socket-proxy-unix cup-socket-proxy-ro; do
  docker rm -f "$c" >/dev/null 2>&1 && echo ">>> removed $c" || true
done
