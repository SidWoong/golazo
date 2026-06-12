# goal-kick — 世界杯进球终端特效插件 · 开发需求文档

> 一个 Claude Code 插件：用户关注世界杯球队，球队进球时，像素小人从 Claude Code 状态栏"跑出"，跳出终端窗口，在 macOS 桌面上踢出足球射门，爆出 GOOOAL 特效，随后回归状态栏显示比分。

---

## 0. 阅读说明（给实现者 Claude Code）

- 按里程碑 M1 → M4 顺序实现，每个里程碑有独立验收标准，完成一个再进入下一个。
- 所有代码命名用英文，注释用中文。
- Python 部分使用 Python 3.11+。Shell 脚本用 bash 并保证 macOS 自带 bash 3.2 兼容。
- 不要删除任何已有文件；需要重大变更先说明再执行。
- 网络环境：开发机在中国大陆，外部 API 请求必须支持通过 `HTTPS_PROXY` / `HTTP_PROXY` 环境变量走本地代理（Clash，默认 `http://127.0.0.1:7890`，需可配置）。

---

## 1. 项目概述

### 1.1 一句话描述
世界杯期间，开发者在写代码时不错过自己球队的每一个进球——而且是以"小人从终端里跳出来庆祝"的方式得知。

### 1.2 目标平台与形态
- **平台**：macOS（Apple Silicon 优先，Intel 兼容）
- **形态**：标准 Claude Code 插件（通过自建 marketplace 分发）+ 配套后台守护进程 + Hammerspoon 屏幕特效脚本
- **版本规划**：
  - v0.1（本文档范围）：Hammerspoon 实现屏幕覆盖层
  - v1.0（不在本文档范围，但架构需为其预留）：Tauri 独立 App 替换 Hammerspoon，`overlay/` 目录整体可替换

### 1.3 核心体验流程
1. 用户安装插件，运行 `/goal-kick:setup`，对话式选择关注球队
2. 之后每次启动 Claude Code，后台 poller 自动运行（用户无感）
3. 关注球队进球 → 状态栏播 ASCII 小人助跑动画 → 小人"跳出"终端窗口边缘 → 桌面覆盖层播放奔跑、射门、GOOOAL、彩带 → 覆盖层销毁 → 状态栏常驻显示比分若干分钟

---

## 2. 仓库结构

```
goal-kick/
├── .claude-plugin/
│   └── marketplace.json        # 自建插件市场清单（本仓库即市场）
├── plugin/                     # Claude Code 插件本体
│   ├── .claude-plugin/
│   │   └── plugin.json         # 插件清单
│   ├── commands/               # 斜杠命令（markdown 提示词文件）
│   │   ├── setup.md
│   │   ├── follow.md
│   │   ├── unfollow.md
│   │   ├── status.md
│   │   ├── mute.md
│   │   └── test.md
│   ├── hooks/
│   │   └── hooks.json          # SessionStart hook：确保 poller 存活
│   └── scripts/
│       ├── statusline.sh       # 状态栏渲染脚本（含包装用户原有 statusline 的逻辑）
│       ├── ensure-poller.sh    # 检查/拉起 poller 守护进程
│       └── trigger-test.sh     # 手动触发一次完整特效（供 /goal-kick:test）
├── poller/                     # 进球监控守护进程（Python）
│   ├── pyproject.toml
│   ├── goal_poller/
│   │   ├── __main__.py         # 入口：python -m goal_poller
│   │   ├── config.py           # 读写 ~/.claude/goal-kick/config.json
│   │   ├── providers/          # 数据源适配层（关键抽象，见 §5）
│   │   │   ├── base.py         # Provider 抽象基类
│   │   │   └── football_data.py# football-data.org 实现
│   │   ├── detector.py         # 比分变化检测（含去重、防回滚）
│   │   └── dispatcher.py       # 进球事件分发：写状态文件 + 调起 overlay
│   └── tests/
├── overlay/                    # 屏幕特效端（v0.1 = Hammerspoon）
│   ├── GoalKick.spoon/
│   │   ├── init.lua            # Spoon 入口：窗口定位 + 动画时间轴 + 渲染
│   │   └── anim/               # 动画帧定义（拆分文件便于 v1.0 移植）
│   └── README.md
├── shared/
│   └── state-schema.md         # 状态文件 JSON Schema 文档（三端契约）
├── install.sh                  # 一键安装脚本（setup 命令内部调用它）
├── README.md                   # 含 GIF 演示位（顶部）、安装、FAQ
└── LICENSE                     # MIT
```

---

## 3. 三端架构与通信契约

三个独立进程通过**状态文件**单向通信，互不感知对方实现：

