# R4 网络检查与交互原型交接

更新：2026 年 10 月 9 日。**状态：`paused_by_user`，用户要求保存当前检查结果后暂停。插件已关闭，当前文件保持打开；未继续诊断、修复或验证。** 精准恢复点见[机器可读暂停记录](../../design/figma-r4-pause-checkpoint-2026-10-09.json)。须等待用户明确继续，本文不代表全轮验收通过。

## 1. 文件与评审入口

沿用[原独立 Figma 文件](https://www.figma.com/design/LwH8GU8iQfxhxIT3YXAcyR)，未新建或重建。需求已更新至 [0.6](requirements.md)，决定见 [D-32～D-36](decisions.md)，验收依据为 [R4 清单](acceptance-r4.md)。本轮只修改设计与模拟交互，未编写 App／后端，未连接真实账号或评分服务，没有产品体验演示模式。

| 入口／区域 | 浅色 | 深色 |
|---|---|---|
| 可点击原型 | [1:500](https://www.figma.com/proto/LwH8GU8iQfxhxIT3YXAcyR?page-id=0%3A1&node-id=1-500&starting-point-node-id=1%3A500&scaling=scale-down) | [1:4088](https://www.figma.com/proto/LwH8GU8iQfxhxIT3YXAcyR?page-id=0%3A1&node-id=1-4088&starting-point-node-id=1%3A4088&scaling=scale-down) |
| 原评审画布 | [1:43251](https://www.figma.com/design/LwH8GU8iQfxhxIT3YXAcyR?node-id=1-43251) | [1:43253](https://www.figma.com/design/LwH8GU8iQfxhxIT3YXAcyR?node-id=1-43253) |
| 交互状态与返回路径 | [1:43252](https://www.figma.com/design/LwH8GU8iQfxhxIT3YXAcyR?node-id=1-43252) | [1:43254](https://www.figma.com/design/LwH8GU8iQfxhxIT3YXAcyR?node-id=1-43254) |
| R4 评审目录 | [53:1119634](https://www.figma.com/design/LwH8GU8iQfxhxIT3YXAcyR?node-id=53-1119634) | [53:1121194](https://www.figma.com/design/LwH8GU8iQfxhxIT3YXAcyR?node-id=53-1121194) |
| 网络检查目录 | [46:136512](https://www.figma.com/design/LwH8GU8iQfxhxIT3YXAcyR?node-id=46-136512) | [46:138573](https://www.figma.com/design/LwH8GU8iQfxhxIT3YXAcyR?node-id=46-138573) |

[入口回执](../../design/figma-r4-entries-final.json)确认当前仅保留原 `1:500`、`1:4088` 两个 R4 原型起点，原链接继续有效。主执行代理已重新加载两原入口并查看像素，网络／小组件目录返回 R4 目录正确，浏览器 Flows 只显示两个 R4 主题，见[入口发布截图](../../design/review-r4/final-cloud-flows.jpg)。这确认入口发布，不证明所有本地更改已同步。所有结果选择入口属于设计评审，不是产品内的网络检查绕过按钮。

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

## 4. 点击、审计发现与暂停状态

[实际点击日志](../../design/figma-r4-click-log.json)当前记录 **71 条观察、45 张像素核验点击截图**，另有前述 **90 张原生 PNG**。已有案例观察与整轮完成分开：**`R4-OBS-ISSUE-003` 仍开放**——小号 work 组件完成配置、关闭详情后，Home 返回进入账号管理页；浅深共享 Home 的修复候选尚未应用。其余逐项观察和限制以日志为准。

本次只读审计已完整落盘为[最终修复前快照](../../design/figma-r4-audit-before-final-fixes.json)，**72,230 字节**，runId `r4compact-1791504787585`。浅深各 14,485 根（14,483 primary＋2 legacy）、915,107 节点；两队列 `remaining = 0`，`incompleteRoots = 0`、`legacyUnscanned = 0`，配对 14,483 根，`reachableRoots = inspectedReachableRoots = 28,642`。这是完整扫描快照，**不是最终通过报告**。

快照报告候选 `hiddenTargets: 53`、`legacyTargets: 52`、`themeReactionMismatch: 1`。前两类重叠，不能相加。样本包括可见 Widgets/Detail 的 Codex／Cursor Expand 连到隐藏 R2，以及 Settings-denied 浅深反应不一致；均暂停待诊断，不把候选数量当成已经确认的独立缺陷总数。

两个独立候选模块均**未应用**：`r4-widget-return-repair.js`、`r4-audit-compact-next.js`。最终修复后的审计、最终原生交付备份和整体云端同步确认都未完成。当前文件名未显示警告仍不足以证明全部同步，未为暂停额外诊断。

| 收尾项目 | 暂停时状态 |
|---|---|
| 原生 PNG 静态检查 | 90／90 已记录，无已确认可见缺陷；不替代交互验证 |
| 实际交互问题 | ISSUE-003 开放，候选修复未应用 |
| 审计候选诊断 | 53 hidden／52 legacy 重叠及 1 浅深反应差异待核验 |
| 最终审计通过 | 未完成；已保存修复前快照 |
| 最终 `.fig` | 未完成；已保存独立暂停备份 |
| 整体云端同步 | 未证实，原入口发布此前已确认 |
| 用户暂停 | 已保存记录并停止，等待明确继续 |

用户明确继续后，先读取暂停记录、交接和审计快照，核对原文件同步与内存状态；再在原节点范围诊断和局部修复，不能直接重跑生成或清理。修复后重做相关点击和最终只读审计；同一运行保持 `runId` 一致，中断／重启后 reset，不拼接不同运行报告，不使用旧 full audit。最后确认整体同步、最终原生备份和交付结果。

## 5. 暂停备份

本次[原生暂停备份](../../design/订阅额度%20iPhone%20原型-R4-检查暂停点-2026-10-09.fig)已保存并核验：**10,293,242 字节**，SHA-256 `f795c2d9c5a842126ee60ccd7a836c1120a5916dc00d5612b73198dd48cf9359`。ZIP 无坏成员，包含 `canvas.fig`、`thumbnail.png`、`meta.json`、`images/` 四项。

该备份包含当前浅深 cleanup、arrange 和 entries 状态，两候选修复均未应用；**这是暂停检查点，不是最终交付备份**。此前阶段备份继续保留，路径与散列见 [state](../../design/figma-state.json) 的检查点历史。

## 6. 状态解释与恢复历史

[figma-state.json](../../design/figma-state.json) 的 `currentRound` 和[实时进度](../../design/figma-r4-live-progress.json)记录本轮，均为 `paused_by_user`；顶层 R3 内容保留为最近完整验收历史，不能据此误读本轮仍未写入。[10 月 8 日交接](figma-handoff-2026-10-08.md)也是历史材料。

重要恢复过程保留在 state：编辑器最初恢复时核对四区与 R3 基线一致；之后出现过内存耗尽、临时桌面迟滞及两次工具确认锁屏，均已恢复。没有为恢复删除旧归档根或新建文件，不推断各事件间因果。原生 AX 仍含本地保存、重连后同步的未保存更改提示；即使两入口已发布，也不等于所有更改云端同步已确认。浅色 cleanup 的 0／23／31 部分创建计数未知，不推断总量；第一次排布会话无完成回执，不推断零写入，最终以成功回执为准。

本轮现已按用户要求暂停。保存证据后不继续工作；仅在用户明确恢复后，处理开放问题、重做最终审计并补齐最终备份和整体云端确认。无需重跑已完成的生成、cleanup、arrange 或 entries。
