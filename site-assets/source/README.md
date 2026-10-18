# 素材源文件

- `01-cover.html` … `06-app-icon.html`：每张图的设计稿，共用 `kit.css`（样式）和 `kit.js`（平台列表、手机、手表、额度环等组件）。
- `logos/`：平台 Logo，来自 Lobe Icons（@lobehub/icons-static-svg 1.95.1）。Muse Code 使用 Meta 标识。
- 修改后重新导出全部图片：`./render.sh`；只导出一张：`./render.sh 01-cover 1600 900`。需要本机已安装 Google Chrome，图片输出到 `../images/`，按 2 倍分辨率导出。
- 新增平台：在 `kit.js` 的 `PLATFORMS` 里加一行，并把 Logo 放进 `logos/`。
