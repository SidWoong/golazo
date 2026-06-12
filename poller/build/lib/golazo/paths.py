"""Filesystem locations: the single source of truth for everything we persist.
The GOLAZO_DIR env var redirects the whole tree (used by tests)."""
import os
from pathlib import Path


def base_dir() -> Path:
    d = os.environ.get("GOLAZO_DIR")
    return Path(d) if d else Path.home() / ".claude" / "golazo"


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
