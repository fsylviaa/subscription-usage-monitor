# 页面落点

`QuotaView.swift` 为额度无账户页面及顶部操作，`SettingsView.swift` 为设置分组入口；`Sources/App/RootView.swift` 组装底部导航及共享连接弹层。

T07 的三个连接按钮共用 `CodexConnectionFlow`：新鲜网络检查、申请一次性代码、安全保存临时事务、主动复制和系统默认官网打开。低分／未知不申请，取消阻止迟到结果，重试等待旧工作结束；不读取或写入正式账户。`CodexConnectionView` 负责简短反馈和代码步骤，采用系统浅深颜色，等待／失败为轻量弹层。

`CodexConnectionUITestSupport` 仅在 Debug 且显式 UI 测试启动参数下用固定数据与内存存储；没有产品开关或菜单，Release 不包含替身。其余未接入操作仍禁用。完整分工见 [项目结构](../../docs/project-structure.md)。
