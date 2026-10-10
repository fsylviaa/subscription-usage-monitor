# 共用流程落点

T06 的 `NetworkScoreChecker` 每次从当前设备请求指定来源，返回有效放行、有效低分、无法取得或取消。`checkThenPerform` 只在有效评分 > 50 且尚未取消时执行原操作；操作本身失败独立抛出，不冒充登录或查询成功。

调用方持有并取消本次 Task，退出时取消；若后续闭包中还有等待，实际发起授权/查询前仍须检查取消。每次授权或查询均重新检查，不保存、跨账户复用或跨操作复用旧的放行结果。T07 连接页面已调用本检查；T12 首次额度查询也已调用；其他触发由对应后续刷新任务接入。

## 指定来源

2026-10-10 核对 [Net.Coffee 指定页面](https://ip.net.coffee/claude/) 及其 [页面脚本](https://ip.net.coffee/claude/claude-page.js?v=20260916a)：

1. `claude.ai/cdn-cgi/trace` 获取本次设备访问 Claude 的出口地址。
2. `ip.net.coffee/api/iprisk/{本次地址}` 返回数值 `trust_score`，按页面 `countryCode` 地区覆盖得到最终分数。
3. 按 NET-05，缺失/无效分数始终为未知，即使地区为受限也不伪造为 0；有效分数才应用页面地区规则。

服务端按 CIDR 缓存，响应的 `ip` 可能不等于查询地址，页面也以请求时的地址关联结果。本 App 不保存地址或分数，不输出原始响应、地址或包含地址的请求 URL；不读取登录授权。评分网络使用独立临时 URLSession，关闭本机缓存、Cookies、凭据和自动跳转。出口 trace 禁用缓存；评分 API 按指定网页默认策略使用来源的服务端评分缓存，不强制远端重新验证；每次仍重新请求本次出口对应的结果。

**网络含义：** 这是同一设备、当次请求取得的指定网页评分。Claude 与后续 Codex 登录/查询域名可能被 VPN 按域名分流；不宣称已证明它们出口相同，或分数可以保证登录/查询成功。T07/T12 在实际操作前执行这一指定前置检查，并验证真实链路，不能拿电脑浏览器的分数代替手机检查。网页自身的服务端评分缓存周期由 Net.Coffee 管理，App 禁用的是本机 HTTP 缓存复用，不能承诺该来源底层数据实时重算。

后续连接／刷新协调和提醒流程随对应任务逐项引入，不预建多平台框架。

## 后台额度刷新（T30）

`BackgroundQuotaRefresh.swift` 注册 BGAppRefreshTask、保留当前30分钟目标请求并记录调度／执行结果。App、前台和后台共用同一个 CodexConnectionFlow；冷后台启动只恢复账户缓存，不启动登录恢复。后台成功仍经过原网络检查、查询与持久保存。

去敏观察文件为 App 容器 `Library/Application Support/BackgroundRefresh/events.json`，最多保留100条，不含邮箱、账户ID、凭据或余额；只记调度目标、实际起止、结果计数和原／新成功时间。`request`只说明申请，`debug`仅调试触发，普通系统回调为`system`。自然执行是否发生须核对实际started/finished记录，不能把scheduled当作执行。

Debug隔离验收使用独立tmp/T30-debug，Release无测试参数或调试调用。T31将继续核验中断／失败恢复；T53收口自然后台证据。
