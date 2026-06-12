--- === GoalKick ===
--- 世界杯进球桌面特效覆盖层（goal-kick v0.1）
--- 被 `hs -c "spoon.GoalKick:play()"` 调起后：读取 ~/.claude/goal-kick/state.json，
--- 小人沿终端窗口底边从左跑到右 → 从窗口边框跃出 → 落地放大 → 助跑射门 →
--- GOOOAL 彩带 → 淡出销毁。
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

local function clamp(v, lo, hi)
  if v < lo then return lo elseif v > hi then return hi end
  return v
end

-- "#rrggbb" → 颜色表；非法输入返回 nil（调用方回退默认配色）
local function hexColor(hex)
  if type(hex) ~= "string" then return nil end
  local r, g, b = hex:match("^#?(%x%x)(%x%x)(%x%x)$")
  if not r then return nil end
  return { red = tonumber(r, 16) / 255, green = tonumber(g, 16) / 255,
           blue = tonumber(b, 16) / 255, alpha = 1.0 }
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
-- 返回 mode（"window" 沿窗口底边跑动后跃出 / "bottom" 从屏幕底边钻出 /
-- "center" 屏幕中央开演）、目标屏幕、终端窗口对象（window 模式时非 nil）

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
  return "window", screen, win
end

-- ── 元素构建辅助 ────────────────────────────────────────────────────────────

-- 像素小人：以"脚底中心"(x, y) 为锚点，按目标高度 h 渲染指定帧；flip 为真时水平镜像
-- pal 为调色板（默认 PAL；进球队球衣换装时传入覆盖代理）
-- 同色横向连续格合并为单个矩形，控制元素数量
local function spriteElements(frameName, x, y, h, flip, pal)
  pal = pal or PAL
  local frame = SPR.frames[frameName]
  local ps = h / SPR.grid.rows               -- 单像素格边长
  local left = x - SPR.grid.cols * ps / 2
  local top = y - h
  local elems = {}
  for row, line in ipairs(frame) do
    if flip then line = line:reverse() end
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
          fillColor = pal[SPR.legend[ch]] or PAL.white,
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

-- 足球：白底 + 黑色点缀
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

