#!/bin/bash
# golazo clean uninstall: stop the poller → restore the user statusline →
# remove the Spoon and the init.lua block → delete the data directory.
# Idempotent; any missing step is skipped silently. Bilingual output picked
# from the system locale.

set -u

GZ_DIR="${GOLAZO_DIR:-$HOME/.claude/golazo}"
SETTINGS="$HOME/.claude/settings.json"

case "${LC_ALL:-${LANG:-}}" in zh*) GZ_L=zh ;; *) GZ_L=en ;; esac
pick() { if [ "$GZ_L" = zh ]; then printf '%s' "$1"; else printf '%s' "$2"; fi; }
step() { printf '\n\033[1;36m▸ %s\033[0m\n' "$(pick "$1" "$2")"; }
ok()   { printf '\033[32m  ✓ %s\033[0m\n' "$(pick "$1" "$2")"; }
warn() { printf '\033[33m  ⚠ %s\033[0m\n' "$(pick "$1" "$2")"; }

step "停止 poller" "Stopping poller"
if [ -r "$GZ_DIR/poller.pid" ]; then
  pid=$(cat "$GZ_DIR/poller.pid" 2>/dev/null)
  if [ -n "$pid" ] && kill "$pid" 2>/dev/null; then
    ok "已结束进程 $pid" "Killed process $pid"
  fi
fi

step "还原 statusline 配置" "Restoring statusline config"
if [ -r "$SETTINGS" ] && command -v jq >/dev/null 2>&1; then
  current=$(jq -r '.statusLine.command // empty' "$SETTINGS" 2>/dev/null)
  case "$current" in
    *golazo*)
      wrapped=$(jq -r '.wrapped_statusline_cmd // empty' "$GZ_DIR/config.json" 2>/dev/null)
      tmp=$(mktemp)
      if [ -n "$wrapped" ]; then
        # restore the user's original statusline command
        jq --arg cmd "$wrapped" '.statusLine = {type: "command", command: $cmd}' \
          "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
        ok "statusLine 已还原为原配置：$wrapped" "statusLine restored to: $wrapped"
      else
        jq 'del(.statusLine)' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
        ok "statusLine 已移除（安装前无自定义配置）" "statusLine removed (none existed before install)"
      fi
      ;;
    "") ok "settings 中无 statusLine（无需处理）" "No statusLine in settings (nothing to do)" ;;
    *)  ok "statusLine 非 golazo 所设（保持不动）" "statusLine not set by golazo (left untouched)" ;;
  esac
else
  warn "未找到 jq 或 settings.json，请手动检查 ~/.claude/settings.json 的 statusLine 字段" \
       "jq or settings.json missing; check the statusLine field in ~/.claude/settings.json manually"
fi

step "移除 Hammerspoon 组件" "Removing Hammerspoon components"
rm -rf "$HOME/.hammerspoon/Spoons/Golazo.spoon" && ok "Spoon 已删除" "Spoon removed"
HS_INIT="$HOME/.hammerspoon/init.lua"
if [ -f "$HS_INIT" ] && grep -qF "golazo BEGIN" "$HS_INIT"; then
  sed -i '' '/golazo BEGIN/,/golazo END/d' "$HS_INIT"
  ok "init.lua 注册块已移除" "init.lua block removed"
fi

step "删除数据目录" "Deleting data directory"
rm -rf "$GZ_DIR" && ok "$GZ_DIR 已删除" "$GZ_DIR deleted"

echo ""
pick "卸载完成。如通过插件市场安装，请在 Claude Code 中执行 /plugin uninstall golazo" \
     "Uninstall complete. If installed via marketplace, also run /plugin uninstall golazo in Claude Code"
echo