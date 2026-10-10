# 本机存储

T04 的 `AccountStore` 用带 schemaVersion 的 Codable JSON 文件保存有序账户列表；提供 load、append、update 和 reorder。首次无文件返回空列表，新增追加末尾，更新只替换同一本地 ID 的原位置，重排必须是现有 ID 的完整排列。重复本地 ID 属于存储一致性错误，不是同邮箱重复登录的产品行为；登录去重由 T18/T20 完成。

App 接入时组装一个共享 actor 实例，串行执行无挂起点的读改写；磁盘采用原子替换和首次解锁后可读的文件保护。只在成功写入后返回；没有会提前更新的内存缓存。损坏文件、未知版本和读取／写入失败向调用方返回错误，保留文件，不降级为空列表或自动重置。

`applicationStore()` 提供 App 私有 Application Support/SubscriptionUsage/accounts.json 路径，当前未接入页面或生命周期。测试显式传入唯一临时路径；重新构造实例验证真正从文件读取，测试文件不会进入生产路径。

普通文件只保存账户元数据、凭据 UUID 引用和当前尚未获取额度状态；不保存登录令牌、原始认证响应或 Cookie。T05 已提供独立钥匙串存取能力，额度窗口和快照在 T11/T12 接入，页面恢复在 T15 接入；没有实现这些后续流程。组件共享在 T32 接入，不共用此账户文件写入器。

## T05 登录授权存取

`CredentialVault.applicationVault()` 创建本 App 的授权存储；后续由 App 入口组装共享实例。`Entry.credential(account.credentialRef)` 保存正式授权，`Entry.loginTransaction(transactionID)` 保存临时登录资料；两个命名空间对应不同 service，即使 UUID 相同也不会互相覆盖。

`save` 将完整 `CredentialPayload` 一次写入同一条 Keychain 记录；已有项用 `SecItemUpdate`，不存在才新增，不先删后写。采用 `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` 和 `kSecAttrSynchronizable=false`，不配置共享 Keychain group。`load` 仅在条目不存在时返回 nil；暂不可读和其他系统错误向上抛出，不删除授权或账户。`remove` 只删除指定命名空间和 UUID；已不存在视为删除成功，其余失败可由后续调用方重试。

`CredentialPayload` 是整包二进制容器，不实现 Codable，普通账户文件仍只保留 UUID 引用。打印、调试描述和反射隐藏包内容；错误只含内部类别或系统状态码。后续 Codex 适配器负责整包编码/解码并保留真实返回的 token、版本、时间和身份绑定；调用方不得记录 `.data` 或原始认证响应。本次不固定尚未接入的协议字段，不把存储成功当作身份验证成功。

临时事务的到期、一次消费、验证后提交、登录取消及账户移除重试编排均由对应后续任务接入；本次仅提供分离的存取/删除能力。测试使用随机专属 service 与虚构标记，退出时逐条删除测试项，不枚举或清空用户钥匙串。

可访问性依据：[Apple Keychain 可访问性](https://developer.apple.com/documentation/security/ksecattraccessibleafterfirstunlockthisdeviceonly)与[条目属性](https://developer.apple.com/documentation/security/item-attribute-keys-and-values)。实际检查范围见 [T05 验收](../../docs/mvp任务清单/记录/T05-验收.md)。
