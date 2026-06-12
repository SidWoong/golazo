-- goal-kick 配色数据（纯数据文件，v1.0 Tauri 移植直接复用）
-- 颜色统一为 { red, green, blue, alpha }，分量 0~1
return {
  -- 主特效色：金色 #f7c948
  gold        = { red = 0.969, green = 0.788, blue = 0.282, alpha = 1.0 },
  goldSoft    = { red = 0.969, green = 0.788, blue = 0.282, alpha = 0.35 },
  white       = { red = 1.0,   green = 1.0,   blue = 1.0,   alpha = 1.0 },
  shadow      = { red = 0.0,   green = 0.0,   blue = 0.0,   alpha = 0.25 },
  netLine     = { red = 1.0,   green = 1.0,   blue = 1.0,   alpha = 0.85 },
  goalPost    = { red = 0.92,  green = 0.92,  blue = 0.95,  alpha = 1.0 },
  scoreText   = { red = 1.0,   green = 1.0,   blue = 1.0,   alpha = 0.95 },

  -- 像素小人各部位
  skin   = { red = 0.96, green = 0.80, blue = 0.62, alpha = 1.0 },
  hair   = { red = 0.20, green = 0.14, blue = 0.08, alpha = 1.0 },
  jersey = { red = 0.45, green = 0.75, blue = 0.95, alpha = 1.0 },  -- 天蓝球衣
  stripe = { red = 1.0,  green = 1.0,  blue = 1.0,  alpha = 1.0 },  -- 白条纹
  shorts = { red = 0.10, green = 0.12, blue = 0.30, alpha = 1.0 },
  boots  = { red = 0.12, green = 0.12, blue = 0.12, alpha = 1.0 },

  -- 足球
  ballWhite = { red = 0.98, green = 0.98, blue = 0.96, alpha = 1.0 },
  ballBlack = { red = 0.10, green = 0.10, blue = 0.10, alpha = 1.0 },

  -- 彩带六色：金/红/蓝/绿/粉/橙
  confetti = {
    { red = 0.969, green = 0.788, blue = 0.282, alpha = 1.0 },
    { red = 0.92,  green = 0.26,  blue = 0.21,  alpha = 1.0 },
    { red = 0.26,  green = 0.52,  blue = 0.96,  alpha = 1.0 },
    { red = 0.20,  green = 0.78,  blue = 0.35,  alpha = 1.0 },
    { red = 0.96,  green = 0.45,  blue = 0.71,  alpha = 1.0 },
    { red = 0.98,  green = 0.55,  blue = 0.15,  alpha = 1.0 },
  },
}
