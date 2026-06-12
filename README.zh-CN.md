# golazo ⚽

> 世界杯期间写代码，不错过你的球队的每一个进球——而且是以"像素小人从 Claude Code 状态栏跑出来、跳上桌面射门庆祝"的方式得知。

[English](README.md) | **简体中文**

![演示](docs/demo.gif)

*↑ 录制 GIF 后替换 `docs/demo.gif`（可用 `/golazo:test` 触发完整动画录屏）*

## 它做了什么

关注的球队进球时：

1. Claude Code **状态栏**播放 ASCII 小人助跑动画（3 秒）
2. 小人**穿着进球队的主场球衣**沿终端窗口底边奔跑、从窗口边框**跃出**，落到桌面上助跑、射门、球入网、150 片彩带 + 金色 **GOOOAL!** 大字（8 秒，Hammerspoon 覆盖层，点击穿透不抢焦点）
3. 状态栏**常驻比分** 10 分钟：`⚽ GOOOAL! 🇦🇷 阿根廷 2-1 法国`

平时状态栏完全透传你原有的 statusline 配置，无感共存。

## 安装（3 行）

```
/plugin marketplace add SidWoong/golazo
/plugin install golazo@golazo
/golazo:setup
```

setup 是对话式向导：自动安装依赖（Hammerspoon、Python 运行时、Spoon）、引导注册
[football-data.org](https://www.football-data.org/client/register) 免费 token、用自然语言选择关注球队、处理 statusline 共存，最后播一次测试动画。

## 命令

| 命令                      | 作用 |
|-------------------------|---|
| `/golazo:setup`         | 完整初始化向导 |
| `/golazo:follow 阿根廷和法国` | 增加关注（中文/英文/别名模糊匹配） |
| `/golazo:unfollow 法国`   | 取消关注 |
| `/golazo:status`        | 关注列表、poller 心跳、近期比分 |
| `/golazo:mute 2h`       | 静音（`30m` / `今天` / `off` 均可） |
| `/golazo:test`          | 注入伪造进球，播完整动画 |

## 架构

三个进程通过 `~/.claude/golazo/state.json` 单向通信（契约见 [shared/state-schema.md](shared/state-schema.md)）：

```
poller(Python 守护进程) ──写──▶ state.json ◀──读── statusline.sh(Claude Code)
        │ hs -c 调起                  ▲
        └──────▶ Golazo.spoon ──读──┘ (Hammerspoon 桌面覆盖层)
```

- **poller**：football-data.org 轮询（比赛中 20s / 空闲休眠到开赛前 5 分钟），比分增量判定进球，确定性事件 id 幂等去重，VAR 回滚不误报，断网恢复不补播旧进球
- **statusline.sh**：单次 awk 渲染约 7ms，远低于 50ms 预算；无事件时透传原 statusline
- **overlay**：v0.1 用 Hammerspoon；动画数据与渲染分离，v1.0 可整体替换为 Tauri App

## FAQ

**语言怎么定？**
展示语言按系统 locale 自动判定（`lang: auto`），可手动覆盖：`~/.claude/golazo/venv/bin/python -m golazo config set lang zh`（或 `en`）。斜杠命令始终跟随你输入的语言。

**代理怎么配？**
默认直连，且自动尊重 `HTTPS_PROXY`/`HTTP_PROXY` 环境变量。需要固定代理时：`~/.claude/golazo/venv/bin/python -m golazo config set proxy http://127.0.0.1:7890`（Clash 常见端口）。

**桌面动画不出现？**
依次检查：① Hammerspoon 在运行且已授予「辅助功能」权限（系统设置 → 隐私与安全性）；② `hs -c "1+1"` 能输出 2（不能则 Hammerspoon 控制台跑一次 `hs.ipc.cliInstall()`）；③ `/golazo:test` 看脚本提示。状态栏动画与桌面动画相互独立，桌面侧失败不影响状态栏。

**我已有自己的 statusline 工具怎么办？**
setup 会检测并询问是否"包装"：你的命令原样保留在 `wrapped_statusline_cmd`，平时输出完全是它的结果，只有进球后的动画/比分窗口期才被接管。

**API 免费档够用吗？**
football-data.org 免费档约 10 请求/分钟。poller 每轮只发 1 个赛事级请求，比赛中 20 秒一轮（3 次/分钟），空闲时 5 分钟一轮，远低于限额。安装后运行 `python -m golazo probe` 实测覆盖与配额。

> **probe 实测结论（2026-06-12，世界杯开赛次日）**：免费档确认覆盖 2026 世界杯，
> 赛事 code 为 `WC`，全部 104 场比赛可见，比分实时更新（揭幕战比分已验证）；
> 限频实测 10 请求/分钟。**免费档不提供进球者/比赛分钟**（`goals: null`），
> 动画与状态栏会优雅省略人名行；付费档或备用数据源（provider 层可插拔）可点亮。

**如何卸载？**
仓库根目录运行 `bash uninstall.sh`：停 poller、还原你原有的 statusline 配置、移除 Spoon 与 init.lua 注册块、删除 `~/.claude/golazo`。最后 `/plugin uninstall golazo` 移除插件本体。

## 开发

```bash
# poller 测试
cd poller && python3 -m venv .venv && .venv/bin/pip install -e ".[dev]" && .venv/bin/pytest
# overlay 干跑（需 brew install lua）
lua overlay/tests/dryrun.lua
# 手动触发动画链路（默认重现 2022 决赛梅西 108 分钟进球）
plugin/scripts/trigger-test.sh
plugin/scripts/trigger-test.sh --team 日本 --flag 🇯🇵   # 或任意球队
```

里程碑与验收标准见 [golazo-开发需求.md](golazo-开发需求.md)。MIT License。
