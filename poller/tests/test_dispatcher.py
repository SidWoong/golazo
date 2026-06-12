"""分发层：state.json 组装与时间轴矩阵、静音抑制、overlay 调用条件。"""
import json

from goal_poller import dispatcher
from goal_poller.detector import GoalEvent
from goal_poller.paths import state_path
from goal_poller.providers.base import Match


def mk_event(etype="goal", scoring="home"):
    m = Match(id=100, status="IN_PLAY", home_id=762, home_name="Argentina",
              away_id=773, away_name="France", home_score=2, away_score=1,
              minute=78, scorer="梅西")
    return GoalEvent(event_id="fd-100-goal-3", type=etype, match=m,
                     scoring_side=scoring, followed_side="home", ts=5000.0)


def base_cfg(**over):
    cfg = {"followed_teams": [{"provider_team_id": 762, "name_zh": "阿根廷",
                               "name_en": "Argentina", "flag": "🇦🇷"}],
           "overlay_enabled": True, "scoreboard_hold_min": 10, "muted_until": 0}
    cfg.update(over)
    return cfg


def test_goal_state_and_timeline():
    st = dispatcher.build_state(mk_event(), base_cfg())
    ev, tl = st["event"], st["timeline"]
    assert ev["team"] == "阿根廷" and ev["team_flag"] == "🇦🇷"
    assert ev["opponent"] == "法国"          # 静态表解析非关注队中文名
    assert ev["score"] == "2-1" and ev["scorer"] == "梅西" and ev["minute"] == 78
    assert tl["statusline_run"] == [0.0, 3.0] and tl["handoff"] == 3.0
    assert tl["overlay_play"] == [3.0, 11.2]
    assert tl["scoreboard_hold"] == [11.2, 611.2]   # 10 分钟常驻


def test_goal_event_carries_team_kit():
    st = dispatcher.build_state(mk_event(), base_cfg())
    assert st["event"]["kit"] == {"jersey": "#74acdf", "stripe": "#ffffff",
                                  "shorts": "#1a1a2e"}   # 阿根廷主场


def test_opponent_goal_has_no_kit():
    st = dispatcher.build_state(mk_event("opponent_goal", "away"), base_cfg())
    assert "kit" not in st["event"]


def test_overlay_disabled_timeline_collapses():
    st = dispatcher.build_state(mk_event(), base_cfg(overlay_enabled=False))
    tl = st["timeline"]
    assert tl["overlay_play"] == [3.0, 3.0]          # 零长 → 读取方跳过覆盖层
    assert tl["scoreboard_hold"][0] == 3.0


def test_opponent_goal_short_notice():
    st = dispatcher.build_state(mk_event("opponent_goal", "away"), base_cfg())
    assert st["event"]["team"] == "法国"             # 提示主语为进球的对手
    assert st["timeline"]["statusline_run"] == [0.0, 0.0]
    assert st["timeline"]["scoreboard_hold"] == [0.0, 90.0]


def test_dispatch_writes_state_and_calls_overlay(monkeypatch):
    calls = []
    monkeypatch.setattr(dispatcher, "_trigger_overlay", lambda: calls.append(1) or True)
    assert dispatcher.dispatch(mk_event(), base_cfg(), now=5000.0)
    assert calls == [1]
    st = json.loads(state_path().read_text())
    assert st["schema_version"] == 1 and st["event"]["id"] == "fd-100-goal-3"


def test_dispatch_opponent_goal_never_calls_overlay(monkeypatch):
    calls = []
    monkeypatch.setattr(dispatcher, "_trigger_overlay", lambda: calls.append(1) or True)
    assert dispatcher.dispatch(mk_event("opponent_goal", "away"), base_cfg(), now=5000.0)
    assert calls == []


def test_dispatch_muted_suppresses_everything(monkeypatch):
    calls = []
    monkeypatch.setattr(dispatcher, "_trigger_overlay", lambda: calls.append(1) or True)
    assert not dispatcher.dispatch(mk_event(), base_cfg(muted_until=9999.0), now=5000.0)
    assert calls == [] and not state_path().exists()
