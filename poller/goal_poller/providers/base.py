"""数据源适配层抽象：新增备用源（如 API-Football）时实现本接口并在 __init__ 注册。"""
from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass, field


@dataclass
class Team:
    id: int
    name: str               # provider 侧英文名
    tla: str = ""           # 三字母代码（provider 提供时填写）


@dataclass
class Match:
    id: int
    status: str             # 标准化状态：SCHEDULED / IN_PLAY / PAUSED / FINISHED / 其他原样
    home_id: int
    home_name: str
    away_id: int
    away_name: str
    home_score: int
    away_score: int
    minute: int = 0         # 比赛进行分钟数，provider 不提供时为 0
    utc_ts: float = 0.0     # 开赛时间 epoch 秒（SCHEDULED 时用于智能休眠）
    scorer: str = ""        # 最近一粒进球的球员名，provider 不提供时为空

    @property
    def total_goals(self) -> int:
        return self.home_score + self.away_score

    @property
    def in_play(self) -> bool:
        return self.status in ("IN_PLAY", "PAUSED")


class Provider(ABC):
    """接口最小集（见需求 §5.1）。实现必须支持 proxy 配置、10s 超时。"""

    name: str = "base"

    @abstractmethod
    def list_teams(self, competition: str) -> list[Team]:
        """某赛事全部参赛队（用于解析 provider_team_id）。"""

    @abstractmethod
    def live_matches(self, team_ids: list[int]) -> list[Match]:
        """指定球队近期窗口内的比赛（含 SCHEDULED/IN_PLAY/FINISHED，调用方自行筛选）。"""

    def last_goal(self, match_id: int) -> GoalDetail | None:
        """补查某场比赛最近一粒进球的细节（进球者等）。

        可选能力：列表接口通常不含进球者，检测到进球后调用本方法富化事件；
        未实现或查询失败返回 None，调用方照常分发（只是没有人名）。
        """
        return None


@dataclass
class GoalDetail:
    """单粒进球的细节（进球者/分钟/进球方），由比赛详情接口补查。"""
    scorer: str
    minute: int
    team_id: int


@dataclass
class ProbeResult:
    """probe 子命令的探测结论。"""
    ok: bool
    detail: str
    competition: str = ""
    matches_sampled: int = 0
    rate_limit_remaining: str = ""
    extra: dict = field(default_factory=dict)
