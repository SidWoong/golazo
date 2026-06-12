-- goal-kick overlay animation timeline (pure data; reused as-is by the v1.0 Tauri port)
-- All times are "overlay-internal seconds": 0 = state.json timeline.overlay_play[1]
-- (i.e. the handoff moment).
-- All coordinates are fractions (0~1) of the target screen; the renderer maps to pixels.
-- `easing` values are named references implemented in the renderer's EASING table
-- (linear/easeOutQuad/easeInQuad/easeOutCubic/easeOutBack).
--
-- Mirroring rule (implemented in the renderer): when there is not enough room to
-- the right of the exit point, the whole pitch mirrors horizontally (run left,
-- goal on the left, sprites flipped). All x values here are written for a
-- rightward attack.
return {
  total = 8.2,          -- total duration; the timer MUST stop and the canvas be destroyed at the end
  fps = 30,

  -- scene constants
  groundY = 0.80,       -- "ground" baseline: 80% of screen height (renderer lowers it for low windows, capped at 0.92)
  playerScaleStart = 1.0,
  playerScaleEnd = 3.0, -- the runner grows ~3x while landing
  playerBaseHeightFrac = 0.045,  -- starting size: 4.5% of screen height (~13.5% after ×3)

  goal = {              -- the goal (written for a rightward attack; renderer mirrors when needed)
    x = 0.88,           -- left edge of the goalposts
    width = 0.10,
    height = 0.22,      -- relative to screen height, rising from the ground
    netRows = 5,
    netCols = 7,
  },

  phases = {
    -- run along the inside of the window's bottom edge, left to right
    -- (window mode only; the runner is hidden in this phase for other modes)
    approach = { from = 0.0, to = 1.2, runFrameDur = 0.12, easing = "easeInQuad" },
    -- exit: reach the window's bottom-right border, mark the handoff with a
    -- ripple, leap out along a parabola while growing
    ripple  = { from = 1.2, to = 1.7, rippleMaxR = 0.04, easing = "easeOutQuad" },
    jump    = { from = 1.2, to = 2.0, arcHeight = 0.08, driftX = 0.07, easing = "easeInQuad" },
    -- run-up: sprint along the ground towards the ball
    run     = { from = 2.0, to = 3.0, runFrameDur = 0.12, easing = "linear",
                endX = 0.74,       -- stop just short of the ball (ball at 0.78)
                ballX = 0.78 },
    -- kick: strike pose; the ball flies to the goal on a parabola with a golden trail
    kick    = { from = 3.0, to = 3.3, easing = "linear" },
    flight  = { from = 3.3, to = 3.8, arcHeight = 0.10, trailLen = 6, easing = "easeOutQuad" },
    -- GOOOAL: net bulge, goal shake, confetti, elastic title entrance
    gooal   = { from = 3.8, to = 6.8,
                shakeDur = 0.5, shakeAmp = 0.008,
                confettiCount = 150, confettiGravity = 0.35,
                textInDur = 0.6, textEasing = "easeOutBack",
                titleSizeFrac = 0.09,   -- "GOOOAL!" font size as a fraction of screen height
                scoreSizeFrac = 0.035 },
    -- outro: fade everything out
    fade    = { from = 6.8, to = 8.2, easing = "easeOutQuad" },
  },
}
