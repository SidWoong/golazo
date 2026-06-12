--- === Golazo ===
--- World Cup goal celebration overlay for the desktop (golazo v0.1).
--- Triggered via `hs -c "spoon.Golazo:play()"`: reads ~/.claude/golazo/state.json,
--- then the runner dashes along the terminal window's bottom edge → leaps out of the
--- window frame → lands and grows → run-up and shot → GOOOAL confetti → fades out
--- and destroys itself.
--- Rendering logic lives in this file; all animation parameters (timeline/palette/
--- frames) live in the anim/ data files to ease the v1.0 port.

local obj = {}
obj.__index = obj

obj.name = "Golazo"
obj.version = "0.1.0"
obj.author = "golazo"
obj.license = "MIT"
obj.homepage = "https://github.com/SidWoong/golazo"

-- Playback state (held while playing; MUST be cleared at the end to avoid leaks)
obj._canvas = nil
obj._timer = nil
obj._playing = false
obj._confetti = nil

local TL, PAL, SPR   -- anim/ data, loaded in init()

-- Apps that qualify as "terminal hosts": matched by bundle ID first (immune to
-- system-language localization — e.g. Terminal.app displays as 「终端」 on a
-- Chinese system), with the app name only as a fallback.
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

-- Does this window belong to a terminal-host app?
local function isHostWindow(w)
  local app = w and w:application()
  if not app then return false end
  local bid = app:bundleID()
  if bid and HOST_BUNDLES[bid] then return true end
  return HOST_APPS[app:name()] or false
end

-- Easing implementations: referenced by name from the anim/ data
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

-- Normalized progress [0,1] within a phase
local function phaseT(phase, t)
  if phase.to <= phase.from then return 1 end
  return (t - phase.from) / (phase.to - phase.from)
end

local function clamp(v, lo, hi)
  if v < lo then return lo elseif v > hi then return hi end
  return v
end

-- "#rrggbb" → color table; nil for invalid input (callers fall back to defaults)
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

-- ── state file ──────────────────────────────────────────────────────────────

local function stateDir()
  return (os.getenv("GOLAZO_DIR") or (os.getenv("HOME") .. "/.claude/golazo"))
end

local function readState()
  local st = hs.json.read(stateDir() .. "/state.json")
  if not st or st.schema_version ~= 1 or not st.event then return nil end
  return st
end

