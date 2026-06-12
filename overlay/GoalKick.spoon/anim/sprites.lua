-- goal-kick pixel-runner frames (pure data; reused as-is by the v1.0 Tauri port)
-- Each frame is a character grid (array of row strings); characters map to
-- palette keys via `legend`; "." is transparent.
-- Grid orientation: the runner faces right.
local legend = {
  H = "hair",
  S = "skin",
  J = "jersey",
  W = "stripe",
  P = "shorts",
  B = "boots",
}

-- run frame A: front leg extended
local runA = {
  "...HHH....",
  "...HSS....",
  "...SSS....",
  "..JJJJ....",
  ".SJWWJS...",
  "..JJJJ....",
  "..JWWJ....",
  "...PPP....",
  "..PP.PP...",
  ".BB...PP..",
  ".......BB.",
}

-- run frame B: legs swapped
local runB = {
  "...HHH....",
  "...HSS....",
  "...SSS....",
  "..JJJJ....",
  "..JWWJS...",
  ".SJJJJ....",
  "..JWWJ....",
  "...PPP....",
  "...PPP....",
  "...P.PP...",
  "..BB..BB..",
}

-- kick frame: right leg raised for the strike
local kick = {
  "...HHH....",
  "...HSS....",
  "...SSS....",
  "..JJJJ....",
  ".SJWWJS...",
  "..JJJJ....",
  "..JWWJ....",
  "...PPP....",
  "..PP.PPP..",
  ".BB....BB.",
  "..........",
}

-- cheer frame: both arms raised
local cheer = {
  ".S.....S..",
  ".SS...SS..",
  "..JHHHJ...",
  "..JHSSJ...",
  "...SSS....",
  "..JJJJ....",
  "..JWWJ....",
  "..JJJJ....",
  "...PPP....",
  "..PP.PP...",
  ".BB...BB..",
}

return {
  legend = legend,
  -- the jump/fall phase reuses run frame A (a tucked-leg pose is out of scope for v0.1)
  frames = { runA = runA, runB = runB, kick = kick, cheer = cheer },
  -- grid size (identical for all frames): the renderer maps it to target pixels
  grid = { cols = 10, rows = 11 },
}
