---
description: Follow teams (multiple at once; fuzzy zh/en names and FIFA codes)
argument-hint: <team names, e.g. "argentina and japan" / "阿根廷和日本">
---

The user wants to follow: $ARGUMENTS

Parse one or more team names (separators like commas, "and", 、, 和 all count). For each team:

1. `~/.claude/golazo/venv/bin/python -m golazo config search-team <name>` to confirm the match;
   - no match: tell the user the team is not among the 48 of World Cup 2026, or suggest rephrasing;
   - multiple matches: list the candidates and let the user choose.
2. On a unique match, persist with `config add-team <name>`.

When done, run `config list` and report the updated followed list in the user's language. The poller re-reads the config every cycle — no restart needed.
