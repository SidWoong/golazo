"""config.json access and the CLI subcommand backend.

config.json is a machine-managed file: apart from statusline.sh reading
wrapped_statusline_cmd, every mutation must go through
`python -m golazo config <subcommand>` (hand-written JSON risks corruption).
Schema: shared/state-schema.md.
"""
from __future__ import annotations

import json
import os
import tempfile
from pathlib import Path
from typing import Any

from .paths import config_path

DEFAULTS: dict[str, Any] = {
    "schema_version": 1,
    "followed_teams": [],
    "provider": "football_data",
    "api_token": "",
    "proxy": "",
    "poll_interval_sec": 20,
    "idle_interval_sec": 300,
    "overlay_enabled": True,
    "scoreboard_hold_min": 10,
    "wrapped_statusline_cmd": "",
    "muted_until": 0,
    "lang": "auto",          # display language: zh / en / auto (auto = system locale)
}


def resolve_lang(cfg: dict[str, Any]) -> str:
    """Resolve the display language. For auto, read the system locale
    (LC_ALL > LANG): Chinese locales get zh, everything else en."""
    lang = str(cfg.get("lang", "auto")).lower()
    if lang in ("zh", "en"):
        return lang
    locale = os.environ.get("LC_ALL") or os.environ.get("LANG") or ""
    return "zh" if locale.lower().startswith("zh") else "en"


def atomic_write_json(path: Path, data: dict) -> None:
    """Write a temp file in the same dir, then rename — readers never see half a JSON."""
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
            f.write("\n")
        os.replace(tmp, path)
    except BaseException:
        os.unlink(tmp)
        raise


def load() -> dict[str, Any]:
    """Load config, filling in defaults; a missing/corrupt file yields pure defaults."""
    cfg = dict(DEFAULTS)
    try:
        on_disk = json.loads(config_path().read_text(encoding="utf-8"))
        if isinstance(on_disk, dict):
            cfg.update(on_disk)
    except (FileNotFoundError, json.JSONDecodeError):
        pass
    return cfg


def save(cfg: dict[str, Any]) -> None:
    atomic_write_json(config_path(), cfg)


def add_team(cfg: dict, *, name_zh: str, name_en: str, flag: str,
             provider_team_id: int | None = None) -> bool:
    """Add a team to the followed list; if already present (keyed by name_en),
    refresh its fields instead. Returns True when newly added."""
    for t in cfg["followed_teams"]:
        if t.get("name_en") == name_en:
            t.update(name_zh=name_zh, flag=flag)
            if provider_team_id is not None:
                t["provider_team_id"] = provider_team_id
            return False
    cfg["followed_teams"].append({
        "provider_team_id": provider_team_id,
        "name_zh": name_zh,
        "name_en": name_en,
        "flag": flag,
    })
    return True


def remove_team(cfg: dict, keyword: str) -> list[str]:
    """Remove followed teams matching the keyword (zh/en substring).
    Returns the Chinese names of the removed teams."""
    kw = keyword.strip().lower()
    removed = [t for t in cfg["followed_teams"]
               if kw in t.get("name_zh", "").lower() or kw in t.get("name_en", "").lower()]
    cfg["followed_teams"] = [t for t in cfg["followed_teams"] if t not in removed]
    return [t["name_zh"] for t in removed]
