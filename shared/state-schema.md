# goal-kick 状态文件契约（三端共同遵守）

本文件是 poller（写入方）、statusline.sh（读取方）、GoalKick.spoon（读取方）之间的**唯一契约**。
任何一端的实现与本文件冲突时，以本文件为准；修改本文件必须同步检查三端。

## 文件位置

| 文件 | 路径 | 写入方 | 读取方 |
|---|---|---|---|
| 状态文件 | `~/.claude/goal-kick/state.json` | poller / trigger-test.sh | statusline.sh、GoalKick.spoon |
| 用户配置 | `~/.claude/goal-kick/config.json` | poller CLI（`config` 子命令） | poller、statusline.sh（只读 `wrapped_statusline_cmd`） |

所有路径根目录可用环境变量 `GOAL_KICK_DIR` 覆盖（默认 `~/.claude/goal-kick`），便于测试。

## 写入规则

- **原子写**：先写同目录临时文件，再 `rename()` 覆盖。读取方永远不会看到半个 JSON。
- **覆盖语义**：每个新事件整体覆盖 state.json，不追加。同一时刻只有一个"当前事件"。
- 编码 UTF-8，无 BOM。顶层键顺序不保证，读取方不得依赖键顺序。

## 读取规则

- 读取方根据 `now - event.ts`（下称 `elapsed`，单位秒）对照 `timeline` 决定当前渲染内容。
- `elapsed < 0`（时钟偏差）或超出所有区间 → 当作无事件处理。
- 文件不存在、解析失败 → 当作无事件处理，**不得报错刷屏**。

## state.json Schema（schema_version = 1）

```jsonc
{
  "schema_version": 1,                  // int，必填。读取方遇到不认识的版本应静默忽略整个文件
  "event": {
    "id": "fd-12345-goal-2",            // string，必填。全局唯一，幂等去重键。
                                        // 格式：{provider}-{match_id}-goal-{total_goals}
                                        // VAR 回滚事件：{provider}-{match_id}-var-{ts取整}
                                        // 测试事件：test-{ts取整}
    "type": "goal",                     // "goal" | "opponent_goal" | "var_cancel"，必填
    "team": "阿根廷",                    // string，必填。goal=进球的关注球队；opponent_goal=进球的对手队名
    "team_flag": "🇦🇷",                  // string，可为空串
    "opponent": "法国",                  // string，必填。team 的对阵方
    "score": "2-1",                     // string，必填。恒为「关注球队得分-对手得分」视角
    "scorer": "梅西",                    // string，可为空串（数据源未提供时）
    "minute": 78,                       // int，可为 0（未知）
    "ts": 1781234567.0,                 // float，必填。事件触发时刻 epoch 秒
    "kit": {                            // 可选。进球队主场球衣三色，overlay 给小人换装；
      "jersey": "#74acdf",              // 缺省或非法时读取方回退默认配色
      "stripe": "#ffffff",
      "shorts": "#1a1a2e"
    }
  },
  "timeline": {                         // 相对 event.ts 的秒数；由写入方按事件类型生成，读取方只管执行
    "statusline_run": [0.0, 3.0],       // [start, end)：状态栏小人助跑动画窗口
    "handoff": 3.0,                     // 交接瞬间：状态栏小人消失、覆盖层小人出现
    "overlay_play": [3.0, 11.2],        // [start, end)：桌面覆盖层动画窗口（8.2s，
                                        // 含沿窗口底边跑动 1.2s + 跃出/助跑/射门/GOOOAL/淡出）
    "scoreboard_hold": [11.2, 611.2]    // [start, end)：状态栏常驻比分窗口
  },
  "muted_until": 0                      // float epoch 秒。/goal-kick:mute 写入；poller 在此时间前不触发任何动画。
                                        // 读取方无需检查此字段（静音时 poller 根本不写事件）。
}
```

### 事件类型与默认时间轴

写入方按 `type` 生成不同 timeline，读取方**只按 timeline 渲染**，不自行判断类型该播什么：

| type | statusline_run | handoff | overlay_play | scoreboard_hold | 说明 |
|---|---|---|---|---|---|
| `goal` | `[0, 3]` | `3` | `[3, 11.2]` | `[11.2, 11.2 + hold_min*60]` | 完整庆祝链路 |
| `goal`（overlay_enabled=false） | `[0, 3]` | `3` | `[3, 3]`（零长） | `[3, 3 + hold_min*60]` | 跳过覆盖层 |
| `opponent_goal` | `[0, 0]`（零长） | `0` | `[0, 0]` | `[0, 90]` | 灰色一行，90 秒 |
| `var_cancel` | `[0, 0]` | `0` | `[0, 0]` | `[0, 90]` | `进球被 VAR 取消 😤` |

> 为什么 statusline_run 是 3 秒而不是需求示例的 1.5 秒：Claude Code 的
> `statusLine.refreshInterval` 最小粒度为 1 秒（官方文档），1.5 秒窗口只能刷出 1~2 帧。
> 3 秒窗口在 1s 刷新率下可见 3 帧助跑，体验完整。时间轴是数据不是代码，后续可调。

### 各读取方的渲染分支（规范性）

`elapsed = now - event.ts`：

- **statusline.sh**
  1. `statusline_run[0] <= elapsed < statusline_run[1]` 且区间非零长 → 助跑帧（帧号 = `floor(elapsed - start)`）
  2. `handoff <= elapsed < overlay_play[1]` 且 overlay 区间非零长 → `小人离开了终端，正在你的桌面上…`
  3. `scoreboard_hold[0] <= elapsed < scoreboard_hold[1]` → 按 type 渲染：
     - `goal`：`⚽ GOOOAL! {team_flag} {team} {score} {opponent} ({minute}' {scorer})` 金色
     - `opponent_goal`：`⚽ {team} 进球了… {score}` 灰色
     - `var_cancel`：`进球被 VAR 取消 😤` 灰色
  4. 其余 → 透传模式
- **GoalKick.spoon**：仅当被 `hs -c "spoon.GoalKick:play()"` 调起时读 state.json；
  若 `event.type != "goal"` 或 `elapsed` 已超过 `overlay_play[1]` → 直接返回不播放。
  动画内部时间轴以 `overlay_play[0]` 为零点，详见 `overlay/GoalKick.spoon/anim/`。

## config.json Schema（schema_version = 1）

```jsonc
{
  "schema_version": 1,
  "followed_teams": [
    {
      "provider_team_id": 762,          // int | null。null 表示尚未通过 API 解析到 provider id
      "name_zh": "阿根廷",
      "name_en": "Argentina",
      "flag": "🇦🇷"
    }
  ],
  "provider": "football_data",
  "api_token": "",
  "proxy": "http://127.0.0.1:7890",     // 空串 = 直连
  "poll_interval_sec": 20,
  "idle_interval_sec": 300,
  "overlay_enabled": true,
  "scoreboard_hold_min": 10,
  "wrapped_statusline_cmd": ""          // setup 时记录的用户原有 statusline 命令；空串 = 无
}
```

**写入约束**：除 statusline.sh 只读 `wrapped_statusline_cmd` 外，config.json 一律通过
`python -m goal_poller config <子命令>` 读写，禁止任何端手写 JSON 覆盖（防格式损坏）。