```
┌─────────────┐  写入   ┌──────────────────────────┐  读取  ┌────────────────┐
│   poller    │ ──────▶ │ ~/.claude/goal-kick/      │ ◀───── │ statusline.sh  │
│ (守护进程)   │         │   state.json (事件+时间轴) │        │ (Claude Code内) │
└──────┬──────┘         └──────────────────────────┘        └────────────────┘
       │ hs -c 调起
       ▼
┌─────────────┐
│ Hammerspoon │  读取同一 state.json，按时间轴渲染桌面覆盖层
│ GoalKick    │
└─────────────┘
```

### 3.1 状态文件 `~/.claude/goal-kick/state.json`

```json
{
  "schema_version": 1,
  "event": {
    "id": "fd-12345-goal-2",          // 全局唯一，用于幂等去重
    "type": "goal",
    "team": "阿根廷",
    "team_flag": "🇦🇷",
    "opponent": "法国",
    "score": "2-1",
    "scorer": "梅西",
    "minute": 78,
    "ts": 1781234567.0                 // 事件触发时刻（epoch 秒）
  },
  "timeline": {                        // 三端共用同一时间轴（相对 ts 的秒数）
    "statusline_run": [0.0, 1.5],      // 状态栏小人助跑
    "handoff": 1.5,                    // 交接瞬间：状态栏小人消失、覆盖层小人出现
    "overlay_play": [1.5, 8.5],        // 桌面动画总时长
    "scoreboard_hold": [8.5, 600]      // 状态栏常驻比分（10 分钟）
  },
  "muted_until": 0                     // /goal-kick:mute 写入的静音截止时间
}
```

- poller 每次进球**覆盖写入**该文件（原子写：先写临时文件再 rename）。
- statusline.sh 和 Hammerspoon 各自根据 `now - event.ts` 计算当前应渲染的帧。
- 完整 Schema 写入 `shared/state-schema.md`，三端实现必须以它为准。

### 3.2 用户配置 `~/.claude/goal-kick/config.json`

```json
{
  "schema_version": 1,
  "followed_teams": [
    { "provider_team_id": 762, "name_zh": "阿根廷", "flag": "🇦🇷" }
  ],
  "provider": "football_data",
  "api_token": "",                     // setup 时引导用户填写（免费注册）
  "proxy": "http://127.0.0.1:7890",   // 空字符串表示直连
  "poll_interval_sec": 20,             // 比赛进行中轮询间隔
  "idle_interval_sec": 300,            // 无关注球队比赛时的间隔（省请求配额）
  "overlay_enabled": true,             // false 时只播 statusline 动画
  "scoreboard_hold_min": 10
}
```

---

## 4. Claude Code 插件部分（plugin/）

### 4.1 plugin.json 要点
- name: `goal-kick`，命令命名空间即 `/goal-kick:*`
- 声明 hooks 与 statusLine 默认配置（statusLine 仅在用户 setup 确认后写入全局 settings，不在安装时静默覆盖）

### 4.2 斜杠命令（commands/*.md 提示词设计要求）

每个命令文件是给 Claude 的提示词。共同要求：用中文与用户交互；所有落盘操作通过调用 `plugin/scripts/` 或 poller 的 CLI 子命令完成，**不要让 Claude 手写 JSON 直接覆盖配置文件**（避免格式损坏），poller 需提供 `python -m goal_poller config add-team/remove-team/list/...` 子命令供其调用。

| 命令 | 行为 |
|---|---|
| `/goal-kick:setup` | 完整初始化向导：① 检测 Hammerspoon（缺失则引导 `brew install --cask hammerspoon`，并提示授予辅助功能权限）② 检测 Python 3.11+ ③ 引导注册 football-data.org 拿免费 token 并写入配置 ④ 对话式选择关注球队（用户说自然语言如"阿根廷和日本"，Claude 调用 `config add-team` 落盘，球队名→ID 映射见 §5.3）⑤ 处理 statusline：检测用户全局 settings 中已有 statusLine 配置，若有则询问是否包装（见 §4.3），若无则直接写入 ⑥ 安装 Spoon 到 `~/.hammerspoon/Spoons/` 并在 init.lua 注册 ⑦ 启动 poller ⑧ 最后主动询问"要播一次测试动画吗？" |
| `/goal-kick:follow $ARGUMENTS` | 增加关注球队，支持一次多个、模糊中文名/英文名/国家代码 |
| `/goal-kick:unfollow $ARGUMENTS` | 取消关注 |
| `/goal-kick:status` | 展示：关注列表、poller 运行状态（pid/最近一次轮询时间）、今日相关赛程与比分 |
| `/goal-kick:mute $ARGUMENTS` | 静音，支持 `2h` / `30m` / `今天` 等自然表达，换算后写 `muted_until` |
| `/goal-kick:test` | 调用 `trigger-test.sh` 注入一条伪造进球事件到 state.json 并调起完整动画链路（statusline + overlay），用于安装后即时验证和录 GIF |

