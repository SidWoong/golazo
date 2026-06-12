"""Event dispatch: assemble state.json (localized display fields + timeline)
→ atomic write → trigger the overlay → structured log line.

Timeline generation strictly follows the "event type → default timeline"
matrix in shared/state-schema.md.
"""
from __future__ import annotations

import json
import subprocess
import time

from . import teams
from . import config as cfgmod
from .config import atomic_write_json
from .detector import GoalEvent
from .paths import log_path, state_path

# Timeline constants (seconds), aligned with state-schema.md
RUN_DUR = 3.0
OVERLAY_DUR = 8.2
NOTICE_HOLD = 90.0      # display window for opponent_goal / var_cancel notices


def _team_display(api_name: str, cfg: dict) -> tuple[str, str]:
    """Provider-side (English) team name → (localized display name, flag).

    Display language comes from config.lang (the single i18n point: the writer
    localizes, readers only render the strings they are given).
    Prefers the followed-teams config, falls back to the static table, then to
    the raw API name.
    """
    lang = cfgmod.resolve_lang(cfg)
    key = "name_zh" if lang == "zh" else "name_en"
    for t in cfg.get("followed_teams", []):
        if t.get("name_en", "").lower() == api_name.lower():
            return t.get(key) or api_name, t.get("flag", "")
    hit = teams.match_api_name(api_name)
    if hit:
        return hit[key], hit["flag"]
    return api_name, ""


def build_state(ge: GoalEvent, cfg: dict) -> dict:
    """Assemble the state.json content for a detected event (no disk I/O)."""
    m = ge.match
    followed_name = m.home_name if ge.followed_side == "home" else m.away_name
    opponent_name = m.away_name if ge.followed_side == "home" else m.home_name
    f_score = m.home_score if ge.followed_side == "home" else m.away_score
    o_score = m.away_score if ge.followed_side == "home" else m.home_score

    if ge.type == "goal":
        team_zh, flag = _team_display(followed_name, cfg)
        opp_zh, _ = _team_display(opponent_name, cfg)
    else:
        # opponent_goal / var_cancel: event.team is the notice subject
        # (the opponent, or our own team — see the schema)
        team_zh, flag = _team_display(opponent_name, cfg) if ge.type == "opponent_goal" \
            else _team_display(followed_name, cfg)
        opp_zh, _ = _team_display(followed_name if ge.type == "opponent_goal" else opponent_name, cfg)

    hold_sec = float(cfg.get("scoreboard_hold_min", 10)) * 60.0
    if ge.type == "goal":
        overlay_end = RUN_DUR + (OVERLAY_DUR if cfg.get("overlay_enabled", True) else 0.0)
        timeline = {
            "statusline_run": [0.0, RUN_DUR],
            "handoff": RUN_DUR,
            "overlay_play": [RUN_DUR, overlay_end],
            "scoreboard_hold": [overlay_end, overlay_end + hold_sec],
        }
    else:
        timeline = {
            "statusline_run": [0.0, 0.0],
            "handoff": 0.0,
            "overlay_play": [0.0, 0.0],
            "scoreboard_hold": [0.0, NOTICE_HOLD],
        }

    event = {
        "id": ge.event_id,
        "type": ge.type,
        "team": team_zh,
        "team_flag": flag,
        "opponent": opp_zh,
        "score": f"{f_score}-{o_score}",
        "scorer": m.scorer,
        "minute": m.minute,
        "ts": ge.ts,
    }
    # Dress the runner in the scoring team's home kit (optional field;
    # readers fall back to the default palette when absent)
    if ge.type == "goal":
        kit = teams.kit_for(teams.match_api_name(followed_name))
        if kit:
            event["kit"] = kit

    return {
        "schema_version": 1,
        "event": event,
        "timeline": timeline,
        "muted_until": float(cfg.get("muted_until", 0)),
    }


def dispatch(ge: GoalEvent, cfg: dict, now: float | None = None) -> bool:
    """Fully dispatch one event. Returns False (and writes nothing) while muted."""
    now = time.time() if now is None else now
    if now < float(cfg.get("muted_until", 0)):
        _log({"action": "suppressed_muted", "event_id": ge.event_id, "ts": now})
        return False

    state = build_state(ge, cfg)
    atomic_write_json(state_path(), state)

    overlay_called = False
    if ge.type == "goal" and cfg.get("overlay_enabled", True):
        overlay_called = _trigger_overlay()

    _log({"action": "dispatched", "event_id": ge.event_id, "type": ge.type,
          "score": state["event"]["score"], "team": state["event"]["team"],
          "overlay": overlay_called, "ts": now})
    return True


def _trigger_overlay() -> bool:
    """Invoke the Spoon via the hs CLI; a missing/failing hs is non-fatal
    (the statusline animation still plays)."""
    try:
        subprocess.run(["hs", "-c", "spoon.GoalKick:play()"],
                       capture_output=True, timeout=10, check=True)
        return True
    except (FileNotFoundError, subprocess.SubprocessError):
        return False


def _log(record: dict) -> None:
    try:
        log_path().parent.mkdir(parents=True, exist_ok=True)
        with log_path().open("a", encoding="utf-8") as f:
            f.write(json.dumps(record, ensure_ascii=False) + "\n")
    except OSError:
        pass
