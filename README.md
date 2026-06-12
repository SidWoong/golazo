# goal-kick ⚽

> 世界杯期间写代码，不错过你的球队的每一个进球——而且是以"像素小人从 Claude Code 状态栏跑出来、跳上桌面射门庆祝"的方式得知。

![演示](docs/demo.gif)

*↑ 录制 GIF 后替换 `docs/demo.gif`（可用 `/goal-kick:test` 触发完整动画录屏）*

## 它做了什么

关注的球队进球时：

1. Claude Code **状态栏**播放 ASCII 小人助跑动画（3 秒）
2. 小人从终端窗口右缘**跳出**，落到桌面上助跑、射门、球入网、150 片彩带 + 金色 **GOOOAL!** 大字（7 秒，Hammerspoon 覆盖层，点击穿透不抢焦点）
3. 状态栏**常驻比分** 10 分钟：`⚽ GOOOAL! 🇦🇷 阿根廷 2-1 法国 (78′ 梅西)`

平时状态栏完全透传你原有的 statusline 配置，无感共存。

## 安装（3 行）

```
/plugin marketplace add soulland/goal-kick
/plugin install goal-kick@goal-kick
/goal-kick:setup
```

setup 是对话式向导：自动安装依赖（Hammerspoon、Python 运行时、Spoon）、引导注册
[football-data.org](https://www.football-data.org/client/register) 免费 token、用自然语言选择关注球队、处理 statusline 共存，最后播一次测试动画。

## 命令

| 命令 | 作用 |
|---|---|
| `/goal-kick:setup` | 完整初始化向导 |
| `/goal-kick:follow 阿根廷和日本` | 增加关注（中文/英文/别名模糊匹配） |
| `/goal-kick:unfollow 日本` | 取消关注 |
| `/goal-kick:status` | 关注列表、poller 心跳、近期比分 |
| `/goal-kick:mute 2h` | 静音（`30m` / `今天` / `off` 均可） |
| `/goal-kick:test` | 注入伪造进球，播完整动画 |

## 架构

三个进程通过 `~/.claude/goal-kick/state.json` 单向通信（契约见 [shared/state-schema.md](shared/state-schema.md)）：

```
poller(Python 守护进程) ──写──▶ state.json ◀──读── statusline.sh(Claude Code)
        │ hs -c 调起                  ▲
        └──────▶ GoalKick.spoon ──读──┘ (Hammerspoon 桌面覆盖层)
```

- **poller**：football-data.org 轮询（比赛中 20s / 空闲休眠到开赛前 5 分钟），比分增量判定进球，确定性事件 id 幂等去重，VAR 回滚不误报，断网恢复不补播旧进球
- **statusline.sh**：单次 awk 渲染约 7ms，远低于 50ms 预算；无事件时透传原 statusline
- **overlay**：v0.1 用 Hammerspoon；动画数据与渲染分离，v1.0 可整体替换为 Tauri App

## FAQ

**代理怎么配？**
国内网络默认走 `http://127.0.0.1:7890`（Clash）。改地址：`~/.claude/goal-kick/venv/bin/python -m goal_poller config set proxy http://127.0.0.1:端口`；直连：`config set proxy ""`。空配置时也尊重 `HTTPS_PROXY`/`HTTP_PROXY` 环境变量。

**桌面动画不出现？**
依次检查：① Hammerspoon 在运行且已授予「辅助功能」权限（系统设置 → 隐私与安全性）；② `hs -c "1+1"` 能输出 2（不能则 Hammerspoon 控制台跑一次 `hs.ipc.cliInstall()`）；③ `/goal-kick:test` 看脚本提示。状态栏动画与桌面动画相互独立，桌面侧失败不影响状态栏。

**我已有自己的 statusline 工具怎么办？**
setup 会检测并询问是否"包装"：你的命令原样保留在 `wrapped_statusline_cmd`，平时输出完全是它的结果，只有进球后的动画/比分窗口期才被接管。

**API 免费档够用吗？**
football-data.org 免费档约 10 请求/分钟。poller 每轮只发 1 个赛事级请求，比赛中 20 秒一轮（3 次/分钟），空闲时 5 分钟一轮，远低于限额。安装后运行 `python -m goal_poller probe` 实测覆盖与配额。

> **probe 实测结论（2026-06-12，世界杯开赛次日）**：免费档确认覆盖 2026 世界杯，
> 赛事 code 为 `WC`，全部 104 场比赛可见，比分实时更新（揭幕战比分已验证）；
> 进球者需经 `/v4/matches/{id}` 详情接口补查（poller 已实现）。限频实测 10 请求/分钟。

**如何卸载？**
仓库根目录运行 `bash uninstall.sh`：停 poller、还原你原有的 statusline 配置、移除 Spoon 与 init.lua 注册块、删除 `~/.claude/goal-kick`。最后 `/plugin uninstall goal-kick` 移除插件本体。

## 开发

```bash
# poller 测试
cd poller && python3 -m venv .venv && .venv/bin/pip install -e ".[dev]" && .venv/bin/pytest
# overlay 干跑（需 brew install lua）
lua overlay/tests/dryrun.lua
# 手动触发动画链路
plugin/scripts/trigger-test.sh
```

里程碑与验收标准见 [goal-kick-开发需求.md](goal-kick-开发需求.md)。MIT License。
