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
