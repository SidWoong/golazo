#!/bin/bash
# SessionStart hook：确保 poller 守护进程存活，不存活则拉起
# 幂等、静音（hook 内输出会进入会话上下文，保持简短）；失败不阻塞会话启动

GK_DIR="${GOAL_KICK_DIR:-$HOME/.claude/goal-kick}"
PID_FILE="$GK_DIR/poller.pid"
LOG_FILE="$GK_DIR/poller.log"
CONFIG_FILE="$GK_DIR/config.json"

# 未完成 setup（无配置）则什么都不做
[ -r "$CONFIG_FILE" ] || exit 0

# 世界杯已结束则不再拉起（poller 自身也会在该日期后自动退出）
if [ "$(date +%Y%m%d)" -gt 20260719 ]; then
  exit 0
fi

# pid 文件存在且进程存活 → 无事可做
if [ -r "$PID_FILE" ]; then
  pid=$(cat "$PID_FILE" 2>/dev/null)
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
    exit 0
  fi
fi

# 选择 Python 解释器：优先 install.sh 创建的专属 venv，回退系统 python3
PYTHON="$GK_DIR/venv/bin/python"
[ -x "$PYTHON" ] || PYTHON=$(command -v python3 || true)
[ -n "$PYTHON" ] || exit 0

mkdir -p "$GK_DIR"
nohup "$PYTHON" -m goal_poller run >> "$LOG_FILE" 2>&1 &
echo $! > "$PID_FILE"
echo "goal-kick: poller 已拉起 (pid $!)"
