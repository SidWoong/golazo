"""config.json 读写与 CLI 子命令实现。

config.json 是机器管理文件：除 statusline.sh 只读 wrapped_statusline_cmd 外，
一切修改必须经由 `python -m goal_poller config <子命令>`（防手写 JSON 损坏格式）。
Schema 见 shared/state-schema.md。
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
    "lang": "auto",          # 展示语言：zh / en / auto（auto 按系统 locale 判定）
}


def resolve_lang(cfg: dict[str, Any]) -> str:
    """解析展示语言。auto 时读系统 locale（LC_ALL > LANG），中文环境 zh，其余 en。"""
    lang = str(cfg.get("lang", "auto")).lower()
    if lang in ("zh", "en"):
        return lang
    locale = os.environ.get("LC_ALL") or os.environ.get("LANG") or ""
    return "zh" if locale.lower().startswith("zh") else "en"


def atomic_write_json(path: Path, data: dict) -> None:
    """同目录临时文件 + rename 原子覆盖，读取方永远不见半个 JSON。"""
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
    """读取配置并补齐缺省键；文件不存在/损坏时返回纯默认值。"""
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
    """加入关注列表；已存在（按 name_en 判重）则更新字段。返回是否新增。"""
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
    """按关键词（中/英文名、子串）移除关注球队，返回被移除的中文名列表。"""
    kw = keyword.strip().lower()
    removed = [t for t in cfg["followed_teams"]
               if kw in t.get("name_zh", "").lower() or kw in t.get("name_en", "").lower()]
    cfg["followed_teams"] = [t for t in cfg["followed_teams"] if t not in removed]
    return [t["name_zh"] for t in removed]
