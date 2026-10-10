# 共享展示数据

T32 提供 `WidgetSnapshot` 和 `WidgetSnapshotStore`，App Group 为 `group.com.iceflying.SubscriptionUsage`，文件为容器内 `Widget/first-account.json`。未来 Widget Extension 只需编入这两个纯 Foundation 文件并使用同一组权限；账户投影 `Storage/WidgetSnapshotProjection.swift` 只属于 App。

快照只含当前有效首账户的本地 ID、展示身份、套餐及观测时间、额度状态、周／5 小时的明确额度语义及原成功／重置时间、演示标记。点击目标由同一份快照的本地 ID 派生，不含邮箱或授权。未知、不限量、真实零、尚未获取、已确认无适用额度、无账户分别保存；不会跳过尚未获取额度的首账户。

`AccountStore` 在可信账户文件提交后原子写入快照，读取时也修复中断后漏写的数据；共享写失败不会将已提交登录当成失败而回滚有效凭据。尽力清除失效共享文件，下次可信读取再重建；文件读取错误不伪装成空账户或成功。隔离 `AccountStore(fileURL:)` 默认不发布正式共享文件，测试显式注入独立路径。真机 App Group 检查也使用独立测试文件。

授权、凭据引用、远端作用域、原始响应和查询逻辑均不进入共享文件。T32 不创建组件页面，不实现系统 timeline reload（T35）、点击处理（T36）或失败样式收口（T37）。数据已准备不等于桌面画面已更新。
