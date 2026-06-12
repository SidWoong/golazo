-- goal-kick 覆盖层动画时间轴数据（纯数据文件，v1.0 Tauri 移植直接复用）
-- 所有时间为「覆盖层内部秒」：0 = state.json timeline.overlay_play[1]（即 handoff 时刻）
-- 所有坐标为目标屏幕的比例值（0~1），渲染端负责映射到像素
-- easing 为命名引用，实现见渲染端 EASING 表（linear/easeOutQuad/easeInQuad/easeOutCubic/easeOutBack）
return {
  total = 7.0,          -- 动画总时长；播完必须停 timer、销毁 canvas
  fps = 30,

  -- 场景常量
  groundY = 0.80,       -- "地面"：屏幕高度 80% 处
  playerScaleStart = 1.0,
  playerScaleEnd = 3.0, -- 落地后体型放大约 3 倍
  playerBaseHeightFrac = 0.045,  -- 起始体型：屏高的 4.5%（×3 后约 13.5%）

  goal = {              -- 屏幕右侧球门
    x = 0.88,           -- 门柱左缘
    width = 0.10,
    height = 0.22,      -- 相对屏高，从地面向上
    netRows = 5,
    netCols = 7,
  },

  phases = {
    -- 交接：终端窗口右缘画出小人 + 一圈金色涟漪标记交接点
    handoff = { from = 0.0, to = 0.5, rippleMaxR = 0.04, easing = "easeOutQuad" },
    -- 跳出：抛物线跃出窗口边框，落地过程放大
    jump    = { from = 0.0, to = 0.8, arcHeight = 0.08, easing = "easeInQuad" },
    -- 助跑：沿地面向右奔跑，足球出现在前方
    run     = { from = 0.8, to = 1.8, runFrameDur = 0.12, easing = "linear",
                startX = nil,      -- 落地点，运行时由跳出阶段终点决定
                endX = 0.74,       -- 跑到球前（球在 0.78）
                ballX = 0.78 },
    -- 射门：踢腿，球以抛物线 + 金色拖尾飞向球门
    kick    = { from = 1.8, to = 2.1, easing = "linear" },
    flight  = { from = 2.1, to = 2.6, arcHeight = 0.10, trailLen = 6, easing = "easeOutQuad" },
    -- GOOOAL：入网、球门震动、彩带、大字弹性入场
    gooal   = { from = 2.6, to = 5.5,
                shakeDur = 0.5, shakeAmp = 0.008,
                confettiCount = 150, confettiGravity = 0.35,
                textInDur = 0.6, textEasing = "easeOutBack",
                titleSizeFrac = 0.09,   -- "GOOOAL!" 字号：屏高比例
                scoreSizeFrac = 0.035 },
    -- 收场：全部元素淡出
    fade    = { from = 5.5, to = 7.0, easing = "easeOutQuad" },
  },
}
