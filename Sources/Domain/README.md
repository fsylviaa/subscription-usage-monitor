# 业务数据

T04 的 `ConnectedAccount` 保存稳定本地 ID（`id`）、provider/product、可空的可靠邮箱／服务端用户 ID／显示名、查询作用域、credentialRef、generation 和独立的 `AccountQuotaState.notFetched`。Codex 的 `scope.remoteAccountID` 是授权验证的查询账户 ID，与人的 `remoteUserID` 分开。

列表顺序以存储文档的账户数组位置为唯一来源，不另设竞争的 displayOrder 字段；邮箱不作本地主键。模型只携带凭据 UUID 引用，不携带令牌。当前未获取状态没有数值、重置时间或成功时间；额度窗口语义在 T11 单独实现，成功快照在 T12 接入，不在账户身份中混入百分比。

公共数据不依赖页面、具体 Codex 请求或存储实现。模型能够表达经验证的身份，不负责证明登录成功、邮箱去重、重连替换或阻止旧请求；这些流程仍由后续任务实现。
