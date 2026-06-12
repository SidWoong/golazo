-- goal-kick 覆盖层动画时间轴数据（纯数据文件，v1.0 Tauri 移植直接复用）
-- 所有时间为「覆盖层内部秒」：0 = state.json timeline.overlay_play[1]（即 handoff 时刻）
-- 所有坐标为目标屏幕的比例值（0~1），渲染端负责映射到像素
-- easing 为命名引用，实现见渲染端 EASING 表（linear/easeOutQuad/easeInQuad/easeOutCubic/easeOutBack）
--
-- 镜像规则（渲染端实现）：跳出点右侧空间不足时整场水平镜像
-- （向左助跑、球门置于左侧、小人翻转），数据中的 x 坐标均按"向右进攻"书写。
return {
  total = 8.2,          -- 动画总时长；播完必须停 timer、销毁 canvas
  fps = 30,

  -- 场景常量
  groundY = 0.80,       -- "地面"基准：屏幕高度 80% 处（窗口更低时渲染端动态下移，上限 0.92）
  playerScaleStart = 1.0,
  playerScaleEnd = 3.0, -- 落地后体型放大约 3 倍
  playerBaseHeightFrac = 0.045,  -- 起始体型：屏高的 4.5%（×3 后约 13.5%）

  goal = {              -- 球门（按向右进攻书写；镜像时渲染端换算到左侧）
    x = 0.88,           -- 门柱左缘
    width = 0.10,
    height = 0.22,      -- 相对屏高，从地面向上
    netRows = 5,
    netCols = 7,
  },

  phases = {
    -- 沿窗口底边内侧从左走到右（仅 window 模式；其他模式此阶段不出现小人）
    approach = { from = 0.0, to = 1.2, runFrameDur = 0.12, easing = "easeInQuad" },
    -- 跳出：抵达窗口右下角边框，涟漪标记交接点，抛物线跃出并放大
    ripple  = { from = 1.2, to = 1.7, rippleMaxR = 0.04, easing = "easeOutQuad" },
    jump    = { from = 1.2, to = 2.0, arcHeight = 0.08, driftX = 0.07, easing = "easeInQuad" },
    -- 助跑：沿地面奔向足球
    run     = { from = 2.0, to = 3.0, runFrameDur = 0.12, easing = "linear",
                endX = 0.74,       -- 跑到球前（球在 0.78）
                ballX = 0.78 },
    -- 射门：踢腿，球以抛物线 + 金色拖尾飞向球门
    kick    = { from = 3.0, to = 3.3, easing = "linear" },
    flight  = { from = 3.3, to = 3.8, arcHeight = 0.10, trailLen = 6, easing = "easeOutQuad" },
    -- GOOOAL：入网、球门震动、彩带、大字弹性入场
    gooal   = { from = 3.8, to = 6.8,
                shakeDur = 0.5, shakeAmp = 0.008,
                confettiCount = 150, confettiGravity = 0.35,
                textInDur = 0.6, textEasing = "easeOutBack",
                titleSizeFrac = 0.09,   -- "GOOOAL!" 字号：屏高比例
                scoreSizeFrac = 0.035 },
    -- 收场：全部元素淡出
    fade    = { from = 6.8, to = 8.2, easing = "easeOutQuad" },
  },
}
