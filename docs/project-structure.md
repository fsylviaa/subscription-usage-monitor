# 工程结构与依赖

T01 的基础脚手架说明，更新于 2026-10-10。运行步骤见[根 README](../README.md)，实际验证与待验事项见[T01 验收记录](mvp任务清单/记录/T01-验收.md)。任务状态以[项目进度](项目进度.md)为准。

当前工程只包含 SwiftUI 空壳页面和测试入口，启动及测试的实际结果以验收记录为准。登录、额度查询、账户管理、小组件、通知与后台更新均在后续对应任务接入；下文的目录分工不表示这些功能已经实现。

## 工程入口与配置

| 项目 | 当前配置 |
|---|---|
| 工程文件 | `SubscriptionUsage.xcodeproj` |
| 共享 Scheme | `SubscriptionUsage`；配置保存在工程的 `xcshareddata/xcschemes/`，随 Git 保存 |
| App target | `SubscriptionUsage`；仅 iPhone，使用 SwiftUI |
| 单元测试 target | `SubscriptionUsageTests` |
| UI 测试 target | `SubscriptionUsageUITests` |
| Swift 语言模式 | Swift 6 |
| 部署基线 | iOS 17.0；目前是工程基线，T02 已识别 iPhone 11 / iOS 26.5；真机安装与启动结果见 T02 验收 |
| 本次开发环境 | macOS 26.6.2、Xcode 26.6（17F113）、随 Xcode 提供的 Swift 6.3.3 |
| 本次模拟器环境 | iPhone 17 Pro，iOS 26.5（23F77） |

工程文件直接纳入 Git，无工程生成器或额外生成步骤。模拟器运行不依赖个人签名证书、电脑 Codex 登录状态或仓库外参考项目。iOS 17.0 的部署配置不等于已经在该系统版本完成运行验收；已执行的检查以验收记录为准。

## 目录职责

目录与 Xcode 工程中的分组对应。尚未实现的业务位置仅用简短 `README.md` 保留，不预建空服务、平台实现或独立包。

```text
app/
├── SubscriptionUsage.xcodeproj/   工程、targets 与共享 Scheme
├── Config/                       本机开发团队的可选配置入口
├── Sources/
│   ├── App/                      App 入口与根页面
│   ├── Features/                 后续各功能页面
│   ├── Domain/                   后续公共业务数据与必要接口
│   ├── Providers/Codex/          后续 Codex 登录、请求与解析
│   ├── Services/                 后续共用流程与系统能力
│   ├── Storage/                  后续本地数据与安全存储
│   └── Shared/                   后续 App 与组件共享的非敏感结果
├── Resources/
│   └── Assets.xcassets/          当前资源目录
├── Tests/
│   ├── Unit/                     单元及隔离集成测试
│   └── UI/                       启动和界面操作测试
├── docs/                         需求、技术依据、任务与验收记录
├── AGENTS.md                     项目执行规则
└── README.md                     开发及运行入口
```

| 位置 | 负责什么 | 后续落点与边界 |
|---|---|---|
| `Config/Signing.xcconfig` | App 的 Debug/Release 读取可选的本机开发团队 | 实际团队保存在被 Git 忽略的 `Signing.local.xcconfig`；不保存账户、证书或私钥；文件缺少时模拟器仍可用 |
| `Sources/App/SubscriptionUsageApp.swift` | SwiftUI 的 `@main` 入口，打开根页面 | 后续在此组装必要依赖、连接 App 生命周期，不直接承担平台解析 |
| `Sources/App/RootView.swift` | T01 的简洁空壳页面 | T03 起接入实际页面；当前不显示样例账户或伪造额度 |
| `Sources/Features/` | 额度、账户、设置、教程等页面及直接相关展示逻辑 | T03 及后续页面任务添加；页面调用业务能力，不自行管理授权秘密 |
| `Sources/Domain/` | 公共账户数据、额度语义及必要接口 | T04、T11 起添加；不依赖具体页面或 Codex 实现 |
| `Sources/Providers/Codex/` | Codex 连接、请求构建、响应解析与平台差异 | T07–T14 逐项添加；当前不建其他平台实现或完整多平台框架 |
| `Sources/Services/` | 网络检查、连接及刷新协调、系统提醒等共用流程 | T06 及对应后续任务接入；按实际需要添加，不预建通用框架 |
| `Sources/Storage/` | 本机账户元数据、最近成功快照与钥匙串访问 | T04、T05 起添加；普通数据与授权秘密分开保存 |
| `Sources/Shared/` | App 和小组件都需要的纯展示数据、必要格式化与非敏感快照约定 | T32 实现实际共享；不放密码、令牌、登录流程或钥匙串访问 |
| `Resources/` | 图片、颜色、图标和实际采用代码的许可资料 | T01 仅建立必要资源位置，不做正式品牌设计；实际引入第三方代码时补对应许可 |
| `Tests/Unit/RootViewTests.swift` | 用 App 承载的单元测试检查根视图加载与布局 | 后续单元及隔离集成测试放 `Tests/Unit/`；需要时建立 `Tests/Fixtures/` 保存去敏固定样例、`Tests/TestSupport/` 保存测试替身 |
| `Tests/UI/LaunchTests.swift` | 通过测试运行器检查首次启动和退出后重启 | 后续界面测试放 `Tests/UI/`；测试入口不作为产品页面或用户设置 |
| `docs/` | 已确认需求、原研究证据、任务说明和验收结果 | 保留已有资料及历史；新增功能随对应任务更新进度和证据 |

