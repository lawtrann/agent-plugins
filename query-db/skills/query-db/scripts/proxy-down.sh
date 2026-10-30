#!/usr/bin/env bash
#
# proxy-down.sh — stop a proxy started by proxy-up.sh.
#
#   ${CLAUDE_SKILL_DIR}/scripts/proxy-down.sh <PORT>
#
# Only kills the pid recorded in /tmp/csp-<PORT>.pid. A proxy the user started
# by hand has no pidfile and is left alone.
set -euo pipefail

PORT="${1:-}"
[[ "$PORT" =~ ^[0-9]{4,5}$ ]] || { echo "usage: proxy-down.sh <PORT>" >&2; exit 2; }
PIDFILE="/tmp/csp-$PORT.pid"

if [ ! -f "$PIDFILE" ]; then
  echo "no pidfile for $PORT — not started by proxy-up.sh, leaving it running"
  exit 0
fi
PID="$(cat "$PIDFILE")"
if kill "$PID" 2>/dev/null; then
  echo "stopped proxy on $PORT (pid $PID)"
else
  echo "pid $PID already gone"
fi
rm -f "$PIDFILE"
