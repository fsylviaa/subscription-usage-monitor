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
