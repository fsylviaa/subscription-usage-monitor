# 测试入口

共享 Scheme `SubscriptionUsage` 包含两个测试目标：

- `SubscriptionUsageTests`：`Unit/` 内的单元／集成测试，由 App 承载。当前检查根视图能加载并布局，以及 `AccountStoreTests` 的隔离文件持久化、单账户更新、顺序、无额度状态和失败保护；`CredentialVaultTests` 检查隔离 Keychain 条目的保存、替换、删除、命名空间、属性与故障恢复。
- `SubscriptionUsageUITests`：`UI/` 内的界面测试，检查无账户页、顶部操作同排、额度／设置往返与当前入口、未接入操作禁用及退出后重启，并保存页面截图。

在 Xcode 按 `⌘U` 执行全部测试，命令行步骤见[根 README](../README.md)。

后续去敏固定样例放 `Fixtures/`，替身放 `TestSupport/`，需要时再创建并加入对应测试目标。样例资源只归测试目标，不打入 App，不读真实授权、不访问真实账户存储、不发送系统通知。默认测试不查询网络、无需 Codex 登录。T06 的真实取分需开发者显式开启，见下文。

T04 使用每个测试独立创建并清理的临时目录，以及 `example.invalid` 下的人工邮箱和虚构用户／查询账户标识。账户存储实例重新创建后读回同一文件；不依赖内存缓存。命令及固定输入的实际结果见[根 README](../README.md)及[T04 验收](../docs/mvp任务清单/记录/T04-验收.md)。

在实体 iPhone 上用 ⌘U 时，两个测试 target 与 App 共用 `Config/Signing.xcconfig` 中的本机签名入口；手机需解锁并保持连接。模拟器无需开发团队。T04 的默认验收由开发者执行测试并提交易读结果，用户不必自行运行测试或排查构建错误。

T05 的 `CredentialVaultTests` 为每项测试生成唯一 Keychain service 与 UUID，只写运行时生成的虚构授权包。结束时逐条清理自己的条目，不访问正式 service、不枚举/清空其他 Keychain 数据。真实 Keychain 存取与属性核对使用系统实现；临时不可读、更新和删除失败通过受锁保护的系统调用包装器注入状态码，恢复后再从真实测试条目核对。日志与断言仅报告匹配/存在与否，不打印包内容。此处模拟故障不等于真机重启后未首次解锁的自然事件验证。


T06 的 `NetworkScoreCheckerTests` 用隔离传输替身检查临界分数、未知、HTTP 失败、取消迟到及每次重取，不访问真实网站或账户。`NetworkScoreLiveTests` 默认跳过，仅在测试进程环境 `T06_LIVE_NETWORK_CHECK=1` 时从执行设备访问指定评分链；只输出最终分数及允许/阻止，不输出出口地址、请求 URL 或响应原文。开发者将实际设备结果单列，不能用固定输入通过冒充真实取分。


T07 的 `CodexDeviceAuthorizationTests` 和 `CodexConnectionFlowTests` 各 17 项，默认不联网；涵盖协议、临时 Keychain、评分门槛、保存／取消交错、到期、主动复制及官网打开。`CodexConnectionUITests` 的常规 3 项使用显式 Debug 启动参数，仅显示 `TEST-CODE`，覆盖三个入口和简短结果。截图只收集固定样例；正式产品没有场景选择器。

真实检查单列：`CodexConnectionLiveTests` 仅在测试环境 `T07_LIVE_CONNECTION=1` 时运行，从设备当前网络按指定来源取分；只有 >50 才实际申请代码、核对真实剪贴板和系统 HTTPS 打开。代码只进随机测试 service 临时条目，结束精确删除；不打印代码或保存真实截图。`testRealDefaultBrowserHasOfficialPage` 仅在 `T07_LIVE_BROWSER_VERIFY=1` 时只读核对当前前台浏览器的官方域名和登录／设备确认内容，不指定浏览器，不填写或提交账户资料。普通 ⌘U 跳过以上真实检查。


T09 的 `CodexLoginRecoveryTests` 10 项覆盖安全恢复、重新评分、交换不重放、到期清理、取消迟到和旧账户保护；协议及身份测试增加 7 项内部失败分类。`CodexLoginCompletionUITests` 增加 4 项固定场景，显示 TEST-0001/0002 与 example.invalid，使用独立临时目录，无正式场景选择器。到期场景仅把测试代码设为 6 秒，正式协议期限不变。

