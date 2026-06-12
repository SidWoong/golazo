"""CLI subcommands: config add/remove/search, mute expression parsing, unknown-key guard."""
import json
import time

import pytest

from golazo.__main__ import main, parse_mute_expr
from golazo.paths import config_path


def test_add_search_remove_team(capsys):
    assert main(["config", "add-team", "阿根廷"]) == 0
    assert "Following" in capsys.readouterr().out
    cfg = json.loads(config_path().read_text())
    assert cfg["followed_teams"][0]["name_en"] == "Argentina"

    assert main(["config", "list"]) == 0
    assert "阿根廷" in capsys.readouterr().out

    # aliases and fuzzy matching
    assert main(["config", "search-team", "南韩"]) == 0
    assert "South Korea" in capsys.readouterr().out

    assert main(["config", "remove-team", "阿根廷"]) == 0
    capsys.readouterr()
    assert json.loads(config_path().read_text())["followed_teams"] == []


def test_add_team_ambiguous(capsys):
    # "刚果" hits several aliases of the same team (DR Congo) → still unambiguous, succeeds
    assert main(["config", "add-team", "刚果"]) == 0
    capsys.readouterr()


def test_config_set_rejects_unknown_key(capsys):
    assert main(["config", "set", "evil_key", "1"]) == 1


def test_config_set_type_coercion():
    assert main(["config", "set", "poll_interval_sec", "30"]) == 0
    assert main(["config", "set", "overlay_enabled", "false"]) == 0
    cfg = json.loads(config_path().read_text())
    assert cfg["poll_interval_sec"] == 30 and cfg["overlay_enabled"] is False


def test_mute_expressions():
    now = 1_000_000.0
    assert parse_mute_expr("2h", now) == now + 7200
    assert parse_mute_expr("30m", now) == now + 1800
    assert parse_mute_expr("90秒", now) == now + 90
    assert parse_mute_expr("1.5小时", now) == now + 5400
    assert parse_mute_expr("off", now) == 0.0
    assert parse_mute_expr("今天", now) > time.time()   # always in the future until tonight's midnight
    with pytest.raises(ValueError):
        parse_mute_expr("永远", now)


def test_mute_cli_roundtrip(capsys):
    assert main(["mute", "2h"]) == 0
    cfg = json.loads(config_path().read_text())
    assert cfg["muted_until"] > time.time() + 7000
    assert main(["mute", "off"]) == 0
    assert json.loads(config_path().read_text())["muted_until"] == 0
