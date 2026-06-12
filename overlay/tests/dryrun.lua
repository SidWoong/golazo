-- GoalKick.spoon 干跑测试：用 hs API 桩逐帧跑完整条动画时间轴
-- 验证：play() 三种降级模式不报错、全程渲染无 nil 错误、播完自动 stop 并销毁 canvas
-- 用法：lua overlay/tests/dryrun.lua  （在仓库根目录执行）

local SPOON_DIR = "overlay/GoalKick.spoon/"

-- ── hs API 桩 ────────────────────────────────────────────────────────────────
local clock = 1000.0          -- 受控假时钟
local deletedCanvases = 0
local liveCanvases = 0
local tickFn = nil            -- 捕获的帧回调
local maxElems = 0

local function makeCanvas()
  liveCanvases = liveCanvases + 1
  local c = {}
  local function chain() return c end
  c.level = chain; c.behaviorAsLabels = chain; c.clickActivating = chain
  c.canvasMouseEvents = chain; c.show = chain; c.alpha = chain
  c.replaceElements = function(_, elems)
    assert(type(elems) == "table", "replaceElements 需要元素表")
    if #elems > maxElems then maxElems = #elems end
    return c
  end
  c.delete = function()
    liveCanvases = liveCanvases - 1
    deletedCanvases = deletedCanvases + 1
  end
  return c
end

local fakeState = {
  schema_version = 1,
  event = { id = "test-1", type = "goal", team = "阿根廷", team_flag = "🇦🇷",
            opponent = "法国", score = "2-1", scorer = "梅西", minute = 78, ts = nil },
  timeline = { statusline_run = { 0, 3 }, handoff = 3,
               overlay_play = { 3, 10 }, scoreboard_hold = { 10, 610 } },
  muted_until = 0,
}

local screenStub = { fullFrame = function() return { x = 0, y = 0, w = 1920, h = 1080 } end }
local focusedWin = nil        -- 各场景注入

hs = {
  spoons = { resourcePath = function(rel) return SPOON_DIR .. rel end },
  json = { read = function(_) return fakeState end },
  canvas = { new = function(_) return makeCanvas() end,
             windowLevels = { screenSaver = 1000 } },
  timer = {
    secondsSinceEpoch = function() return clock end,
    doEvery = function(_, fn) tickFn = fn; return { stop = function() tickFn = nil end } end,
  },
  window = {
    focusedWindow = function() return focusedWin end,
    orderedWindows = function() return {} end,
  },
  screen = { mainScreen = function() return screenStub end },
}
os.time = function() return math.floor(clock) end
math.randomseed(42)

-- ── 用例 ────────────────────────────────────────────────────────────────────
local function makeWin(fullscreen)
  return {
    application = function() return { name = function() return "iTerm2" end } end,
    isStandard = function() return true end,
    isFullScreen = function() return fullscreen end,
    screen = function() return screenStub end,
    frame = function() return { x = 100, y = 100, w = 1200, h = 800 } end,
  }
end

local scenarios = {
  { name = "window 模式（终端窗口右缘跳出）", win = makeWin(false) },
  { name = "bottom 模式（全屏 Space 底边钻出）", win = makeWin(true) },
  { name = "center 模式（无终端窗口降级）", win = nil },
}

local obj = dofile(SPOON_DIR .. "init.lua")
obj:init()

for _, sc in ipairs(scenarios) do
  focusedWin = sc.win
  fakeState.event.ts = clock - 3       -- elapsed=3，正好到 overlay_play 起点
  maxElems = 0

  obj:play()
  assert(tickFn, sc.name .. ": play() 未启动帧 timer")
  assert(liveCanvases == 1, sc.name .. ": 应有且仅有 1 个存活 canvas")

  -- 以 30fps 推进 7.5 秒（超出 total=7.0，验证自动收尾）
  local frames = 0
  for _ = 1, math.floor(7.5 * 30) do
    if not tickFn then break end
    clock = clock + 1 / 30
    tickFn()
    frames = frames + 1
  end

  assert(tickFn == nil, sc.name .. ": 播完后 timer 未停止")
  assert(liveCanvases == 0, sc.name .. ": 播完后 canvas 未销毁")
  assert(obj._playing == false, sc.name .. ": _playing 未复位")
  assert(obj._confetti == nil, sc.name .. ": 粒子缓存未释放")
  print(string.format("✅ %s — %d 帧，峰值元素数 %d", sc.name, frames, maxElems))
end

-- 用例：非 goal 事件不播放
fakeState.event.type = "opponent_goal"
obj:play()
assert(liveCanvases == 0 and tickFn == nil, "opponent_goal 不应触发覆盖层")
print("✅ 非 goal 事件不触发覆盖层")

-- 用例：事件已过覆盖层窗口不播放
fakeState.event.type = "goal"
fakeState.event.ts = clock - 60
obj:play()
assert(liveCanvases == 0 and tickFn == nil, "过期事件不应触发覆盖层")
print("✅ 过期事件不触发覆盖层")

-- 用例：连播 5 次（模拟 M2 验收的内存检查路径）：每次都应干净收场
focusedWin = makeWin(false)
for i = 1, 5 do
  fakeState.event.ts = clock - 3
  obj:play()
  for _ = 1, math.floor(7.5 * 30) do
    if not tickFn then break end
    clock = clock + 1 / 30
    tickFn()
  end
  assert(liveCanvases == 0, "第 " .. i .. " 次连播后 canvas 残留")
end
print("✅ 连播 5 次无 canvas/timer 残留")
print("全部干跑用例通过 🎉")
