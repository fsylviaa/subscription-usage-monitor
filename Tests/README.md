# 测试入口

共享 Scheme `SubscriptionUsage` 包含两个测试目标：

- `SubscriptionUsageTests`：`Unit/` 内的单元／集成测试，由 App 承载。当前检查根视图能加载并布局；后续业务固定输入测试在此添加。
- `SubscriptionUsageUITests`：`UI/` 内的启动测试，检查 App 首次启动与退出后重启。

在 Xcode 按 `⌘U` 执行全部测试，命令行步骤见[根 README](../README.md)。

后续去敏固定样例放 `Fixtures/`，替身放 `TestSupport/`，需要时再创建并加入对应测试目标。样例资源只归测试目标，不打入 App，不读真实授权、不访问真实账户存储、不发送系统通知。当前测试不查询网络、无需 Codex 登录。
