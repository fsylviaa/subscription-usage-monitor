# Codex 接入落点

T07 已实现 `CodexDeviceAuthorizationClient` 和 `CodexDeviceAuthorization`：向固定官方端点申请一次性设备码，验证字段，固定官方确认地址，按最初请求时间保存 15 分钟客户端截止。调用前必须由连接流程执行 T06 网络检查。

协议依据：[官方固定源码快照](https://github.com/openai/codex/blob/165299214855c2e48facf9bb3bc3c0fc277ee639/codex-rs/login/src/device_code_auth.rs)。`user_code`／`usercode`、字符串或整数 interval 均有隔离验证；固定 HTTPS 页面不带代码参数。没有服务器完整含码 URL 或 expires_in 的证据，不编造自动填码或服务器保留期限。

请求无浏览器 Cookie、共享认证、缓存或重定向；模型打印与反射去敏。T07 不轮询、换令牌、验证身份或保存正式账户，这些由 T08 等后续任务逐项实现。不读取电脑登录状态，也未复制参考项目源码。