真实检查必须显式开启：`T09_LIVE_CANCEL=1` 运行 `testT09RealCancellationPreservesSavedAccountAndAllowsFreshCode`，使用真实网络评分和官方设备码、独立临时存储，正式账户/授权仅布尔比较，未提交官网确认。用户本人完成再次官网确认时使用 DEBUG 参数 `--t09-live-ui --t09-live-run-id <规范 UUID>`；全部生产核验照常，账户路径为 App 临时目录 `T09-live-UUID/accounts.json`，Keychain 基础 service 为 `T09.live.UUID`。错误参数不回退正式存储。

真实重开需 `T09_LIVE_REOPEN=1` 与 `T09_LIVE_RUN_ID=<相同 UUID>`；真实保存核验需 `T09_LIVE_SAVED_ACCOUNT=1`，只读该独立账户并请求官方核验；再设 `T09_LIVE_CLEANUP=1` 则在核验通过后精确删除本次独立账户及凭据。先跑页面重开，再核验/清理，最后无参数普通启动恢复正式账户。两项均不记录真实身份截图、一次性代码或 token。


T10 新增 `CodexLoginInterruptionTests` 15 项与 `CodexLoginTransactionRecoveryTests` 16 项：使用真实独立 Keychain 重建 reader，覆盖三个安全阶段、不明兑换、到期、坏阶段、取消迟到读取／写入、正式账户残留、重复返回、网络门控与后台暂停。默认不联网。新增三项 `testT10...` UI 测试使用 `--t10-isolated-ui` 和 `--t10-run-id`，专属 Application Support/T10-ui-UUID 与 T10.ui.UUID；结束以 `--t10-reset-storage` 精确清理。

真实 T10 使用 DEBUG 参数 `--t10-live-ui --t10-live-run-id <规范 UUID>`，目录 Application Support/T10-live-UUID，基础 service T10.live.UUID。`testRealT10PendingCodeSurvivesWebsiteReturnAndRelaunch` 需 `T10_LIVE_PENDING_REOPEN=1` 与 `T10_LIVE_RUN_ID`，真实评分通过后申请并验证官网返回／退出重开保留原代码；默认取消收尾，设 `T10_LIVE_KEEP_PENDING=1` 可留给本人确认。后续 `testRealT10IsolatedAccountSurvivesRelaunch` 需 `T10_LIVE_REOPEN=1`；`testT10IsolatedSavedIdentityAndCleanup` 需 `T10_LIVE_SAVED_ACCOUNT=1`，可加 `T10_LIVE_CLEANUP=1`；仅清理指定验收用 `testT10CleanupIsolatedRun` 与 `T10_LIVE_CLEANUP_ONLY=1`。均使用相同 UUID，原正式账户／授权只作布尔核对，不输出真实身份或秘密，不导出真实截图。


T11 的 `CodexUsageParserTests` 使用源码内人工 JSON、`example.invalid` 账户和固定时间，纯解析五类验收输入，并覆盖非法数值／类型、冲突账户、窗口歧义和额外字段；领域明确不限量不产生百分比。没有网络、文件写入、Keychain 或正式账户访问。专项复验可只运行 `CodexUsageParserTests`；测试代码只编入测试目标，不增加 App 验收页面。实际输入输出和运行数量见 [T11 验收](../docs/mvp任务清单/记录/T11-验收.md)。

T12 的 `CodexQuotaServiceTests` 覆盖首次自动查询、响应后成功时间、网络门控、缺失字段、失败保留、取消、身份变化、旧文件兼容及快照保存读回；默认使用人工 JSON 与独立目录。`CodexQuotaUITests` 使用 DEBUG `--t12-isolated-ui` 的 success／partial／blocked 场景及唯一 `--t08-run-id`，无网络、无正式账户或钥匙串访问。hosted 单元测试的 App 主场景自动使用空隔离流程，阻止启动副作用。

`CodexQuotaLiveTests` 仅在 `T12_LIVE_QUERY=1` 时读取本 iPhone App 正式登录，执行真实 T06 检查和 usage 主请求，并将成功快照写回同一账户；不读桌面授权，不续期或修改凭据。传输记录器只在内存中对照同次平台响应，日志仅输出数值、窗口、时间、HTTP 状态与固定阶段，不输出身份和秘密。`T12_LIVE_REOPEN=1` 才运行普通真实页面重开检查。默认不启用这两项；实际证据见 [T12 验收](../docs/mvp任务清单/记录/T12-验收.md)。

