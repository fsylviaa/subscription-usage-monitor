# R4 网络检查与交互原型交接

更新：2026 年 10 月 9 日。用户已明确授权恢复，已完成原文件局部修复、冻结分批审计、代表故事实际点击和最终原生备份。**设计／运行验收范围已完成，最终本地原生备份已核验；唯一剩余项为整体云端同步确认，受 Figma 内存不足阻碍。未宣称整轮完全交付通过。** 原暂停记录保留为历史，不再构成执行限制。

## 1. 文件与评审入口

沿用[原独立 Figma 文件](https://www.figma.com/design/LwH8GU8iQfxhxIT3YXAcyR)，未新建或重建。需求已更新至 [0.6](requirements.md)，决定见 [D-32～D-36](decisions.md)，验收依据为 [R4 清单](acceptance-r4.md)。本轮只修改设计与模拟交互，未编写 App／后端，未连接真实账号或评分服务，没有产品体验演示模式。

| 入口／区域 | 浅色 | 深色 |
|---|---|---|
| 可点击原型 | [1:500](https://www.figma.com/proto/LwH8GU8iQfxhxIT3YXAcyR?page-id=0%3A1&node-id=1-500&starting-point-node-id=1%3A500&scaling=scale-down) | [1:4088](https://www.figma.com/proto/LwH8GU8iQfxhxIT3YXAcyR?page-id=0%3A1&node-id=1-4088&starting-point-node-id=1%3A4088&scaling=scale-down) |
| 原评审画布 | [1:43251](https://www.figma.com/design/LwH8GU8iQfxhxIT3YXAcyR?node-id=1-43251) | [1:43253](https://www.figma.com/design/LwH8GU8iQfxhxIT3YXAcyR?node-id=1-43253) |
| 交互状态与返回路径 | [1:43252](https://www.figma.com/design/LwH8GU8iQfxhxIT3YXAcyR?node-id=1-43252) | [1:43254](https://www.figma.com/design/LwH8GU8iQfxhxIT3YXAcyR?node-id=1-43254) |
| R4 评审目录 | [53:1119634](https://www.figma.com/design/LwH8GU8iQfxhxIT3YXAcyR?node-id=53-1119634) | [53:1121194](https://www.figma.com/design/LwH8GU8iQfxhxIT3YXAcyR?node-id=53-1121194) |
| 网络检查目录 | [46:136512](https://www.figma.com/design/LwH8GU8iQfxhxIT3YXAcyR?node-id=46-136512) | [46:138573](https://www.figma.com/design/LwH8GU8iQfxhxIT3YXAcyR?node-id=46-138573) |

[入口回执](../../design/figma-r4-entries-final.json)确认当前仅保留原 `1:500`、`1:4088` 两个 R4 原型起点，原链接继续有效。主执行代理已重新加载两原入口并查看像素，网络／小组件目录返回 R4 目录正确，浏览器 Flows 只显示两个 R4 主题，见[入口发布截图](../../design/review-r4/final-cloud-flows.jpg)。入口发布与整体保存分开记录；最终同步结论见第 6 节。所有结果选择入口属于设计评审，不是产品内的网络检查绕过按钮。

## 2. 已完成的设计内容

- 网络检查补齐轻量检查反馈、51 分通过后自动授权／查询、49／50 分阻止、超时、网站不可用和无有效评分，以及重新检查、取消与来源返回。有效低分显示当前评分和“需高于 50”；无结果不编造评分。后续授权／额度查询失败与检查失败分开。
- 新增前检查、首次查询、全部／单账号刷新、进入 App 自动更新、重连、通知点击、小组件联网及重试都有相应模拟路径。后台与小组件采用内联状态；失败保留可信旧额度和原成功时间，首次未获取额度不显示伪造旧数据。
- 账号操作按具体身份处理，同平台可继续添加；通知权限与来源返回、小组件配置和点击目标补齐。小组件断开回退优先同平台列表首位，否则当前列表首个绑定账号；无账号显示“未连接账号，无数据”，其他组件保持原选择。未知额度候选和旧缓存点击目标另有指定评审故事。
- 保持黑白灰浅深两套、Claude／Codex／Cursor、固定剩余、左侧实色已用与右侧灰色剩余、刷新连接横排、常显账号身份及 R3 TXT-01～06 精简要求。空组件不再保留“轻点打开对应账号”的过时说明。

Figma 使用有限账号样例与预设结果评审上述行为；样例数量和有限组合不构成产品账号上限或功能限制。产品要求仍以需求 0.6 为准：指定来源的 Claude AI 信任评分有效且 `> 50` 才继续；仅看缓存／倒计时不新增检查。

## 3. 原生回执、画布和截图

| 已核验项目 | 结果与证据 |
|---|---|
| 原评审旧路径清理 | 浅深各 32／32，`complete: true`、`remainingLegacyEdges: []`，保留原 44 个评审根。[浅色](../../design/figma-r4-cleanup-light-complete.json)／[深色](../../design/figma-r4-cleanup-dark-complete.json) |
| 交付只读清单 | 两套各 14,439 个可见 R4 根、44 张原评审、45 个关键目标；`legacyVisible: 0`，无重复名称或缺失关键目标。[浅色](../../design/figma-r4-delivery-light.json)／[深色](../../design/figma-r4-delivery-dark.json) |
| 画布排布 | 两套均 `complete: true`；仅排布交互区现有 R4 根，原 44 张评审坐标不变，不改根名称、父级、反应或共享组件。[浅色](../../design/figma-r4-arrange-light.json)／[深色](../../design/figma-r4-arrange-dark.json) |
| 通知保持局部审计 | 两套各 20 个 ready 集合、4 条代表新增路线，`passed: true`、错误为空。[浅色](../../design/figma-r4-permissions-light-audit.json)／[深色](../../design/figma-r4-permissions-dark-audit.json) |
| 原生 PNG | 90／90 已提取，浅深各 45 张，缺失 0；保留原始 PNG 字节、未重编码，文件哈希已核对。[清单](../../design/figma-r4-native-images.json)／[图片目录](../../design/review-r4/native/) |

可查看[浅色原生图集](../../design/figma-r4-gallery-light.html)和[深色原生图集](../../design/figma-r4-gallery-dark.html)。示例：[网络 49 分](../../design/review-r4/native/light-network-score49.png)、[未知额度回退](../../design/review-r4/native/dark-widgets-cross-platform-pending.png)、[空组件](../../design/review-r4/native/light-widgets-empty.png)。正式截图文件以 90 张清单为准。

已保存的实际像素审查覆盖 **90／90 张**，在各自可见静态范围内无已确认缺陷：[概览与首次查询 14 张](../../design/figma-r4-static-overview-first-query-review.json)、[账号与系统 18 张](../../design/figma-r4-static-accounts-system.json)、[小组件 22 张](../../design/figma-r4-static-widgets-review.json)、[网络与后台 36 张](../../design/figma-r4-static-network-background-review.json)。后台失败画面的首屏 Cursor 额度需滚动查看，浅深已实际滚动核验并保存证据，该跟进项已解决。静态图不证明连线、关闭栈、动画或真实服务；独立弹层 PNG 的透明上部也不等同于产品空白页面。

## 4. 本次恢复的局部修复

先验证暂停备份，再读取同一文件现状；没有重新生成或运行旧修订／清理。结合[逐项诊断](../../design/figma-r4-resume-audit-diagnosis.json)和[原生现场预检](../../design/figma-r4-resume-live-inspection.json)，仅修改 **39 个节点的 reaction**，新建 0、删除 0；[修复回执](../../design/figma-r4-resume-local-repair.json)同时核对 3,034 个无关节点保持不变。

- 共享 Home `46:142410`／`46:152771` 的返回箭头改为 `BACK`。浅深分别实际验证：配置 work → 完成 → 详情 → 关闭 → Home 返回配置；从评审进入后返回评审；从账号列表进入后按历史返回账号列表。`R4-OBS-ISSUE-003` 已闭环。
- 修复前 `hiddenTargets: 53` 与 `legacyTargets: 52` 有 52 条重叠，不能相加。逐项定位后移除 37 个 R4 源节点的陈旧反应：10 个可见但内容已展开的标题热区、26 个隐藏 More 热区，以及 1 个隐藏设置偏好热区。没有新增展开页或修改文案／布局。
- 剩余 16 条属于切断源入口后不可达的旧 R2 内部连线，保留旧节点且不做清理；最终主图审计不再到达这些旧分支。浅深 Settings-denied 的唯一反应差异随该隐藏热区修复消除。
- 实际点击了浅深合计 10 个可见标题热区；确认保留当前详情／账号页，不再误入隐藏 R2。两个 Home 的修复不能只由代码判定，其历史来源均另有真实点击记录。

## 5. 最终验收证据与备份

[冻结后的分批只读审计](../../design/figma-r4-audit-after-final-fixes.json)运行 `r4compact-1791522480002`，时间 05:08:00～05:20:54 UTC。每套扫描 14,483 个根、914,775 个节点，队列剩余 0、未扫描 0、不完整 0，问题计数为空；14,483 组浅深根配对，28,638 个可达根全部检查。原浅深各 44 张画面仍保留，四区目录签名与修复前一致。使用替换后的 compact 模块，未并载两个定义，未运行旧全量 Audit。

比修复前每套少扫描 2 个旧根和 332 个节点，来自旧 R2 变为不可达，**不是删除节点**。审计期间冻结设计修改；审计不替代像素与实际运行验证。

[实际点击日志](../../design/figma-r4-click-log.json)共 **87 条观察**，本次追加 072～087，保留原 001～071 事实与限制。[46 项需求映射](../../design/figma-r4-resume-acceptance-mapping.json)和[R4 验收清单](acceptance-r4.md)记录各项静态、运行及交付证据。评分 49／50 阻止、51 继续、各类检查失败、取消／重试、首次／全部／单账号查询、多账号与通知权限、小组件配置及回退均在声明的代表故事范围核验；运行补证清单已清空。

实际回退确认身份、额度和详情目标同步，其他组件选择不变。查询失败保留可信旧额度与成功更新时间；新增首次查询失败保留“尚未获取额度”，实际面板重试后新账号变为 54%／91%，旧账号未改变。该账号故事的成功时间为预设 09:41；09:45 属于单独的后台／小组件更新故事，不能混用。

新增 32 张运行截图逐张检查：21 张主体完整、4 张仅用作内容／阶段证据、7 张存在浏览器缺绘或空白，不用于完整静态通过结论。截图缺绘与设计缺陷分开。原 90 张原生 PNG 的画面内容未被本次 reaction 修复改变，可继续作为静态图集；点击图也不替代原生图。

[最终原生 `.fig`](../../design/订阅额度%20iPhone%20原型-R4-最终验收-2026-10-09.fig)已保存，**10,245,818 字节**，SHA-256：

`c259e30b5560459cbc9a2b1c9c2247a4cb3a81afb035b9a2eabd873179913b56`

[备份核验清单](../../design/figma-r4-final-backup-2026-10-09.json)记录 ZIP 完整性通过，`canvas.fig` 与审计后检查点的 SHA-256 完全一致，确认审计后设计内容没有漂移。原暂停备份（10,293,242 字节，`f795c2d9…359`）及其他阶段备份保留，未覆盖。

## 6. 云端保存与交接边界

原文件已保存命名版本 **R4 · 网络检查与返回路径验收 · 2026-10-09**，版本 ID `2408215105198163984`；版本保存操作成功，历史列表和 Copy link 均有实际观察。最新关键修复已在云端原型中实测。

**整体云端同步仍未最终确认。** 独立 Chrome 加载固定版本因内存不足失败；恢复操作自动移除 `version-id` 后虽能打开同一文件当前画布，但不能据此宣称固定版本加载通过。原生客户端随后也在加载该固定版本时出现相同内存错误。此前看到选中条目与原画布属于过渡观察，后续错误使其不足以证明完整版本重开。

[最终同步记录](../../design/figma-r4-final-sync-2026-10-09.json)与[原生内存错误截图](../../design/review-r4/resume-final-version-native-oom.jpg)保留该阻碍。未取得固定版本导出，也没有声称云端／本地逐字节等价。最终本地 `.fig` 在这些只读核验之前已经完整保存和校验。恢复时继续沿用同一文件；没有点击 Restore、Duplicate 或删除归档。

只剩云端整体保存核验需要后续完成；不必重跑生成、旧审计、已完成的 87 条点击或 90 张静态图审查。版本历史的使用依据参考 [Figma 官方说明](https://help.figma.com/hc/en-us/articles/360038006754-View-a-file-s-version-history)，该说明不替代本文件的实际核验。

本轮范围只有需求文档、Figma 模拟与验收；没有接入真实账号、IP 检测或评分服务，没有 App／后端实现。动画核验包括路径一致、自动推进及既有克制转场配置；未作设备帧率测量，也未声称穷举所有账号排列。模拟样本与数量不代表产品限制。

文件较大，最终导出时原生内存约 92%；固定版本核验失败后，已恢复到同一文件当前画布，内存约 53.64%，URL 仍带 `recovery=true`，四个 R4 分区均可见。没有为恢复删除归档、重建或导入另一文件。最终原文件保持打开，开发检查工具已关闭。此前暂停与故障经过可查[暂停交接历史](figma-handoff-2026-10-09-pause-history.md)、[暂停检查点](../../design/figma-r4-pause-checkpoint-2026-10-09.json)；当前状态以 [state](../../design/figma-state.json) 和[进度](../../design/figma-r4-live-progress.json)为准。
