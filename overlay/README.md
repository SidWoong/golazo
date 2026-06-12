# overlay — 桌面特效端（v0.1 = Hammerspoon）

进球时在 macOS 桌面播放"小人跳出终端 → 助跑 → 射门 → GOOOAL"覆盖层动画。

## 结构

```
Golazo.spoon/
├── init.lua      # 渲染逻辑：窗口定位、三种降级、30fps 帧驱动、资源销毁
└── anim/         # 纯数据：时间轴/配色/像素帧 —— v1.0 Tauri 移植直接复用
    ├── timeline.lua
    ├── palette.lua
    └── sprites.lua
tests/dryrun.lua  # hs API 桩干跑测试：lua overlay/tests/dryrun.lua
```

## 安装（/golazo:setup 会自动完成）

1. `brew install --cask hammerspoon`，启动并授予「辅助功能」权限
2. 拷贝 `Golazo.spoon` 到 `~/.hammerspoon/Spoons/`
3. `~/.hammerspoon/init.lua` 中加入：
   ```lua
   hs.loadSpoon("Golazo")
   require("hs.ipc")          -- 启用 hs CLI，poller 靠它调起动画
   hs.ipc.cliInstall()
   ```
4. 重载 Hammerspoon 配置，验证：`hs -c "spoon.Golazo:play()"`（需 state.json 中有未过期 goal 事件，可先跑 `plugin/scripts/trigger-test.sh`）

## 行为契约

- 只响应 `event.type == "goal"` 且未超出 `timeline.overlay_play` 窗口的事件（见 `shared/state-schema.md`）
- 窗口定位降级链：焦点终端窗口右缘跳出 → 全屏 Space 从屏幕底边钻出 → 找不到终端窗口则屏幕中央开演
- 覆盖层置顶、点击穿透、不抢焦点；播放完毕停 timer、删 canvas，无残留

## v1.0 替换约定

`overlay/` 目录整体可替换为 Tauri App：实现方只需读取同一 state.json、消费 `anim/` 下的
数据文件（时间轴/配色/帧均与渲染逻辑分离），并提供等价的"被一条 CLI 命令调起"的入口。
