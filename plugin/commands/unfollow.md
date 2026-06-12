---
description: Unfollow teams
argument-hint: <team names, one or more>
---

The user wants to unfollow: $ARGUMENTS

Parse the team names and run for each:
`~/.claude/goal-kick/venv/bin/python -m goal_poller config remove-team <name>`

The command prints what was actually removed (substring match on zh/en names). Afterwards run `config list` and report the remaining followed teams. If the list is now empty, mention the poller will idle and no animations will trigger.
