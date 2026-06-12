---
description: 取消关注球队
argument-hint: <球队名，可多个>
---

用户想取消关注：$ARGUMENTS

解析出球队名，对每个执行：
`~/.claude/goal-kick/venv/bin/python -m goal_poller config remove-team <名称>`

命令会输出实际移除结果（按子串匹配中英文名）。完成后 `config list` 汇报剩余关注列表。若列表已空，提醒用户 poller 将进入待机、不再触发任何动画。
