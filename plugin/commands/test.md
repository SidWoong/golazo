---
description: 注入一条伪造进球，播放完整特效链路（状态栏 + 桌面动画）
argument-hint: <球队名 team name>
---

运行测试动画。参数（可为空）：$ARGUMENTS

**测试动画不预设球队，必须确定一支球队再触发**：

1. 确定球队：
   - 用户在参数里指定了 → 用它；
   - 未指定 → 先跑 `~/.claude/goal-kick/venv/bin/python -m goal_poller config list` 查看关注列表：恰好关注一支就用它（告知用户），多支则列出请用户选，一支都没有则直接问用户想看哪支球队的庆祝。
2. 解析球队信息：`config search-team <名称>` 取得队名（按用户语言选中文/英文名）与旗帜 emoji；再取球衣配色：
   `~/.claude/goal-kick/venv/bin/python -c "from goal_poller import teams; print(teams.kit_for(teams.search('<名称>')[0]))"`
3. 执行 `~/.claude/goal-kick/bin/trigger-test.sh --team <队名> --flag <emoji> --jersey <hex> --stripe <hex> --shorts <hex>`（可加 `--opponent/--score/--scorer/--minute` 丰富细节）。
4. 告诉用户接下来约 12 秒会发生什么：状态栏小人助跑 3 秒 → 沿终端窗口底边跑到边框跳出 → 桌面助跑射门 GOOOAL（约 8 秒）→ 状态栏常驻比分 2 分钟。
5. 若脚本警告 hs CLI 不可用，解释桌面动画未播放的原因（Hammerspoon 未运行 / 未授权辅助功能 / hs.ipc 未启用），状态栏动画不受影响。
