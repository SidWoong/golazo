---
description: Show followed teams, poller health and recent scores
---

Run the following and compose a concise report in the user's language:

1. `~/.claude/goal-kick/venv/bin/python -m goal_poller status` — followed teams, mute state, poller heartbeat (pid / last poll / matches in window).
2. If the heartbeat is missing or the process is gone, mention that `bash "${CLAUDE_PLUGIN_ROOT}/scripts/ensure-poller.sh"` restarts it.
3. Read `~/.claude/goal-kick/state.json` (if present): report the current score/event when one is still inside its display window.
4. If an api_token is configured you may additionally run `python -m goal_poller probe` to confirm data-source health (mind the free-tier rate limit — don't call it repeatedly).

Suggested format: one line for followed teams, one for poller health, one per relevant match today (score and status).
