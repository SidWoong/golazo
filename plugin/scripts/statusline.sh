#!/bin/bash
# goal-kick 状态栏渲染器
# 输入：Claude Code 经 stdin 传入的会话 JSON；输出：单行状态栏文本（ANSI 256 色）
# 三种模式：动画/比分（state.json 时间轴命中时）→ 透传（用户原 statusline）→ 默认（模型名 · 当前目录）
# 性能约束：必须 50ms 内返回，禁止网络请求。渲染主体为单次 awk 调用。

GK_DIR="${GOAL_KICK_DIR:-$HOME/.claude/goal-kick}"
STATE_FILE="$GK_DIR/state.json"
CONFIG_FILE="$GK_DIR/config.json"

# stdin 必须先整体读走：动画模式用不到，但透传模式要原样转发给被包装命令
input=$(cat)
cols="${COLUMNS:-80}"
now=$(date +%s)

# 展示语言：config.lang 显式指定优先，auto/缺失时按系统 locale 判定
gk_lang=""
[ -r "$CONFIG_FILE" ] && gk_lang=$(sed -n 's/.*"lang"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$CONFIG_FILE" | head -1)
case "$gk_lang" in
  zh|en) ;;
  *) case "${LC_ALL:-${LANG:-}}" in zh*) gk_lang=zh ;; *) gk_lang=en ;; esac ;;
esac

