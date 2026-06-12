import pytest


@pytest.fixture(autouse=True)
def gk_dir(tmp_path, monkeypatch):
    """每个用例独立的数据目录，避免污染真实 ~/.claude/goal-kick。"""
    monkeypatch.setenv("GOAL_KICK_DIR", str(tmp_path))
    return tmp_path
