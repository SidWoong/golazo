---
description: 静音进球特效（支持 2h / 30m / 今天 等自然表达）
argument-hint: <时长，如 2h、30分钟、今天；"取消"解除静音>
---

用户的静音请求：$ARGUMENTS

把自然语言换算为 CLI 接受的表达（`2h` / `30m` / `90s` / `今天` / `off`），例如"俩小时"→`2h`、"半小时"→`30m`、"今天别吵我"→`今天`、"取消静音/解除"→`off`。无法判断时向用户确认。

执行：`~/.claude/goal-kick/venv/bin/python -m goal_poller mute <表达>`

把命令输出的静音截止时间告诉用户。静音期间 poller 仍照常记录比分，只是不触发任何动画。
