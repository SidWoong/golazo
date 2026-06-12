"""CLI 入口：python -m goal_poller <子命令>

斜杠命令（plugin/commands/*.md）只通过这里的子命令读写配置，禁止手写 JSON。
输出为英文行文本（开源惯例；中文用户经 Claude 中转交互）。
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import re
import sys
import time

from . import config as cfgmod
from . import teams
from .paths import base_dir, status_path
from .providers import make_provider


# ── config 子命令 ──────────────────────────────────────────────────────────

def cmd_config(args: argparse.Namespace) -> int:
    cfg = cfgmod.load()
    action = args.config_action

    if action == "list":
        if not cfg["followed_teams"]:
            print("No teams followed yet.")
        for t in cfg["followed_teams"]:
            rid = t.get("provider_team_id") or "unresolved"
            print(f"{t.get('flag','')} {t['name_zh']} / {t.get('name_en','')} (id={rid})")
        return 0

    if action == "search-team":
        hits = teams.search(args.keyword)
        if not hits:
            print(f"No 2026 World Cup team matches '{args.keyword}'.")
            return 1
        for t in hits:
            print(f"{t['flag']} {t['name_zh']} / {t['name_en']} ({t['tla']})")
        return 0

    if action == "add-team":
        hits = teams.search(args.keyword)
        if not hits:
            print(f"No team matches '{args.keyword}'; try search-team first.")
            return 1
        if len(hits) > 1:
            print(f"'{args.keyword}' matches multiple teams; be more specific:")
            for t in hits:
                print(f"  {t['flag']} {t['name_zh']} / {t['name_en']}")
            return 2
        t = hits[0]
        added = cfgmod.add_team(cfg, name_zh=t["name_zh"], name_en=t["name_en"],
                                flag=t["flag"])
        # 有 token 时顺手在线解析 provider_team_id（失败不阻塞，poller 会重试）
        if cfg["api_token"]:
            try:
                for at in make_provider(cfg).list_teams(""):
                    entry = teams.match_api_name(at.name, at.tla)
                    if entry and entry["name_en"] == t["name_en"]:
                        cfgmod.add_team(cfg, name_zh=t["name_zh"], name_en=t["name_en"],
                                        flag=t["flag"], provider_team_id=at.id)
                        break
            except Exception:
                pass
        cfgmod.save(cfg)
        print(f"{'Following' if added else 'Already following (refreshed)'}: {t['flag']} {t['name_zh']} / {t['name_en']}")
        return 0

    if action == "remove-team":
        removed = cfgmod.remove_team(cfg, args.keyword)
        cfgmod.save(cfg)
        if removed:
            print("Unfollowed: " + ", ".join(removed))
            return 0
        print(f"No followed team matches '{args.keyword}'.")
        return 1

    if action == "get":
        if args.key:
            print(json.dumps(cfg.get(args.key), ensure_ascii=False))
        else:
            print(json.dumps(cfg, ensure_ascii=False, indent=2))
        return 0

    if action == "set":
        if args.key not in cfgmod.DEFAULTS:
            print(f"Unknown config key: {args.key} (valid: {', '.join(cfgmod.DEFAULTS)})")
            return 1
        default = cfgmod.DEFAULTS[args.key]
        raw = args.value
        # 按默认值类型转换
        value: object = raw
        if isinstance(default, bool):
            value = raw.lower() in ("1", "true", "yes", "on", "开")
        elif isinstance(default, int):
            value = int(raw)
        elif isinstance(default, float):
            value = float(raw)
        elif isinstance(default, list):
            print("Use add-team / remove-team to manage list values.")
            return 1
        cfg[args.key] = value
        cfgmod.save(cfg)
        print(f"Set {args.key} = {json.dumps(value, ensure_ascii=False)}")
        return 0

    print(f"Unknown config action: {action}")
    return 2


# ── mute ───────────────────────────────────────────────────────────────────

def parse_mute_expr(expr: str, now: float | None = None) -> float:
    """'2h' / '30m' / '90s' / '今天' / 'off' → muted_until epoch 秒（0 表示取消静音）。"""
    now = time.time() if now is None else now
    e = expr.strip().lower()
    if e in ("off", "0", "取消", "解除"):
        return 0.0
    if e in ("今天", "今日", "today"):
        midnight = dt.datetime.combine(dt.date.today() + dt.timedelta(days=1),
                                       dt.time.min)
        return midnight.timestamp()
    m = re.fullmatch(r"(\d+(?:\.\d+)?)\s*(h|m|s|小时|时|分钟|分|秒)", e)
    if not m:
        raise ValueError(f"Cannot parse mute duration: {expr} (try 2h / 30m / 90s / today / off)")
    n = float(m.group(1))
    unit = {"h": 3600, "小时": 3600, "时": 3600,
            "m": 60, "分钟": 60, "分": 60, "s": 1, "秒": 1}[m.group(2)]
    return now + n * unit


def cmd_mute(args: argparse.Namespace) -> int:
    cfg = cfgmod.load()
    try:
        until = parse_mute_expr(args.duration)
    except ValueError as e:
        print(str(e))
        return 1
    cfg["muted_until"] = until
    cfgmod.save(cfg)
    if until == 0:
        print("Mute lifted.")
    else:
        print("Muted until " + dt.datetime.fromtimestamp(until).strftime("%m-%d %H:%M"))
    return 0


# ── probe / status / run ───────────────────────────────────────────────────

def cmd_probe(_: argparse.Namespace) -> int:
    cfg = cfgmod.load()
    provider = make_provider(cfg)
    if not hasattr(provider, "probe"):
        print(f"provider {cfg['provider']} does not implement probe.")
        return 2
    r = provider.probe()
    print(("✅ " if r.ok else "❌ ") + r.detail)
    if r.rate_limit_remaining:
        print(f"Requests remaining this minute: {r.rate_limit_remaining}")
    return 0 if r.ok else 1


def cmd_status(_: argparse.Namespace) -> int:
    cfg = cfgmod.load()
    print(f"Data dir: {base_dir()}")
    print("Followed: " + (", ".join(f"{t['name_zh']}/{t['name_en']}" for t in cfg["followed_teams"]) or "(none)"))
    muted = float(cfg.get("muted_until", 0))
    if muted > time.time():
        print("Muted until " + dt.datetime.fromtimestamp(muted).strftime("%m-%d %H:%M"))
    try:
        hb = json.loads(status_path().read_text(encoding="utf-8"))
        age = time.time() - hb.get("last_poll_ts", 0)
        print(f"poller: pid={hb.get('pid')}, state={hb.get('state')}, "
              f"last poll {int(age)}s ago, matches in window: {hb.get('matches_in_window', '?')}")
    except (FileNotFoundError, json.JSONDecodeError):
        print("poller: not running (no heartbeat file)")
    return 0


def cmd_run(args: argparse.Namespace) -> int:
    from .runner import run_loop
    run_loop(once=args.once)
    return 0


# ── 入口 ───────────────────────────────────────────────────────────────────

def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(prog="goal_poller", description="goal-kick goal-watch daemon")
    sub = p.add_subparsers(dest="command", required=True)

    run_p = sub.add_parser("run", help="run the polling daemon loop")
    run_p.add_argument("--once", action="store_true", help="run a single iteration (debug)")
    run_p.set_defaults(fn=cmd_run)

    sub.add_parser("probe", help="verify provider connectivity and World Cup coverage").set_defaults(fn=cmd_probe)
    sub.add_parser("status", help="show followed teams and poller heartbeat").set_defaults(fn=cmd_status)

    mute_p = sub.add_parser("mute", help="mute effects (2h / 30m / today / off)")
    mute_p.add_argument("duration")
    mute_p.set_defaults(fn=cmd_mute)

    cfg_p = sub.add_parser("config", help="read/write config (the only sanctioned channel)")
    cfg_sub = cfg_p.add_subparsers(dest="config_action", required=True)
    cfg_sub.add_parser("list")
    for name in ("search-team", "add-team", "remove-team"):
        sp = cfg_sub.add_parser(name)
        sp.add_argument("keyword")
    gp = cfg_sub.add_parser("get")
    gp.add_argument("key", nargs="?")
    sp = cfg_sub.add_parser("set")
    sp.add_argument("key")
    sp.add_argument("value")
    cfg_p.set_defaults(fn=cmd_config)

    args = p.parse_args(argv)
    return args.fn(args)


if __name__ == "__main__":
    sys.exit(main())