T14 的 `CodexCredentialRenewalTests` 18 项使用固定时钟、独立真实 Keychain 与故障注入，覆盖续期、401 有界恢复、保存失败重试、防重放、并发、取消及旧包保护；`CodexIdentityVerifierTests` 的 5 项 T14 测试使用内存生成 RSA 公私钥，核验签名、绑定、可选旧身份与到期时间。默认不联网、不访问正式账户。

`CodexCredentialRenewalLiveTests` 仅在 `T14_LIVE_QUERY=1` 时使用本 iPhone App 的正式授权和生产续期路径，先执行 T06 评分，查询与保存实际套餐／适用额度；接近到期时可能真实更新本 App 授权，不能再断言凭据永远不变。只报告身份匹配、成功时间、期限和是否发生续期，不打印秘密；不读电脑授权。当前真实查询与普通重开通过，未发生自然续期；后续 T54 必须区别每次真实续期及同次成功查询，不能以默认隔离测试代替。


T15 在 `CodexQuotaServiceTests` 中增加 6 项具名启动恢复检查：登录恢复挂起时先显示已存账户、无账户仍防止并发连接、首次查询等待及失败的无数据语义、旧版缓存失败保留、恢复后成功保存再读取、错作用域拒绝展示。均使用独立目录和受控输入，不访问真实网络或正式授权。

页面验收复用 `--t12-isolated-ui` 和唯一 `--t08-run-id`；只在该隔离入口追加 `--t15-delay-login-read`（挂起登录恢复）、`--t15-offline`（评分不可用）、`--t15-read-only`（单独检查未获取状态的本地读取）。生产入口没有这些选项或页面。旧页面夹具已改为同进程重复返回相同授权包，符合 T14 的替换保护检查。

`T15_LIVE_RESTORE=1` 显式启用 `testT15RealSavedAccountRestoresWithNetworkUnavailable`，只读手机正式账户文件，以受控断网验证两次恢复相同；计数断言网络检查与正式授权读取均为 0。它不是系统飞行模式实测，也不替代真实周／五小时额度验收；后者按用户安排留到多账户增删就绪。

## T16 多账户隔离验收

`CodexAccountBindingStoreTests` 覆盖独立凭据追加、提交后恢复防重复、不同登录并发、连续六次完整连接、B 失败保持 A、取消 B、B 登录中断恢复，以及多个未获取账户重开依次补齐且后续成功不清除前序失败。用随机目录和钥匙串 service，服务端身份与数值全为样例；真实存储、查询解析与流程代码照常执行。

`--t16-isolated-ui success|failure --t16-run-id <UUID>` 仅 Debug 生效，使用同一 UUID 可重开对应隔离场景。UI 检查两列表顺序、两账户不同值、失败账户归属、六账户滚动及重开；不触达正式账户或网络。`T12_LIVE_REOPEN=1` 的已有普通真实重开检查可另行确认原正式账户未受影响，不代替真实双账户验收，也不补做已延期的五小时真实查询。

T16 连接入口修正：`CodexConnectionFlowTests` 验证未选平台零网络／零登录申请、选择后单次门控和低分阻止。`CodexConnectionUITests` 验证短弹层、上拉吸附、重开复位、四个入口及原登录失败／取消；`--t16-platform-grid-overflow` 仅 Debug 生成重复图标以验证网格溢出和固定标题，不代表接入其他平台，Release 不包含此参数。`T16_LIVE_PICKER=1` 才执行普通真机弹窗检查，只开合与上拉，不选择平台、不拍真实账户截图，也不补做延期的真实额度核验。


## T17 排序验收

`CodexAccountBindingStoreTests` 的四个 `testT17…` 使用独立目录与钥匙串，覆盖三账户局部／首末移动、完整数据和授权不变、排序后新增及重开、真实文件故障重试、保存前不发布及并发入口阻止。不会联网或核对正式账户余额。

页面复用 `--t16-isolated-ui success --t16-run-id <UUID>`；`order-failure` 只在这一隔离入口的首次排序注入保存失败，以验证保留旧序和再次拖动恢复。`testT17DragOrderAcrossPagesReopenAndAppend` 与 `testT17FailedDragRetainsOrderAndRetrySaves` 验证原生把手、两页一致、重开及追加。

`T17_LIVE_ORDER=1` 才执行 `testT17RealAccountOrderPersistsAndOriginalOrderIsRestored`，只移动本机已保存的真实账户、比较页面身份顺序与重开，再恢复原顺序；不核对真实余额，不输出真实身份或主动导出真实截图。手机不足两个账户则明确跳过，不记通过。延期的五小时真实查询仍等多账户增删就绪。


## T18 添加入口重复连接验收

