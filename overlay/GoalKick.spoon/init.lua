--- === GoalKick ===
--- 世界杯进球桌面特效覆盖层（goal-kick v0.1）
--- 被 `hs -c "spoon.GoalKick:play()"` 调起后：读取 ~/.claude/goal-kick/state.json，
--- 在终端窗口边缘画出像素小人 → 跳出 → 助跑 → 射门 → GOOOAL 彩带 → 淡出销毁。
--- 渲染逻辑在本文件；全部动画参数（时间轴/配色/帧）在 anim/ 数据文件中，便于 v1.0 移植。

local obj = {}
obj.__index = obj

obj.name = "GoalKick"
obj.version = "0.1.0"
obj.author = "goal-kick"
obj.license = "MIT"
obj.homepage = "https://github.com/soulland/goal-kick"

-- 运行态（播放期间持有，结束必须清空防泄漏）
obj._canvas = nil
obj._timer = nil
obj._playing = false
obj._confetti = nil

local TL, PAL, SPR   -- anim/ 数据，init() 时加载

-- 可作为"终端宿主"的应用：优先按 bundle ID 匹配（不随系统语言本地化，
-- 如中文系统里 Terminal.app 显示名为「终端」），应用名仅作回退
local HOST_BUNDLES = {
  ["com.apple.Terminal"] = true, ["com.googlecode.iterm2"] = true,
  ["dev.warp.Warp-Stable"] = true, ["net.kovidgoyal.kitty"] = true,
  ["org.alacritty"] = true, ["io.alacritty"] = true,
  ["com.mitchellh.ghostty"] = true, ["com.github.wez.wezterm"] = true,
  ["co.zeit.hyper"] = true, ["com.microsoft.VSCode"] = true,
  ["com.jetbrains.pycharm"] = true, ["com.jetbrains.pycharm.ce"] = true,
  ["com.jetbrains.intellij"] = true, ["com.jetbrains.intellij.ce"] = true,
  ["com.jetbrains.WebStorm"] = true, ["com.jetbrains.goland"] = true,
}
local HOST_APPS = {
  ["Terminal"] = true, ["终端"] = true, ["iTerm2"] = true, ["Warp"] = true,
  ["kitty"] = true, ["Alacritty"] = true, ["Ghostty"] = true, ["WezTerm"] = true,
  ["Hyper"] = true, ["Code"] = true, ["Visual Studio Code"] = true,
  ["Cursor"] = true, ["PyCharm"] = true, ["IntelliJ IDEA"] = true,
  ["WebStorm"] = true, ["GoLand"] = true,
}

-- 窗口所属应用是否为终端宿主
local function isHostWindow(w)
  local app = w and w:application()
  if not app then return false end
  local bid = app:bundleID()
  if bid and HOST_BUNDLES[bid] then return true end
  return HOST_APPS[app:name()] or false
end

-- 缓动函数实现：anim/ 数据中以名字引用
local EASING = {
  linear       = function(t) return t end,
  easeInQuad   = function(t) return t * t end,
  easeOutQuad  = function(t) return 1 - (1 - t) * (1 - t) end,
  easeOutCubic = function(t) return 1 - (1 - t) ^ 3 end,
  easeOutBack  = function(t)
    local c1, c3 = 1.70158, 2.70158
    return 1 + c3 * (t - 1) ^ 3 + c1 * (t - 1) ^ 2
  end,
}

local function ease(name, t)
  if t < 0 then t = 0 elseif t > 1 then t = 1 end
  return (EASING[name] or EASING.linear)(t)
end

-- 阶段内归一化进度 [0,1]
local function phaseT(phase, t)
  if phase.to <= phase.from then return 1 end
  return (t - phase.from) / (phase.to - phase.from)
end

function obj:init()
  TL = dofile(hs.spoons.resourcePath("anim/timeline.lua"))
  PAL = dofile(hs.spoons.resourcePath("anim/palette.lua"))
  SPR = dofile(hs.spoons.resourcePath("anim/sprites.lua"))
  return self
