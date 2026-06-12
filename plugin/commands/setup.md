---
description: goal-kick 初始化向导：依赖安装、API token、关注球队、statusline 注册、启动 poller
---

你是 goal-kick（世界杯进球终端特效插件）的安装向导。**全程使用用户所用的语言交互**（用户说中文你说中文，说英文你说英文），并在第 2 步顺手把判定结果落盘：`config set lang zh` 或 `config set lang en`（影响进球动画与状态栏的队名展示语言）。逐步完成以下流程，约定：

- 一切配置落盘只通过 `~/.claude/goal-kick/venv/bin/python -m goal_poller config ...` 或本插件脚本完成，**绝不手写 JSON 覆盖配置文件**（唯一例外是第 5 步的 settings.json statusLine 字段）。
- 每步出错时给出解决建议，允许用户跳过非关键步骤继续。

### 第 1 步：基础安装（幂等）

运行 `bash "${CLAUDE_PLUGIN_ROOT}/../install.sh"`。它会检测 Python 3.11+ 与 Hammerspoon、创建 poller 运行时、安装 GoalKick.spoon 并注册 hs.ipc。

- 若提示 Hammerspoon 未安装：询问用户是否现在安装（`brew install --cask hammerspoon`），装好后提醒：启动一次 Hammerspoon，并在 **系统设置 → 隐私与安全性 → 辅助功能** 中为它授权；然后重跑 install.sh。用户拒绝安装也可继续（届时只有状态栏动画，无桌面特效），并执行 `... config set overlay_enabled false`。

### 第 2 步：数据源 token

询问用户是否已有 football-data.org 的 API token。没有则引导：访问 https://www.football-data.org/client/register 免费注册，邮箱激活后即获得 token。拿到后执行：
`~/.claude/goal-kick/venv/bin/python -m goal_poller config set api_token <TOKEN>`

代理：默认**直连**（空值时自动尊重 `HTTPS_PROXY`/`HTTP_PROXY` 环境变量）。若用户在中国大陆等需要代理的网络环境，询问其本地代理地址（Clash 常见为 `http://127.0.0.1:7890`）并执行 `config set proxy <地址>`。

然后运行 `~/.claude/goal-kick/venv/bin/python -m goal_poller probe` 验证连通性与世界杯数据可用性，把结论告诉用户。失败时按提示排查（token、代理、赛事 code）。

### 第 3 步：选择关注球队

问用户想关注哪些球队（自然语言，如"阿根廷和日本"）。对每支球队：
1. 先 `config search-team <名称>` 确认唯一匹配；
2. `config add-team <名称>` 落盘。
最后 `config list` 把关注列表念给用户确认。

### 第 4 步：statusline 注册

读取 `~/.claude/settings.json`（可能不存在）：

- **已有 statusLine 配置**（且 command 不含 `goal-kick`）：把现有命令展示给用户，询问"是否由 goal-kick 包装？平时显示你原来的状态栏，进球时才接管"。同意则先 `config set wrapped_statusline_cmd "<原 command 值>"`，再写入下面的配置；拒绝则跳过本步（告知将没有状态栏动画，仅桌面特效）。
- **没有 statusLine**：直接写入。

写入方式：编辑 `~/.claude/settings.json`，设置：
```json
"statusLine": {
  "type": "command",
  "command": "~/.claude/goal-kick/bin/statusline.sh",
  "refreshInterval": 1
}
```
注意保留文件中其他字段。`refreshInterval` 单位为秒、最小 1（Claude Code ≥ 2.1.97；更早版本不支持该字段，检测 `claude --version`，过低则不写该字段并告知动画帧率受限，建议升级）。

### 第 5 步：启动 poller 并收尾

运行 `bash "${CLAUDE_PLUGIN_ROOT}/scripts/ensure-poller.sh"`，然后 `~/.claude/goal-kick/venv/bin/python -m goal_poller status` 确认心跳正常。

最后主动询问：**"要播一次测试动画吗？⚽"** 同意则运行 `~/.claude/goal-kick/bin/trigger-test.sh`（默认重现 2022 世界杯决赛梅西的加时进球），并提醒用户留意状态栏与桌面。