未来小组件文件落在根目录 `Widgets/`，当前不创建此目录、扩展 target 或组件配置。T32/T33 根据实际共享和显示需求建立相关能力；小组件只读取必要结果，不依赖主 App 页面、登录流程或钥匙串。

## 各部分如何协作

T01 仅建立 `App → 根页面` 的实际调用。后续依次增加以下简单分工，不要求拆成多个 Swift Package：

- App 入口负责组装页面、业务流程、平台接入和存储，避免页面自行创建整套依赖。
- 页面调用必要业务能力，以 Domain 中的数据表达账户和额度；Domain 不反向引用界面或平台实现。
- Services 协调网络检查、连接、刷新与系统能力；Providers/Codex 处理平台协议和解析，Storage 负责本机读写。两者均不反向依赖界面。
- App 根据成功结果写入必要的共享快照；后续 Widgets 读取 Shared 定义的非敏感结果。授权凭据只由主 App 管理。

这些职责沿用[技术连接方案](首版平台登录与额度连接方案.md)第 3、17 章的公共能力与 Codex 接入边界。参考目录位于仓库外，仅用于研究；当前没有复制 CodexBar 源码，也没有把其桌面依赖作为 App 依赖。

## 当前依赖

**当前无第三方库依赖。** 没有远程 Swift Package、CocoaPods、Carthage 或工程生成器依赖，因此没有第三方版本锁文件。工具链版本随本次环境记录，不以本机包管理器状态作为打开工程的前提。

| 名称 | 当前用途 | 来源及版本方式 |
|---|---|---|
| SwiftUI | App 生命周期、窗口和空壳页面 | Apple iOS SDK，随 Xcode 提供 |
| UIKit | 根页面使用系统背景色；单元测试通过 `UIHostingController` 加载和布局 SwiftUI 根视图 | Apple iOS SDK，随 Xcode 提供 |
| Foundation | SwiftUI 与测试所依赖的系统基础类型及运行支持 | Apple iOS SDK，随 Xcode 提供；当前没有网络请求或持久化流程 |
| XCTest / XCUITest | 单元测试与 UI 启动检查 | Apple Xcode 测试框架，随 Xcode 提供；仅测试 targets 使用 |

App 与测试 targets 共用同一工程和共享 Scheme。测试代码、固定样例与替身留在 `Tests/`，不加入 App 的产品资源；需要固定输入时只使用去敏或人工构造数据，不读取真实账户或覆盖真实快照。样例文件如需由测试读取，应加入测试 target 的资源，不加入主 App target。

## 后续按任务接入的系统能力

下表均为已知后续落点，**尚未实现或启用**。无需为 T01 提前打开权限、添加扩展或配置生产授权。

| 系统能力 | 用途 | 接入时机 |
|---|---|---|
| Foundation 的 URLSession 与 Codable 等能力 | 网络评分、Codex 请求与数据解析 | T06 及 T07–T14，随实际链路接入 |
| Security / Keychain | 本机安全保存、更新和移除授权凭据 | T05 起 |
| 系统浏览器打开能力 | 打开 Codex 设备码确认页面，回 App 后继续原流程 | T07–T10；不预先引入登录 SDK、内嵌浏览器或浏览器扩展 |
| BackgroundTasks | 以 30 分钟为目标、由 iOS 尽力调度的后台刷新 | T30/T31；不是持续运行或准点执行保证 |
| App Groups | 在 App 与小组件之间保存必要非敏感快照 | T32，实际能力与配置在对应任务建立 |
| WidgetKit | 小号、中号桌面小组件，统一展示列表首账户的周及 5 小时额度 | T33–T37；没有独立账户选择器 |
| UserNotifications | 权限和基于真实重置时间的本地提醒 | T38–T41；测试数据不触发真实通知 |

若后续确有必要引入第三方依赖，应在当次任务记录名称、用途、上游来源、许可及锁定版本，并提交适用的锁文件。采用上游实质源码时保留版权和许可；技术参考或服务协议证据本身不算已引入的库。

## 保存与复现

共享 Scheme、工程配置、源码、资源及测试随 Git 保存；构建产物、`DerivedData`、个人 Xcode 状态和签名秘密由忽略规则排除。模拟器运行步骤与检查命令统一维护在[根 README](../README.md)，避免在多处保留不同版本的命令。

T01 的重新打开、构建、启动及测试结果写入[验收记录](mvp任务清单/记录/T01-验收.md)。真机安装、个人开发团队及手机系统核验见 [T02 验收记录](mvp任务清单/记录/T02-验收.md)；此文档不代替必要的真实验证，也不将开发者自检记为用户亲验。