end

-- ── 状态文件 ────────────────────────────────────────────────────────────────

local function stateDir()
  return (os.getenv("GOAL_KICK_DIR") or (os.getenv("HOME") .. "/.claude/goal-kick"))
end

local function readState()
  local st = hs.json.read(stateDir() .. "/state.json")
  if not st or st.schema_version ~= 1 or not st.event then return nil end
  return st
end

-- ── 窗口定位与降级策略 ──────────────────────────────────────────────────────
-- 返回 mode（"window" 从窗口右缘跳出 / "bottom" 从屏幕底边钻出 / "center" 屏幕中央开演）、
-- 目标屏幕、交接点（绝对坐标，window 模式有效）

local function locateStage()
  local win = hs.window.focusedWindow()
  if not isHostWindow(win) then
    win = nil
    for _, w in ipairs(hs.window.orderedWindows()) do
      if isHostWindow(w) and w:isStandard() then
        win = w
        break
      end
    end
  end

  if not win then
    return "center", hs.screen.mainScreen(), nil
  end

  local screen = win:screen() or hs.screen.mainScreen()
  if win:isFullScreen() then
    return "bottom", screen, nil
  end

  local wf = win:frame()
  -- 交接点：窗口右缘、状态栏对应高度（Claude Code 状态栏位于窗口底部）
  return "window", screen, { x = wf.x + wf.w, y = wf.y + wf.h - 36 }
end

-- ── 元素构建辅助 ────────────────────────────────────────────────────────────

-- 像素小人：以"脚底中心"(x, y) 为锚点，按目标高度 h 渲染指定帧
-- 同色横向连续格合并为单个矩形，控制元素数量
local function spriteElements(frameName, x, y, h)
  local frame = SPR.frames[frameName]
  local ps = h / SPR.grid.rows               -- 单像素格边长
  local left = x - SPR.grid.cols * ps / 2
  local top = y - h
  local elems = {}
  for row, line in ipairs(frame) do
    local col = 1
    while col <= #line do
      local ch = line:sub(col, col)
      if ch ~= "." then
        local runEnd = col
        while runEnd < #line and line:sub(runEnd + 1, runEnd + 1) == ch do
          runEnd = runEnd + 1
        end
        elems[#elems + 1] = {
          type = "rectangle", action = "fill",
          fillColor = PAL[SPR.legend[ch]] or PAL.white,
          frame = { x = left + (col - 1) * ps, y = top + (row - 1) * ps,
                    w = (runEnd - col + 1) * ps, h = ps },
        }
        col = runEnd + 1
      else
        col = col + 1
      end
    end
  end
  -- 脚下阴影
  elems[#elems + 1] = {
    type = "oval", action = "fill", fillColor = PAL.shadow,
    frame = { x = x - h * 0.35, y = y - h * 0.04, w = h * 0.7, h = h * 0.1 },
  }
  return elems
end

-- 足球：白底 + 黑色五边形点缀（简化为中心黑点）
local function ballElements(x, y, r)
  return {
    { type = "circle", action = "fill", fillColor = PAL.ballWhite,
      center = { x = x, y = y }, radius = r },
    { type = "circle", action = "fill", fillColor = PAL.ballBlack,
      center = { x = x, y = y }, radius = r * 0.32 },
    { type = "circle", action = "stroke", strokeColor = PAL.ballBlack, strokeWidth = 1,
      center = { x = x, y = y }, radius = r },
  }
end

