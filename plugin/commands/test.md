---
description: Simulate a live goal through the real pipeline (mock API) and play the full effects chain
argument-hint: [optional team name]
---

Run the goal simulation. Arguments (may be empty): $ARGUMENTS

1. Run the simulation (use the user's team if they named one):
   - no team: `~/.claude/golazo/venv/bin/python -m golazo test-run`
   - team given: `~/.claude/golazo/venv/bin/python -m golazo test-run --team <name>`
2. Before/while it runs, tell the user what is happening and what to watch for:
   - This is **not** a canned animation: it drives the real production pipeline — poll #1 establishes a score baseline, then after ~5 seconds the **mock API** returns a goal, and detection, dedup, dispatch, the state.json write and the overlay invocation all run the same code paths as a real World Cup goal. Only the HTTP call is simulated.
   - Visible sequence after the goal "arrives": statusline runner sprint (3s) → the runner dashes along the terminal's bottom edge and leaps out of the frame → desktop run-up, shot, GOOOAL (~8s) → the score stays in the statusline for 10 minutes.
   - Team pick: explicit team > the user's first followed team > Messi's 108' goal in the 2022 final (Argentina 3-2 France).
3. Relay the command's printed poll-by-poll progress to the user.
4. If the output mentions the overlay was not invoked, explain why the desktop animation didn't play (Hammerspoon not running / Accessibility not granted / hs.ipc not enabled); the statusline animation is unaffected.

(For low-level debugging there is also `~/.claude/golazo/bin/trigger-test.sh`, which writes a fabricated state.json directly, bypassing the pipeline — prefer `test-run` unless asked.)
