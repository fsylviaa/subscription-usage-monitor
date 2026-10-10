# 测试入口

共享 Scheme `SubscriptionUsage` 包含两个测试目标：

- `SubscriptionUsageTests`：`Unit/` 内的单元／集成测试，由 App 承载。当前检查根视图能加载并布局，以及 `AccountStoreTests` 的隔离文件持久化、单账户更新、顺序、无额度状态和失败保护；`CredentialVaultTests` 检查隔离 Keychain 条目的保存、替换、删除、命名空间、属性与故障恢复。
- `SubscriptionUsageUITests`：`UI/` 内的界面测试，检查无账户页、顶部操作同排、额度／设置往返与当前入口、未接入操作禁用及退出后重启，并保存页面截图。

在 Xcode 按 `⌘U` 执行全部测试，命令行步骤见[根 README](../README.md)。

后续去敏固定样例放 `Fixtures/`，替身放 `TestSupport/`，需要时再创建并加入对应测试目标。样例资源只归测试目标，不打入 App，不读真实授权、不访问真实账户存储、不发送系统通知。当前测试不查询网络、无需 Codex 登录。

T04 使用每个测试独立创建并清理的临时目录，以及 `example.invalid` 下的人工邮箱和虚构用户／查询账户标识。账户存储实例重新创建后读回同一文件；不依赖内存缓存。命令及固定输入的实际结果见[根 README](../README.md)及[T04 验收](../docs/mvp任务清单/记录/T04-验收.md)。

在实体 iPhone 上用 ⌘U 时，两个测试 target 与 App 共用 `Config/Signing.xcconfig` 中的本机签名入口；手机需解锁并保持连接。模拟器无需开发团队。T04 的默认验收由开发者执行测试并提交易读结果，用户不必自行运行测试或排查构建错误。

T05 的 `CredentialVaultTests` 为每项测试生成唯一 Keychain service 与 UUID，只写运行时生成的虚构授权包。结束时逐条清理自己的条目，不访问正式 service、不枚举/清空其他 Keychain 数据。真实 Keychain 存取与属性核对使用系统实现；临时不可读、更新和删除失败通过受锁保护的系统调用包装器注入状态码，恢复后再从真实测试条目核对。日志与断言仅报告匹配/存在与否，不打印包内容。此处模拟故障不等于真机重启后未首次解锁的自然事件验证。
