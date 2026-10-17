# 资源

`Assets.xcassets` 含黑白灰强调色及 T13 额度页所用的 Figma 资源；正式 App 图标已由T63接入，见[品牌说明](Brand/README.md)。

- `DesignBg/Card/Elevated/Text/Secondary/Muted/Track/Line/Accent/AccentText`：原型 `design/figma-plugin/mono-palette.json` 的浅深配对值，随系统外观切换。
- `DesignCodex`／`DesignCursor`：T102 起为 Lobe Icons 的 OpenAI／Cursor 平台标志（见下方“T102 Lobe Icons 平台标志”），模板着色；只用于对应平台账户标识。
- 原 `DesignRefresh/Link/Chart/Settings/Clock/Close/Down/Up`（原型 ICONS 自绘矢量）已于 T100 删除：功能图标按 D-79 改用 Lucide，见下方“T99 Lucide 功能图标”。未使用页面截图充当界面或图标，没有远端临时资源依赖。
- 原型字号映射到 App 既有系统字体并随 Dynamic Type 缩放；界面布局按安全区自适应，未复制原型的状态栏和设备外框。

以上源文件位于工作区 `app` 的同级 `design` 目录，保持只读；实际运行资源已包含在本 App 仓库内。

## T45 实际素材许可（T102 起已不再采用，仅保留历史）

`DesignCodex.svg`与只读参考`CodexBar/docs/logos/codex-dark.svg`逐字节相同，SHA-256为`5c999792f6d26c9d14a197aa6e6c20f5af3def433473f7b66bd0d8c8a41cd8cf`；通过项目原型资源进入本App。采用的是平台标志SVG，不是CodexBar桌面库。完整上游MIT许可（Copyright (c) 2026 Peter Steinberger）原字节保存在[CodexBar-MIT.txt](Licenses/CodexBar-MIT.txt)，主App资源阶段打包，设置可离线阅读。其他仅研究参考没有作为依赖列入产品清单。

## T93 Cursor 图标（T102 起已替换，仅保留历史）

`DesignCursor.svg` 与只读参考 `CodexBar/Sources/CodexBar/Resources/ProviderIcon-cursor.svg` 逐字节相同，SHA-256 为 `01bac27782652bb9f607f35fac6359e639d6ade0f1a1a0b34d530a367e23ecd3`，与 Codex 标志同属 CodexBar 平台图标集（MIT，许可原文同上 `CodexBar-MIT.txt`），模板着色，用于平台选择弹层；卡片水印用同一路径的原生几何（`CursorMarkShape`）。

## T99 Lucide 功能图标（D-79）

`Lucide*.imageset`：取自 npm `lucide-static@0.460.0` 的 `icons/*.svg`（全部同一版本），路径原样保留，只把 `currentColor` 换成黑色并把描边参数（宽 2、圆头圆角）移到外层 `<g>`，资源设为模板着色，颜色跟随界面前景色与浅深。代码统一通过 `AppIcon`／`AppIconView`／`IconLabel`（`Sources/Features/QuotaView.swift`）调用。完整 ISC 许可原文与上游 `LICENSE` 逐字节相同（SHA-256 `1e7290b35280a048667bbf0ebabac1c7fd52a75300e8b2946ac165715997f2bc`），保存在 [Lucide-ISC.txt](Licenses/Lucide-ISC.txt)，设置“开源许可→Lucide”可离线阅读。

| 资源 | Lucide 名称 | 用途 |
|---|---|---|
| LucideCirclePlus | circle-plus | 额度页右上“连接账号”、“未连接账户” |
| LucideGauge／LucideSettings | gauge／settings | 底部“额度”“设置” |
| LucidePalette／LucideMoon／LucideBell | palette／moon／bell | 设置“卡片样式”“深色模式”“重置提醒” |
| LucideLayoutGrid／LucideCircleHelp／LucideShieldCheck／LucideInfo | layout-grid／circle-help／shield-check／info | “如何添加小组件”（设置及额度页）、“帮助与说明”、“隐私说明”、“开源许可” |
| LucideX／LucideRefreshCw／LucideEllipsis／LucideTrash2／LucideCircleAlert／LucideKeyRound／LucideCopy／LucideCheck | x／refresh-cw／ellipsis／trash-2／circle-alert／key-round／copy／check | T100 其余功能图标 |

## T102 Lobe Icons 平台标志（D-79）

取自 npm `@lobehub/icons-static-svg@1.95.1` 的 `icons/openai.svg`（SHA-256 `a595df6b423920c67a7f8f73c063e4bfb72d415948097b6cac063a2366bb5186`）与 `icons/cursor.svg`（SHA-256 `0cb51bddf264ae108926fd554c063ef40fc1aac3c5c921ddb39ad184e4e5d0ef`）。Codex 账户显示 OpenAI 标志，Cursor 账户显示 Cursor 标志。

- 图片资源 `DesignCodex.imageset/LobeOpenAI.svg`、`DesignCursor.imageset/LobeCursor.svg`：路径原样保留，只把 `currentColor` 换成黑色、去掉 `1em` 尺寸与标题，保留 `fill-rule="evenodd"`，模板着色；用于“连接账号”弹层、Cursor 浏览器登录等待页、“如何添加小组件”教程。
- 原生形状 `OpenAIMarkShape`／`CursorMarkShape`（`Sources/Shared/CardStyles/QuotaWatermarkShape.swift`）：同一路径转换为原生几何（圆弧转三次曲线；512 像素栅格与原 SVG 对比最大差 8/255），24×24 画布铺满框；填充一律用 `PlatformMarkShape.fillStyle`（奇偶规则），镂空不被填满；用于 13 款卡片水印、蓝条水印款卡片与小组件标题小标志。
- 完整 MIT 许可与上游 `lobehub/lobe-icons` 仓库 `LICENSE` 逐字节相同（SHA-256 `add9d7531d1b21646317a8958e38fc727506fa39d24bdecb44154d943c82753a`；npm 包内不含 LICENSE 文件，`package.json` 声明 MIT），保存在 [LobeIcons-MIT.txt](Licenses/LobeIcons-MIT.txt)，设置“开源许可→Lobe Icons”可离线阅读。
- 旧 CodexBar 平台标志（Codex、Cursor）已全部替换，产品中不再含 CodexBar 素材或代码，`CodexBar-MIT.txt` 已移出 App 与“开源许可”清单。`Sources/Providers/Codex` 中对 CodexBar 固定版本的引用只是字段契约核对说明，未复制其代码或素材。