-- 球门：门柱 + 横梁 + 网格，offsetX/offsetY 用于震动
local function goalElements(W, H, offsetX, offsetY)
  local g = TL.goal
  local gx, gw = g.x * W + offsetX, g.width * W
  local groundPx = TL.groundY * H + offsetY
  local gh = g.height * H
  local topY = groundPx - gh
  local post = math.max(3, H * 0.004)
  local elems = {
    { type = "rectangle", action = "fill", fillColor = PAL.goalPost,
      frame = { x = gx, y = topY, w = post, h = gh } },
    { type = "rectangle", action = "fill", fillColor = PAL.goalPost,
      frame = { x = gx, y = topY, w = gw, h = post } },
  }
  -- 网格线（细描边）
  for i = 1, g.netCols do
    local nx = gx + gw * i / g.netCols
    elems[#elems + 1] = { type = "segments", action = "stroke",
      strokeColor = PAL.netLine, strokeWidth = 0.5,
      coordinates = { { x = nx, y = topY }, { x = nx, y = groundPx } } }
  end
  for i = 1, g.netRows do
    local ny = topY + gh * i / g.netRows
    elems[#elems + 1] = { type = "segments", action = "stroke",
      strokeColor = PAL.netLine, strokeWidth = 0.5,
      coordinates = { { x = gx, y = ny }, { x = gx + gw, y = ny } } }
  end
  return elems
end

-- ── 主流程 ──────────────────────────────────────────────────────────────────

--- GoalKick:play()
--- 读取 state.json 并播放完整覆盖层动画。事件非 goal 类型或已过覆盖层窗口则直接返回。
function obj:play()
  if self._playing then self:stop() end

  local st = readState()
  if not st or st.event.type ~= "goal" then return self end
  local overlayWin = (st.timeline and st.timeline.overlay_play) or { 0, 0 }
  local elapsed = os.time() - st.event.ts
  if overlayWin[2] <= overlayWin[1] or elapsed >= overlayWin[2] then return self end

  local mode, screen, exitPt = locateStage()
  local sf = screen:fullFrame()
  local W, H = sf.w, sf.h

  -- 画布覆盖整个目标屏幕；坐标系内部使用画布局部坐标
  local canvas = hs.canvas.new(sf)
  canvas:level(hs.canvas.windowLevels.screenSaver)
  canvas:behaviorAsLabels({ "canJoinAllSpaces", "stationary" })
  canvas:clickActivating(false)
  canvas:canvasMouseEvents(false, false, false, false)
  canvas:show()

  -- 起点与落地点（画布局部比例坐标）
  local groundPx = TL.groundY * H
  local startX, startY
  if mode == "window" and exitPt then
    startX = (exitPt.x - sf.x) / W
    startY = (exitPt.y - sf.y) / H
  elseif mode == "bottom" then
    startX, startY = 0.25, 1.05          -- 屏幕底边外，钻出
  else
    startX, startY = 0.35, TL.groundY    -- 中央开演：直接站在地面
  end
  local landX = math.min(math.max(startX + 0.08, 0.08), 0.55)
  local runStartX = (mode == "center") and startX or landX

  -- 播放若晚于 overlay 窗口起点（如手动重播），动画从对应进度续播
  local tOffset = math.max(0, elapsed - overlayWin[1])
  local t0 = hs.timer.secondsSinceEpoch() - tOffset
  local ev = st.event

  self._canvas = canvas
  self._playing = true
  self._confetti = nil

  self._timer = hs.timer.doEvery(1 / TL.fps, function()
    local ok, err = pcall(function()
      local t = hs.timer.secondsSinceEpoch() - t0
      if t >= TL.total then
        self:stop()
        return
      end
      self:_renderFrame(t, { mode = mode, W = W, H = H, groundPx = groundPx,
                             startX = startX, startY = startY, landX = landX,
                             runStartX = runStartX, ev = ev })
    end)
    if not ok then
      print("GoalKick render error: " .. tostring(err))
      self:stop()
    end
  end)
  return self
end

--- GoalKick:stop()
--- 立即停止播放并销毁全部资源（timer、canvas、粒子缓存）。
function obj:stop()
  if self._timer then self._timer:stop(); self._timer = nil end
  if self._canvas then self._canvas:delete(); self._canvas = nil end
  self._confetti = nil
  self._playing = false
  return self