-- 球门：门柱 + 横梁 + 网格；gxFrac 为门柱"开口侧"对齐用的左缘 x（已镜像换算）
local function goalElements(W, H, gxFrac, groundFrac, offsetX, offsetY, mirrored)
  local g = TL.goal
  local gx, gw = gxFrac * W + offsetX, g.width * W
  local groundPx = groundFrac * H + offsetY
  local gh = g.height * H
  local topY = groundPx - gh
  local post = math.max(3, H * 0.004)
  -- 立柱画在背向进攻的一侧：向右进攻时在左缘，镜像时在右缘
  local postX = mirrored and (gx + gw - post) or gx
  local elems = {
    { type = "rectangle", action = "fill", fillColor = PAL.goalPost,
      frame = { x = postX, y = topY, w = post, h = gh } },
    { type = "rectangle", action = "fill", fillColor = PAL.goalPost,
      frame = { x = gx, y = topY, w = gw, h = post } },
  }
  -- 网格线（细描边）
  for i = 1, g.netCols do
    local nx = gx + gw * i / (g.netCols + 1)
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

  local mode, screen, win = locateStage()
  local sf = screen:fullFrame()
  local W, H = sf.w, sf.h

  -- 画布覆盖整个目标屏幕；坐标系内部使用画布局部比例坐标
  local canvas = hs.canvas.new(sf)
  canvas:level(hs.canvas.windowLevels.screenSaver)
  canvas:behaviorAsLabels({ "canJoinAllSpaces", "stationary" })
  canvas:clickActivating(false)
  canvas:canvasMouseEvents(false, false, false, false)
  canvas:show()

  -- ── 舞台几何 ──
  -- ctx.dir：1 = 向右进攻，-1 = 跳出点右侧空间不足时整场镜像（向左进攻）
  local ctx = { mode = mode, W = W, H = H }
  if mode == "window" and win then
    local wf = win:frame()
    ctx.wL = clamp((wf.x - sf.x) / W + 0.012, 0, 1)            -- 窗口底边内侧起点
    ctx.wR = clamp((wf.x + wf.w - sf.x) / W, 0.05, 0.99)       -- 跳出点：右下角边框
    ctx.yEdge = clamp((wf.y + wf.h - sf.y) / H - 0.012, 0.1, 0.98)
    ctx.dir = (ctx.wR <= 0.55) and 1 or -1
    -- 地面不能高于窗口底边（小人不能"跳上去"），随窗口动态下移
    ctx.ground = clamp(math.max(TL.groundY, ctx.yEdge + 0.08), TL.groundY, 0.92)
    ctx.jumpFromX, ctx.jumpFromY = ctx.wR, ctx.yEdge
  elseif mode == "bottom" then
    ctx.dir = 1
    ctx.ground = TL.groundY
    ctx.jumpFromX, ctx.jumpFromY = 0.25, 1.05                  -- 屏幕底边外钻出
  else
    ctx.dir = 1
    ctx.ground = TL.groundY
    ctx.jumpFromX, ctx.jumpFromY = 0.35, TL.groundY            -- 中央开演：直接站在地面
  end

  -- 镜像换算：数据中的 x 均按"向右进攻"书写
  local function mx(x) return ctx.dir == 1 and x or (1 - x) end
  ctx.mx = mx
  ctx.landX = clamp(ctx.jumpFromX + TL.phases.jump.driftX * ctx.dir, 0.05, 0.95)
  ctx.runEndX = mx(TL.phases.run.endX)
  ctx.ballX = mx(TL.phases.run.ballX)
  ctx.goalLeftX = ctx.dir == 1 and TL.goal.x or (1 - TL.goal.x - TL.goal.width)
  ctx.goalCx = ctx.goalLeftX + TL.goal.width * 0.5
  ctx.ev = st.event

  -- 球衣换装：event.kit 提供时覆盖小人配色（jersey/stripe/shorts），缺省用默认配色
  local kit = st.event.kit
  if type(kit) == "table" then
    local over = { jersey = hexColor(kit.jersey), stripe = hexColor(kit.stripe),
                   shorts = hexColor(kit.shorts) }
    ctx.pal = setmetatable({}, { __index = function(_, k) return over[k] or PAL[k] end })
  end

  -- 播放若晚于 overlay 窗口起点（如手动重播），动画从对应进度续播
  local tOffset = math.max(0, elapsed - overlayWin[1])
  local t0 = hs.timer.secondsSinceEpoch() - tOffset

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
      self:_renderFrame(t, ctx)
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
  local W, H = ctx.W, ctx.H
  local P = TL.phases
  local groundPx = ctx.ground * H
  local playerH = TL.playerBaseHeightFrac * H
  local flip = (ctx.dir == -1)
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
  add(goalElements(W, H, ctx.goalLeftX, ctx.ground, shakeX, shakeY, flip))

  -- 涟漪：抵达窗口边框、即将跃出的交接标记（仅 window 模式）
  if ctx.mode == "window" and t >= P.ripple.from and t < P.ripple.to then
    local pt = ease(P.ripple.easing, phaseT(P.ripple, t))
    local r = P.ripple.rippleMaxR * H * pt
    local ring = { red = PAL.gold.red, green = PAL.gold.green, blue = PAL.gold.blue,
                   alpha = (1 - pt) * 0.9 }
    elems[#elems + 1] = { type = "circle", action = "stroke", strokeColor = ring,
      strokeWidth = 3, center = { x = ctx.jumpFromX * W, y = ctx.jumpFromY * H },
      radius = math.max(r, 1) }
  end

  -- 小人位置与体型（按阶段）
  local px, py, ph, frameName
  local pflip = flip
  if t < P.approach.to then
    if ctx.mode ~= "window" then
      px = nil                              -- 非 window 模式此阶段不出现小人
    else
      -- 沿窗口底边内侧从左走到右（始终向右，与状态栏小人方向一致）
      local at = ease(P.approach.easing, phaseT(P.approach, t))
      px = ctx.wL + (ctx.wR - ctx.wL) * at
      py = ctx.yEdge
      ph = playerH
      pflip = false
      frameName = (math.floor(t / P.approach.runFrameDur) % 2 == 0) and "runA" or "runB"
    end
  elseif t < P.jump.to and ctx.mode ~= "center" then
    -- 跳出：抛物线越过窗口边框落到地面，体型放大
    local jt = ease(P.jump.easing, phaseT(P.jump, t))
    px = ctx.jumpFromX + (ctx.landX - ctx.jumpFromX) * jt
    py = ctx.jumpFromY + (ctx.ground - ctx.jumpFromY) * jt
         - P.jump.arcHeight * math.sin(jt * math.pi)
    ph = playerH * (TL.playerScaleStart + (TL.playerScaleEnd - TL.playerScaleStart) * jt)
    frameName = "runA"
  elseif t < P.run.to then
    -- 助跑：沿地面奔向足球，双帧交替
    local rt = ease(P.run.easing, phaseT(P.run, math.max(t, P.run.from)))
    local fromX = (ctx.mode == "center") and ctx.jumpFromX or ctx.landX
    px = fromX + (ctx.runEndX - fromX) * rt
    py = ctx.ground
    ph = playerH * TL.playerScaleEnd
    frameName = (math.floor(t / P.run.runFrameDur) % 2 == 0) and "runA" or "runB"
  elseif t < P.kick.to then
    px, py, ph, frameName = ctx.runEndX, ctx.ground, playerH * TL.playerScaleEnd, "kick"
  else
    -- 射门后原地庆祝
    px, py, ph, frameName = ctx.runEndX, ctx.ground, playerH * TL.playerScaleEnd, "cheer"
  end
  if px then
    add(spriteElements(frameName, px * W, py * H, ph, pflip, ctx.pal))
  end

  -- 足球
  local ballR = math.max(6, H * 0.011)
  local goalCx = ctx.goalCx * W
  local goalCy = groundPx - TL.goal.height * H * 0.45
  if t >= P.run.from and t < P.flight.from then
    -- 静置在小人前方地面
    add(ballElements(ctx.ballX * W, groundPx - ballR, ballR))
  elseif t >= P.flight.from and t < P.flight.to then
    -- 飞行：抛物线 + 金色拖尾
    local ft = ease(P.flight.easing, phaseT(P.flight, t))
    local bx0, by0 = ctx.ballX * W, groundPx - ballR
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
          x = ctx.goalCx + (math.random() - 0.5) * 0.12,
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
      local subSize = P.gooal.scoreSizeFrac * H * scale
      elems[#elems + 1] = { type = "text", text = sub,
        textSize = subSize, textColor = PAL.scoreText, textAlignment = "center",
        frame = { x = 0, y = H * 0.28 + titleSize * 0.85, w = W, h = subSize * 1.4 } }
      -- 进球者独立一行（金色），分钟/人名按可得性组合
      local minute, scorer = ev.minute or 0, ev.scorer or ""
      local who = ""
      if scorer ~= "" and minute > 0 then
        who = string.format("⚽ %d′  %s", minute, scorer)
      elseif scorer ~= "" then
        who = "⚽ " .. scorer
      elseif minute > 0 then
        who = string.format("⚽ %d′", minute)
      end
      if who ~= "" then
        elems[#elems + 1] = { type = "text", text = who,
          textSize = subSize * 0.92, textColor = PAL.gold, textAlignment = "center",
          frame = { x = 0, y = H * 0.28 + titleSize * 0.85 + subSize * 1.5,
                    w = W, h = subSize * 1.4 } }
      end
    end
  end

  self._canvas:replaceElements(elems)
end

return obj
