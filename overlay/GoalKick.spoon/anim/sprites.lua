-- goal-kick 像素小人帧数据（纯数据文件，v1.0 Tauri 移植直接复用）
-- 每帧为字符网格：行字符串数组，字符 → palette 键的映射见 legend；"." 为透明
-- 网格朝向：小人面向右
local legend = {
  H = "hair",
  S = "skin",
  J = "jersey",
  W = "stripe",
  P = "shorts",
  B = "boots",
}

-- 奔跑帧 A：前腿迈出
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

-- 奔跑帧 B：双腿交换
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

-- 射门帧：右腿高抬踢出
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

-- 庆祝帧：双臂高举
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
  -- 跳出/下落阶段复用奔跑帧 A（蜷腿姿态差异在 v0.1 不做）
  frames = { runA = runA, runB = runB, kick = kick, cheer = cheer },
  -- 网格尺寸（所有帧一致）：渲染端据此把网格映射到目标像素尺寸
  grid = { cols = 10, rows = 11 },
}
