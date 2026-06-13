---
description: Simulate a live goal through the real pipeline (mock API) and play the full effects chain
argument-hint: [team] [opponent] [score, e.g. 4-1]
---

Run the goal simulation. Arguments (may be empty): $ARGUMENTS

Parse the arguments in any language/order into up to three optional parts, then build the command:

- **scoring team** → `--team <name>` (the team that celebrates; fuzzy zh/en/FIFA-code)
- **opponent** → `--opponent <name>` (the other side)
- **scoreline** like `4-1` / `4:1` / "4 比 1" → `--score 4-1` (the followed team must lead)

Examples:
- "美国 巴拉圭 4-1" → `--team 美国 --opponent 巴拉圭 --score 4-1`
- "Japan 2-0" → `--team Japan --score 2-0`
- (nothing) → no flags

Then run, prepending the venv python and only the flags you parsed:
`~/.claude/golazo/venv/bin/python -m golazo test-run [--team …] [--opponent …] [--score …]`

While it runs, tell the user what's happening and what to watch for:
- This is **not** a canned animation: it drives the real production pipeline — poll #1 establishes a score baseline, then after ~5 seconds the **mock API** returns the goal, and detection, dedup, dispatch, the state.json write and the overlay invocation all run the same code paths as a real World Cup goal. Only the HTTP call is simulated.
- Visible sequence after the goal "arrives": statusline runner sprint (3s) → the runner dashes along the terminal's bottom edge and leaps out of the frame → desktop run-up, shot, GOOOAL (~8s) → the score stays in the statusline for 10 minutes.
- Defaults when unspecified: team = first followed team, else Messi's 108' in the 2022 final (Argentina 3-2 France); opponent = France; score = 1-0. The scoring team wears its real home kit.

Relay the command's printed poll-by-poll progress. If a team/opponent/score is rejected (not in the 48-team table, or the followed team doesn't lead), report the message and let the user correct it.

If the output says the overlay was not invoked, explain why the desktop animation didn't play (Hammerspoon not running / Accessibility not granted / hs.ipc not enabled); the statusline animation is unaffected.

(For low-level debugging there is also `~/.claude/golazo/bin/trigger-test.sh`, which writes a fabricated state.json directly, bypassing the pipeline — prefer `test-run` unless asked.)
