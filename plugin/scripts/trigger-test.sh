#!/bin/bash
# 手动触发一次完整进球特效链路（供 /goal-kick:test 与开发调试使用）
# 行为：向 state.json 原子写入一条伪造进球事件 → 若 Hammerspoon 可用则调起覆盖层动画
# 用法：trigger-test.sh [--team 名称] [--opponent 名称] [--score 比分] [--scorer 进球者] [--no-overlay]

set -eu

GK_DIR="${GOAL_KICK_DIR:-$HOME/.claude/goal-kick}"
STATE_FILE="$GK_DIR/state.json"

# 默认场面：上一届（2022 卡塔尔）世界杯决赛，梅西加时 108 分钟进球（阿根廷 3-2 法国）
case "${LC_ALL:-${LANG:-}}" in
  zh*) TEAM="阿根廷"; OPPONENT="法国"; SCORER="梅西" ;;
  *)   TEAM="Argentina"; OPPONENT="France"; SCORER="Messi" ;;
esac
FLAG="🇦🇷"; SCORE="3-2"; MINUTE=108
JERSEY="#74acdf"; STRIPE="#ffffff"; SHORTS="#1a1a2e"   # 阿根廷主场球衣
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

# 显式换队但未给球衣 → 丢弃默认的阿根廷球衣（避免张冠李戴），overlay 用默认配色
if [ "$TEAM_SET" = 1 ] && [ "$JERSEY_SET" = 0 ]; then
  JERSEY=""; STRIPE=""; SHORTS=""
fi

# 球衣三色齐全才写 kit 字段，否则 overlay 使用默认配色
KIT_JSON=""
if [ -n "$JERSEY" ] && [ -n "$STRIPE" ] && [ -n "$SHORTS" ]; then
  KIT_JSON=",
    \"kit\": { \"jersey\": \"$JERSEY\", \"stripe\": \"$STRIPE\", \"shorts\": \"$SHORTS\" }"
fi

mkdir -p "$GK_DIR"
NOW=$(date +%s)

# 时间轴与 shared/state-schema.md 的 goal 类型默认值一致；测试事件比分常驻缩短为 2 分钟
if [ "$NO_OVERLAY" -eq 1 ]; then
  OV_END=3.0; HOLD_START=3.0; HOLD_END=123.0
else
  OV_END=11.2; HOLD_START=11.2; HOLD_END=131.2
fi

# 原子写：同目录临时文件 + mv 覆盖（rename 原子性保证读取方不见半个 JSON）
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

# 调起 Hammerspoon 覆盖层（hs CLI 需在 setup 时通过 hs.ipc 安装）
if command -v hs >/dev/null 2>&1; then
  if hs -c "spoon.GoalKick:play()" >/dev/null 2>&1; then
    echo "🎬 已调起桌面覆盖层动画。"
  else
    echo "⚠️  hs CLI 调用失败：请确认 Hammerspoon 正在运行、init.lua 已加载 GoalKick.spoon 并启用 hs.ipc。" >&2
  fi
else
  echo "⚠️  未找到 hs 命令（Hammerspoon CLI），跳过覆盖层。状态栏动画不受影响。" >&2
fi
