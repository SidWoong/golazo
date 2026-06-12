"""Daemon main loop: adaptive polling intervals, exponential backoff,
heartbeat file, automatic exit once the World Cup is over."""
from __future__ import annotations

import datetime as dt
import os
import time

from . import config as cfgmod
from . import teams
from .config import atomic_write_json
from .detector import GoalDetector
from .dispatcher import dispatch
from .paths import pid_path, status_path
from .providers import make_provider

WORLD_CUP_END = dt.date(2026, 7, 19)   # final's date; exit automatically afterwards (spec §4.4)
BACKOFF_START = 20
BACKOFF_CAP = 300
PRE_MATCH_LEAD = 300                    # resume fast polling 5 min before kickoff


def _heartbeat(state: str, next_poll_in: float, extra: dict | None = None) -> None:
    rec = {"pid": os.getpid(), "state": state, "last_poll_ts": time.time(),
           "next_poll_in_sec": round(next_poll_in, 1)}
    if extra:
        rec.update(extra)
    try:
        atomic_write_json(status_path(), rec)
    except OSError:
        pass


def _resolve_team_ids(provider, cfg: dict) -> bool:
    """Resolve provider_team_id online for followed teams that lack one.
    Returns True when anything was updated."""
    pending = [t for t in cfg["followed_teams"] if not t.get("provider_team_id")]
    if not pending:
        return False
    try:
        api_teams = provider.list_teams("")
    except Exception:
        return False
    changed = False
    for t in pending:
        for at in api_teams:
            entry = teams.match_api_name(at.name, at.tla)
            if entry and entry["name_en"] == t.get("name_en"):
                t["provider_team_id"] = at.id
                changed = True
                break
    if changed:
        cfgmod.save(cfg)
    return changed


def _enrich_scorer(provider, ev) -> None:
    """Backfill the scorer for goal events (list endpoints carry no names).
    Failures are silent — a goal without a name still gets celebrated."""
    if ev.type not in ("goal", "opponent_goal"):
        return
    try:
        detail = provider.last_goal(ev.match.id)
    except Exception:
        return
    if not detail:
        return
    scoring_id = ev.match.home_id if ev.scoring_side == "home" else ev.match.away_id
    # Mismatch guard: the latest goal in the detail feed must belong to the
    # side we just detected scoring
    if detail.team_id and detail.team_id != scoring_id:
        return
    if detail.scorer:
        ev.match.scorer = detail.scorer
    if detail.minute:
        ev.match.minute = detail.minute


def run_loop(*, once: bool = False) -> None:
    """Main loop. once=True runs a single iteration (for tests)."""
    pid_path().parent.mkdir(parents=True, exist_ok=True)
    pid_path().write_text(str(os.getpid()), encoding="utf-8")

    provider = None
    provider_key = None
    detector = None
    backoff = BACKOFF_START

    while True:
        if dt.date.today() > WORLD_CUP_END:
            _heartbeat("finished", 0, {"reason": "world cup ended"})
            return

        cfg = cfgmod.load()
        key = (cfg["provider"], cfg["api_token"], cfg["proxy"])
        if key != provider_key:
            provider = make_provider(cfg)
            provider_key = key
            detector = GoalDetector(provider.name)

        if not cfg["api_token"] or not cfg["followed_teams"]:
            _heartbeat("waiting_setup", cfg["idle_interval_sec"])
            if once:
                return
            time.sleep(cfg["idle_interval_sec"])
            continue

        _resolve_team_ids(provider, cfg)
        ids = {t["provider_team_id"] for t in cfg["followed_teams"]
               if t.get("provider_team_id")}
        if not ids:
            _heartbeat("ids_unresolved", cfg["idle_interval_sec"])
            if once:
                return
            time.sleep(cfg["idle_interval_sec"])
            continue

        try:
            matches = provider.live_matches(sorted(ids))
            backoff = BACKOFF_START
        except Exception as e:
            _heartbeat("backoff", backoff, {"error": repr(e)})
            if once:
                return
            time.sleep(backoff)
            backoff = min(backoff * 2, BACKOFF_CAP)   # 20→40→…→300 exponential backoff
            continue

        for ev in detector.process(matches, ids):
            _enrich_scorer(provider, ev)
            dispatch(ev, cfg)

        # Adaptive interval: a live followed match → fast polling; otherwise
        # sleep until 5 min before the next kickoff (low-frequency checks meanwhile)
        now = time.time()
        if any(m.in_play for m in matches):
            sleep_sec = cfg["poll_interval_sec"]
            state = "live_polling"
        else:
            upcoming = [m.utc_ts for m in matches
                        if m.status == "SCHEDULED" and m.utc_ts > now]
            if upcoming:
                until_kickoff = min(upcoming) - PRE_MATCH_LEAD - now
                sleep_sec = max(cfg["poll_interval_sec"],
                                min(until_kickoff, cfg["idle_interval_sec"]))
            else:
                sleep_sec = cfg["idle_interval_sec"]
            state = "idle"

        _heartbeat(state, sleep_sec, {"matches_in_window": len(matches)})
        if once:
            return
        time.sleep(sleep_sec)
