"""Data-source adapter layer: to add a fallback source (e.g. API-Football),
implement this interface and register it in providers/__init__.py."""
from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass, field


@dataclass
class Team:
    id: int
    name: str               # provider-side English name
    tla: str = ""           # three-letter code (when the provider supplies one)


@dataclass
class Match:
    id: int
    status: str             # normalized: SCHEDULED / IN_PLAY / PAUSED / FINISHED / passthrough
    home_id: int
    home_name: str
    away_id: int
    away_name: str
    home_score: int
    away_score: int
    minute: int = 0         # match minute, 0 when the provider has none
    utc_ts: float = 0.0     # kickoff epoch seconds (drives smart sleep for SCHEDULED)
    scorer: str = ""        # latest goalscorer name, empty when unavailable

    @property
    def total_goals(self) -> int:
        return self.home_score + self.away_score

    @property
    def in_play(self) -> bool:
        return self.status in ("IN_PLAY", "PAUSED")


class Provider(ABC):
    """Minimal interface (spec §5.1). Implementations must honor the proxy
    setting and use a 10s timeout."""

    name: str = "base"

    @abstractmethod
    def list_teams(self, competition: str) -> list[Team]:
        """All teams of a competition (used to resolve provider_team_id)."""

    @abstractmethod
    def live_matches(self, team_ids: list[int]) -> list[Match]:
        """Matches involving the given teams within the near-term window
        (includes SCHEDULED/IN_PLAY/FINISHED; callers filter as needed)."""

    def last_goal(self, match_id: int) -> GoalDetail | None:
        """Look up details of a match's most recent goal (scorer etc.).

        Optional capability: list endpoints rarely include scorers, so this is
        called after a goal is detected to enrich the event. Returning None
        (unimplemented or failed) is fine — dispatch proceeds without a name.
        """
        return None


@dataclass
class GoalDetail:
    """Details of a single goal (scorer/minute/scoring team),
    backfilled from a match-detail endpoint."""
    scorer: str
    minute: int
    team_id: int


@dataclass
class ProbeResult:
    """Findings of the probe subcommand."""
    ok: bool
    detail: str
    competition: str = ""
    matches_sampled: int = 0
    rate_limit_remaining: str = ""
    extra: dict = field(default_factory=dict)
