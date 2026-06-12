---
description: 查看关注列表、poller 运行状态与近期赛程比分
---

执行以下命令并把结果整理成用户所用语言的简洁汇报：

1. `~/.claude/goal-kick/venv/bin/python -m goal_poller status` —— 关注列表、静音状态、poller 心跳（pid / 上次轮询时间 / 窗口内比赛数）。
2. 若 poller 心跳缺失或进程不在，提示可运行 `bash "${CLAUDE_PLUGIN_ROOT}/scripts/ensure-poller.sh"` 拉起。
3. 读取 `~/.claude/goal-kick/state.json`（若存在）：有未过期事件时把当前比分/事件告诉用户。
4. 若用户配置了 api_token，可再跑 `python -m goal_poller probe` 顺带确认数据源健康（注意免费档限频，不要反复调用）。

汇报格式建议：关注球队一行、poller 状态一行、今日相关比赛各一行（含比分与状态）。
