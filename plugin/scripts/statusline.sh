#!/bin/bash
# golazo statusline renderer
# Input: the session JSON Claude Code pipes to stdin; output: one statusline
# row (ANSI 256-color).
# Three modes: animation/scoreboard (when state.json's timeline matches) →
# passthrough (the user's original statusline) → default (model · directory).
# Performance contract: must return within 50ms, no network requests. The main
# rendering is a single awk invocation.

GZ_DIR="${GOLAZO_DIR:-$HOME/.claude/golazo}"
STATE_FILE="$GZ_DIR/state.json"
CONFIG_FILE="$GZ_DIR/config.json"

# stdin must be drained up front: the animation mode never uses it, but
# passthrough mode forwards it verbatim to the wrapped command
input=$(cat)
cols="${COLUMNS:-80}"
now=$(date +%s)

# Display language: an explicit config.lang wins; auto/missing falls back to
# the system locale
gz_lang=""
[ -r "$CONFIG_FILE" ] && gz_lang=$(sed -n 's/.*"lang"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$CONFIG_FILE" | head -1)
case "$gz_lang" in
  zh|en) ;;
  *) case "${LC_ALL:-${LANG:-}}" in zh*) gz_lang=zh ;; *) gz_lang=en ;; esac ;;
esac

# ── Mode 1: timeline rendering from state.json ───────────────────────────────
# One awk pass does everything: parse (whole-file slurp, independent of key
# order/line layout) → timeline branch → output. Prints nothing when no window
# matches, handing over to the passthrough logic below.
if [ -r "$STATE_FILE" ]; then
  rendered=$(awk -v now="$now" -v cols="$cols" -v lang="$gz_lang" '
    { buf = buf $0 " " }

    # extract a string field: "key": "value" (values must not contain double
    # quotes — guaranteed by the writer)
    function gstr(key,    re, s) {
      re = "\"" key "\"[[:space:]]*:[[:space:]]*\""
      if (!match(buf, re)) return ""
      s = substr(buf, RSTART + RLENGTH)
      sub(/".*/, "", s)
      return s
    }
    # extract a numeric field: "key": 123.45
    function gnum(key,    re, s) {
      re = "\"" key "\"[[:space:]]*:[[:space:]]*-?[0-9.]+"
      if (!match(buf, re)) return -1
      s = substr(buf, RSTART, RLENGTH)
      sub(/^.*:[[:space:]]*/, "", s)
      return s + 0
    }
    # extract a two-element array field: "key": [a, b] → globals A1/A2
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
      if (gnum("schema_version") != 1) exit   # unknown version: ignore silently
      ts = gnum("ts"); if (ts < 0) exit
      elapsed = now - ts
      # ts is a float (microsecond precision) while now is whole seconds: a
      # just-fired event can yield elapsed of -1~0 — clamp to zero; only large
      # negatives (true clock skew) are treated as no event
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

      # scorer note: (78′ Messi) / (78′) / empty
      note = ""
      if (minute > 0 && scorer != "") note = " (" minute "\xe2\x80\xb2 " scorer ")"
      else if (minute > 0)            note = " (" minute "\xe2\x80\xb2)"
      else if (scorer != "")          note = " (" scorer ")"

      # Branch 1: the statusline run animation (non-zero-length window)
      if (run2 > run1 && elapsed >= run1 && elapsed < run2) {
        frac = (elapsed - run1) / (run2 - run1)
        indent = int(frac * (cols > 40 ? cols - 38 : 2))   # width-adaptive: the runner moves right over time
        pad = sprintf("%" (indent > 0 ? indent : 1) "s", "")
        runner = (int(elapsed - run1) % 2 == 0) ? "\xe1\x95\x95( \xe1\x90\x9b )\xe1\x95\x97" : "\xe1\x95\x97( \xe1\x90\x9b )\xe1\x95\x95"
        tail = (frac > 0.66) ? " \xe2\x94\x80\xe2\x94\x80\xe2\x96\xb6" : ""
        printf "%s\xe2\x9a\xbd GOOOAL!%s%s%s%s%s%s\n", GOLD, R, pad, CYAN, runner, tail, R
        exit
      }
      # Branch 2: after the handoff, while the overlay plays (non-zero-length window)
      if (ov2 > ov1 && elapsed >= handoff && elapsed < ov2) {
        msg = (lang == "zh") ? "小人离开了终端，正在你的桌面上\xe2\x80\xa6" \
                             : "The runner left the terminal \xe2\x80\x94 now on your desktop\xe2\x80\xa6"
        printf "%s\xe2\x9a\xbd %s%s\n", DIM, msg, R
        exit
      }
      # Branch 3: scoreboard hold / opponent goal / VAR cancel
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

# ── Mode 2: pass through to the user's original statusline ──────────────────
if [ -r "$CONFIG_FILE" ]; then
  if command -v jq >/dev/null 2>&1; then
    wrapped=$(jq -r '.wrapped_statusline_cmd // empty' "$CONFIG_FILE" 2>/dev/null)
  else
    # naive extraction without jq: give up on wrapping when the command
    # contains escaped quotes (very rare)
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

# ── Mode 3: default output (model name · current directory) ─────────────────
if command -v jq >/dev/null 2>&1; then
  line=$(printf '%s' "$input" | jq -r '"\(.model.display_name // "Claude") · \(.workspace.current_dir // .cwd // "~" | split("/") | last)"' 2>/dev/null)
else
  model=$(printf '%s' "$input" | sed -n 's/.*"display_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
  dir=$(printf '%s' "$input" | sed -n 's/.*"current_dir"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
  line="${model:-Claude} · ${dir##*/}"
fi
printf '\033[38;5;245m%s\033[0m\n' "${line:-Claude}"