### 4.3 statusline.sh（状态栏渲染）

输入：Claude Code 通过 stdin 传入的 JSON（含 model、workspace 等字段）。
输出：单行文本（支持 ANSI 颜色）。

逻辑：
1. 读 state.json。若不存在或 `now - ts` 超出 `scoreboard_hold` 区间 → 进入**透传模式**
2. 透传模式：若安装时记录了用户原有 statusline 命令（保存在 config 的 `wrapped_statusline_cmd` 字段），把 stdin 原样转发给它并输出其结果；否则输出默认内容（模型名 · 当前目录）
3. 动画模式（`now - ts` 落在 `statusline_run` 区间）：按帧表输出小人助跑帧，例如：
   ```
   帧0:  ⚽ GOAL!  ᕕ( ᐛ )ᕗ
   帧1:  ⚽ GOAL!    ᕕ( ᐛ )ᕗ
   帧2:  ⚽ GOAL!       ᕕ( ᐛ )ᕗ ──▶
   ```
   小人字符与样式可自行设计得更好，要求：单行、宽度自适应（读 COLUMNS 环境变量）、配色用 ANSI 256 色
4. 交接后（`handoff` 之后、`overlay_play` 期间）：输出 `小人离开了终端，正在你的桌面上…`
5. 比分常驻期：输出 `⚽ GOOOAL! 阿根廷 2-1 法国 (78' 梅西)`，金色高亮
6. **性能硬要求**：脚本必须在 50ms 内完成（statusline 会被高频调用），禁止在脚本内发起网络请求
7. setup 时将 statusLine 的 `refreshInterval` 设为 300ms 左右以支持动画帧率（需检测 Claude Code 版本 ≥ 2.1.97 支持该字段，不支持则降级为静态文本提示 + 覆盖层动画）

### 4.4 hooks.json

- `SessionStart`：执行 `ensure-poller.sh` —— 检查 pid 文件对应进程是否存活，不存活则 `nohup python -m goal_poller &` 拉起，日志写 `~/.claude/goal-kick/poller.log`
- 不做 SessionEnd 杀进程（比赛期间需要跨会话常驻）；poller 自身在世界杯结束日期（2026-07-19）之后自动退出

---

## 5. poller（进球监控守护进程）

### 5.1 数据源策略（重要）

- 首选 provider：**football-data.org**（免费档约 10 请求/分钟，覆盖世界杯赛事，需注册 token）
- **实现时必须先实际验证**：免费档对 2026 世界杯（competition code 可能为 `WC`）的覆盖与限频，写一个 `python -m goal_poller probe` 子命令用于验证连通性和数据形态
- Provider 层为抽象基类 + 适配器模式，接口最小集：
  ```python
  class Provider(ABC):
      def list_teams(self, competition: str) -> list[Team]: ...
      def live_matches(self, team_ids: list[int]) -> list[Match]: ...
  ```
  便于后续增加备用源（如 API-Football）或切换。所有请求走 `httpx`，超时 10s，支持 proxy 配置。

### 5.2 轮询与进球判定

- 智能间隔：关注球队有比赛处于进行中 → `poll_interval_sec`（默认 20s）；否则按赛程表休眠到下一场开赛前 5 分钟，期间用 `idle_interval_sec` 低频校对赛程
- 进球判定：本地缓存每场比赛上次比分，比分增加即判定进球；为每个进球生成确定性 `event.id`（`{provider}-{match_id}-goal-{total_goals}`）做幂等，**防止重复触发**
- 防回滚：VAR 取消进球会导致比分回退，检测到回退时清掉对应缓存但不触发任何动画（可在 statusline 短暂显示一条 `进球被 VAR 取消 😤`）
- 网络容错：连续失败指数退避（20s → 40s → … 上限 5min），恢复后不补播错过窗口超过 3 分钟的进球（只更新比分缓存）
- 双方都可能进球：只为**关注球队**的进球播庆祝动画；对手进球可在 statusline 短暂显示灰色一行（不调 overlay）

### 5.3 球队名映射

内置一份 2026 世界杯 48 强的静态映射表（中文名、英文名、常见别名、国旗 emoji → provider team id），随仓库维护。setup/follow 命令的 Claude 通过 `config search-team <关键词>` 查询该表。

### 5.4 事件分发（dispatcher）

