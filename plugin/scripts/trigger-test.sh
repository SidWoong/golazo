#!/bin/bash
# Manually trigger one full goal-effect chain (used by /goal-kick:test and for
# development).
# Behavior: atomically write a fabricated goal event into state.json → invoke
# the overlay animation if Hammerspoon is available.
# Usage: trigger-test.sh [--team NAME] [--opponent NAME] [--score X-Y]
#        [--scorer NAME] [--minute N] [--flag EMOJI]
#        [--jersey/--stripe/--shorts #hex] [--no-overlay]

set -eu

GK_DIR="${GOAL_KICK_DIR:-$HOME/.claude/goal-kick}"
STATE_FILE="$GK_DIR/state.json"

# Default scene: the 2022 Qatar World Cup final — Messi's 108th-minute goal
# (Argentina 3-2 France). Team names follow the system locale.
case "${LC_ALL:-${LANG:-}}" in
  zh*) TEAM="阿根廷"; OPPONENT="法国"; SCORER="梅西" ;;
  *)   TEAM="Argentina"; OPPONENT="France"; SCORER="Messi" ;;
esac
FLAG="🇦🇷"; SCORE="3-2"; MINUTE=108
JERSEY="#74acdf"; STRIPE="#ffffff"; SHORTS="#1a1a2e"   # Argentina home kit
NO_OVERLAY=0

TEAM_SET=0; JERSEY_SET=0
while [ $# -gt 0 ]; do
  case "$1" in
    --team)     TEAM="$2"; TEAM_SET=1; shift 2 ;;
    --flag)     FLAG="$2"; shift 2 ;;
    --opponent) OPPONENT="$2"; shift 2 ;;
    --score)    SCORE="$2"; shift 2 ;;
    --scorer)   SCORER="$2"; shift 2 ;;
    --minute)   MINUTE="$2"; shift 2 ;;
    --jersey)   JERSEY="$2"; JERSEY_SET=1; shift 2 ;;
    --stripe)   STRIPE="$2"; shift 2 ;;
    --shorts)   SHORTS="$2"; shift 2 ;;
    --no-overlay) NO_OVERLAY=1; shift ;;
    *) echo "未知参数 unknown arg: $1" >&2; exit 2 ;;
  esac
done

# An explicit team without an explicit kit → drop the default Argentina kit
# (no jersey mix-ups); the overlay falls back to its default palette
if [ "$TEAM_SET" = 1 ] && [ "$JERSEY_SET" = 0 ]; then
  JERSEY=""; STRIPE=""; SHORTS=""
fi

# Only write the kit field when all three colors are present; the overlay uses
# its default palette otherwise
KIT_JSON=""
if [ -n "$JERSEY" ] && [ -n "$STRIPE" ] && [ -n "$SHORTS" ]; then
  KIT_JSON=",
    \"kit\": { \"jersey\": \"$JERSEY\", \"stripe\": \"$STRIPE\", \"shorts\": \"$SHORTS\" }"
fi

mkdir -p "$GK_DIR"
NOW=$(date +%s)

# Timeline matches the goal-type defaults in shared/state-schema.md; the test
# event's scoreboard hold is shortened to 2 minutes
if [ "$NO_OVERLAY" -eq 1 ]; then
  OV_END=3.0; HOLD_START=3.0; HOLD_END=123.0
else
  OV_END=11.2; HOLD_START=11.2; HOLD_END=131.2
fi

# Atomic write: temp file in the same dir + mv (rename atomicity means readers
# never see half a JSON)
TMP=$(mktemp "$GK_DIR/.state.json.XXXXXX")
cat > "$TMP" <<EOF
{
  "schema_version": 1,
  "event": {
    "id": "test-$NOW",
    "type": "goal",
    "team": "$TEAM",
    "team_flag": "$FLAG",
    "opponent": "$OPPONENT",
    "score": "$SCORE",
    "scorer": "$SCORER",
    "minute": $MINUTE,
    "ts": $NOW.0$KIT_JSON
  },
  "timeline": {
    "statusline_run": [0.0, 3.0],
    "handoff": 3.0,
    "overlay_play": [3.0, $OV_END],
    "scoreboard_hold": [$HOLD_START, $HOLD_END]
  },
  "muted_until": 0
}
EOF
mv -f "$TMP" "$STATE_FILE"
echo "✅ 已注入测试进球事件：${TEAM} ${SCORE} ${OPPONENT} -> ${STATE_FILE}"

if [ "$NO_OVERLAY" -eq 1 ]; then
  echo "ℹ️  --no-overlay：仅状态栏动画。"
  exit 0
fi

# Invoke the Hammerspoon overlay (the hs CLI is installed via hs.ipc during setup)
if command -v hs >/dev/null 2>&1; then
  if hs -c "spoon.GoalKick:play()" >/dev/null 2>&1; then
    echo "🎬 已调起桌面覆盖层动画。"
  else
    echo "⚠️  hs CLI 调用失败：请确认 Hammerspoon 正在运行、init.lua 已加载 GoalKick.spoon 并启用 hs.ipc。" >&2
  fi
else
  echo "⚠️  未找到 hs 命令（Hammerspoon CLI），跳过覆盖层。状态栏动画不受影响。" >&2
fi
