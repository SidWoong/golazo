"""run_loop driven by a mock provider: the full chain (poll → detect → dispatch → state.json)."""
import json

from golazo import config as cfgmod
from golazo import runner
from golazo.paths import state_path, status_path
from golazo.providers.base import Match, Provider, Team


class MockProvider(Provider):
    """Returns a scripted score sequence, one entry per polling round."""
    name = "fd"

    def __init__(self, script):
        self.script = list(script)
        self.calls = 0

    def list_teams(self, competition=""):
        return [Team(id=762, name="Argentina", tla="ARG")]

    def live_matches(self, team_ids):
        idx = min(self.calls, len(self.script) - 1)
        self.calls += 1
        home, away = self.script[idx]
        return [Match(id=100, status="IN_PLAY", home_id=762, home_name="Argentina",
                      away_id=773, away_name="France",
                      home_score=home, away_score=away, minute=50)]


def setup_cfg():
    cfg = cfgmod.load()
    cfg["api_token"] = "dummy"
    cfg["lang"] = "zh"          # assertions expect Chinese display names; decouple from the host locale
    cfgmod.add_team(cfg, name_zh="阿根廷", name_en="Argentina", flag="🇦🇷",
                    provider_team_id=762)
    cfgmod.save(cfg)


def test_full_chain_goal_to_state(monkeypatch):
    setup_cfg()
    mock = MockProvider([(0, 0), (1, 0), (1, 0)])
    monkeypatch.setattr(runner, "make_provider", lambda cfg: mock)
    monkeypatch.setattr("golazo.dispatcher._trigger_overlay", lambda: True)

    runner.run_loop(once=True)                 # round 1: establish the 0-0 baseline
    assert not state_path().exists()

    runner.run_loop(once=True)                 # round 2: 1-0 → goal
    st = json.loads(state_path().read_text())
    assert st["event"]["type"] == "goal" and st["event"]["team"] == "阿根廷"
    assert st["event"]["score"] == "1-0"
    first_id = st["event"]["id"]

    runner.run_loop(once=True)                 # round 3: duplicate push → state not overwritten
    assert json.loads(state_path().read_text())["event"]["id"] == first_id

    hb = json.loads(status_path().read_text())
    assert hb["state"] == "live_polling" and hb["matches_in_window"] == 1


def test_scorer_enriched_from_match_detail(monkeypatch):
    from golazo.providers.base import GoalDetail

    setup_cfg()

    class WithDetail(MockProvider):
        def last_goal(self, match_id):
            return GoalDetail(scorer="Lionel Messi", minute=78, team_id=762)

    mock = WithDetail([(0, 0), (1, 0)])
    monkeypatch.setattr(runner, "make_provider", lambda cfg: mock)
    monkeypatch.setattr("golazo.dispatcher._trigger_overlay", lambda: True)

    runner.run_loop(once=True)
    runner.run_loop(once=True)
    st = json.loads(state_path().read_text())
    assert st["event"]["scorer"] == "Lionel Messi" and st["event"]["minute"] == 78


def test_scorer_mismatched_team_not_applied(monkeypatch):
    from golazo.providers.base import GoalDetail

    setup_cfg()

    class WrongTeam(MockProvider):
        def last_goal(self, match_id):
            # the detail feed's latest goal belongs to the opponent (lagging data) → must not be misattributed
            return GoalDetail(scorer="Kylian Mbappé", minute=80, team_id=773)

    mock = WrongTeam([(0, 0), (1, 0)])
    monkeypatch.setattr(runner, "make_provider", lambda cfg: mock)
    monkeypatch.setattr("golazo.dispatcher._trigger_overlay", lambda: True)

    runner.run_loop(once=True)
    runner.run_loop(once=True)
    st = json.loads(state_path().read_text())
    assert st["event"]["scorer"] == ""


def test_backoff_on_provider_error(monkeypatch):
    setup_cfg()

    class Boom(MockProvider):
        def live_matches(self, team_ids):
            raise ConnectionError("network down")

    monkeypatch.setattr(runner, "make_provider", lambda cfg: Boom([]))
    runner.run_loop(once=True)
    hb = json.loads(status_path().read_text())
    assert hb["state"] == "backoff" and "ConnectionError" in hb["error"]
