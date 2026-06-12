#!/bin/bash
# SessionStart hook: make sure the poller daemon is alive, spawning it if not.
# Idempotent and quiet (hook output lands in the session context — keep it
# short); failures never block session startup.

GZ_DIR="${GOLAZO_DIR:-$HOME/.claude/golazo}"
PID_FILE="$GZ_DIR/poller.pid"
LOG_FILE="$GZ_DIR/poller.log"
CONFIG_FILE="$GZ_DIR/config.json"

# Setup not completed (no config) → nothing to do
[ -r "$CONFIG_FILE" ] || exit 0

# Don't respawn once the World Cup is over (the poller also exits by itself
# after that date)
if [ "$(date +%Y%m%d)" -gt 20260719 ]; then
  exit 0
fi

# pid file present and the process alive → nothing to do
if [ -r "$PID_FILE" ]; then
  pid=$(cat "$PID_FILE" 2>/dev/null)
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
    exit 0
  fi
fi

# Pick a Python interpreter: the dedicated venv created by install.sh first,
# the system python3 as a fallback
PYTHON="$GZ_DIR/venv/bin/python"
[ -x "$PYTHON" ] || PYTHON=$(command -v python3 || true)
[ -n "$PYTHON" ] || exit 0

mkdir -p "$GZ_DIR"
nohup "$PYTHON" -m golazo run >> "$LOG_FILE" 2>&1 &
echo $! > "$PID_FILE"
echo "golazo: poller 已拉起 (pid $!)"
