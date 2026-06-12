import pytest


@pytest.fixture(autouse=True)
def gk_dir(tmp_path, monkeypatch):
    """A fresh data dir per test case so the real ~/.claude/goal-kick is never touched."""
    monkeypatch.setenv("GOAL_KICK_DIR", str(tmp_path))
    return tmp_path
