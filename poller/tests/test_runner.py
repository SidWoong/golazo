"""mock provider 驱动 run_loop：完整链路（轮询→检测→分发→state.json 落盘）。"""
import json

from goal_poller import config as cfgmod
from goal_poller import runner
from goal_poller.paths import state_path, status_path
from goal_poller.providers.base import Match, Provider, Team


class MockProvider(Provider):
    """按预设脚本逐轮返回比分序列。"""
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
    cfgmod.add_team(cfg, name_zh="阿根廷", name_en="Argentina", flag="🇦🇷",
                    provider_team_id=762)
    cfgmod.save(cfg)


def test_full_chain_goal_to_state(monkeypatch):
    setup_cfg()
    mock = MockProvider([(0, 0), (1, 0), (1, 0)])
    monkeypatch.setattr(runner, "make_provider", lambda cfg: mock)
    monkeypatch.setattr("goal_poller.dispatcher._trigger_overlay", lambda: True)

    runner.run_loop(once=True)                 # 第一轮：建立 0-0 基线
    assert not state_path().exists()

    runner.run_loop(once=True)                 # 第二轮：1-0 → 进球
    st = json.loads(state_path().read_text())
    assert st["event"]["type"] == "goal" and st["event"]["team"] == "阿根廷"
    assert st["event"]["score"] == "1-0"
    first_id = st["event"]["id"]

    runner.run_loop(once=True)                 # 第三轮：重复推送 → 不覆盖新事件
    assert json.loads(state_path().read_text())["event"]["id"] == first_id

    hb = json.loads(status_path().read_text())
    assert hb["state"] == "live_polling" and hb["matches_in_window"] == 1


def test_backoff_on_provider_error(monkeypatch):
    setup_cfg()

    class Boom(MockProvider):
        def live_matches(self, team_ids):
            raise ConnectionError("network down")

    monkeypatch.setattr(runner, "make_provider", lambda cfg: Boom([]))
    runner.run_loop(once=True)
    hb = json.loads(status_path().read_text())
    assert hb["state"] == "backoff" and "ConnectionError" in hb["error"]
