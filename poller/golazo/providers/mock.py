"""Mock provider: replays a scripted score sequence through the real pipeline.

Backs `python -m golazo test-run` — everything downstream of live_matches()
(detector dedup, dispatcher assembly, atomic state.json write, overlay
invocation) runs exactly as in production; only the HTTP fetch is simulated.
"""
from __future__ import annotations

from .base import GoalDetail, Match, Provider, Team


class MockProvider(Provider):
    name = "mock"

    def __init__(self, fixture: dict, steps: list[tuple[int, int]],
                 scorer: str = "", minute: int = 0):
        """fixture: id/home_id/home_name/away_id/away_name of the simulated match.
        steps: score per polling round, e.g. [(0, 0), (1, 0)].
        scorer/minute: returned by the simulated match-detail endpoint
        (last_goal); both empty mirrors the free-tier reality."""
        self._fixture = fixture
        self._steps = list(steps)
        self._scorer = scorer
        self._minute = minute
        self.calls = 0

    def list_teams(self, competition: str = "") -> list[Team]:
        f = self._fixture
        return [Team(id=f["home_id"], name=f["home_name"])]

    def live_matches(self, team_ids: list[int]) -> list[Match]:
        i = min(self.calls, len(self._steps) - 1)
        self.calls += 1
        home, away = self._steps[i]
        f = self._fixture
        return [Match(id=f["id"], status="IN_PLAY",
                      home_id=f["home_id"], home_name=f["home_name"],
                      away_id=f["away_id"], away_name=f["away_name"],
                      home_score=home, away_score=away, minute=self._minute)]

    def last_goal(self, match_id: int) -> GoalDetail | None:
        if not self._scorer and not self._minute:
            return None
        return GoalDetail(scorer=self._scorer, minute=self._minute,
                          team_id=self._fixture["home_id"])