`CodexAccountBindingStoreTests` 的 `testT18…` 使用真实隔离 Keychain／文件和固定验证结果，覆盖重复更新与移动后位置、成功重开、新凭据及作用域查询、取消／核验失败、凭据及文件写入失败、同作用域查询失败保留旧值旧时间、身份或作用域变化清空旧值、邮箱大小写、演示隔离、旧凭据清理失败重试以及历史重复行合并。

`CodexQuotaUITests/testT18DuplicateLoginKeepsPositionAndCountAfterReopenAndCancel` 使用 Debug `--t16-isolated-ui duplicate --t16-run-id <UUID>`：先添加 A/B，再以新授权连接 A，检查只两条原位置、重开一致、取消不改数据。固定样例与正式账户隔离，不把模拟额度作为真实五小时核对；本人真实重复登录按 [T18 记录](../docs/mvp任务清单/记录/T18-验收.md)另验。


## T17 异高卡片连续换位回归

`RootViewTests/testT17UnequalHeightUIKitMovementHoldsThenReversesWithoutOscillation` 在隔离窗口中承载无额度短卡与两张演示高卡，重放七个停留位置各 30 次 ±0.5 点移动，核对稳定目标及实际布局，再验证下移、连续跨项、主动反向、取消不保存和松手仅保存最终位置。另两项 `testT17StableBoundaries…`、`testT17CrossingDeadband…` 覆盖等高／异高／大高度差与边界微动；测试不查询真实余额。

页面回归沿用 `testT17DragOrderAcrossPagesReopenAndAppend`、`testT17FailedDragRetainsOrderAndRetrySaves`、`testLongDemoListScrollAndDragToTop`，新增 `testT17LongDemoListDragFirstToBottomAndReopen` 验证反向边缘滚动和重开。结果见 [T17 修复记录](../docs/mvp任务清单/记录/T17-验收.md)。


## T22 迟到结果保护

`StaleAccountResultTests` 使用明确的开始／释放闸门，刻意让请求不配合取消：先挂起旧结果，完成取消、删除或新连接，再释放旧结果。七项测试覆盖迟到登录、旧额度覆盖新连接、删除后查询、删除清理中断时的续期／核验、重复添加清理中断时的续期／核验、取消刷新，以及页面删除无需等待旧请求。续期的响应与核验两个提交阶段分别检查。

每项重新创建文件 reader 和独立 Keychain reader，逐字段比较未操作 C 的身份、顺序、额度及成功时间。全部使用随机 `T22.tests.UUID` 命名空间、example.invalid 人工身份、固定时钟及假 HTTP 传输，不查询真实额度、不读取正式授权；不会因真实五小时核对延期而默认启用任何 live 测试。页面回归沿用现有隔离添加／重复连接／演示管理入口；Release 没有新增测试入口。

## T23 卡片专项

复用 T11 解析、T12 套餐／失败保护与已有缺窗口页面检查；新增三项 `CodexQuotaUITests/testT23…` 核验浅深双账户归属、0%／100%／70%／20% 的剩余标签与条形语义、动态套餐常显、未知／不限量无条形、Free 无占位，以及刷新失败保持旧值旧成功时间。

`--t23-card-fixture limits|states light|dark` 仅 Debug，直接输入内存领域样例并使用独立外观偏好，不读写正式文件、Keychain 或网络。不限量仅验证渲染领域状态，不表示 Codex 接口已识别出不限量，更不能从 credits 或缺字段推导不限量。普通演示模式没有新增这些样例或入口。`--t12-isolated-ui t23-cached-failure` 复用原独立临时目录与假传输，第一次成功、后续请求失败；正式查询逻辑不变。真实双账户余额仍按用户要求延期。

T23 大字号专项优化：`testT23AccessibilityLayoutUsesFullWidthIdentityAndSeparatesResetTime` 使用既有纯内存 `limits` 场景，在辅助字号最小／最大两档与浅深四种组合中检查套餐／身份使用完整内容宽度、重置时间在条形下方、两项余额可见及账户菜单可点击。普通字号沿用原两项卡片检查，并将其四张截图与 `c1a8999` 的同模拟器原图比较（仅排除系统状态栏时钟）。系统字号实时切换另外通过模拟器 `content_size` 验证，并恢复原值；不修改真实手机字号或添加产品设置。


## T24 详情与重置时间

`CodexQuotaServiceTests/testT24CrossingEachResetOnlyChangesDisplayAndPreservesStoredObservation` 使用隔离文件、假传输与测试时钟，从五小时重置前一秒推进至两个窗口各自的重置时刻及之后；核对展示状态、剩余值、原成功时间、文件字节与重读结果，时间展示不新增查询或网络评分。真实五小时余额仍不启用。

