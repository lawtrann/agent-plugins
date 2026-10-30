#!/usr/bin/env bash
#
# proxy-up.sh — idempotent cloud-sql-proxy start for the query-db skill.
#
#   ${CLAUDE_SKILL_DIR}/scripts/proxy-up.sh <PORT> <INSTANCE_CONNECTION_NAME>
#
# Reuses a proxy that is already accepting connections on <PORT> (yours or a
# previous session's), otherwise starts one detached with IAM auth, records the
# pid in /tmp/csp-<PORT>.pid, and waits until pg_isready succeeds.
# Prints exactly one line on success:  ready localhost:<PORT> (<reused|started pid N>)
set -euo pipefail

PORT="${1:-}"; CONN="${2:-}"
if ! [[ "$PORT" =~ ^[0-9]{4,5}$ ]] || ! [[ "$CONN" =~ ^[a-z0-9-]+:[a-z0-9-]+:[a-z0-9-]+$ ]]; then
  echo "usage: proxy-up.sh <PORT> <project:region:instance>   (connect.sh calls this with a target from the config)" >&2
  exit 2
fi
for bin in cloud-sql-proxy pg_isready; do
  command -v "$bin" >/dev/null || { echo "$bin not found in PATH" >&2; exit 2; }
done

LOG="/tmp/csp-$PORT.log"; PIDFILE="/tmp/csp-$PORT.pid"

if pg_isready -h localhost -p "$PORT" -q; then
  echo "ready localhost:$PORT (reused)"
  exit 0
fi

nohup cloud-sql-proxy "$CONN?port=$PORT" --auto-iam-authn >"$LOG" 2>&1 &
PID=$!
echo "$PID" >"$PIDFILE"

for _ in $(seq 1 30); do
  if pg_isready -h localhost -p "$PORT" -q; then
    echo "ready localhost:$PORT (started pid $PID)"
    exit 0
  fi
  if ! kill -0 "$PID" 2>/dev/null; then
    echo "cloud-sql-proxy exited early; last log lines:" >&2
    tail -n 5 "$LOG" >&2
    exit 1
  fi
  sleep 1
done
echo "proxy on $PORT not ready after 30s; see $LOG" >&2
exit 1
