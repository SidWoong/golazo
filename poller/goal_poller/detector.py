"""Score-change detection: goal judgement, idempotent dedup, VAR rollback safety,
and no replays after connectivity gaps.

The cache persists to cache.json so a restarted poller never replays old goals.
"""
from __future__ import annotations

import json
import time
from dataclasses import dataclass

from .config import atomic_write_json
from .paths import cache_path
from .providers.base import Match

# After being offline/not polling longer than this, recovered goals only update
# the cache and play no animation (spec §5.2)
MISSED_WINDOW_SEC = 180
# Cap for the emitted-ids list (a whole World Cup has far fewer goals)
EMITTED_CAP = 500


@dataclass
class GoalEvent:
    """Detector output: facts only; localized display fields are the dispatcher's job."""
    event_id: str
    type: str               # "goal" | "opponent_goal" | "var_cancel"
    match: Match
    scoring_side: str       # "home" | "away" | "" (empty for var_cancel)
    followed_side: str      # "home" | "away" (the scoring side when both teams are followed)
    ts: float


class GoalDetector:
    def __init__(self, provider_name: str):
        self._provider = provider_name
        self._cache = self._load()

    # ── cache persistence ──────────────────────────────────────

    @staticmethod
    def _load() -> dict:
        try:
            c = json.loads(cache_path().read_text(encoding="utf-8"))
            if isinstance(c, dict):
                c.setdefault("matches", {})
                c.setdefault("emitted", [])
                c.setdefault("last_ok_poll", 0.0)
                return c
        except (FileNotFoundError, json.JSONDecodeError):
            pass
        return {"matches": {}, "emitted": [], "last_ok_poll": 0.0}

    def _save(self) -> None:
        if len(self._cache["emitted"]) > EMITTED_CAP:
            self._cache["emitted"] = self._cache["emitted"][-EMITTED_CAP:]
        atomic_write_json(cache_path(), self._cache)

    # ── core judgement ─────────────────────────────────────────

    def process(self, matches: list[Match], followed_ids: set[int],
                now: float | None = None) -> list[GoalEvent]:
        """Judge one polling round. Returns the events to dispatch (possibly none).

        Rules (spec §5.2):
        - Score increased → goal; deterministic event ids
          ({provider}-{match_id}-goal-{total}) give idempotent dedup
        - Score decreased (VAR) → reset the cache, emit var_cancel
          (statusline notice only, never an animation)
        - More than MISSED_WINDOW_SEC since the last successful poll →
          goals found this round update the cache silently
        - A multi-goal jump (e.g. 1→3) emits only the latest goal; the
          intermediate ids are still registered to prevent later false alarms
        """
        now = time.time() if now is None else now
        last_ok = self._cache["last_ok_poll"]
        # The very first poll (no baseline yet) is treated like a recovery:
        # record scores without emitting, so a cold-started poller never
        # celebrates pre-existing goals of finished/in-play matches
        stale = last_ok == 0 or (now - last_ok) > MISSED_WINDOW_SEC
        events: list[GoalEvent] = []

        for m in matches:
            if m.home_id not in followed_ids and m.away_id not in followed_ids:
                continue
            key = str(m.id)
            prev = self._cache["matches"].get(key, {"home": 0, "away": 0})
            dh, da = m.home_score - prev["home"], m.away_score - prev["away"]
            total_delta = dh + da

            if total_delta < 0:
                # VAR disallowed a goal: reset the cache, never celebrate
                ev_id = f"{self._provider}-{m.id}-var-{int(now)}"
                if ev_id not in self._cache["emitted"]:
                    self._cache["emitted"].append(ev_id)
                    if not stale:
                        events.append(GoalEvent(
                            event_id=ev_id, type="var_cancel", match=m,
                            scoring_side="",
                            followed_side="home" if m.home_id in followed_ids else "away",
                            ts=now))
            elif total_delta > 0:
                # Register an idempotency id per goal; emit only the latest one
                new_ids = [f"{self._provider}-{m.id}-goal-{g}"
                           for g in range(prev["home"] + prev["away"] + 1, m.total_goals + 1)]
                latest_id = new_ids[-1]
                fresh = latest_id not in self._cache["emitted"]
                self._cache["emitted"].extend(
                    i for i in new_ids if i not in self._cache["emitted"])
                if fresh and not stale:
                    # Scoring side: on a multi-goal jump take the side with the
                    # larger delta; on a tie take the followed side
                    side = "home" if dh > da else ("away" if da > dh else
                           ("home" if m.home_id in followed_ids else "away"))
                    scoring_id = m.home_id if side == "home" else m.away_id
                    followed_side = side if scoring_id in followed_ids else \
                        ("home" if m.home_id in followed_ids else "away")
                    events.append(GoalEvent(
                        event_id=latest_id,
                        type="goal" if scoring_id in followed_ids else "opponent_goal",
                        match=m, scoring_side=side, followed_side=followed_side,
                        ts=now))

            self._cache["matches"][key] = {"home": m.home_score, "away": m.away_score}

        self._cache["last_ok_poll"] = now
        self._save()
        return events
