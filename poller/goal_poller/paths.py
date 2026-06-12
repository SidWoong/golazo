"""目录与文件路径：所有落盘位置的唯一出处，GOAL_KICK_DIR 环境变量可整体重定向（测试用）。"""
import os
from pathlib import Path


def base_dir() -> Path:
    d = os.environ.get("GOAL_KICK_DIR")
    return Path(d) if d else Path.home() / ".claude" / "goal-kick"


def config_path() -> Path:
    return base_dir() / "config.json"


def state_path() -> Path:
    return base_dir() / "state.json"


def cache_path() -> Path:
    return base_dir() / "cache.json"


def status_path() -> Path:
    return base_dir() / "poller_status.json"


def log_path() -> Path:
    return base_dir() / "poller.log"


def pid_path() -> Path:
    return base_dir() / "poller.pid"
