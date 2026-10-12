# App 图标

用户于2026-10-12明确选定并授权保存为本项目App图标。D-70正式显示名称为“Token 仪表盘”；用户随后明确授权同步主App／组件扩展显示名，并覆盖安装本人手机。首次仅保存资源的历史结果见T63追加记录。

- 原始设计：[AppIcon-source.png](AppIcon-source.png)，1254×1254、不透明PNG，与会话最后一张黑色指针版本逐字节一致。
- 实际图标：[AppIcon.png](../Assets.xcassets/AppIcon.appiconset/AppIcon.png)，1024×1024、不透明PNG；仅对原图等比缩小，没有重新生成或更改造型。
- 配置：`AppIcon.appiconset`采用单一iOS通用1024图；主App Debug／Release指定`ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`，由Xcode生成各显示尺寸。系统处理外部圆角，不在资源里预裁切圆角。
- 视觉：浅底；汽车仪表的粗弧与五道深灰刻度；指针朝右上、圆形轴心与指针为黑色；外圈从左侧红端，经橙／黄／粉紫／蓝／青，连续渐变到右侧绿端，颜色鲜艳饱满。
- 生成方式：内置ImageGen，依次选择仪表造型、调整指针和外圈配色；最后一次编辑要求仅将橙色指针及轴心改为纯黑，保留彩色外圈、五道刻度、浅色背景与原布局。
- 原图SHA-256：`21bbbdde9651b3d5e08962ae42b5847e06b5f54a2c460339a75ad0d516a0e8ba`。
- 1024图SHA-256：`afc2746b0ceca7a50739d0d5a2dfa26fea6b473e3ddb57276471b411c16633c8`。

验收与保存范围见[T63记录](../../docs/mvp任务清单/记录/T63-验收.md)。原始设计留在此目录供后续修改，不作为额外运行时资源复制进App。
