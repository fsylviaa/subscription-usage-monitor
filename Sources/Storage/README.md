# 本机存储

T04 的 `AccountStore` 用带 schemaVersion 的 Codable JSON 文件保存有序账户列表；提供 load、append、update 和 reorder。首次无文件返回空列表，新增追加末尾，更新只替换同一本地 ID 的原位置，重排必须是现有 ID 的完整排列。重复本地 ID 属于存储一致性错误，不是同邮箱重复登录的产品行为；登录去重由 T18/T20 完成。

App 接入时组装一个共享 actor 实例，串行执行无挂起点的读改写；磁盘采用原子替换和首次解锁后可读的文件保护。只在成功写入后返回；没有会提前更新的内存缓存。损坏文件、未知版本和读取／写入失败向调用方返回错误，保留文件，不降级为空列表或自动重置。

`applicationStore()` 提供 App 私有 Application Support/SubscriptionUsage/accounts.json 路径，T08 已接入首账户绑定与启动读取。测试显式传入唯一临时路径；重新构造实例验证真正从文件读取，测试文件不会进入生产路径。

普通文件只保存账户元数据、凭据 UUID 引用和当前尚未获取额度状态；不保存登录令牌、原始认证响应或 Cookie。T05 已提供独立钥匙串存取能力，额度窗口和快照在 T11/T12 接入，T08 已提供最小身份重开，完整可信快照恢复在 T15 接入；没有实现后续额度流程。组件共享在 T32 接入，不共用此账户文件写入器。

## T05 登录授权存取

`CredentialVault.applicationVault()` 创建本 App 的授权存储；后续由 App 入口组装共享实例。`Entry.credential(account.credentialRef)` 保存正式授权，`Entry.loginTransaction(transactionID)` 保存临时登录资料；两个命名空间对应不同 service，即使 UUID 相同也不会互相覆盖。

`save` 将完整 `CredentialPayload` 一次写入同一条 Keychain 记录；已有项用 `SecItemUpdate`，不存在才新增，不先删后写。采用 `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` 和 `kSecAttrSynchronizable=false`，不配置共享 Keychain group。`load` 仅在条目不存在时返回 nil；暂不可读和其他系统错误向上抛出，不删除授权或账户。`remove` 只删除指定命名空间和 UUID；已不存在视为删除成功，其余失败可由后续调用方重试。

`CredentialPayload` 是整包二进制容器，不实现 Codable，普通账户文件仍只保留 UUID 引用。打印、调试描述和反射隐藏包内容；错误只含内部类别或系统状态码。后续 Codex 适配器负责整包编码/解码并保留真实返回的 token、版本、时间和身份绑定；调用方不得记录 `.data` 或原始认证响应。T08 已由 Codex 适配器固定本次协议字段，不把存储成功当作身份验证成功。

T08 已接入核验后提交；T09/T10 已接入到期、取消清理和登录中断恢复，账户移除重试仍留对应后续任务。测试使用随机专属 service 与虚构标记，退出时逐条删除测试项，不枚举或清空用户钥匙串。

可访问性依据：[Apple Keychain 可访问性](https://developer.apple.com/documentation/security/ksecattraccessibleafterfirstunlockthisdeviceonly)与[条目属性](https://developer.apple.com/documentation/security/item-attribute-keys-and-values)。实际检查范围见 [T05 验收](../../docs/mvp任务清单/记录/T05-验收.md)。


## T07 临时设备码事务

`CodexLoginTransactionStore` 将单个当前连接事务整包存入临时 Keychain 固定槽位；包内有独立 transactionID、平台／产品、公共 clientID、设备码、展示码、轮询间隔、原始开始和截止。普通文件不保存秘密。T10 已接入固定槽读取和退出后恢复，始终保留原开始时间与期限。

取消按事务 ID 清理；读取后删除还通过 `CredentialVault.remove(ifMatching:for:)` 在同一 actor 无挂起地比较和移除，避免旧取消删掉新包。清理失败保留引用，下一次申请前重试；不删除正式授权或账户。T09/T10 已接入登录失败和恢复编排。

T08 的 `CodexAccountBindingStore` 仅接受已验证登录结果；先保存本 App 的独立凭据条目，再在账户 actor 内原子提交首账户。失败只回滚本次新引用，不修改已有账户；取消在提交前检查，提交后保持已保存事实。`CodexPendingLoginStore` 临时保存授权码及未核验令牌，正常完成/取消清理。T10 读取具名阶段恢复；系统拒绝删除时不声称已清除。

## T10 持久恢复与取消

待领取状态由原设备事务表示；`CodexPendingLoginStore` 的 version 1 包含 transactionID 和 `codeReady`、`exchangeStarted`、`tokensReady` 三个阶段。真正发送一次性兑换前先原子写入 exchangeStarted 并删除持久代码；只有 codeReady 可以交换，tokensReady 只做核验。T09 旧 codeReceived 没有兑换开始标记，因此一律按结果不明清理重试，旧完整 tokensReceived 可核验。

取消先写不含秘密的 ID tombstone，再等待旧写入结束并精确清理。初次保存前已取消的同 ID 不能迟到复活；旧取消不覆盖新 ID。条件替换只在同一 vault actor 内比较、写入，登录入口自身合并重复恢复。永久损坏的阶段按事务清理；固定槽仅在当前包确实不可解码时条件移除，系统暂不可用保留重试。已有正式账户优先于未清理的临时事务，避免崩溃收尾重复保存。
