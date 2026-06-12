---
description: 增加关注球队（支持一次多个、中文/英文/国家代码模糊匹配）
argument-hint: <球队名，可多个，如"阿根廷和日本">
---

用户想关注这些球队：$ARGUMENTS

从中解析出一个或多个球队名（支持顿号、逗号、"和"等分隔）。对每支球队执行：

1. `~/.claude/goal-kick/venv/bin/python -m goal_poller config search-team <名称>` 确认匹配；
   - 无匹配：告知用户该队不在 2026 世界杯 48 强，或换个说法再试；
   - 多个匹配：列出候选请用户选择。
2. 唯一匹配后 `config add-team <名称>` 落盘。

全部处理完后运行 `config list`，用用户所用的语言汇报最新关注列表。poller 每轮自动重读配置，无需重启。
