"""CLI 入口：python -m goal_poller <子命令>

斜杠命令（plugin/commands/*.md）只通过这里的子命令读写配置，禁止手写 JSON。
输出为面向人/Claude 的简洁中文行文本。
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
            print("当前没有关注任何球队。")
        for t in cfg["followed_teams"]:
            rid = t.get("provider_team_id") or "未解析"
            print(f"{t.get('flag','')} {t['name_zh']}（{t.get('name_en','')}，id={rid}）")
        return 0

    if action == "search-team":
        hits = teams.search(args.keyword)
        if not hits:
            print(f"未找到匹配“{args.keyword}”的 2026 世界杯参赛队。")
            return 1
        for t in hits:
            print(f"{t['flag']} {t['name_zh']} / {t['name_en']} ({t['tla']})")
        return 0

    if action == "add-team":
        hits = teams.search(args.keyword)
        if not hits:
            print(f"未找到匹配“{args.keyword}”的参赛队，请用 search-team 先确认。")
            return 1
        if len(hits) > 1:
            print(f"“{args.keyword}”匹配到多支球队，请更精确：")
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
        print(f"{'已关注' if added else '已在关注列表（信息已刷新）'}：{t['flag']} {t['name_zh']}")
        return 0

    if action == "remove-team":
        removed = cfgmod.remove_team(cfg, args.keyword)
        cfgmod.save(cfg)
        if removed:
            print("已取消关注：" + "、".join(removed))
            return 0
        print(f"关注列表中没有匹配“{args.keyword}”的球队。")
        return 1

    if action == "get":
        if args.key:
            print(json.dumps(cfg.get(args.key), ensure_ascii=False))
        else:
            print(json.dumps(cfg, ensure_ascii=False, indent=2))
        return 0

    if action == "set":
        if args.key not in cfgmod.DEFAULTS:
            print(f"未知配置项：{args.key}（合法项：{', '.join(cfgmod.DEFAULTS)}）")
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
            print("列表项请用 add-team / remove-team 管理。")
            return 1
        cfg[args.key] = value
        cfgmod.save(cfg)
        print(f"已设置 {args.key} = {json.dumps(value, ensure_ascii=False)}")
        return 0

    print(f"未知 config 动作：{action}")
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
        raise ValueError(f"无法理解的静音时长：{expr}（支持 2h / 30m / 90s / 今天 / off）")
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
        print("已解除静音。")
    else:
        print("已静音至 " + dt.datetime.fromtimestamp(until).strftime("%m-%d %H:%M"))
    return 0


# ── probe / status / run ───────────────────────────────────────────────────

def cmd_probe(_: argparse.Namespace) -> int:
    cfg = cfgmod.load()
    provider = make_provider(cfg)
    if not hasattr(provider, "probe"):
        print(f"provider {cfg['provider']} 未实现 probe。")
        return 2
    r = provider.probe()
    print(("✅ " if r.ok else "❌ ") + r.detail)
    if r.rate_limit_remaining:
        print(f"本分钟剩余请求配额：{r.rate_limit_remaining}")
    return 0 if r.ok else 1


def cmd_status(_: argparse.Namespace) -> int:
    cfg = cfgmod.load()
    print(f"数据目录：{base_dir()}")
    print(f"关注球队：{'、'.join(t['name_zh'] for t in cfg['followed_teams']) or '（无）'}")
    muted = float(cfg.get("muted_until", 0))
    if muted > time.time():
        print("静音中，至 " + dt.datetime.fromtimestamp(muted).strftime("%m-%d %H:%M"))
    try:
        hb = json.loads(status_path().read_text(encoding="utf-8"))
        age = time.time() - hb.get("last_poll_ts", 0)
        print(f"poller：pid={hb.get('pid')}，状态={hb.get('state')}，"
              f"上次轮询 {int(age)} 秒前，窗口内比赛 {hb.get('matches_in_window', '?')} 场")
    except (FileNotFoundError, json.JSONDecodeError):
        print("poller：尚未运行（无心跳文件）")
    return 0


def cmd_run(args: argparse.Namespace) -> int:
    from .runner import run_loop
    run_loop(once=args.once)
    return 0


# ── 入口 ───────────────────────────────────────────────────────────────────

def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(prog="goal_poller", description="goal-kick 进球监控守护进程")
    sub = p.add_subparsers(dest="command", required=True)

    run_p = sub.add_parser("run", help="启动守护进程主循环")
    run_p.add_argument("--once", action="store_true", help="只执行一轮（调试用）")
    run_p.set_defaults(fn=cmd_run)

    sub.add_parser("probe", help="验证数据源连通性与世界杯数据可用性").set_defaults(fn=cmd_probe)
    sub.add_parser("status", help="展示关注列表与 poller 心跳").set_defaults(fn=cmd_status)

    mute_p = sub.add_parser("mute", help="静音（2h / 30m / 今天 / off）")
    mute_p.add_argument("duration")
    mute_p.set_defaults(fn=cmd_mute)

    cfg_p = sub.add_parser("config", help="配置读写（唯一合法的配置修改通道）")
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
