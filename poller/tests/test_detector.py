"""§5.2 进球判定矩阵：去重 / 防回滚 / 断网不补播 / 双方进球区分。"""
from goal_poller.detector import GoalDetector, MISSED_WINDOW_SEC
from goal_poller.providers.base import Match

ARG, FRA = 762, 773          # 关注阿根廷；法国为对手
FOLLOWED = {ARG}


def mk(home=0, away=0, status="IN_PLAY", mid=100, minute=30):
    return Match(id=mid, status=status, home_id=ARG, home_name="Argentina",
                 away_id=FRA, away_name="France", home_score=home,
                 away_score=away, minute=minute)


def test_goal_detected_once_and_deduped():
    d = GoalDetector("fd")
    t = 1000.0
    assert d.process([mk(0, 0)], FOLLOWED, now=t) == []
    # 进球 1-0
    evs = d.process([mk(1, 0)], FOLLOWED, now=t + 20)
    assert len(evs) == 1 and evs[0].type == "goal" and evs[0].event_id == "fd-100-goal-1"
    # 同一比分重复推送 → 不再触发
    assert d.process([mk(1, 0)], FOLLOWED, now=t + 40) == []
    assert d.process([mk(1, 0)], FOLLOWED, now=t + 60) == []


def test_dedupe_survives_restart():
    t = 1000.0
    d1 = GoalDetector("fd")
    d1.process([mk(0, 0)], FOLLOWED, now=t)
    assert len(d1.process([mk(1, 0)], FOLLOWED, now=t + 20)) == 1
    # 模拟 poller 重启：新实例读同一缓存，旧比分不重播
    d2 = GoalDetector("fd")
    assert d2.process([mk(1, 0)], FOLLOWED, now=t + 40) == []


def test_opponent_goal_type():
    d = GoalDetector("fd")
    d.process([mk(0, 0)], FOLLOWED, now=1000)
    evs = d.process([mk(0, 1)], FOLLOWED, now=1020)
    assert len(evs) == 1 and evs[0].type == "opponent_goal"
    assert evs[0].scoring_side == "away" and evs[0].followed_side == "home"


def test_var_rollback_no_celebration():
    d = GoalDetector("fd")
    d.process([mk(0, 0)], FOLLOWED, now=1000)
    d.process([mk(1, 0)], FOLLOWED, now=1020)
    # VAR 取消：1-0 → 0-0，产出 var_cancel，绝不产出 goal
    evs = d.process([mk(0, 0)], FOLLOWED, now=1040)
    assert [e.type for e in evs] == ["var_cancel"]
    # 随后真进球（再到 1-0）：goal-1 的 id 已登记过 → 不重播（保守防误报），
    # 但缓存已重置为 0-0，比分到 2-0 时正常触发 goal-2
    assert d.process([mk(1, 0)], FOLLOWED, now=1060) == []
    evs = d.process([mk(2, 0)], FOLLOWED, now=1080)
    assert len(evs) == 1 and evs[0].event_id == "fd-100-goal-2"


def test_multi_goal_jump_emits_only_latest():
    d = GoalDetector("fd")
    d.process([mk(0, 0)], FOLLOWED, now=1000)
    # 一次轮询比分从 0-0 跳到 2-1（双方都进球）
    evs = d.process([mk(2, 1)], FOLLOWED, now=1020)
    assert len(evs) == 1
    assert evs[0].event_id == "fd-100-goal-3"
    assert evs[0].type == "goal"            # 净增大的一侧是主队（关注队）
    # 中间的 goal-1 / goal-2 已登记，后续不会误报
    assert d.process([mk(2, 1)], FOLLOWED, now=1040) == []


def test_missed_window_no_replay():
    d = GoalDetector("fd")
    d.process([mk(0, 0)], FOLLOWED, now=1000)
    # 断网超过 3 分钟后恢复，期间进球只记缓存不播
    evs = d.process([mk(1, 0)], FOLLOWED, now=1000 + MISSED_WINDOW_SEC + 60)
    assert evs == []
    # 恢复正常轮询后的新进球照常触发
    evs = d.process([mk(2, 0)], FOLLOWED, now=1000 + MISSED_WINDOW_SEC + 80)
    assert len(evs) == 1 and evs[0].event_id == "fd-100-goal-2"


def test_unrelated_match_ignored():
    d = GoalDetector("fd")
    other = Match(id=200, status="IN_PLAY", home_id=1, home_name="A",
                  away_id=2, away_name="B", home_score=0, away_score=0)
    d.process([other], FOLLOWED, now=1000)
    other.home_score = 3
    assert d.process([other], FOLLOWED, now=1020) == []
