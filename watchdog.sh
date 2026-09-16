#!/usr/bin/env bash
#===============================================================================
#  GoldWaterTunnel watchdog
#  - probes the REAL end-to-end path (socks -> fisher -> reality -> server -> internet)
#    every GWT_CHECK_INTERVAL seconds
#  - only acts after GWT_FAIL_THRESHOLD *consecutive* verified failures, so a
#    single blip never causes a restart
#  - restart ladder: local waterwall -> verify -> remote waterwall via restricted
#    SSH key -> verify; storm protection pauses actions for 10 minutes after
#    6 restart cycles within one hour (probing continues)
#===============================================================================
ENV_FILE="/etc/goldwater/env"
[ -f "$ENV_FILE" ] && . "$ENV_FILE"

LOG_DIR="/var/log/goldwater"
STATE_DIR="/var/lib/goldwater"
mkdir -p "$LOG_DIR" "$STATE_DIR" 2>/dev/null || true
LOG="$LOG_DIR/watchdog.log"

INTERVAL="${GWT_CHECK_INTERVAL:-20}"
THRESHOLD="${GWT_FAIL_THRESHOLD:-3}"
TIMEOUT="${GWT_SOCKS_TIMEOUT:-8}"
EXPECTED="${GWT_EXPECTED_EXIT:-}"
SOCKS_PORT="${GWT_TEST_SOCKS:-40000}"
SSH_TARGET="${GWT_WATCHDOG_SSH:-}"
SSH_KEY="${GWT_WATCHDOG_KEY:-/root/.ssh/id_ed25519_goldwater}"

log() { echo "$(date '+%F %T') $*" >> "$LOG"; }

probe() {
  [ -n "$EXPECTED" ] || return 1
  local ip
  ip="$(curl -s -m "$TIMEOUT" --socks5-hostname "127.0.0.1:$SOCKS_PORT" https://api.ipify.org 2>/dev/null)" || return 1
  [ "$ip" = "$EXPECTED" ]
}

probe_with_retries() { # $1 = attempts
  local i
  for i in $(seq 1 "${1:-3}"); do
    probe && return 0
    sleep 5
  done
  return 1
}

remote_restart() {
  if [ -n "$SSH_TARGET" ] && [ -f "$SSH_KEY" ]; then
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 \
        -o BatchMode=yes "$SSH_TARGET" restart >> "$LOG" 2>&1
  else
    log "remote restart unavailable (no SSH key/target configured)"
  fi
}

fails=0
restart_cycles=0
hour_marker="$(date +%s)"
backoff_until=0

log "watchdog started (interval=${INTERVAL}s threshold=${THRESHOLD} expected_exit=${EXPECTED})"
echo "$$" > "$STATE_DIR/watchdog.pid"

while true; do
  now="$(date +%s)"

  # reset the per-hour restart counter (rolling ~3600s window)
  if [ $((now - hour_marker)) -ge 3600 ]; then
    hour_marker="$now"; restart_cycles=0
  fi

  if [ "$now" -lt "$backoff_until" ]; then
    sleep "$INTERVAL"; continue
  fi

  if probe; then
    if [ "$fails" -gt 0 ]; then
      log "OK: tunnel healthy again after $fails failure(s), no action was taken yet"
    fi
    fails=0
    echo "1" > "$STATE_DIR/last_status"
  else
    fails=$((fails + 1))
    log "FAIL $fails/$THRESHOLD: end-to-end probe failed"
    echo "0" > "$STATE_DIR/last_status"

    if [ "$fails" -ge "$THRESHOLD" ]; then
      restart_cycles=$((restart_cycles + 1))
      log "DOWN-CONFIRMED: $fails consecutive failures — restarting local waterwall (cycle #$restart_cycles)"
      systemctl restart waterwall >> "$LOG" 2>&1

      if probe_with_retries 3; then
        log "RECOVERED after local restart"
        fails=0
      else
        log "still down after local restart — requesting remote waterwall restart"
        remote_restart
        if probe_with_retries 3; then
          log "RECOVERED after remote restart"
          fails=0
        else
          log "STILL DOWN after local+remote restart (cycle #$restart_cycles)"
        fi
      fi

      if [ "$restart_cycles" -ge 6 ]; then
        backoff_until=$(( $(date +%s) + 600 ))
        log "BACKOFF: $restart_cycles restart cycles this hour — pausing actions 600s (probing continues)"
      fi
    fi
  fi

  sleep "$INTERVAL"
done