三个 `CodexQuotaUITests/testT24…` 检查重复展开／收起后标题及额度的位置、下张卡片位移、两个账户详情归属、浅深重置显示、缺失／已到点状态和最大辅助字号可滚动读详情。复用 Debug 纯内存 `--t23-card-fixture times`，时间样例只在隔离入口存在，不进入产品演示模式。旧值失败、从未获取、Free、未知额度和排序使用既有回归测试。

动画过程中间帧必须另验，不能把动画结束后的 UI 断言当作无回弹证明。本次模拟器录像以固定文字区域逐帧比较，保留原版缺陷、修复后录像与数值摘要；最终标题、身份及两项数值区域位置稳定。手机页面与构建结果、用户步骤见 [T24 验收](../docs/mvp任务清单/记录/T24-验收.md)。

## T26 全部刷新与部分失败

`CodexQuotaServiceTests/testT26…` 六项使用 `T26BatchFixture` 的随机临时目录、人工账户与合成授权，经过正式 `CodexQuotaService` 的网络检查／解析／保存，覆盖部分失败及全部范围重试、低分与未知评分、最多三户并行、五户取消与迟到检查、慢账户不阻塞成功、删除不复活。没有真实网络或正式 Keychain 读取。

`CodexQuotaUITests/testT26…` 两项用 Debug 专用 `--t26-isolated-ui partial|blocked|ui-cancel` 验证页面按钮、各户新旧值及时间、整批重试和迟到检查取消；不加入产品设置。`LaunchTests/testT26DemoToolbarUpdatesEveryCardAndPersistsOnReopen` 走已有演示模式验证用户亲验路径、空列表刷新禁用及结果重开保持；既有单卡／删除／关闭演示回归使用 `testManagementDemoMenuClearAndReopen`。结果见 [T26 验收](../docs/mvp任务清单/记录/T26-验收.md)。真实五小时余额仍延期。


### D-60 已登录账户刷新反馈修正

`testD60…` 验证手动全量／单卡的原生转圈、各户独立停转、固定标题／身份／卡片位置、深色最大辅助字号，以及自动触发成功无提示／失败才提示。自动触发由Debug `--t26-auto`显式调用，**不代表T27前台生命周期已接入**。`--t26-dark`仅用于隔离外观，不更改正式偏好。使用可访问标识查询，iOS将该转圈报告为ActivityIndicator。

`testT26BlockedFailureCanCloseWithoutChangingCards`替代旧检查取消页面测试；普通刷新不再提供取消按钮。T26内部取消测试仍用于验证系统中断和旧结果保护，不作为产品取消入口。登录弹层的查询／取消回归沿用`testQueryProgressStaysWithItsOriginAndDoesNotOfferFailureClose`，仅更新其已有卡片重试阶段的预期。


### T59 下拉全量刷新

RootViewTests新增4项：真实滚动控件的门槛／松手／收回／单次震动调用、禁用及中断、静态圆圈缩放上限与原生回弹、正式列表承载视图的浅深截图和回调。UI新增2项用真实触摸手势验证轻拉不触发、充分下拉松手全量刷新、刷新中再拉不重复及部分失败／全量重试。全部用隔离演示或合成身份，不执行真实五小时查询。自动化可验证轻震调用，实际触感由用户亲验。

2026-10-11 D-62修订：顶部全量刷新按钮已移除，相关页面测试改为真实下拉操作；空页及双卡布局检查按钮不存在、连接入口仍在标题右侧。静默查询用连接入口的既有启用状态观察结束。下拉反馈改用heavy，单手势调用次数及收回规则沿用T59验证；真实触感待用户反馈。


## T27 前台生命周期专项（2026-10-11）

`CodexQuotaServiceTests.testT27…`核对冷启动、缓存先显示、短时间重复返回、非活跃启动、空账户、失败旧值及登录往返；`CodexLoginInterruptionTests.testT27ColdLoginResumesWhileExistingAccountQueryWaits`核对慢刷新不挡登录恢复。新测试包含真实服务的评分／解析／存储路径，但使用合成响应，不能当作真实平台余额证据。

页面测试用`--t26-isolated-ui ui-foreground --t27-lifecycle`，从RootView实际生命周期触发，无定时器代触发；两户旧值90%／70%在启动及两次主屏幕往返后依次成为55%／50%／45%。`blocked`场景验证自动失败及关闭。原T26固定输入页面专项目的是验证手动反馈，因此其隔离工厂默认关闭前台触发；只有`--t27-lifecycle`显式启用，正式App始终启用，无产品设置。演示管理回归仍使用真实前台触发，重开预期由“旧值永久不变”改为“身份持久保存后自动更新”。

