import pytest


@pytest.fixture(autouse=True)
def gk_dir(tmp_path, monkeypatch):
    """A fresh data dir per test case so the real ~/.claude/golazo is never touched."""
    monkeypatch.setenv("GOLAZO_DIR", str(tmp_path))
    return tmp_path
