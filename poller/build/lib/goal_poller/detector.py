"""比分变化检测：进球判定、幂等去重、VAR 回滚、断网恢复不补播。

缓存持久化到 cache.json，poller 重启后不会把历史进球当新进球重播。
"""
from __future__ import annotations

import json
import time
from dataclasses import dataclass

from .config import atomic_write_json
from .paths import cache_path
from .providers.base import Match

# 断网/停轮询超过该秒数后恢复，期间的进球只记缓存不播动画（需求 §5.2）
MISSED_WINDOW_SEC = 180
# emitted 列表上限（防无限增长；一届世界杯总进球远小于此）
EMITTED_CAP = 500


@dataclass
class GoalEvent:
    """检测层产物：只含事实，中文展示字段由 dispatcher 负责。"""
    event_id: str
    type: str               # "goal" | "opponent_goal" | "var_cancel"
    match: Match
    scoring_side: str       # "home" | "away" | ""（var_cancel 时为空）
    followed_side: str      # "home" | "away"（双关注对阵时为进球方）
    ts: float


class GoalDetector:
    def __init__(self, provider_name: str):
        self._provider = provider_name
        self._cache = self._load()

    # ── 缓存持久化 ─────────────────────────────────────────────

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

    # ── 核心判定 ───────────────────────────────────────────────

    def process(self, matches: list[Match], followed_ids: set[int],
                now: float | None = None) -> list[GoalEvent]:
        """对一次轮询结果做进球判定。返回应当分发的事件（可能为空）。

        规则（需求 §5.2）：
        - 比分增加 → 进球；事件 id 确定性生成（{provider}-{match_id}-goal-{total}）幂等去重
        - 比分回退（VAR）→ 清缓存重置，产出 var_cancel（仅 statusline 短暂提示，不播动画）
        - 距上次成功轮询超过 MISSED_WINDOW_SEC → 本轮发现的进球只更新缓存不产出事件
        - 一次跳多球（如 1→3）只为最新一粒产出事件，其余 id 记为已发防止后续误报
        """
        now = time.time() if now is None else now
        last_ok = self._cache["last_ok_poll"]
        stale = last_ok > 0 and (now - last_ok) > MISSED_WINDOW_SEC
        events: list[GoalEvent] = []

        for m in matches:
            if m.home_id not in followed_ids and m.away_id not in followed_ids:
                continue
            key = str(m.id)
            prev = self._cache["matches"].get(key, {"home": 0, "away": 0})
            dh, da = m.home_score - prev["home"], m.away_score - prev["away"]
            total_delta = dh + da

            if total_delta < 0:
                # VAR 取消进球：重置缓存，不触发庆祝
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
                # 为每粒进球登记幂等 id；只为最新一粒产出事件
                new_ids = [f"{self._provider}-{m.id}-goal-{g}"
                           for g in range(prev["home"] + prev["away"] + 1, m.total_goals + 1)]
                latest_id = new_ids[-1]
                fresh = latest_id not in self._cache["emitted"]
                self._cache["emitted"].extend(
                    i for i in new_ids if i not in self._cache["emitted"])
                if fresh and not stale:
                    # 进球方：跳多球时以净增大的一侧为准，平增时取关注侧
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
