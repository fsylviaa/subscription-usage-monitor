# Codex 接入落点

T07 已实现 `CodexDeviceAuthorizationClient` 和 `CodexDeviceAuthorization`：向固定官方端点申请一次性设备码，验证字段，固定官方确认地址，按最初请求时间保存 15 分钟客户端截止。调用前必须由连接流程执行 T06 网络检查。

协议依据：[官方固定源码快照](https://github.com/openai/codex/blob/165299214855c2e48facf9bb3bc3c0fc277ee639/codex-rs/login/src/device_code_auth.rs)。`user_code`／`usercode`、字符串或整数 interval 均有隔离验证；固定 HTTPS 页面不带代码参数。没有服务器完整含码 URL 或 expires_in 的证据，不编造自动填码或服务器保留期限。

请求无浏览器 Cookie、共享认证、缓存或重定向；模型打印与反射去敏。T08 的 `CodexLoginClient` 领取授权码、校验 PKCE 对应关系并交换令牌；`CodexIdentityVerifier` 使用固定官方 JWKS 验证两种令牌的 RSA 签名、签发者、受众和主体，核对可信邮箱及账户作用域，再经 T06 检查请求 usage 验证服务端账户一致。此次不解析或保存额度窗口。身份核验来源和真实验证状态见 [T08 验收](../../../docs/mvp任务清单/记录/T08-验收.md)。不读取电脑登录状态，也未复制参考项目源码。


## T11 纯额度解释

`CodexUsageParser.parse(_:for:observedAt:)` 只接收数据、已经验证的请求账户和明确观测时间，返回独立领域快照。自身没有网络、账户存储、Keychain 或系统当前时间依赖；T12 查询服务在获得已门控的真实响应后调用。

- 只读主 `rate_limit` 的 `primary_window`／`secondary_window`，以 `limit_window_seconds` 精确等于 18000／604800 识别 5 小时／周，不按位置、套餐名或四舍五入推测。其他时长与额外模型窗口不能替代；同类型主窗口重复时拒绝歧义。
- `used_percent` 缺失／null 保持未知，真实 0／100 保留；`reset_at` 为平台给出的 Unix 秒，缺失／null 保持无时间，不按 `reset_after_seconds` 或窗口长度推算。百分比、时间各自独立。
- 已知字段类型错误、有效窗口的非法数值、冲突账户 ID 或重复目标窗口让解析失败；不夹取为 0／100。后续查询层应保留原可信快照与成功时间，只显示既定简短失败提示。
- 响应 `account_id`／`accountId` 若存在，均须与请求的已验证作用域一致。未返回 ID 时仅保留调用者传入的身份上下文；解析器本身不证明请求授权或网络检查已通过。
- credits（包括 `credits.unlimited`）、API 余额、支出控制、模型附加额度和 allowed/limit_reached 均不推导订阅比例。现有协议无可信的窗口不限量字段，所以领域 `.unlimited` 有独立固定输入测试，wire parser 不制造此标记。套餐缺失保持 nil，未知套餐字符串原样保留，不推断额度。
- 全未知输入可以解释成功，但 `hasKnownQuota == false`，不代表取得额度。T12 已接入成功保存及失败保留，部分响应按本次真实字段保存，后续持续刷新由对应任务实现。

字段契约参考本地 CodexBar 固定版本 `03a51bdcfc6f6804e005d7e5007de67bac82b494` 的 [CodexOAuthUsageFetcher.swift](https://github.com/steipete/CodexBar/blob/03a51bdcfc6f6804e005d7e5007de67bac82b494/Sources/CodexBarCore/Providers/Codex/CodexOAuth/CodexOAuthUsageFetcher.swift)（Response／RateLimitDetails／WindowSnapshot／CreditDetails）。本实现独立编写，没有复制或链接参考项目源码；参考项目为 [MIT License](https://github.com/steipete/CodexBar/blob/03a51bdcfc6f6804e005d7e5007de67bac82b494/LICENSE)，Copyright (c) 2026 Peter Steinberger。没有新增第三方库依赖。

## T12 真实查询与成功快照

`CodexQuotaService` 从本 App 钥匙串精确读取 credentialRef，核对包版本、issuer/client、已验证用户及 scope，使用 T08 的无 Cookie、无共享认证、无重定向传输。每次实际 usage 请求前重新执行 T06；不会借用身份核验时的评分或另一账户数据。固定 HTTPS GET 与 Bearer/ChatGPT-Account-Id 沿用上述证据，不请求 credits 或其他端点。

响应必须 HTTP 成功、身份与已验证账户一致。先独立解析非空 `plan_type`，保留大小写和未知新名称；再解释额度，交给 `AccountStore.saveObservation` 一次原子保存。至少一个已知窗口才保存额度快照；经核验为 Free 且主／次窗口字段明确提供为 null 或合法的非本期窗口时，保存“无本期适用额度”。有任何受支持窗口但缺有效数值、窗口容器缺失／畸形或适用性不明仍失败，不能默认免费。Free 判断仅用于该平台适用性语义，不参与套餐名称映射，也不会跳过以后实际查询中的支持窗口。

额度解析失败仍可保存已核验套餐；同套餐保留原额度时间，确认套餐变更清除旧额度。套餐观测时间和额度成功时间独立；取消、身份错误及磁盘错误不提交。当前真实响应只有套餐标识 `free`，界面显示“Codex · free”，不强制改成 Free。DEBUG 仅记录固定失败阶段，不打印响应、凭据、邮箱或错误对象。真实验收结果与同次去敏窗口摘要见 [T12 验收](../../../docs/mvp任务清单/记录/T12-验收.md)。自动续期已由 T14 接入，下述说明为本次实现边界。

## T14 手机授权续期

`CodexCredentialRenewal` 是正式查询链共享的串行处理器；按 credentialRef 合并在途工作。固定 `/oauth/token` JSON 请求只带 `grant_type=refresh_token`、既有 client ID、手机自己的 refresh token，依据同一官方源码快照的 [auth/manager.rs](https://github.com/openai/codex/blob/165299214855c2e48facf9bb3bc3c0fc277ee639/codex-rs/login/src/auth/manager.rs)。可省略 id/refresh 替换项，但必须取得可用访问授权；不复制 CodexBar 的桌面共享凭据所有权或额外 scope。

- 已保存到期时间优先；旧授权包缺 expires_in 时，仅用已经核验并保存在钥匙串中的访问令牌期限作续期时机提示，不能据此建立身份。60 秒以内按可控时钟提前续期；不更改系统时间或定时唤醒。
- 发送前条件替换写入持久开始标记；收到响应后先将候选存入同一钥匙串包，再验证新 RSA 签名、issuer、audience、subject 和 scope。省略原 id_token 时保留原已验证身份，不要求该旧身份令牌仍未过期；新访问令牌必须未过期，取签名期限与响应期限较早者。
- 验证失败或提交失败不发布新连接。已存候选可重试核验/保存；候选保存失败可在同进程重试保存同一响应。若进程重开只剩开始标记、没有可信的新响应，不重放可能已消费的旧 refresh token；保留原包及账户数据，保留失败结果；后续如从已有添加入口再次连接同邮箱，按 T18 更新授权。D-59 不提供独立重新登录入口。
- 开始标记、候选和正式包均用 `CredentialVault.replace(ifMatching:)` 原子条件替换；取消查询后仍尽力保存已发续期的结果，但取消的查询不能发布额度。完整账户操作与 generation 生命周期由 T22 后续收口。
- 查询前网络门槛保留；续期后再取得新评分才发实际查询。401 最多适用续期一次并重查一次，403/429/5xx 不触发该恢复。保存快照前再次比较凭据包，账户存储继续核对原绑定及 generation。
- 同一授权链的最近两次续期开始／完成／原到期／触发原因与新授权一起保存，不含导出令牌；这里只证明轮换，T54 还需同次成功查询证据。当前真实自然轮换为 0，参见 [T14 验收](../../../docs/mvp任务清单/记录/T14-验收.md)。

## T62 D-67重置卡摘要

既有usage响应的`rate_limit_reset_credits.available_count`表示可用额度重置卡张数；来源为OpenAI官方backend-client类型与读取代码。`subscription`独立解析可选非负Int64并保存到AccountSubscription，缺失／非法保持nil，不破坏主窗口或套餐。UI按明确用户要求将无可信值显示0，不将其写成真实平台确认。沿用已有身份门控／保存上下文、失败保留及重连scope保护；不新增查询或兑换操作。旧文件缺字段正常读取。来源链接及限定见技术方案D-67与T62修订验收。