进球确认后依次执行：
1. 原子写 state.json
2. 若 `overlay_enabled` 且未静音：执行 `hs -c "spoon.GoalKick:play()"`（Hammerspoon CLI；需在 setup 时确认用户已启用 `hs.ipc`）
3. 写一行结构化日志

---

## 6. overlay（Hammerspoon Spoon）

### 6.1 窗口定位
- 用 `hs.window` 查找终端窗口：优先匹配当前焦点窗口属于 Terminal/iTerm2/Warp/Kitty/Alacritty/VS Code/PyCharm 等常见宿主；找不到合理窗口 → 降级为"屏幕中央直接开演"模式
- 终端处于全屏 Space：小人改为从屏幕底边钻出
- 多显示器：在终端窗口所在屏幕播放

### 6.2 动画时间轴（与 state.json 的 timeline 对齐）

| 阶段 | 相对时间 | 内容 |
|---|---|---|
| handoff | 1.5s | 在终端窗口右缘、状态栏对应高度处画出小人，带一圈金色涟漪标记交接点 |
| 跳出 | 1.5–2.3s | 抛物线跃出窗口边框，落地过程体型放大约 3 倍 |
| 助跑 | 2.3–3.3s | 沿"地面"（屏幕高度 80% 处）向右奔跑，足球出现在前方 |
| 射门 | 3.3–3.6s | 踢腿动作，球以抛物线 + 金色拖尾飞向屏幕右侧球门 |
| GOOOAL | 3.6–7.0s | 球入网、球门震动、150 片彩带粒子、"GOOOAL!" 大字 + 比分 + 进球者，弹性放大入场 |
| 收场 | 7.0–8.5s | 全部元素淡出，canvas 销毁，释放资源 |

### 6.3 技术要求
- 全程使用 `hs.canvas`，覆盖层窗口 level 置顶、忽略鼠标事件（点击穿透）、不抢焦点
- 帧驱动用 `hs.timer.doevery(1/30, ...)`，播放完毕必须停 timer 并删除 canvas（防内存泄漏）
- 动画帧参数（坐标关键帧、缓动函数、配色）集中放在 `anim/` 目录的数据文件中，渲染逻辑与数据分离——v1.0 移植 Tauri 时直接复用数据
- 配色基调：金色 #f7c948 主特效色、彩带六色（金/红/蓝/绿/粉/橙）

---

## 7. install.sh 与 README

- install.sh：幂等可重复执行；依次处理 brew 依赖检测、Python 环境（优先 `uv`，回退 venv）、Spoon 安装、目录初始化；所有步骤打印清晰中文进度
- README.md：顶部预留 GIF 演示位（`docs/demo.gif`）；安装三行命令；FAQ 至少覆盖：代理配置、Hammerspoon 辅助功能权限、statusline 与已有工具共存、如何卸载（提供 `uninstall.sh` 干净移除所有落盘内容并还原用户原 statusline 配置）

---

## 8. 里程碑与验收标准

### M1 — 链路骨架（最优先）
- [ ] state.json 契约文档完成；`trigger-test.sh` 能注入伪造进球
- [ ] statusline.sh 完成：透传模式 + 动画模式 + 比分常驻，50ms 内返回
- [ ] **验收**：手动执行 trigger-test.sh 后，Claude Code 状态栏完整播放助跑动画并显示比分

### M2 — 桌面覆盖层
- [ ] GoalKick.spoon 完成全部六阶段动画；窗口定位 + 三种降级策略生效
- [ ] **验收**：trigger-test.sh 触发后，小人从真实终端窗口边缘跳出，桌面动画完整播放并自动销毁；连播 5 次无内存增长、无残留窗口

### M3 — 真实数据
- [ ] poller 完成：provider 适配层、智能轮询、幂等去重、VAR 回滚处理、代理支持
- [ ] `probe` 子命令验证 football-data.org 世界杯数据可用性并在 README 记录结论
- [ ] **验收**：mock provider 注入比分序列（含重复推送、回滚场景），动画触发行为全部符合 §5.2；真实 API 跑通一场正在进行的比赛

### M4 — 插件化与分发
- [ ] 全部斜杠命令提示词完成；setup 全流程在干净环境跑通
- [ ] marketplace.json 配置完成，从 GitHub 通过 `/plugin marketplace add` + `/plugin install` 安装成功
- [ ] uninstall.sh 干净卸载验证
- [ ] **验收**：一台未配置过的 Mac 上，从安装到看到测试动画 ≤ 5 分钟，全程只需复制粘贴命令和对话

---

## 9. 明确不做（v0.1 范围外）
- Windows / Linux 支持
- Tauri 独立 App（仅预留 overlay/ 可替换架构）
- 多赛事支持（只做 2026 世界杯，但 provider 层不写死赛事 ID）
- 声音效果（可留 TODO）
