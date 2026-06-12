---
description: 注入一条伪造进球，播放完整特效链路（状态栏 + 桌面动画）
argument-hint: [可选：球队名]
---

运行测试动画。参数（可为空）：$ARGUMENTS

1. 若用户指定了球队，先用 `~/.claude/goal-kick/venv/bin/python -m goal_poller config search-team <名称>` 取得中文名与旗帜 emoji；再取该队球衣配色：
   `~/.claude/goal-kick/venv/bin/python -c "from goal_poller import teams; print(teams.kit_for(teams.search('<名称>')[0]))"`
   未指定球队则用默认（阿根廷 2-1 法国，梅西 78 分钟，蓝白球衣）。
2. 执行 `~/.claude/goal-kick/bin/trigger-test.sh`（指定球队时附加 `--team <中文名> --flag <emoji> --jersey <hex> --stripe <hex> --shorts <hex>`）。
3. 告诉用户接下来 10 秒会发生什么：状态栏小人助跑 3 秒 → 跳到桌面射门庆祝 7 秒 → 状态栏常驻比分 2 分钟。
4. 若脚本警告 hs CLI 不可用，解释桌面动画未播放的原因（Hammerspoon 未运行 / 未授权辅助功能 / hs.ipc 未启用），状态栏动画不受影响。
