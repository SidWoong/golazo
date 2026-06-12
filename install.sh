#!/bin/bash
# goal-kick 一键安装脚本（幂等，可重复执行；/goal-kick:setup 内部调用）
# 职责：依赖检测 → Python 运行时（优先 uv，回退 venv）→ 安装 poller →
#       落地 statusline/trigger 脚本到稳定路径 → 安装 Hammerspoon Spoon
# 不做的事：写用户 settings.json（statusline 注册由 setup 对话确认后处理）

set -eu

REPO_DIR=$(cd "$(dirname "$0")" && pwd)
GK_DIR="${GOAL_KICK_DIR:-$HOME/.claude/goal-kick}"
VENV_DIR="$GK_DIR/venv"
BIN_DIR="$GK_DIR/bin"

step() { printf '\n\033[1;36m▸ %s\033[0m\n' "$1"; }
ok()   { printf '\033[32m  ✓ %s\033[0m\n' "$1"; }
warn() { printf '\033[33m  ⚠ %s\033[0m\n' "$1"; }

step "检查运行环境"
[ "$(uname)" = "Darwin" ] || { echo "仅支持 macOS"; exit 1; }

PYTHON=""
for cand in python3.13 python3.12 python3.11 python3; do
  if command -v "$cand" >/dev/null 2>&1; then
    ver=$("$cand" -c 'import sys; print(sys.version_info >= (3,11))' 2>/dev/null || echo False)
    if [ "$ver" = "True" ]; then PYTHON=$(command -v "$cand"); break; fi
  fi
done
[ -n "$PYTHON" ] || { echo "需要 Python 3.11+（brew install python@3.12）"; exit 1; }
ok "Python: $PYTHON"

if [ -d "/Applications/Hammerspoon.app" ]; then
  ok "Hammerspoon 已安装"
  HS_PRESENT=1
else
  warn "Hammerspoon 未安装：桌面动画需要它（brew install --cask hammerspoon，"
  warn "安装后启动一次并在 系统设置→隐私与安全性→辅助功能 中授权）"
  HS_PRESENT=0
fi

step "安装 poller 运行时 → $VENV_DIR"
mkdir -p "$GK_DIR" "$BIN_DIR"
if command -v uv >/dev/null 2>&1; then
  uv venv --quiet --python "$PYTHON" "$VENV_DIR" 2>/dev/null || true
  uv pip install --quiet --python "$VENV_DIR/bin/python" "$REPO_DIR/poller"
  ok "经 uv 安装完成"
else
  [ -x "$VENV_DIR/bin/python" ] || "$PYTHON" -m venv "$VENV_DIR"
  "$VENV_DIR/bin/pip" install --quiet --upgrade "$REPO_DIR/poller"
  ok "经 venv/pip 安装完成"
fi
"$VENV_DIR/bin/python" -m goal_poller config get schema_version >/dev/null
ok "goal_poller CLI 可用"

step "落地脚本到稳定路径 → $BIN_DIR"
# settings.json 引用的命令路径不能随插件更新漂移，故复制而非引用插件目录
cp -f "$REPO_DIR/plugin/scripts/statusline.sh" "$BIN_DIR/statusline.sh"
cp -f "$REPO_DIR/plugin/scripts/trigger-test.sh" "$BIN_DIR/trigger-test.sh"
chmod +x "$BIN_DIR"/*.sh
ok "statusline.sh / trigger-test.sh"

step "安装 GoalKick.spoon"
SPOON_DST="$HOME/.hammerspoon/Spoons/GoalKick.spoon"
mkdir -p "$HOME/.hammerspoon/Spoons"
rm -rf "$SPOON_DST"
cp -R "$REPO_DIR/overlay/GoalKick.spoon" "$SPOON_DST"
ok "已拷贝到 $SPOON_DST"

HS_INIT="$HOME/.hammerspoon/init.lua"
MARK_BEGIN="-- goal-kick BEGIN（自动管理，勿手改）"
if ! grep -qF -e "$MARK_BEGIN" "$HS_INIT" 2>/dev/null; then
  {
    echo ""
    echo "$MARK_BEGIN"
    echo 'hs.loadSpoon("GoalKick")'
    echo 'require("hs.ipc")'
    echo 'hs.ipc.cliInstall()'
    echo "-- goal-kick END"
  } >> "$HS_INIT"
  ok "已在 init.lua 注册 Spoon 与 hs.ipc"
else
  ok "init.lua 已注册过（跳过）"
fi
if [ "$HS_PRESENT" = "1" ]; then
  open -g -a Hammerspoon 2>/dev/null || true
fi

step "完成"
echo "  数据目录：$GK_DIR"
echo "  后续：在 Claude Code 中运行 /goal-kick:setup 完成 token、球队与 statusline 配置"
