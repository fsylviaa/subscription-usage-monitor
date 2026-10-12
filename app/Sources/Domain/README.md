# 业务数据

T04 的 `ConnectedAccount` 保存稳定本地 ID（`id`）、provider/product、可空的可靠邮箱／服务端用户 ID／显示名、查询作用域、credentialRef、generation 和独立的 `AccountQuotaState.notFetched`。Codex 的 `scope.remoteAccountID` 是授权验证的查询账户 ID，与人的 `remoteUserID` 分开。

列表顺序以存储文档的账户数组位置为唯一来源，不另设竞争的 displayOrder 字段；邮箱不作本地主键。模型只携带凭据 UUID 引用，不携带令牌。当前未获取状态没有数值、重置时间或成功时间；T11 已用独立的 `CodexQuotaSnapshot` 表达窗口语义，T12 已通过可选 quotaSnapshot 接入成功快照保存，不在账户身份中混入百分比。

公共数据不依赖页面、具体 Codex 请求或存储实现。模型能够表达经验证的身份，不负责证明登录成功、邮箱去重、重连替换或阻止旧请求；这些流程仍由后续任务实现。


T11 的 `QuotaPercentage` 只接受有限的 0…100 已用百分比，剩余由 `100 - used` 得到；`QuotaAmount` 分为未知、已知限额和明确不限量。未知／不限量不输出百分比或进度条。进度输出左侧已用、右侧剩余，两窗口不能合并。

`QuotaWindowSnapshot` 分别保存精确 5 小时／周含义、百分比单位、可空的真实重置时间和观测时间。到重置点仅 `isAwaitingUpdate(at:)` 变为 true，原始额度不变。`CodexQuotaSnapshot` 保存账户本地 ID、provider/product、查询 scope、generation、原样套餐和观测时间；不携带邮箱或凭据。`hasKnownQuota` 用于区分“解释完成”与“确实有已知额度”；T12 在保存前检查此值，全未知结果不会产生新的额度成功时间。

T12 的可选 `AccountSubscription` 独立保存平台原始套餐文本及观测时间，挂在已验证账户／产品／作用域之下。`notApplicable` 表示已确认无本期适用额度，须有套餐且没有额度快照；`notFetched` 不等同免费或不限量。原文件缺少 subscription 时兼容读取，升级首次查询补齐。
