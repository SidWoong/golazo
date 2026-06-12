---
description: Mute goal effects (natural durations like 2h / 30m / today)
argument-hint: <duration, e.g. 2h, 30 minutes, today; "off" to unmute>
---

The user's mute request: $ARGUMENTS

Convert natural language into an expression the CLI accepts (`2h` / `30m` / `90s` / `今天` / `today` / `off`), e.g. "a couple of hours" → `2h`, "half an hour" → `30m`, "leave me alone today" → `今天`, "unmute/cancel" → `off`. Ask the user when ambiguous.

Run: `~/.claude/goal-kick/venv/bin/python -m goal_poller mute <expression>`

Relay the mute-until time from the command output. While muted the poller keeps tracking scores — it just triggers no animations.
