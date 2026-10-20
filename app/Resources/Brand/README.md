# 当前 App 图标与名字

2026-10-20，本人选定 App 显示名“TokenLeft”和“刻度 T”图标（[决定 D-87](../../docs/decisions.md)，任务 T122）。取代 D-70 的“Token 仪表盘”与彩虹仪表图标；旧图标保留在 Git 历史（951eb63 定稿版）。

- 设计稿：[AppIcon-source.svg](AppIcon-source.svg)，100×100 坐标的矢量原稿，以后改图标从这里改。
- 原图：[AppIcon-source.png](AppIcon-source.png)，1024×1024、不透明 PNG，与实际图标相同。
- 实际图标：[AppIcon.png](../Assets.xcassets/AppIcon.appiconset/AppIcon.png)，1024×1024、不透明 PNG。按矢量稿的同一套坐标以 4 倍超采样绘制后缩到 1024，不预裁圆角（系统加圆角）。
- 配置不变：`AppIcon.appiconset` 单一 iOS 通用 1024 图，主 App 指定 `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`。
- 视觉：深灰底（#19191C）；象牙白（#F5F1E8）圆角横笔，竖笔切成四格，最上面一格熄灭（#34343A）、下面三格亮着，表示用掉一格、还剩三格；只用两种颜色。
- 来源：Claude 设计画布第三轮“T 字标”六个方向里本人选中；本人要求高级感、用 Token 的字母 T 来做。
- 1024 图 SHA-256：`c57deeb530bc9889cd1a4565718012dbbe7793df0d4f2e973b72520f3cee4f6a`。
