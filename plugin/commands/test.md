---
description: Inject a fabricated goal and play the full effects chain (statusline + desktop)
argument-hint: [optional team name]
---

Play the test animation. Arguments (may be empty): $ARGUMENTS

1. **No team given**: just run `~/.claude/golazo/bin/trigger-test.sh` — it re-enacts the classic scene of the 2022 Qatar final by default: Messi's 108th-minute goal, Argentina 3-2 France, in the sky-blue-and-white kit.
2. **A team was given**: first run `~/.claude/golazo/venv/bin/python -m golazo config search-team <name>` for the display name (zh or en per the user's language) and the flag emoji; then fetch the kit colors:
   `~/.claude/golazo/venv/bin/python -c "from golazo import teams; print(teams.kit_for(teams.search('<name>')[0]))"`
   Then run `trigger-test.sh --team <name> --flag <emoji> --jersey <hex> --stripe <hex> --shorts <hex>` (optionally add `--opponent/--score/--scorer/--minute` for richer detail).
3. Tell the user what the next ~12 seconds look like: 3s statusline sprint → the runner dashes along the terminal's bottom edge and leaps out of the frame → desktop run-up, shot, GOOOAL (~8s) → the score stays in the statusline for 2 minutes.
4. If the script warns that the hs CLI is unavailable, explain why the desktop animation didn't play (Hammerspoon not running / Accessibility not granted / hs.ipc not enabled); the statusline animation is unaffected.
