# 当前 App 图标与名字

2026-10-20，本人选定 App 显示名“TokenLeft”和“流光 T”图标（[决定 D-87](../../docs/decisions.md)，任务 T122）。取代 D-70 的“Token 仪表盘”与彩虹仪表图标；旧图标保留在 Git 历史（951eb63 定稿版）。

- 设计稿：[AppIcon-source.svg](AppIcon-source.svg)，100×100 坐标的矢量原稿，以后改图标从这里改。
- 原图：[AppIcon-source.png](AppIcon-source.png)，1024×1024、不透明 PNG，与实际图标相同。
- 实际图标：[AppIcon.png](../Assets.xcassets/AppIcon.appiconset/AppIcon.png)，1024×1024、不透明 PNG。按矢量稿的同一套坐标以 4 倍超采样绘制后缩到 1024，不预裁圆角（系统加圆角）。
- 配置不变：`AppIcon.appiconset` 单一 iOS 通用 1024 图，主 App 指定 `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`。
- 视觉：深色底（#08080B，底部有一圈很淡的蓝紫光晕）；一个圆角玻璃质感的 T，横笔是空的、竖笔装着紫→青渐变的发光液体（#9B8CFF→#36D7F5），液面高度表示还剩多少；T 外沿一道 40% 白色细描边，横笔左上一道高光。
- 来源：Claude 设计画布第三轮“T 字标”六个方向里本人选中；本人要求高级感、用 Token 的字母 T 来做。
- 1024 图 SHA-256：`4b6086754274556ac8ee91d8657ec9f7ff2e5e506c9859a8b60959205576ec6c`。
