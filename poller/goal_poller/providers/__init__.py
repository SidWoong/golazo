from .base import Match, Provider, Team
from .football_data import FootballDataProvider


def make_provider(cfg: dict) -> Provider:
    """按配置构造 provider；后续新增备用源时在此注册。"""
    name = cfg.get("provider", "football_data")
    if name == "football_data":
        return FootballDataProvider(token=cfg.get("api_token", ""),
                                    proxy=cfg.get("proxy", ""))
    raise ValueError(f"未知 provider: {name}")


__all__ = ["Provider", "Team", "Match", "FootballDataProvider", "make_provider"]