测试目录、授权与正式账户隔离；显式live测试默认跳过，用户要求的真实五小时额度对照仍延期。执行与失败历史见[T27验收](../docs/mvp任务清单/记录/T27-验收.md)。

## T28～T30 连续专项（2026-10-11）

T28在CodexQuotaServiceTests、StaleAccountResultTests中验证自动／手动／单卡／全部在途复用、目标卡片反馈、其他账户独立成功、实际登录完成后旧成功或失败拒写；T29验证关闭后不重现及原单卡／全量重试范围。对应UI测试用既有T26临时夹具执行，不影响正式账户。

T30的四项功能测试覆盖冷后台只恢复缓存（登录事务读取0次）、网络评分50阻止实际查询、前后台合并、30分钟目标与不推迟既有请求，以及去敏记录重读。隔离测试写入的system标记仅验证序列化，不证明自然执行。

两项`testT30SystemDebug…`默认跳过，必须给UI测试Runner设置`T30_SYSTEM_DEBUG=1`。它们使用`--t26-isolated-ui`、`--t27-lifecycle`、`--t30-background-debug`，App退后台后由开发者通过真机LLDB执行Apple官方BGTaskScheduler调试触发命令；测试本身不会调用私有API，Release也没有触发入口。记录中必须出现debug、wasInBackground=true及结果，然后返回前台单独验证第三次查询。前台调试回调不能冒充后台通过。

最终自然观察来自普通正式运行的独立BackgroundRefresh记录，留到T53核验。真实五小时余额及相关真实账户对照仍暂缓；以上不访问正式授权、不代替真实额度验收。


## T35 组件同步与失败发布（2026-10-11）

`WidgetSnapshotTests/testT35…` 验证失败与可信测量分离、重读／补发保持、成功清除、Free／首次失败、排序／指定账户归属、重连清除及迟到成功／失败拒写；`CodexQuotaServiceTests/testT35…` 经过正式网络门控、查询服务、保存和前台／后台流程，用虚构响应验证先保存再请求换图。临时文件独立，默认不访问真实额度或正式授权。

`CodexQuotaUITests/testT35DesktopUsesIsolatedSharedSnapshot` 需要预先放置两种组件并在 UI Runner 设置 `T35_WIDGET_DESKTOP=1`，默认跳过；使用明确 Debug 参数 `--t35-widget-fixture <scenario> <UUID>`。主App账户文件在独立临时目录；组件样例位于 App Group 的 `Widget/T35-validation-<UUID>/snapshot.json`，不改生产 `first-account.json`。只有 Debug 扩展在存在合法会话标记时读取样例；退出检查通过 `cleanup` 移除标记／样例，并请求恢复普通组件。普通 Debug 启动也清除中断遗留；Release 不读取此标记或提供此入口。不得将此开关写入用户设置。手机必须事先放置小号和中号各一个，截图需复核真实尺寸；自动化不修改用户桌面布局。

桌面检查记录单卡／全量／前台、失败旧值、排序、删除、作用域变化、全部删除及后台路径的实际图片。`background` 场景是直接调用路径，不是系统后台执行。`testT35SystemBackgroundPublishesToDesktop` 默认跳过，只有 UI Runner 的 `T35_SYSTEM_DEBUG=1` 时启用：准备相同隔离样例并退后台，由开发者用 Apple 官方调试命令触发 BGTaskScheduler，核对 `background=true`、两户成功及桌面换图；不可用它代替 T53 自然事件。

实际运行、图片、请求／观察时间与未通过项见 [T35验收](../docs/mvp任务清单/记录/T35-验收.md)。

### T35 长按菜单尺寸回归

`CodexQuotaUITests/testT35ResizeFromContextMenu` 默认跳过；只在明确授权调整组件尺寸时设置 UI Runner 的 `T35_WIDGET_RESIZE=1`。默认检查已有小号 → 系统长按菜单 → 中号，`T35_RESIZE_TARGET=small` 检查反向。采用T35独立样例，不修改正式账户文件、授权或系统保存的账户选择；正常结束清理样例。检查SpringBoard实际组件宽度和目标尺寸数量，菜单消失不算通过。测试会改变所测组件尺寸，不能用来宣称未改桌面布局；源码中的230点只用于当前手机／模拟器的尺寸识别，不是产品布局尺寸。长按菜单的系统动画空闲等待可能各耗时60秒，保留失败和截图，不以增加等待伪造成功。

