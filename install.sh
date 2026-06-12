#!/bin/bash
# golazo one-shot installer (idempotent, safe to re-run; called from /golazo:setup)
# Responsibilities: dependency checks → Python runtime (uv preferred, venv fallback)
#   → install the poller → copy statusline/trigger scripts to a stable path
#   → install the Hammerspoon Spoon
# Out of scope: writing the user settings.json (statusline registration is
#   confirmed conversationally during setup)
# Bilingual output: Chinese/English picked from the system locale

set -eu

REPO_DIR=$(cd "$(dirname "$0")" && pwd)
GZ_DIR="${GOLAZO_DIR:-$HOME/.claude/golazo}"
VENV_DIR="$GZ_DIR/venv"
BIN_DIR="$GZ_DIR/bin"

case "${LC_ALL:-${LANG:-}}" in zh*) GZ_L=zh ;; *) GZ_L=en ;; esac
pick() { if [ "$GZ_L" = zh ]; then printf '%s' "$1"; else printf '%s' "$2"; fi; }
step() { printf '\n\033[1;36m▸ %s\033[0m\n' "$(pick "$1" "$2")"; }
ok()   { printf '\033[32m  ✓ %s\033[0m\n' "$(pick "$1" "$2")"; }
warn() { printf '\033[33m  ⚠ %s\033[0m\n' "$(pick "$1" "$2")"; }

step "检查运行环境" "Checking environment"
[ "$(uname)" = "Darwin" ] || { pick "仅支持 macOS" "macOS only"; echo; exit 1; }

PYTHON=""
for cand in python3.13 python3.12 python3.11 python3; do
  if command -v "$cand" >/dev/null 2>&1; then
    ver=$("$cand" -c 'import sys; print(sys.version_info >= (3,11))' 2>/dev/null || echo False)
    if [ "$ver" = "True" ]; then PYTHON=$(command -v "$cand"); break; fi
  fi
done
[ -n "$PYTHON" ] || { pick "需要 Python 3.11+（brew install python@3.12）" \
                            "Python 3.11+ required (brew install python@3.12)"; echo; exit 1; }
ok "Python: $PYTHON" "Python: $PYTHON"

if [ -d "/Applications/Hammerspoon.app" ]; then
  ok "Hammerspoon 已安装" "Hammerspoon found"
  HS_PRESENT=1
else
  warn "Hammerspoon 未安装：桌面动画需要它（brew install --cask hammerspoon，安装后启动并在 系统设置→隐私与安全性→辅助功能 中授权）" \
       "Hammerspoon not installed: desktop effects need it (brew install --cask hammerspoon, then launch it and grant Accessibility in System Settings → Privacy & Security)"
  HS_PRESENT=0
fi

step "安装 poller 运行时 → $VENV_DIR" "Installing poller runtime → $VENV_DIR"
mkdir -p "$GZ_DIR" "$BIN_DIR"
if command -v uv >/dev/null 2>&1; then
  uv venv --quiet --python "$PYTHON" "$VENV_DIR" 2>/dev/null || true
  uv pip install --quiet --python "$VENV_DIR/bin/python" "$REPO_DIR/poller"
  ok "经 uv 安装完成" "Installed via uv"
else
  [ -x "$VENV_DIR/bin/python" ] || "$PYTHON" -m venv "$VENV_DIR"
  "$VENV_DIR/bin/pip" install --quiet --upgrade "$REPO_DIR/poller"
  ok "经 venv/pip 安装完成" "Installed via venv/pip"
fi
"$VENV_DIR/bin/python" -m golazo config get schema_version >/dev/null
ok "golazo CLI 可用" "golazo CLI works"

step "落地脚本到稳定路径 → $BIN_DIR" "Copying scripts to stable path → $BIN_DIR"
# the command path referenced by settings.json must not drift across plugin
# updates, hence copies instead of references into the plugin dir
cp -f "$REPO_DIR/plugin/scripts/statusline.sh" "$BIN_DIR/statusline.sh"
cp -f "$REPO_DIR/plugin/scripts/trigger-test.sh" "$BIN_DIR/trigger-test.sh"
chmod +x "$BIN_DIR"/*.sh
ok "statusline.sh / trigger-test.sh" "statusline.sh / trigger-test.sh"

step "安装 Golazo.spoon" "Installing Golazo.spoon"
SPOON_DST="$HOME/.hammerspoon/Spoons/Golazo.spoon"
mkdir -p "$HOME/.hammerspoon/Spoons"
rm -rf "$SPOON_DST"
cp -R "$REPO_DIR/overlay/Golazo.spoon" "$SPOON_DST"
ok "已拷贝到 $SPOON_DST" "Copied to $SPOON_DST"

HS_INIT="$HOME/.hammerspoon/init.lua"
MARK_BEGIN="-- golazo BEGIN (managed, do not edit)"
MARK_BEGIN_LEGACY="-- golazo BEGIN（自动管理，勿手改）"
if ! grep -qF -e "$MARK_BEGIN" "$HS_INIT" 2>/dev/null \
   && ! grep -qF -e "$MARK_BEGIN_LEGACY" "$HS_INIT" 2>/dev/null; then
  {
    echo ""
    echo "$MARK_BEGIN"
    echo 'hs.loadSpoon("Golazo")'
    echo 'require("hs.ipc")'
    echo 'hs.ipc.cliInstall()'
    echo "-- golazo END"
  } >> "$HS_INIT"
  ok "已在 init.lua 注册 Spoon 与 hs.ipc" "Registered Spoon and hs.ipc in init.lua"
else
  ok "init.lua 已注册过（跳过）" "init.lua already registered (skipped)"
fi
if [ "$HS_PRESENT" = "1" ]; then
  open -g -a Hammerspoon 2>/dev/null || true
fi

step "完成" "Done"
pick "  数据目录：$GZ_DIR" "  Data dir: $GZ_DIR"; echo
pick "  后续：在 Claude Code 中运行 /golazo:setup 完成 token、球队与 statusline 配置" \
     "  Next: run /golazo:setup in Claude Code to configure token, teams and statusline"; echo