-- ── stage location and fallback chain ───────────────────────────────────────
-- Returns mode ("window" = run along the window's bottom edge then leap out /
-- "bottom" = emerge from the screen's bottom edge / "center" = play mid-screen),
-- the target screen, and the terminal window object (non-nil in window mode).

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

-- ── element builders ────────────────────────────────────────────────────────

-- Pixel runner: anchored at the feet center (x, y), rendered at target height h;
-- flip mirrors horizontally. pal is the palette (defaults to PAL; a kit-override
-- proxy is passed when the runner wears a team's jersey).
-- Horizontal runs of the same color merge into single rectangles to keep the
-- element count down.
local function spriteElements(frameName, x, y, h, flip, pal)
  pal = pal or PAL
  local frame = SPR.frames[frameName]
  local ps = h / SPR.grid.rows               -- side length of one pixel cell
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
  -- shadow under the feet
  elems[#elems + 1] = {
    type = "oval", action = "fill", fillColor = PAL.shadow,
    frame = { x = x - h * 0.35, y = y - h * 0.04, w = h * 0.7, h = h * 0.1 },
  }
  return elems
end

-- Football: white base + black accents
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

-- Goal: posts + crossbar + net grid; gxFrac is the (already mirrored) left edge
local function goalElements(W, H, gxFrac, groundFrac, offsetX, offsetY, mirrored)
  local g = TL.goal
  local gx, gw = gxFrac * W + offsetX, g.width * W
  local groundPx = groundFrac * H + offsetY
  local gh = g.height * H
  local topY = groundPx - gh
  local post = math.max(3, H * 0.004)
  -- the upright post sits on the side facing away from the attack:
  -- left edge for a rightward attack, right edge when mirrored
  local postX = mirrored and (gx + gw - post) or gx
  local elems = {
    { type = "rectangle", action = "fill", fillColor = PAL.goalPost,
      frame = { x = postX, y = topY, w = post, h = gh } },
    { type = "rectangle", action = "fill", fillColor = PAL.goalPost,
      frame = { x = gx, y = topY, w = gw, h = post } },
  }
  -- net lines (thin strokes)
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

-- ── main flow ───────────────────────────────────────────────────────────────

--- Golazo:play()
--- Read state.json and play the full overlay animation. Returns immediately for
--- non-goal events or events already past their overlay window.
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

  -- The canvas covers the whole target screen; internal coordinates are
  -- canvas-local fractions
  local canvas = hs.canvas.new(sf)
  canvas:level(hs.canvas.windowLevels.screenSaver)
  canvas:behaviorAsLabels({ "canJoinAllSpaces", "stationary" })
  canvas:clickActivating(false)
  canvas:canvasMouseEvents(false, false, false, false)
  canvas:show()

  -- ── stage geometry ──
  -- ctx.dir: 1 = attack rightward, -1 = mirror the whole pitch (attack leftward)
  -- when there is not enough room to the right of the exit point
  local ctx = { mode = mode, W = W, H = H }
  if mode == "window" and win then
    local wf = win:frame()
    ctx.wL = clamp((wf.x - sf.x) / W + 0.012, 0, 1)            -- start of the run along the bottom edge
    ctx.wR = clamp((wf.x + wf.w - sf.x) / W, 0.05, 0.99)       -- exit point: the bottom-right corner
    ctx.yEdge = clamp((wf.y + wf.h - sf.y) / H - 0.012, 0.1, 0.98)
    ctx.dir = (ctx.wR <= 0.55) and 1 or -1
    -- the ground must not sit above the window's bottom edge (the runner cannot
    -- "jump upward"); it shifts down dynamically for low windows
    ctx.ground = clamp(math.max(TL.groundY, ctx.yEdge + 0.08), TL.groundY, 0.92)
    ctx.jumpFromX, ctx.jumpFromY = ctx.wR, ctx.yEdge
  elseif mode == "bottom" then
    ctx.dir = 1
    ctx.ground = TL.groundY
    ctx.jumpFromX, ctx.jumpFromY = 0.25, 1.05                  -- emerge from below the screen edge
  else
    ctx.dir = 1
    ctx.ground = TL.groundY
    ctx.jumpFromX, ctx.jumpFromY = 0.35, TL.groundY            -- center mode: standing on the ground
  end

  -- Mirror mapping: all x values in the data are written for a rightward attack
  local function mx(x) return ctx.dir == 1 and x or (1 - x) end
  ctx.mx = mx
  ctx.landX = clamp(ctx.jumpFromX + TL.phases.jump.driftX * ctx.dir, 0.05, 0.95)
  ctx.runEndX = mx(TL.phases.run.endX)
  ctx.ballX = mx(TL.phases.run.ballX)
  ctx.goalLeftX = ctx.dir == 1 and TL.goal.x or (1 - TL.goal.x - TL.goal.width)
  ctx.goalCx = ctx.goalLeftX + TL.goal.width * 0.5
  ctx.ev = st.event

  -- Kit swap: when event.kit is present it overrides the runner's colors
  -- (jersey/stripe/shorts); the default palette is used otherwise
  local kit = st.event.kit
  if type(kit) == "table" then
    local over = { jersey = hexColor(kit.jersey), stripe = hexColor(kit.stripe),
                   shorts = hexColor(kit.shorts) }
    ctx.pal = setmetatable({}, { __index = function(_, k) return over[k] or PAL[k] end })
  end

  -- If play() arrives after the overlay window opened (e.g. a manual replay),
  -- resume the animation at the matching progress
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
      print("Golazo render error: " .. tostring(err))
      self:stop()
    end
  end)
  return self
end

--- Golazo:stop()
--- Stop playback immediately and destroy every resource (timer, canvas, particles).
function obj:stop()
  if self._timer then self._timer:stop(); self._timer = nil end
  if self._canvas then self._canvas:delete(); self._canvas = nil end
  self._confetti = nil
  self._playing = false
  return self
end

