# 页面落点

`QuotaView.swift` 为额度无账户／已绑定身份页面及顶部操作，`SettingsView.swift` 为设置分组入口；`Sources/App/RootView.swift` 组装底部导航及共享连接弹层。

T07 的三个连接按钮共用 `CodexConnectionFlow`：新鲜网络检查、申请一次性代码、安全保存临时事务、主动复制和系统默认官网打开。低分／未知不申请，取消阻止迟到结果，重试等待旧工作结束；T08 增加本次事务的结果领取、核验与正式账户保存；核验失败不写账户。`CodexConnectionView` 负责简短反馈和代码步骤，采用系统浅深颜色，等待／失败为轻量弹层。

`CodexConnectionUITestSupport` 仅在 Debug 且显式 UI 测试启动参数下用固定数据、内存替身及专属临时文件；没有产品开关或菜单，Release 不包含替身。T08 仅首账户；保存后显示身份及“尚未获取额度”，暂禁再次连接，重复连接/多账户由 T16/T18 接入。其余未接入操作仍禁用。完整分工见 [项目结构](../../docs/project-structure.md)。
