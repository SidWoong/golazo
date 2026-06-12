"""test-run subcommand: the mock-API simulation must exercise the real pipeline."""
import json

from golazo.__main__ import main
from golazo.paths import state_path


def test_testrun_default_argentina_final(monkeypatch, capsys):
    calls = []
    monkeypatch.setattr("golazo.dispatcher._trigger_overlay",
                        lambda: calls.append(1) or True)
    assert main(["test-run", "--delay", "0"]) == 0
    out = capsys.readouterr().out
    assert "baseline" in out and "GOAL" in out

    st = json.loads(state_path().read_text())
    ev = st["event"]
    assert ev["type"] == "goal" and ev["score"] == "3-2"
    assert ev["scorer"] == "Messi" and ev["minute"] == 108     # enriched via mock last_goal
    assert ev["kit"]["jersey"] == "#74acdf"                    # real dispatcher kit lookup
    assert st["timeline"]["overlay_play"] == [3.0, 11.2]       # production timeline
    assert calls == [1]                                        # overlay invoked once


def test_testrun_team_override_and_rerun_no_dedupe(monkeypatch):
    monkeypatch.setattr("golazo.dispatcher._trigger_overlay", lambda: True)
    assert main(["test-run", "--delay", "0", "--team", "日本"]) == 0
    first = json.loads(state_path().read_text())["event"]
    assert first["kit"]["jersey"] == "#1d2088"                 # Japan blue
    assert first["scorer"] == ""                               # mirrors free-tier reality

    # a second run must fire again (unique match id defeats idempotent dedup)
    monkeypatch.setattr("time.time", lambda: 9_999_999_999.0)  # force a different match id
    assert main(["test-run", "--delay", "0", "--team", "日本"]) == 0
    second = json.loads(state_path().read_text())["event"]
    assert second["id"] != first["id"]


def test_testrun_respects_mute(monkeypatch, capsys):
    from golazo import config as cfgmod
    cfg = cfgmod.load()
    cfg["muted_until"] = 9e9
    cfgmod.save(cfg)
    monkeypatch.setattr("golazo.dispatcher._trigger_overlay", lambda: True)
    assert main(["test-run", "--delay", "0"]) == 0
    assert "suppressed (muted)" in capsys.readouterr().out
    assert not state_path().exists()                           # muted → nothing written