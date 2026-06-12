"""football-data.org v4 adapter.

Free tier allows roughly 10 requests/min; the World Cup competition code is
expected to be WC (verify with probe). All requests go through httpx with a
10s timeout; an empty proxy string means direct connection while still
honoring the HTTPS_PROXY/HTTP_PROXY env vars.
"""
from __future__ import annotations

import datetime as dt

import httpx

from .base import GoalDetail, Match, ProbeResult, Provider, Team

BASE_URL = "https://api.football-data.org/v4"
COMPETITION = "WC"

# football-data.org → normalized status
_STATUS_MAP = {
    "SCHEDULED": "SCHEDULED", "TIMED": "SCHEDULED",
    "IN_PLAY": "IN_PLAY", "PAUSED": "PAUSED",
    "FINISHED": "FINISHED", "SUSPENDED": "PAUSED", "POSTPONED": "POSTPONED",
    "CANCELLED": "CANCELLED", "AWARDED": "FINISHED",
}


class FootballDataProvider(Provider):
    name = "football_data"

    def __init__(self, token: str, proxy: str = "", competition: str = COMPETITION):
        self._token = token
        self._competition = competition
        # An explicit proxy wins; with an empty one httpx keeps trust_env=True
        # and picks up HTTPS_PROXY etc. automatically
        kwargs: dict = {"timeout": 10.0,
                        "headers": {"X-Auth-Token": token} if token else {}}
        if proxy:
            kwargs["proxy"] = proxy
        self._client = httpx.Client(base_url=BASE_URL, **kwargs)

    # ── Provider interface ─────────────────────────────────────────

    def list_teams(self, competition: str = "") -> list[Team]:
        comp = competition or self._competition
        data = self._get(f"/competitions/{comp}/teams")
        return [Team(id=t["id"], name=t.get("name", ""), tla=t.get("tla", ""))
                for t in data.get("teams", [])]

    def live_matches(self, team_ids: list[int]) -> list[Match]:
        """Matches involving the followed teams in the near-term window
        (yesterday to +7 days).

        One competition-level request fetches everything; we filter by
        team_ids locally to preserve the free-tier quota.
        """
        today = dt.date.today()
        params = {"dateFrom": (today - dt.timedelta(days=1)).isoformat(),
                  "dateTo": (today + dt.timedelta(days=7)).isoformat()}
        data = self._get(f"/competitions/{self._competition}/matches", params=params)
        wanted = set(team_ids)
        out = []
        for m in data.get("matches", []):
            home, away = m.get("homeTeam", {}), m.get("awayTeam", {})
            if wanted and home.get("id") not in wanted and away.get("id") not in wanted:
                continue
            out.append(self._to_match(m))
        return out

    def last_goal(self, match_id: int) -> GoalDetail | None:
        """Latest goal from the match-detail endpoint's goals[] (scorer's
        English name, minute, scoring team).

        Costs one extra request per goal — far within the free-tier limit.
        """
        try:
            data = self._get(f"/matches/{match_id}")
        except httpx.HTTPError:
            return None
        goals = data.get("goals") or []
        if not goals:
            return None
        g = goals[-1]
        minute = g.get("minute")
        return GoalDetail(
            scorer=(g.get("scorer") or {}).get("name", "") or "",
            minute=int(minute) if isinstance(minute, int) else 0,
            team_id=(g.get("team") or {}).get("id", 0),
        )

    # ── probe ──────────────────────────────────────────────────────

    def probe(self) -> ProbeResult:
        """Verify connectivity, the token, competition coverage and rate-limit
        headroom (backs `python -m golazo probe`)."""
        if not self._token:
            return ProbeResult(ok=False, detail="api_token not set (register free at football-data.org)")
        try:
            resp = self._client.get(f"/competitions/{self._competition}")
            remaining = resp.headers.get("X-Requests-Available-Minute", "?")
            if resp.status_code == 403:
                return ProbeResult(ok=False, detail="403: invalid token or competition not in free tier",
                                   rate_limit_remaining=remaining)
            if resp.status_code == 404:
                return ProbeResult(ok=False, detail=f"404: competition code '{self._competition}' not found; "
                                                    "check the /competitions endpoint",
                                   rate_limit_remaining=remaining)
            resp.raise_for_status()
            comp = resp.json()
            m = self._client.get(f"/competitions/{self._competition}/matches")
            m.raise_for_status()
            matches = m.json().get("matches", [])
            return ProbeResult(
                ok=True,
                detail=f"Competition OK: {comp.get('name')} ({comp.get('code')}), "
                       f"season from {comp.get('currentSeason', {}).get('startDate', '?')}, "
                       f"{len(matches)} matches returned",
                competition=comp.get("code", ""),
                matches_sampled=len(matches),
                rate_limit_remaining=m.headers.get("X-Requests-Available-Minute", "?"),
            )
        except httpx.HTTPError as e:
            return ProbeResult(ok=False, detail=f"Network error: {e!r} (check proxy settings)")

    # ── internals ──────────────────────────────────────────────────

    def _get(self, path: str, params: dict | None = None) -> dict:
        resp = self._client.get(path, params=params)
        resp.raise_for_status()
        return resp.json()

    @staticmethod
    def _to_match(m: dict) -> Match:
        score = m.get("score", {})
        full = score.get("fullTime", {}) or {}
        # fullTime can be null mid-match; fall back to zero defensively
        home_goals = full.get("home")
        away_goals = full.get("away")
        if home_goals is None or away_goals is None:
            # v4 also reports the running score in fullTime for live matches;
            # the zero fallback is belt-and-braces
            home_goals = home_goals or 0
            away_goals = away_goals or 0
        utc_ts = 0.0
        if m.get("utcDate"):
            try:
                utc_ts = dt.datetime.fromisoformat(
                    m["utcDate"].replace("Z", "+00:00")).timestamp()
            except ValueError:
                pass
        return Match(
            id=m["id"],
            status=_STATUS_MAP.get(m.get("status", ""), m.get("status", "")),
            home_id=m.get("homeTeam", {}).get("id", 0),
            home_name=m.get("homeTeam", {}).get("name", ""),
            away_id=m.get("awayTeam", {}).get("id", 0),
            away_name=m.get("awayTeam", {}).get("name", ""),
            home_score=int(home_goals),
            away_score=int(away_goals),
            minute=int(m.get("minute") or 0) if str(m.get("minute") or 0).isdigit() else 0,
            utc_ts=utc_ts,
        )
