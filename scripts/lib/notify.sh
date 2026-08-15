#!/usr/bin/env bash
#
# Shared notification helper for User Scripts jobs.
#
# Wraps Unraid's built-in notify agent so every job reports through the same path
# the webGUI uses. Silent failure is the enemy here: a backup that has been
# broken for three weeks looks exactly like a backup that has been working, right
# up until you need it (decision D7).
#
# Source from a job script:
#     . /boot/config/scripts/lib/notify.sh

NOTIFY_BIN="/usr/local/emhttp/webGui/scripts/notify"

# notify_send <importance: normal|warning|alert> <subject> <description>
notify_send() {
  local importance="$1" subject="$2" description="$3"
  if [[ -x "$NOTIFY_BIN" ]]; then
    "$NOTIFY_BIN" -e "unraid-nas" -s "$subject" -d "$description" -i "$importance"
  else
    echo "[${importance}] ${subject}: ${description}" >&2
  fi
}

notify_ok()    { notify_send normal  "$1" "${2:-}"; }
notify_warn()  { notify_send warning "$1" "${2:-}"; }
notify_alert() { notify_send alert   "$1" "${2:-}"; }

# run_guarded <job name> <command...>
#
# Runs a command, times it, and notifies on failure with the tail of its output.
# Always notifies on failure; stays quiet on success unless NOTIFY_ON_SUCCESS=1,
# so that a working system does not train you to ignore its own alerts.
run_guarded() {
  local name="$1"; shift
  local log rc start elapsed
  log="$(mktemp)"
  start=$SECONDS

  if "$@" >"$log" 2>&1; then
    rc=0
  else
    rc=$?
  fi
  elapsed=$(( SECONDS - start ))

  if (( rc == 0 )); then
    [[ "${NOTIFY_ON_SUCCESS:-0}" == "1" ]] && \
      notify_ok "${name}: ok" "completed in ${elapsed}s"
  else
    notify_alert "${name}: FAILED (rc=${rc})" \
      "after ${elapsed}s — $(tail -n 15 "$log" | tr '\n' ' ')"
  fi

  cat "$log"
  rm -f "$log"
  return $rc
}
