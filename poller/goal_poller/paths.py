"""Filesystem locations: the single source of truth for everything we persist.
The GOAL_KICK_DIR env var redirects the whole tree (used by tests)."""
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