### T35 补齐两尺寸与固定账户桌面证据

桌面检查会自动双向查找已有组件所在页面，避免把打开App后返回的页面当作组件页面。`testT35SystemBackgroundPublishesToDesktop`要求小／中号均实际显示90%基线后才发出调试就绪信号；开发者触发系统后台任务，测试保持桌面并等待两种尺寸均采用55%，最长观察180秒，随后才回App核对后台完成结果。该观察窗口不是产品刷新时限，也不能代替T53自然调度验收。

`testT35PinnedAccountFollowsIdentityOnDesktop`仅在UI Runner的`T35_WIDGET_PICKER=1`启用。使用WidgetCenter读取已有组件的账户选择，只在隔离快照中让样例batch-1对应其中一个已选ID，不修改系统选择、正式账户或授权。需同时存在默认／无效选择回退实例和该固定账户实例；检查基线、排序、排序后刷新、失败及删除后的桌面截图。自动断言检查关键文字，实例位置及具体数据归属仍须目视复核，不能只凭测试返回成功就记两尺寸通过。结束清理隔离样例。样例ID在同一会话跨启动保持稳定；不存在已有固定选择时不可把默认回退当成固定账户通过。

T26共享夹具使用同一个初始化任务，所有并发读取等待完整账户列表，避免只看到部分样例账户。新增并发回归不涉及Release产品存储。早期模拟器配置UI探测与最终只读真机验证分开记录，不能将跳过或自动化失败记为产品通过。

### T35 后台链路诊断

明确启用的 Debug 隔离会话现在保存 `reload.request/return`、`timeline.begin/return` 和 `provider.read` 分段记录。记录位于对应 `T35-validation-<UUID>/trace`，一事件一文件，组件与App并发记录互不覆盖；只记录隔离额度，不记录正式账户或授权。`cleanup` 先输出当前会话记录供结果包保存，再移除标记与所有名称严格匹配 `T35-validation-<合法UUID>` 的隔离目录（含中断遗留），输出清理结果，并移除独立的 `tmp/T30-debug` 测试事件日志；不清理生产快照或系统账户选择。Release不包含该诊断能力。

UI Runner 可额外设置 `T35_FOREGROUND_CONTROL=1`：在后台观察结束、核对后台汇总后，用 `reloadOnly` 保留同一隔离共享快照，不查询、不重置账户，只在前台重新发出组件更新请求，再对照两尺寸桌面。此阶段单独截图／记录，绝不能算成后台画面已更新；后台观察失败仍保留失败断言。

`T35_OBSERVATION_SECONDS` 可显式扩大桌面观察窗口（默认180秒，范围30～2400秒），用于覆盖已取得系统日志里的较晚调度时间。记录实际窗口和请求／显示时间；测试窗口不成为产品时限，系统调试执行不成为T53自然后台。

## T61 小组件自主更新

`SharedAutomaticRefreshTests`使用临时目录验证迁移、损坏不回退、文件锁、App／组件并发查询、失败非成功及删除保护。跨进程Keychain和桌面通过`T61_WIDGET_ACCEPTANCE=1`显式启用`testT61WidgetFetchesWithoutAppQueryAndKeepsBothSizes`，沿用T35独立UUID显示目录；App保存虚构授权到专属T61测试service，组件读取后通过受控网络输入调用正式查询／解析／保存路径。验收结束按准确service清理虚构授权和目录，真实资料不变。该测试由App请求一次时间线机会，不代表自然后台调度或真实平台查询。

## T39 按预计重置时间安排提醒

`ResetReminderPlanTests` 检查可信身份／套餐及窗口时间，`ResetReminderSchedulerTests` 使用虚拟通知中心核对安排、实际回读、失败及异步交错，`ResetReminderNotificationTests` 只构造系统通知对象检查 UTC 时间、内容、非重复触发与隔离装配，绝不提交这些对象到系统。`ResetReminderIntegrationTests` 实际承载 RootView，使用隔离账户文件、偏好、许可和虚拟中心，检查首次读取不清理旧提醒、加载后自动安排、开关变化及文件不变。保留 T38 的 20 项权限单元测试和关闭状态的浅深 UI 回归。

普通 App 装配才注入系统中心；XCTest host、`--t*` 及 `--management-ui` 全部关闭系统调度，演示账户亦从规划输入排除。真实账户的待发请求及自然投递本次按用户指令延期；测试通过不能改写为真实手机通知通过。实际结果见 [T39 验收](../docs/mvp任务清单/记录/T39-验收.md)。

