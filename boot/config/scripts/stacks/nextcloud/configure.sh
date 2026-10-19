#!/usr/bin/env bash
#
# One-time configuration after a fresh install (idempotent, re-run after an
# upgrade to re-assert settings): Holy Grail (Authentik) login via user_oidc,
# cron background jobs, proxy settings, DB indices.
#
# Run ON THE SERVER after up.sh has finished its first start:
#   bash /boot/config/scripts/stacks/nextcloud/configure.sh

set -euo pipefail

ENV_FILE=/boot/config/secrets/nextcloud.env
[[ -r "$ENV_FILE" ]] || { echo "!! missing $ENV_FILE" >&2; exit 1; }
set -a; . "$ENV_FILE"; set +a
: "${OIDC_CLIENT_ID:?}" "${OIDC_CLIENT_SECRET:?}"

OIDC_DISCOVERY="https://sso.holy-grail.ch/application/o/nextcloud/.well-known/openid-configuration"
PUBLIC_URL="https://cloud.holy-grail.ch"

occ() { docker exec -u www-data -e OIDC_CLIENT_SECRET nextcloud php occ "$@"; }
log() { echo ">>> $*"; }

occ status | grep -q 'installed: true' || { echo "!! Nextcloud is not installed yet" >&2; exit 1; }

log "system settings"
i=0
for d in cloud.holy-grail.ch tower tower.galaxus.box 192.168.1.101:8080 localhost:8080 localhost; do
  occ config:system:set trusted_domains $i --value="$d"; i=$((i+1))
done
occ config:system:set overwrite.cli.url --value="$PUBLIC_URL"
occ config:system:set overwriteprotocol --value=https
occ config:system:set trusted_proxies 0 --value=172.24.0.1
occ config:system:set trusted_proxies 1 --value=192.168.1.2
occ config:system:set maintenance_window_start --type=integer --value=1
occ config:system:set default_phone_region --value=CH
occ config:system:set user_oidc login_label --value="Login with Holy Grail"
occ background:cron

log "user_oidc"
occ app:getpath user_oidc >/dev/null 2>&1 || occ app:install user_oidc
occ app:enable user_oidc
occ user_oidc:provider authentik \
  --clientid="$OIDC_CLIENT_ID" \
  --clientsecret-env=OIDC_CLIENT_SECRET \
  --discoveryuri="$OIDC_DISCOVERY" \
  --scope="openid profile email nextcloud" \
  --unique-uid=0 \
  --mapping-uid=sub \
  --mapping-display-name=name \
  --mapping-email=email \
  --mapping-groups=groups \
  --mapping-avatar=picture \
  --group-provisioning=1
# Holy Grail is the only login: hide the password form (reachable with
# /login?direct=1 on the LAN for shell-side recovery only).
occ config:app:set --type=string --value=0 user_oidc allow_multiple_user_backends

log "db indices / repair"
occ db:add-missing-indices
occ maintenance:repair --include-expensive

log "done"
occ user_oidc:provider authentik 2>/dev/null | sed -E 's/(clientsecret|secret)[^ ]*/\1 <hidden>/' || true