# ── 模式一：state.json 时间轴渲染 ─────────────────────────────────────────────
# 单次 awk 完成：解析（整文件 slurp，不依赖键顺序/换行格式）→ 时间轴分支 → 输出。
# 命不中任何窗口时输出空，交给后面的透传逻辑。
if [ -r "$STATE_FILE" ]; then
  rendered=$(awk -v now="$now" -v cols="$cols" -v lang="$gk_lang" '
    { buf = buf $0 " " }

    # 提取字符串字段："key": "value"（值内不允许出现双引号，由写入方保证）
    function gstr(key,    re, s) {
      re = "\"" key "\"[[:space:]]*:[[:space:]]*\""
      if (!match(buf, re)) return ""
      s = substr(buf, RSTART + RLENGTH)
      sub(/".*/, "", s)
      return s
    }
    # 提取数值字段："key": 123.45
    function gnum(key,    re, s) {
      re = "\"" key "\"[[:space:]]*:[[:space:]]*-?[0-9.]+"
      if (!match(buf, re)) return -1
      s = substr(buf, RSTART, RLENGTH)
      sub(/^.*:[[:space:]]*/, "", s)
      return s + 0
    }
    # 提取二元数组字段："key": [a, b] → 写入全局 A1/A2
    function garr(key,    re, s, parts) {
      re = "\"" key "\"[[:space:]]*:[[:space:]]*\\[[^]]*\\]"
      if (!match(buf, re)) { A1 = -1; A2 = -1; return 0 }
      s = substr(buf, RSTART, RLENGTH)
      sub(/^[^[]*\[/, "", s); sub(/\].*/, "", s)
      split(s, parts, ",")
      A1 = parts[1] + 0; A2 = parts[2] + 0
      return 1
    }

    END {
      if (gnum("schema_version") != 1) exit   # 不认识的版本：静默忽略
      ts = gnum("ts"); if (ts < 0) exit
      elapsed = now - ts
      # ts 为浮点（微秒精度）而 now 为整数秒：刚触发的事件 elapsed 可为 -1~0，归零处理；
      # 仅大幅负值（真正的时钟偏差）才当作无事件
      if (elapsed < 0) { if (elapsed > -2) elapsed = 0; else exit }

      type = gstr("type")
      team = gstr("team"); flag = gstr("team_flag"); opp = gstr("opponent")
      score = gstr("score"); scorer = gstr("scorer"); minute = gnum("minute")

      garr("statusline_run"); run1 = A1; run2 = A2
      handoff = gnum("handoff")
      garr("overlay_play"); ov1 = A1; ov2 = A2
      garr("scoreboard_hold"); hold1 = A1; hold2 = A2

      GOLD = "\033[1;38;5;220m"; DIM = "\033[38;5;245m"
      CYAN = "\033[38;5;51m"; GRN = "\033[38;5;46m"; R = "\033[0m"

      # 进球者注记：(78分钟 梅西) / (78分钟) / 空
      note = ""
      if (minute > 0 && scorer != "") note = " (" minute "\xe2\x80\xb2 " scorer ")"
      else if (minute > 0)            note = " (" minute "\xe2\x80\xb2)"
      else if (scorer != "")          note = " (" scorer ")"

      # 分支一：状态栏助跑动画（窗口非零长）
      if (run2 > run1 && elapsed >= run1 && elapsed < run2) {
        frac = (elapsed - run1) / (run2 - run1)
        indent = int(frac * (cols > 40 ? cols - 38 : 2))   # 宽度自适应：小人随时间向右奔跑
        pad = sprintf("%" (indent > 0 ? indent : 1) "s", "")
        runner = (int(elapsed - run1) % 2 == 0) ? "\xe1\x95\x95( \xe1\x90\x9b )\xe1\x95\x97" : "\xe1\x95\x97( \xe1\x90\x9b )\xe1\x95\x95"
        tail = (frac > 0.66) ? " \xe2\x94\x80\xe2\x94\x80\xe2\x96\xb6" : ""
        printf "%s\xe2\x9a\xbd GOOOAL!%s%s%s%s%s%s\n", GOLD, R, pad, CYAN, runner, tail, R
        exit
      }
      # 分支二：交接后、覆盖层播放期间（覆盖层窗口非零长）
      if (ov2 > ov1 && elapsed >= handoff && elapsed < ov2) {
        msg = (lang == "zh") ? "小人离开了终端，正在你的桌面上\xe2\x80\xa6" \
                             : "The runner left the terminal \xe2\x80\x94 now on your desktop\xe2\x80\xa6"
        printf "%s\xe2\x9a\xbd %s%s\n", DIM, msg, R
        exit
      }
      # 分支三：比分常驻 / 对手进球 / VAR 取消
      if (elapsed >= hold1 && elapsed < hold2) {
        if (type == "goal")
          printf "%s\xe2\x9a\xbd GOOOAL! %s %s %s %s%s%s\n", GOLD, flag, team, score, opp, note, R
        else if (type == "opponent_goal") {
          msg = (lang == "zh") ? " 进球了\xe2\x80\xa6 " : " scored\xe2\x80\xa6 "
          printf "%s\xe2\x9a\xbd %s%s%s%s\n", DIM, team, msg, score, R
        }
        else if (type == "var_cancel") {
          msg = (lang == "zh") ? "进球被 VAR 取消 \xf0\x9f\x98\xa4" : "Goal disallowed by VAR \xf0\x9f\x98\xa4"
          printf "%s%s%s\n", DIM, msg, R
        }
        exit
      }
    }
  ' "$STATE_FILE")
  if [ -n "$rendered" ]; then
    printf '%s\n' "$rendered"
    exit 0
  fi
fi

# ── 模式二：透传用户原有 statusline ──────────────────────────────────────────
if [ -r "$CONFIG_FILE" ]; then
  if command -v jq >/dev/null 2>&1; then
    wrapped=$(jq -r '.wrapped_statusline_cmd // empty' "$CONFIG_FILE" 2>/dev/null)
  else
    # 无 jq 时的朴素提取：命令含转义引号则放弃透传（极少见）
    wrapped=$(sed -n 's/.*"wrapped_statusline_cmd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$CONFIG_FILE")
  fi
  if [ -n "$wrapped" ]; then
    out=$(printf '%s' "$input" | /bin/sh -c "$wrapped" 2>/dev/null)
    if [ -n "$out" ]; then
      printf '%s\n' "$out"
      exit 0
    fi
  fi
fi

# ── 模式三：默认输出（模型名 · 当前目录）────────────────────────────────────
if command -v jq >/dev/null 2>&1; then
  line=$(printf '%s' "$input" | jq -r '"\(.model.display_name // "Claude") · \(.workspace.current_dir // .cwd // "~" | split("/") | last)"' 2>/dev/null)
else
  model=$(printf '%s' "$input" | sed -n 's/.*"display_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
  dir=$(printf '%s' "$input" | sed -n 's/.*"current_dir"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
  line="${model:-Claude} · ${dir##*/}"
fi
printf '\033[38;5;245m%s\033[0m\n' "${line:-Claude}"
