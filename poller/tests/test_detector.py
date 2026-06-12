"""The §5.2 goal-judgement matrix: dedup / VAR rollback safety / no replay after gaps / both-sides scoring."""
from golazo.detector import GoalDetector, MISSED_WINDOW_SEC
from golazo.providers.base import Match

ARG, FRA = 762, 773          # following Argentina; France is the opponent
FOLLOWED = {ARG}


def mk(home=0, away=0, status="IN_PLAY", mid=100, minute=30):
    return Match(id=mid, status=status, home_id=ARG, home_name="Argentina",
                 away_id=FRA, away_name="France", home_score=home,
                 away_score=away, minute=minute)


def test_goal_detected_once_and_deduped():
    d = GoalDetector("fd")
    t = 1000.0
    assert d.process([mk(0, 0)], FOLLOWED, now=t) == []
    # goal: 1-0
    evs = d.process([mk(1, 0)], FOLLOWED, now=t + 20)
    assert len(evs) == 1 and evs[0].type == "goal" and evs[0].event_id == "fd-100-goal-1"
    # the same score pushed again → no re-trigger
    assert d.process([mk(1, 0)], FOLLOWED, now=t + 40) == []
    assert d.process([mk(1, 0)], FOLLOWED, now=t + 60) == []


def test_dedupe_survives_restart():
    t = 1000.0
    d1 = GoalDetector("fd")
    d1.process([mk(0, 0)], FOLLOWED, now=t)
    assert len(d1.process([mk(1, 0)], FOLLOWED, now=t + 20)) == 1
    # simulate a poller restart: a new instance reads the same cache, old scores never replay
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
    # VAR disallows: 1-0 → 0-0 yields var_cancel, never a goal
    evs = d.process([mk(0, 0)], FOLLOWED, now=1040)
    assert [e.type for e in evs] == ["var_cancel"]
    # A real goal afterwards (back to 1-0): goal-1's id is already registered → no replay
    # (conservative against false alarms), but the cache was reset to 0-0, so 2-0 fires goal-2 normally
    assert d.process([mk(1, 0)], FOLLOWED, now=1060) == []
    evs = d.process([mk(2, 0)], FOLLOWED, now=1080)
    assert len(evs) == 1 and evs[0].event_id == "fd-100-goal-2"


def test_multi_goal_jump_emits_only_latest():
    d = GoalDetector("fd")
    d.process([mk(0, 0)], FOLLOWED, now=1000)
    # one polling round jumps 0-0 → 2-1 (both sides scored)
    evs = d.process([mk(2, 1)], FOLLOWED, now=1020)
    assert len(evs) == 1
    assert evs[0].event_id == "fd-100-goal-3"
    assert evs[0].type == "goal"            # the larger delta belongs to home (the followed team)
    # intermediate goal-1 / goal-2 are registered; no later false alarms
    assert d.process([mk(2, 1)], FOLLOWED, now=1040) == []


def test_missed_window_no_replay():
    d = GoalDetector("fd")
    d.process([mk(0, 0)], FOLLOWED, now=1000)
    # recovery after >3 min offline: goals in the gap only update the cache
    evs = d.process([mk(1, 0)], FOLLOWED, now=1000 + MISSED_WINDOW_SEC + 60)
    assert evs == []
    # new goals after polling resumes fire normally
    evs = d.process([mk(2, 0)], FOLLOWED, now=1000 + MISSED_WINDOW_SEC + 80)
    assert len(evs) == 1 and evs[0].event_id == "fd-100-goal-2"


def test_cold_start_existing_score_not_celebrated():
    # cold start with a match already at 2-0 in the window (e.g. the finished opener) → baseline only, no celebration
    d = GoalDetector("fd")
    assert d.process([mk(2, 0, status="FINISHED")], FOLLOWED, now=1000) == []
    # real new goals after the baseline fire normally
    evs = d.process([mk(3, 0)], FOLLOWED, now=1020)
    assert len(evs) == 1 and evs[0].event_id == "fd-100-goal-3"


def test_unrelated_match_ignored():
    d = GoalDetector("fd")
    other = Match(id=200, status="IN_PLAY", home_id=1, home_name="A",
                  away_id=2, away_name="B", home_score=0, away_score=0)
    d.process([other], FOLLOWED, now=1000)
    other.home_score = 3
    assert d.process([other], FOLLOWED, now=1020) == []
