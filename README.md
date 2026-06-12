# golazo ⚽

> Don't miss a single goal from your World Cup team while you code — get told by a pixel runner who dashes out of your Claude Code statusline, leaps onto your desktop, and kicks a GOOOAL celebration.

**English** | [简体中文](README.zh-CN.md)

![demo](docs/demo.gif)

*↑ Record a GIF via `/golazo:test` and replace `docs/demo.gif`*

## What it does

When a team you follow scores:

1. Your Claude Code **statusline** plays an ASCII runner sprint (3s)
2. The runner dashes along your terminal window's bottom edge, then **leaps out of the window frame** onto the desktop — wearing the scoring team's **actual kit colors** — sprints, shoots, and the net bulges into a golden **GOOOAL!** with 150 confetti pieces (8s overlay, click-through, never steals focus)
3. The statusline keeps the score for 10 minutes: `⚽ GOOOAL! 🇦🇷 Argentina 2-1 France`

The rest of the time your statusline is fully passed through to whatever you had before — zero interference.

## Install (3 lines)

```
/plugin marketplace add SidWoong/golazo
/plugin install golazo@golazo
/golazo:setup
```

`setup` is a conversational wizard: installs dependencies (Hammerspoon, Python runtime, Spoon), walks you through a free [football-data.org](https://www.football-data.org/client/register) token, lets you pick teams in natural language, handles statusline coexistence, and offers a test animation at the end. It speaks your language — English, Chinese, whatever you type.

## Commands

| Command                           | What it does |
|-----------------------------------|---|
| `/golazo:setup`                   | Full onboarding wizard |
| `/golazo:follow Argentina, China` | Follow teams (fuzzy & case-insensitive; non-qualified teams like China are politely refused, the rest still added) |
| `/golazo:unfollow China`          | Unfollow |
| `/golazo:status`                  | Followed teams, poller heartbeat, today's scores |
| `/golazo:mute 2h`                 | Mute (`30m` / `today` / `off`) |
| `/golazo:test`                    | Simulate a live goal through the real pipeline (mock API) |

## Architecture

Three processes communicate one-way through `~/.claude/golazo/state.json` (contract: [shared/state-schema.md](shared/state-schema.md)):

```
poller (Python daemon) ──write──▶ state.json ◀──read── statusline.sh (Claude Code)
        │ hs -c                       ▲
        └────────▶ Golazo.spoon ──read┘ (Hammerspoon desktop overlay)
```

- **poller**: polls football-data.org (20s while a followed match is live / sleeps until 5 min before kickoff otherwise), detects goals by score deltas, deterministic event ids for idempotency, VAR-rollback safe, no replays after network gaps
- **statusline.sh**: single awk pass, ~7 ms per render (50 ms budget); passes through your existing statusline when idle
- **overlay**: Hammerspoon for v0.1; all animation data (timeline/palette/sprites) lives in data files, so the renderer is swappable (Tauri planned for v1.0)

## FAQ

**Language?**
Display language is auto-detected from your system locale (`lang: auto`), override with `~/.claude/golazo/venv/bin/python -m golazo config set lang en` (or `zh`). Slash commands always reply in the language you use.

**Proxy?**
Direct connection by default; `HTTPS_PROXY`/`HTTP_PROXY` env vars are honored. To pin one: `config set proxy http://127.0.0.1:7890`.

**Desktop animation doesn't show?**
Check in order: ① Hammerspoon is running and has Accessibility permission (System Settings → Privacy & Security); ② `hs -c "1+1"` prints 2 (if not, run `hs.ipc.cliInstall()` in the Hammerspoon console once); ③ run `/golazo:test` and read the script's hints. The statusline animation is independent and unaffected.

**I already have a custom statusline.**
`setup` detects it and asks to *wrap* it: your command keeps rendering as usual, golazo only takes over during the animation/score windows.

**Is the free API tier enough?**
football-data.org free tier allows ~10 requests/min. The poller uses 1 competition-level request per cycle — 3/min during live matches. Verified live (2026-06-12): free tier covers the 2026 World Cup (code `WC`), all 104 matches visible with real-time scores. Limitation: the free tier does **not** expose goalscorer names/minutes (`goals: null`) — the animation gracefully omits the scorer line; a paid tier or an alternative provider (the provider layer is pluggable) lights it up.

**What if a team I follow isn't in the World Cup?**
E.g. `/golazo:follow Argentina, China`: Argentina is added normally; China isn't on the 48-team whitelist, so it's politely refused with zero config writes.

**Uninstall?**
`bash uninstall.sh` from the repo root: stops the poller, restores your original statusline, removes the Spoon and init.lua block, deletes `~/.claude/golazo`. Then `/plugin uninstall golazo`. The poller also exits by itself after the final on 2026-07-19.

## Development

```bash
# poller tests
cd poller && python3 -m venv .venv && .venv/bin/pip install -e ".[dev]" && .venv/bin/pytest
# overlay dry-run (needs: brew install lua)
lua overlay/tests/dryrun.lua
# trigger the full chain manually (defaults to Messi's 108' goal in the 2022 final)
plugin/scripts/trigger-test.sh
plugin/scripts/trigger-test.sh --team France --flag 🇫🇷   # or any team
```