T39 真实只读补验：`ResetReminderNotificationTests/testT39ReadRealPendingRequestsAgainstSavedResetTimes` 仅在本人 iPhone 的 **Debug XCTest 宿主**显式设置 `T39_LIVE_READBACK=1` 才执行；模拟器或未启用默认跳过，不更改共享 Scheme。直接读取 App Group 已有账户文件并在内存解码，避免 `applicationStore.load()` 的迁移／组件发布副作用；读取系统原始待发请求，再逐条核对身份、内容、非重复触发和时间。只输出账户序号、真实／演示数量、上海时间和匹配结果；不输出邮箱、余额、内部标识、原文件或凭据。不申请权限、不添加／删除通知、不联网。缺少真实有效未来窗口时用例不通过，记录为验收准备不足，不能以0条吻合0条宣称通过。手机临时测试构建后恢复既有正式版普通入口。

## T62／T36面板与组件跳转

RootViewTests的T62／T36用例核对可信字段、稳定身份、非法URL、排序／同邮箱更新／删除、路由无查询副作用。CodexQuotaUITests核对两户面板、单户失败旧值、删除关闭、系统URL冷／热及缓存不等登录恢复。旧T24展开检查已按D-66改为面板交互。

实际桌面用例`testT36ActualSmallAndMediumWidgetTapColdAndBackground`需显式测试环境`T36_WIDGET_DESKTOP=1`，复用已有两尺寸，不改系统配置。DEBUG `--t36-desktop-fixture baseline <UUID>`用20分钟限时标记让实际组件无参数冷启动仍走隔离；后台和系统提醒关闭，结束必须用同入口`cleanup`清理。`T36_CLEANUP_CHECK=1`显式运行只读清理用例，仅核对标记与组件读路径，不读取正式账户／授权。Release没有该隔离入口，普通测试不启用桌面专项。报告、首次失败及手机事实见T62／T36验收。


## T42／T43 添加与选择账户教程

`LaunchTests` 的三个 `testT42…` 页面用例使用独立管理账户与偏好，验证指定单句、删除旧解释、额度／设置来源、双向滑动、两步关闭和完成、返回主屏幕后保持步骤、重进第一步、浅深和最大字号。`CodexQuotaUITests/testT42WidgetAndNotificationReturnDismissTutorialBeforeOpeningAccount` 使用原有两户固定输入，验证外部入口关闭教程并打开对应详情，不向系统发送通知。

`testT43AnimationDoesNotBlockPagingClosingOrBackgroundReturn` 验证动画中两来源的滑动、按钮与后台返回。`testT43SystemMotionPreferenceAnimationAndStaticKeyframes` 从系统设置实际切换REDUCE_MOTION，正常动画到结束、静态全部关键画面及最大字号均检查；teardown等待原值恢复，不修改通知权限。字体通过进程启动参数临时覆盖，App外观在隔离偏好中切换，不修改正式设置。

实际系统用例`testT43ActualSystemAddAndSelectNewWidget`仅在测试runner显式环境`T43_SYSTEM_WIDGET_FLOW=1`时执行，取代旧T42_WIDGET_ADD。复用T36限时隔离会话，在无本App组件的页面添加并唯一识别新实例，按实际系统搜索“订阅用量”、查看小／中号、添加、长按编辑、显示账户选第二个人工账号，确认结果并仅移除该临时实例。已有配置不作为测试编辑对象；无法唯一识别就停止。夹具清理注册XCTest teardown并等待空隔离页；后续可复用T36既有只读清理检查核对标记和正式路径，不读取正式账户／授权。

本次因说明句误匹配而遗留的已识别临时组件，按第2页实际0→1证据进行一次接续选择／移除；该一次性恢复分支已从最终源码移除。原失败与逐段通过保存在T43验收记录；不把一次接续写成整条添加链在同一轮重跑成功。完整系统层级与本机结果留忽略build目录，Git仅保存人工账户截图及去敏摘要。


T43弹窗布局修订：`testT43ContentSizedSheetsAndMatchingAnimationRegions`使用独立管理偏好，实测正常浅深下两页高度、正文至按钮间距、两页动画区域同宽同高与文字边界，截图供目视检查。高度／间距断言是回归检查容差，不是产品固定尺寸要求。滑动坐标随实际教程翻页区域变化，避免半屏弹窗时滑到背景；结合既有播放中导航／后台、最大字号及实际系统动态偏好用例，不运行系统添加组件用例。
