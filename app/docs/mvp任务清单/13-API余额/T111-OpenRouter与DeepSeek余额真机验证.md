# T111｜OpenRouter与DeepSeek余额真机验证

[返回总览](../README.md) · [本轮规划](README.md) · [执行约定](../执行约定.md)

- 状态：待本人对照（2026-10-18 验证页已装机；见[T111验收](../记录/T111-验收.md)）。
- 用户亲验：待验。
- 直接前置：T110；本人准备一把OpenRouter管理密钥和一把DeepSeek API key（可选再准备一把OpenRouter普通key用于确认被拒）；描述文件过期先续签。
- 对应需求：需求0.32，BAL-02、BAL-03、BAL-05、BAL-08；D-82，沿用D-59、D-64、D-71、D-76、D-79、D-81未冲突规则；技术方案第13章、第13a章。

## 本次交付与范围

在本人iPhone上用Debug构建的开发者验证页（`Sources/Debug`，仅启动参数进入，Release不包含）验证两家余额接口：

- OpenRouter：粘贴管理密钥→`GET https://openrouter.ai/api/v1/credits`，显示`total_credits − total_usage`；若本人准备了普通key，确认同一接口返回403（印证官方“须管理密钥”）。
- DeepSeek：粘贴API key→`GET https://api.deepseek.com/user/balance`，显示各币种总余额、充值余额、赠送余额及`is_available`。

key只留在内存，不写入钥匙串、正式账户或日志；不改正式界面和数据。

结论二选一并报告本人：①两家都可用→进入第二阶段；②任一不可用→给出去敏证据，停下等本人决定，不擅自改用网页登录或其他办法。

## 必要检查

- 真机实际请求成功；OpenRouter余额与网页 Settings → Credits 显示一致，DeepSeek余额与 platform.deepseek.com 首页／用量页显示一致（允许刷新时差）。
- 记录去敏响应结构样本（金额打码或改写、无key）作为T113解析测试依据；记录普通key被拒、错误key的实际状态码。

## 你最少怎么验收

本人只做一次：开发者给出Debug版本验证页的打开位置→分别粘贴两把key点验证→对照页面显示的余额与两家网站是否一致。其余由开发者完成。

## 完成、证据与清理

按本项实际范围自检并留证，更新本文件、[项目进度](../../项目进度.md)及`../记录/T111-验收.md`；真实App、实际桌面组件、隔离测试分别标明，未执行的写待验。仅暂存本项成果、记录和进度，本地提交含T111编号，不推送。构建／验证结束先归档必要去敏摘要和少量截图，确认无进程使用后清理本轮DerivedData、编译链接目录、测试运行器、用毕.app和结果包，记录范围与前后大小。保护正式Codex／Cursor账户、授权、App Group、Bundle、手机已有组件配置及其他未提交工作；Figma只读。API key（尤其OpenRouter管理密钥）、token、Cookie不进入日志、截图、记录或Git，截图中只出现末四位。
