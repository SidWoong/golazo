# goal-kick state-file contract (binding for all three ends)

This document is the **single contract** between the poller (writer),
statusline.sh (reader) and GoalKick.spoon (reader).
When any implementation disagrees with this file, this file wins; changing it
requires re-checking all three ends.

## File locations

| File | Path | Writer | Readers |
|---|---|---|---|
| State file | `~/.claude/goal-kick/state.json` | poller / trigger-test.sh | statusline.sh, GoalKick.spoon |
| User config | `~/.claude/goal-kick/config.json` | poller CLI (`config` subcommands) | poller; statusline.sh (read-only: `wrapped_statusline_cmd`, `lang`) |

The root of all paths can be redirected with the `GOAL_KICK_DIR` env var
(default `~/.claude/goal-kick`) — used by tests.

## Write rules

- **Atomic writes**: write a temp file in the same directory, then `rename()`
  over the target. Readers never observe half a JSON.
- **Overwrite semantics**: each new event replaces state.json wholesale, never
  appends. There is exactly one "current event" at a time.
- **Localization happens in the writer**: display strings such as `event.team`
  and `event.opponent` are written in the language selected by `config.lang`
  (zh / en / auto); readers render them verbatim and never translate.
- UTF-8, no BOM. Top-level key order is not guaranteed; readers must not
  depend on it.

## Read rules

- Readers compare `now - event.ts` (called `elapsed`, in seconds) against
  `timeline` to decide what to render.
- `elapsed < 0` (clock skew) or beyond every window → treat as "no event".
- Missing or unparseable file → treat as "no event"; **never spam errors**.

## state.json schema (schema_version = 1)

```jsonc
{
  "schema_version": 1,                  // int, required. Readers must silently ignore unknown versions
  "event": {
    "id": "fd-12345-goal-2",            // string, required. Globally unique idempotency key.
                                        // Format: {provider}-{match_id}-goal-{total_goals}
                                        // VAR rollback events: {provider}-{match_id}-var-{int(ts)}
                                        // Test events: test-{int(ts)}
    "type": "goal",                     // "goal" | "opponent_goal" | "var_cancel", required
    "team": "阿根廷",                    // string, required. goal = the followed team that scored;
                                        // opponent_goal = the opponent that scored
    "team_flag": "🇦🇷",                  // string, may be empty
    "opponent": "法国",                  // string, required. The other side of the fixture
    "score": "2-1",                     // string, required. Always "followed team - opponent"
    "scorer": "梅西",                    // string, may be empty (provider has no data)
    "minute": 78,                       // int, 0 when unknown
    "ts": 1781234567.0,                 // float, required. Event timestamp, epoch seconds
    "kit": {                            // optional. The scoring team's home-kit colors; the overlay
      "jersey": "#74acdf",              // dresses the runner with them. Missing/invalid → readers
      "stripe": "#ffffff",              // fall back to the default palette
      "shorts": "#1a1a2e"
    }
  },
  "timeline": {                         // seconds relative to event.ts; the writer generates them per
                                        // event type, readers only execute
    "statusline_run": [0.0, 3.0],       // [start, end): statusline runner sprint window
    "handoff": 3.0,                     // the handoff instant: statusline runner vanishes, overlay runner appears
    "overlay_play": [3.0, 11.2],        // [start, end): desktop overlay window (8.2s: run along the
                                        // window edge 1.2s + leap/run-up/shot/GOOOAL/fade)
    "scoreboard_hold": [11.2, 611.2]    // [start, end): statusline scoreboard window
  },
  "muted_until": 0                      // float epoch seconds. Written via /goal-kick:mute; the poller
                                        // triggers nothing before this time. Readers may ignore it
                                        // (while muted the poller never writes events at all).
}
```

### Event types and default timelines

The writer generates a different timeline per `type`; readers **render purely
from the timeline** and never decide per type what to play:

| type | statusline_run | handoff | overlay_play | scoreboard_hold | Notes |
|---|---|---|---|---|---|
| `goal` | `[0, 3]` | `3` | `[3, 11.2]` | `[11.2, 11.2 + hold_min*60]` | the full celebration chain |
| `goal` (overlay_enabled=false) | `[0, 3]` | `3` | `[3, 3]` (zero-length) | `[3, 3 + hold_min*60]` | overlay skipped |
| `opponent_goal` | `[0, 0]` (zero-length) | `0` | `[0, 0]` | `[0, 90]` | a dim one-liner for 90s |
| `var_cancel` | `[0, 0]` | `0` | `[0, 0]` | `[0, 90]` | "Goal disallowed by VAR 😤" |

> Why statusline_run is 3s rather than the 1.5s in the original spec example:
> Claude Code's `statusLine.refreshInterval` has a minimum granularity of 1
> second (official docs), so a 1.5s window would show only 1–2 frames. A 3s
> window shows a full 3-frame sprint at a 1s refresh. The timeline is data,
> not code — tune freely later.

### Rendering branches per reader (normative)

`elapsed = now - event.ts`:

- **statusline.sh**
  1. `statusline_run[0] <= elapsed < statusline_run[1]` and the window is
     non-zero-length → sprint frame (frame index = `floor(elapsed - start)`)
  2. `handoff <= elapsed < overlay_play[1]` and the overlay window is
     non-zero-length → "The runner left the terminal — now on your desktop…"
  3. `scoreboard_hold[0] <= elapsed < scoreboard_hold[1]` → render per type:
     - `goal`: `⚽ GOOOAL! {team_flag} {team} {score} {opponent} ({minute}′ {scorer})`, gold
     - `opponent_goal`: `⚽ {team} scored… {score}`, dim
     - `var_cancel`: `Goal disallowed by VAR 😤`, dim
  4. otherwise → passthrough mode
- **GoalKick.spoon**: reads state.json only when invoked via
  `hs -c "spoon.GoalKick:play()"`; returns immediately when
  `event.type != "goal"` or `elapsed` is already past `overlay_play[1]`.
  The animation's internal clock starts at `overlay_play[0]`; see
  `overlay/GoalKick.spoon/anim/`.

## config.json schema (schema_version = 1)

```jsonc
{
  "schema_version": 1,
  "followed_teams": [
    {
      "provider_team_id": 762,          // int | null. null = not yet resolved via the API
      "name_zh": "阿根廷",
      "name_en": "Argentina",
      "flag": "🇦🇷"
    }
  ],
  "provider": "football_data",
  "api_token": "",
  "proxy": "",                          // empty = direct connection (HTTPS_PROXY/HTTP_PROXY env vars still apply)
  "poll_interval_sec": 20,
  "idle_interval_sec": 300,
  "overlay_enabled": true,
  "scoreboard_hold_min": 10,
  "wrapped_statusline_cmd": "",         // the user's pre-existing statusline command captured during setup; empty = none
  "muted_until": 0,
  "lang": "auto"                        // display language: zh / en / auto (auto = system locale)
}
```

**Write constraint**: apart from statusline.sh reading `wrapped_statusline_cmd`
and `lang`, config.json must only ever be modified through
`python -m goal_poller config <subcommand>` — hand-written JSON overwrites are
forbidden (format-corruption protection).
