#!/usr/bin/env bash
#
# Only fastpi (192.168.1.2) may reach the Cup agent port from the LAN. Cup has no
# auth at all, so without this rule port 8000 hands every LAN client an inventory
# of every image and version on tower.
#
# Idempotent. Runs from /boot/config/go BEFORE Docker starts (iptables lives in
# RAM and is empty after every boot, while Docker restarts the agent on its own),
# and again from up.sh. Docker never flushes DOCKER-USER, it only creates it when
# missing.

set -euo pipefail

PORT="${CUP_AGENT_PORT:-8000}"
RULE=(-i br0 ! -s 192.168.1.2/32 -p tcp --dport "$PORT" -j DROP)

iptables -N DOCKER-USER 2>/dev/null || true
iptables -C DOCKER-USER "${RULE[@]}" 2>/dev/null || iptables -I DOCKER-USER "${RULE[@]}"