-- Render one frame: build the element list for the phase containing t and
-- replace the canvas content wholesale
function obj:_renderFrame(t, ctx)
  local W, H = ctx.W, ctx.H
  local P = TL.phases
  local groundPx = ctx.ground * H
  local playerH = TL.playerBaseHeightFrac * H
  local flip = (ctx.dir == -1)
  local elems = {}
  local function add(list) for _, e in ipairs(list) do elems[#elems + 1] = e end end

  -- Outro: the global fade uses canvas-level alpha; elements build as usual
  if t >= P.fade.from then
    self._canvas:alpha(1 - ease(P.fade.easing, phaseT(P.fade, t)))
  end

  -- The goal is always present (shaking for the first shakeDur seconds of gooal)
  local shakeX, shakeY = 0, 0
  if t >= P.gooal.from and t < P.gooal.from + P.gooal.shakeDur then
    local amp = P.gooal.shakeAmp * H * (1 - (t - P.gooal.from) / P.gooal.shakeDur)
    shakeX = math.sin(t * 55) * amp
    shakeY = math.cos(t * 47) * amp * 0.6
  end
  add(goalElements(W, H, ctx.goalLeftX, ctx.ground, shakeX, shakeY, flip))

  -- Ripple: the handoff marker at the window border just before the leap
  -- (window mode only)
  if ctx.mode == "window" and t >= P.ripple.from and t < P.ripple.to then
    local pt = ease(P.ripple.easing, phaseT(P.ripple, t))
    local r = P.ripple.rippleMaxR * H * pt
    local ring = { red = PAL.gold.red, green = PAL.gold.green, blue = PAL.gold.blue,
                   alpha = (1 - pt) * 0.9 }
    elems[#elems + 1] = { type = "circle", action = "stroke", strokeColor = ring,
      strokeWidth = 3, center = { x = ctx.jumpFromX * W, y = ctx.jumpFromY * H },
      radius = math.max(r, 1) }
  end

  -- Runner position and size, per phase
  local px, py, ph, frameName
  local pflip = flip
  if t < P.approach.to then
    if ctx.mode ~= "window" then
      px = nil                              -- the runner is hidden in this phase for non-window modes
    else
      -- run along the inside of the window's bottom edge, left to right
      -- (always rightward, matching the statusline runner's direction)
      local at = ease(P.approach.easing, phaseT(P.approach, t))
      px = ctx.wL + (ctx.wR - ctx.wL) * at
      py = ctx.yEdge
      ph = playerH
      pflip = false
      frameName = (math.floor(t / P.approach.runFrameDur) % 2 == 0) and "runA" or "runB"
    end
  elseif t < P.jump.to and ctx.mode ~= "center" then
    -- leap: parabola over the window border down to the ground, growing
    local jt = ease(P.jump.easing, phaseT(P.jump, t))
    px = ctx.jumpFromX + (ctx.landX - ctx.jumpFromX) * jt
    py = ctx.jumpFromY + (ctx.ground - ctx.jumpFromY) * jt
         - P.jump.arcHeight * math.sin(jt * math.pi)
    ph = playerH * (TL.playerScaleStart + (TL.playerScaleEnd - TL.playerScaleStart) * jt)
    frameName = "runA"
  elseif t < P.run.to then
    -- run-up: sprint along the ground towards the ball, alternating two frames
    local rt = ease(P.run.easing, phaseT(P.run, math.max(t, P.run.from)))
    local fromX = (ctx.mode == "center") and ctx.jumpFromX or ctx.landX
    px = fromX + (ctx.runEndX - fromX) * rt
    py = ctx.ground
    ph = playerH * TL.playerScaleEnd
    frameName = (math.floor(t / P.run.runFrameDur) % 2 == 0) and "runA" or "runB"
  elseif t < P.kick.to then
    px, py, ph, frameName = ctx.runEndX, ctx.ground, playerH * TL.playerScaleEnd, "kick"
  else
    -- celebrate in place after the shot
    px, py, ph, frameName = ctx.runEndX, ctx.ground, playerH * TL.playerScaleEnd, "cheer"
  end
  if px then
    add(spriteElements(frameName, px * W, py * H, ph, pflip, ctx.pal))
  end

  -- The football
  local ballR = math.max(6, H * 0.011)
  local goalCx = ctx.goalCx * W
  local goalCy = groundPx - TL.goal.height * H * 0.45
  if t >= P.run.from and t < P.flight.from then
    -- resting on the ground ahead of the runner
    add(ballElements(ctx.ballX * W, groundPx - ballR, ballR))
  elseif t >= P.flight.from and t < P.flight.to then
    -- flight: parabola plus a golden trail
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
    -- resting in the net
    add(ballElements(goalCx + shakeX, goalCy + shakeY, ballR))
  end

  -- GOOOAL phase: confetti + the big title
  if t >= P.gooal.from then
    local gt = t - P.gooal.from
    -- Confetti particles: generated once on phase entry, then advanced with
    -- simple physics
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
    -- "GOOOAL!" title + score + scorer: elastic scale-in
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
      -- The scorer gets its own golden line; minute/name combine by availability
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
