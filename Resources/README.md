# 资源

`Assets.xcassets` 含黑白灰强调色及 T13 额度页所用的 Figma 资源；正式 App 图标仍未制作。

- `DesignBg/Card/Elevated/Text/Secondary/Muted/Track/Line/Accent/AccentText`：原型 `design/figma-plugin/mono-palette.json` 的浅深配对值，随系统外观切换。
- `DesignCodex`：原型 `design/figma-plugin/revision-assets.js` 中的 Codex 标志 SVG 原字节，模板着色；只用于该平台账户标识。
- `DesignRefresh/Link/Chart/Settings/Clock/Close/Down/Up`：原型 `design/figma-plugin/revision.js` 的 ICONS 矢量定义及原描边参数，24 × 24 画布，作为本地模板资源使用。未使用页面截图充当界面或图标，没有远端临时资源依赖。
- 原型字号映射到 App 既有系统字体并随 Dynamic Type 缩放；界面布局按安全区自适应，未复制原型的状态栏和设备外框。

以上源文件位于工作区 `app` 的同级 `design` 目录，保持只读；实际运行资源已包含在本 App 仓库内。
