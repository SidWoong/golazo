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


def test_testrun_custom_opponent_and_score(monkeypatch, capsys):
    from golazo import config as cfgmod
    cfg = cfgmod.load(); cfg["lang"] = "zh"; cfgmod.save(cfg)   # pin display language
    monkeypatch.setattr("golazo.dispatcher._trigger_overlay", lambda: True)
    assert main(["test-run", "--delay", "0", "--team", "美国",
                 "--opponent", "巴拉圭", "--score", "4-1"]) == 0
    st = json.loads(state_path().read_text())["event"]
    assert st["team"] == "美国" and st["opponent"] == "巴拉圭" and st["score"] == "4-1"
    out = capsys.readouterr().out
    assert "United States vs Paraguay" in out and "4-1 → GOAL" in out


def test_testrun_rejects_bad_inputs():
    assert main(["test-run", "--delay", "0", "--opponent", "火星"]) == 1   # not a WC team
    assert main(["test-run", "--delay", "0", "--score", "1-3"]) == 1       # followed team trails
    assert main(["test-run", "--delay", "0", "--score", "abc"]) == 1       # unparseable


def test_testrun_respects_mute(monkeypatch, capsys):
    from golazo import config as cfgmod
    cfg = cfgmod.load()
    cfg["muted_until"] = 9e9
    cfgmod.save(cfg)
    monkeypatch.setattr("golazo.dispatcher._trigger_overlay", lambda: True)
    assert main(["test-run", "--delay", "0"]) == 0
    assert "suppressed (muted)" in capsys.readouterr().out
    assert not state_path().exists()                           # muted → nothing written