end

-- 单帧渲染：根据 t 所处阶段构建元素表，整体替换画布内容
function obj:_renderFrame(t, ctx)
  local W, H, groundPx = ctx.W, ctx.H, ctx.groundPx
  local P = TL.phases
  local playerH = TL.playerBaseHeightFrac * H
  local elems = {}
  local function add(list) for _, e in ipairs(list) do elems[#elems + 1] = e end end

  -- 收场阶段：整体淡出用画布级 alpha，元素照常构建
  if t >= P.fade.from then
    self._canvas:alpha(1 - ease(P.fade.easing, phaseT(P.fade, t)))
  end

  -- 球门常驻（gooal 阶段前 shakeDur 秒震动）
  local shakeX, shakeY = 0, 0
  if t >= P.gooal.from and t < P.gooal.from + P.gooal.shakeDur then
    local amp = P.gooal.shakeAmp * H * (1 - (t - P.gooal.from) / P.gooal.shakeDur)
    shakeX = math.sin(t * 55) * amp
    shakeY = math.cos(t * 47) * amp * 0.6
  end
  add(goalElements(W, H, shakeX, shakeY))

  -- 阶段一：交接涟漪（仅 window 模式）
  if ctx.mode == "window" and t >= P.handoff.from and t < P.handoff.to then
    local pt = ease(P.handoff.easing, phaseT(P.handoff, t))
    local r = P.handoff.rippleMaxR * H * pt
    local ring = { red = PAL.gold.red, green = PAL.gold.green, blue = PAL.gold.blue,
                   alpha = (1 - pt) * 0.9 }
    elems[#elems + 1] = { type = "circle", action = "stroke", strokeColor = ring,
      strokeWidth = 3, center = { x = ctx.startX * W, y = ctx.startY * H },
      radius = math.max(r, 1) }
  end

  -- 小人位置与体型（按阶段）
  local px, py, ph, frameName
  if t < P.jump.to and ctx.mode ~= "center" then
    -- 跳出：抛物线 + 体型放大
    local jt = ease(P.jump.easing, phaseT(P.jump, t))
    px = ctx.startX + (ctx.landX - ctx.startX) * jt
    local y0, y1 = ctx.startY, TL.groundY
    -- 抛物线：线性插值基线上叠加 sin 形拱高
    py = y0 + (y1 - y0) * jt - P.jump.arcHeight * math.sin(jt * math.pi)
    ph = playerH * (TL.playerScaleStart + (TL.playerScaleEnd - TL.playerScaleStart) * jt)
    frameName = "runA"
  elseif t < P.run.to then
    -- 助跑：沿地面向右，双帧交替
    local rt = ease(P.run.easing, phaseT(P.run, math.max(t, P.run.from)))
    px = ctx.runStartX + (P.run.endX - ctx.runStartX) * rt
    py = TL.groundY
    ph = playerH * TL.playerScaleEnd
    frameName = (math.floor(t / P.run.runFrameDur) % 2 == 0) and "runA" or "runB"
  elseif t < P.kick.to then
    px, py, ph, frameName = P.run.endX, TL.groundY, playerH * TL.playerScaleEnd, "kick"
  else
    -- 射门后原地庆祝
    px, py, ph, frameName = P.run.endX, TL.groundY, playerH * TL.playerScaleEnd, "cheer"
  end
  add(spriteElements(frameName, px * W, py * H, ph))

  -- 足球
  local ballR = math.max(6, H * 0.011)
  local goalCx = (TL.goal.x + TL.goal.width * 0.5) * W
  local goalCy = groundPx - TL.goal.height * H * 0.45
  if t >= P.run.from and t < P.flight.from then
    -- 静置在小人前方地面
    add(ballElements(P.run.ballX * W, groundPx - ballR, ballR))
  elseif t >= P.flight.from and t < P.flight.to then
    -- 飞行：抛物线 + 金色拖尾
    local ft = ease(P.flight.easing, phaseT(P.flight, t))
    local bx0, by0 = P.run.ballX * W, groundPx - ballR
    local bx = bx0 + (goalCx - bx0) * ft
    local by = by0 + (goalCy - by0) * ft - P.flight.arcHeight * H * math.sin(ft * math.pi)
    for i = P.flight.trailLen, 1, -1 do
      local tt = math.max(0, ft - i * 0.04)
      local tx = bx0 + (goalCx - bx0) * tt
      local ty = by0 + (goalCy - by0) * tt - P.flight.arcHeight * H * math.sin(tt * math.pi)
      local trail = { red = PAL.gold.red, green = PAL.gold.green, blue = PAL.gold.blue,
                      alpha = 0.5 * (1 - i / (P.flight.trailLen + 1)) }
      elems[#elems + 1] = { type = "circle", action = "fill", fillColor = trail,
        center = { x = tx, y = ty }, radius = ballR * (1 - i * 0.1) }
    end
    add(ballElements(bx, by, ballR))
  elseif t >= P.flight.to then
    -- 入网静止
    add(ballElements(goalCx + shakeX, goalCy + shakeY, ballR))
  end

  -- GOOOAL 阶段：彩带 + 大字
  if t >= P.gooal.from then
    local gt = t - P.gooal.from
    -- 彩带粒子：进入阶段时一次性生成，之后按简单物理推进
    if not self._confetti then
      self._confetti = {}
      for i = 1, P.gooal.confettiCount do
        self._confetti[#self._confetti + 1] = {
          x = goalCx / W + (math.random() - 0.5) * 0.12,
          y = goalCy / H + (math.random() - 0.5) * 0.06,
          vx = (math.random() - 0.5) * 0.50,
          vy = -math.random() * 0.55 - 0.10,
          size = 3 + math.random() * 5,
          color = PAL.confetti[math.random(#PAL.confetti)],
          wobble = math.random() * math.pi * 2,
        }
      end
    end
    for _, c in ipairs(self._confetti) do
      local cx = (c.x + c.vx * gt + math.sin(gt * 3 + c.wobble) * 0.01) * W
      local cy = (c.y + c.vy * gt + P.gooal.confettiGravity * gt * gt * 0.5) * H
      if cy < H + 20 then
        local col = { red = c.color.red, green = c.color.green, blue = c.color.blue,
                      alpha = math.max(0, 1 - gt / (P.fade.from - P.gooal.from)) }
        elems[#elems + 1] = { type = "rectangle", action = "fill", fillColor = col,
          frame = { x = cx, y = cy, w = c.size, h = c.size * 1.6 } }
      end
    end
    -- "GOOOAL!" 大字 + 比分 + 进球者：弹性放大入场
    local st_ = math.min(1, gt / P.gooal.textInDur)
    local scale = ease(P.gooal.textEasing, st_)
    local titleSize = P.gooal.titleSizeFrac * H * scale
    if titleSize > 1 then
      local ev = ctx.ev
      elems[#elems + 1] = { type = "text", text = "GOOOAL!",
        textSize = titleSize, textColor = PAL.gold, textAlignment = "center",
        frame = { x = 0, y = H * 0.28 - titleSize / 2, w = W, h = titleSize * 1.3 } }
      local sub = string.format("%s %s %s %s",
        ev.team_flag or "", ev.team or "", ev.score or "", ev.opponent or "")
      if (ev.minute or 0) > 0 and (ev.scorer or "") ~= "" then
        sub = sub .. string.format("  (%d′ %s)", ev.minute, ev.scorer)
      end
      elems[#elems + 1] = { type = "text", text = sub,
        textSize = P.gooal.scoreSizeFrac * H * scale, textColor = PAL.scoreText,
        textAlignment = "center",
        frame = { x = 0, y = H * 0.28 + titleSize * 0.85, w = W, h = titleSize } }
    end
  end

  self._canvas:replaceElements(elems)
end

return obj
