# 共享展示数据

T32 提供 `WidgetSnapshot` 和 `WidgetSnapshotStore`，App Group 为 `group.com.pbpuw6l86s.SubscriptionUsage`，文件为容器内 `Widget/first-account.json`。T33 Widget Extension 编入这两个纯 Foundation 文件并使用同一组权限；账户投影 `Storage/WidgetSnapshotProjection.swift` 只属于 App。

快照只含当前有效首账户的本地 ID、展示身份、套餐及观测时间、额度状态、周／5 小时的明确额度语义及原成功／重置时间、演示标记。点击目标由同一份快照的本地 ID 派生，不含邮箱或授权。未知、不限量、真实零、尚未获取、已确认无适用额度、无账户分别保存；不会跳过尚未获取额度的首账户。

`AccountStore` 在可信账户文件提交后原子写入快照，读取时也修复中断后漏写的数据；共享写失败不会将已提交登录当成失败而回滚有效凭据。尽力清除失效共享文件，下次可信读取再重建；文件读取错误不伪装成空账户或成功。隔离 `AccountStore(fileURL:)` 默认不发布正式共享文件，测试显式注入独立路径。真机 App Group 检查也使用独立测试文件。

授权、凭据引用、远端作用域、原始响应和查询逻辑均不进入共享文件。T32 不创建组件页面，不实现系统 timeline reload（T35）、点击处理（T36）或失败样式收口（T37）。数据已准备不等于桌面画面已更新。

T33 增加 `QuotaWidgetContent.swift`：只读快照与小号视图。未知／不限量不画比例；绝对重置与最后成功时间取自快照，不因 timeline 日期更新而变化。视图使用现有 Design 颜色和 Codex 图标，基本浅深跟随系统。共享读取失败短显“刷新失败”，不伪装成无账户；完整账户查询失败样式留 T37。

## T60修订

快照保留 `account` 首项并增加有效 `accounts` 展示列表及 `listRevision`；旧单账户文件仍可读取。D-64取代原编号／按钮选择：系统配置按实例保存账户ID，`WidgetAccountQuery`只读取展示快照生成完整邮箱及套餐选项；默认选项动态跟随首项，指定ID从当前快照解析，排序不影响选择，移除后回首项。旧`selection-N.json`不再读写，配置中没有编号；无需清空原账户或迁移授权。

组件小／中号采用精简卡片，不显示时间、表面切换或刷新按钮；外观随App，无账户提供添加入口。发布成功后请求系统换图；隔离测试注入独立目录及无副作用更新回调。T32/T33原记录保留历史范围，当前交互以D-64/T60修订为准。

T64／T65：QuotaCardStyle保存稳定目录、表面上下文与动效策略；QuotaCardAmount只派生剩余，OriginalQuotaTrack复用于账户／详情／两尺寸。原组件无身份或时间。QuotaCardStylePreferences只保存独立card.style键，未知回original，App Group读取及WidgetCenter请求不改Intent.account；12款新样式渲染现由T66—T77准备，正式设置及宿主接入仍待T78—T81。


## T66—T77 共用原生渲染

`CardStyles/`（D-76起）：`CompactQuotaTheme`配色／背景／水印，`CompactQuotaBars`16款图形（2026-10-19 D-83／D-84／D-85 追加液态玻璃、薄荷新拟态、马卡龙粘土）（按准确比例裁出剩余）与油表，`QuotaStyledCard`账户卡／详情单窗口，`CompactQuotaWidget`小号／中号；旧第二阶段渲染器已删除。展示输入只读`WidgetSnapshot.Account`，不保存偏好。

四上下文共用未取整remainingFraction；未知／不限量无图形。组件全静态且无邮箱／时间；App仅本地图形放开既有容器的禁动画限制，系统减少动态或后台回静态。液体可见／前台才更新时间线，平均波面面积不变；水印不参加动画。`NativeQuotaRenderAudit`仅Debug显式`--lab-probe`或隔离测试环境`T78_HOST_MOTION=1`启用，计数只在内存，Release不包含。

T78正式Root设置选择／账户整卡已接入；T79 Codex详情额度卡已接入；Widget两尺寸新款宿主待T80—T81接入。开发者隔离入口只在Debug启动参数`--t66-native-lab`启用，跳过正式运行时、存储及发布；没有产品预览入口或调额／故障设置。已采用同一CodexBar路径及现有MIT许可（T102起平台标志改为Lobe Icons的OpenAI／Cursor，奇偶填充，见Resources/README.md）。

2026-10-15 T84（D-76）：目录改为12款改后样式＋霓虹派对`rave`共13款，删除原样式及`OriginalQuotaTrack`；默认彩色斜粒`skala`，已存`original`、缺失或未知值读取时都解析为彩色斜粒（不改写原值，App启动发布解析后的值到App Group）。账户卡、详情、组件不再有原样式分支；无账户组件显示“添加账户”。

2026-10-19 T120（D-85）：目录末尾追加第16款马卡龙粘土`clay`（不改变已有13款的存储值与顺序）。`CompactQuotaTheme`新增`ClayPalette`与粘土部件（`ClaySurface`、`ClayPlatformTile`、`ClayBubble`、`ClayPageBackground`、`ClayAddButtonLabel`），`CompactQuotaBars`新增粘土条（第一个窗口薄荷、其后蜜桃）。选中该款时额度页背景、＋按钮和底部栏也随之变色；其他样式与详情页其余部分不变。
