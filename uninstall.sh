#!/bin/bash
# goal-kick 干净卸载：停 poller → 还原用户 statusline → 移除 Spoon/init.lua 注册 → 删数据目录
# 幂等；任何一步缺失都静默跳过

set -u

GK_DIR="${GOAL_KICK_DIR:-$HOME/.claude/goal-kick}"
SETTINGS="$HOME/.claude/settings.json"

step() { printf '\n\033[1;36m▸ %s\033[0m\n' "$1"; }
ok()   { printf '\033[32m  ✓ %s\033[0m\n' "$1"; }
warn() { printf '\033[33m  ⚠ %s\033[0m\n' "$1"; }

step "停止 poller"
if [ -r "$GK_DIR/poller.pid" ]; then
  pid=$(cat "$GK_DIR/poller.pid" 2>/dev/null)
  if [ -n "$pid" ] && kill "$pid" 2>/dev/null; then
    ok "已结束进程 $pid"
  fi
fi

step "还原 statusline 配置"
if [ -r "$SETTINGS" ] && command -v jq >/dev/null 2>&1; then
  current=$(jq -r '.statusLine.command // empty' "$SETTINGS" 2>/dev/null)
  case "$current" in
    *goal-kick*)
      wrapped=$(jq -r '.wrapped_statusline_cmd // empty' "$GK_DIR/config.json" 2>/dev/null)
      tmp=$(mktemp)
      if [ -n "$wrapped" ]; then
        # 还原为用户原有 statusline 命令
        jq --arg cmd "$wrapped" '.statusLine = {type: "command", command: $cmd}' \
          "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
        ok "statusLine 已还原为原配置：$wrapped"
      else
        jq 'del(.statusLine)' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
        ok "statusLine 已移除（安装前无自定义配置）"
      fi
      ;;
    "") ok "settings 中无 statusLine（无需处理）" ;;
    *)  ok "statusLine 非 goal-kick 所设（保持不动）" ;;
  esac
else
  warn "未找到 jq 或 settings.json，请手动检查 ~/.claude/settings.json 的 statusLine 字段"
fi

step "移除 Hammerspoon 组件"
rm -rf "$HOME/.hammerspoon/Spoons/GoalKick.spoon" && ok "Spoon 已删除"
HS_INIT="$HOME/.hammerspoon/init.lua"
if [ -f "$HS_INIT" ] && grep -qF "goal-kick BEGIN" "$HS_INIT"; then
  sed -i '' '/goal-kick BEGIN/,/goal-kick END/d' "$HS_INIT"
  ok "init.lua 注册块已移除"
fi

step "删除数据目录"
rm -rf "$GK_DIR" && ok "$GK_DIR 已删除"

echo ""
echo "卸载完成。如通过插件市场安装，请在 Claude Code 中执行 /plugin uninstall goal-kick"
