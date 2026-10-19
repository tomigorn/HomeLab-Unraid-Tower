#!/usr/bin/env bash
#
# Build tower's clamav-local image (amd64) on fastpi (arm64) without emulation,
# then load it on tower throttled. Same content as fastpi's
# Docker/antivirus/clamav/Dockerfile: alpine:3 + clamav-scanner clamav-libs
# freshclam + entrypoint.sh, freshclam.conf, scan.sh from
# boot/config/scripts/stacks/clamav/clamav/.
#
# fastpi has no amd64 emulation, so nothing can RUN inside an amd64 image here.
# Instead arm64 apk installs the x86_64 packages into an extracted amd64 alpine
# rootfs (--root --arch x86_64 --no-scripts); the one package script (freshclam
# pre-install: the clamav user) is replaced by fixed passwd/group lines.
#
# Run ON FASTPI:  bin/clamav-image.sh          build + load on tower
#                 bin/clamav-image.sh --build  tar only

set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${REPO}/boot/config/scripts/stacks/clamav/clamav"
OUT="${HOME}/backups/tower-images-clamav"
TAR="${OUT}/clamav-local_amd64.tar"
SKOPEO="quay.io/skopeo/stable:latest"
HELPER="alpine:latest"            # native arm64, only runs apk
IMAGE="clamav-local:latest"

log() { echo ">>> $*"; }

mkdir -p "$OUT"
rm -rf "${OUT}/alpine" "${OUT}/rootfs"

log "fetching alpine:3 amd64"
docker run --rm -v "${OUT}:/out" "$SKOPEO" copy --override-arch amd64 --override-os linux \
  docker://docker.io/library/alpine:3 dir:/out/alpine >/dev/null

log "installing clamav into the amd64 rootfs"
docker run --rm -v "${OUT}:/out" -v "${SRC}:/src:ro" "$HELPER" sh -euc '
  layer=$(sed -n "s/.*\"digest\": \"sha256:\([0-9a-f]*\)\".*/\1/p" /out/alpine/manifest.json | tail -1)
  mkdir /out/rootfs && tar -xzf "/out/alpine/$layer" -C /out/rootfs
  apk --root /out/rootfs --arch x86_64 --no-scripts --no-cache --update-cache add clamav-scanner clamav-libs freshclam >/dev/null
  r=/out/rootfs
  grep -q "^clamav:" $r/etc/group  || echo "clamav:x:101:clamav" >> $r/etc/group
  grep -q "^clamav:" $r/etc/passwd || echo "clamav:x:100:101:clamav:/var/lib/clamav:/sbin/nologin" >> $r/etc/passwd
  mkdir -p $r/var/lib/clamav $r/run/clamav $r/etc/clamav
  cp /src/freshclam.conf $r/etc/clamav/freshclam.conf
  cp /src/entrypoint.sh $r/entrypoint.sh
  cp /src/scan.sh $r/scan.sh
  chmod 755 $r/entrypoint.sh $r/scan.sh
  chown -R 100:101 $r/var/lib/clamav $r/run/clamav $r/etc/clamav/freshclam.conf
  grep "^VERSION_ID" $r/etc/os-release
  sed -n "/^P:clamav-scanner$/,/^$/p" $r/lib/apk/db/installed | grep "^V:"
  tar -C $r --numeric-owner -cf /out/clamav-local_amd64.tar .
  rm -rf /out/rootfs /out/alpine
'
log "built ${TAR} ($(du -h "$TAR" | cut -f1))"
[[ "${1:-}" == "--build" ]] && exit 0

log "loading on tower as ${IMAGE} (8 MB/s)"
pv -L 8m "$TAR" | ssh tower-direct "docker import \
  --change 'ENTRYPOINT [\"/entrypoint.sh\"]' \
  --change 'VOLUME /var/lib/clamav' \
  --change 'ENV PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin' \
  - ${IMAGE}"
log "next: ssh tower-direct bash /boot/config/scripts/stacks/clamav/up.sh"
