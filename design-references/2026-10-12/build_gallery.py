#!/usr/bin/env python3
"""Generate a local, static reference gallery from references.json."""

import json
from html import escape
from pathlib import Path


BASE = Path(__file__).resolve().parent
OUTPUT = BASE / "dist" / "index.html"
SOURCE = BASE / "references.json"


def build_gallery(references):
    cards = []
    for item in references:
        number = f"{int(item['id']):02d}"
        title = escape(str(item["title"]))
        source = escape(str(item["source"]))
        url = escape(str(item["url"]), quote=True)
        image = escape(str(item["image"]), quote=True)
        cards.append(f"""<article class="card" id="reference-{number}">
  <a class="preview" href="{url}" target="_blank" rel="noopener noreferrer"><img src="{image}" alt="{number} · {title}" decoding="async"></a>
  <div class="caption"><h2><span>{number}</span> {title}</h2><p>{source} · <a href="{url}" target="_blank" rel="noopener noreferrer">查看原作 ↗</a></p></div>
</article>""")

    count = len(references)
    status = f"{count} 个原作参考 · 点击截图或原作链接查看详情" if count else "正在搜集 30 个原作参考"
    content = "\n".join(cards) if cards else '<p class="empty">原作截图和链接整理后将显示在这里。</p>'
    return f"""<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>首页卡片 · 设计参考初筛</title>
<style>
*{{box-sizing:border-box}}body{{margin:0;background:#f4f4f4;color:#202020;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}}main{{max-width:1560px;margin:auto;padding:32px 24px}}header{{margin-bottom:24px}}h1{{margin:0 0 8px;font-size:26px}}header p{{margin:0;color:#666;font-size:15px}}.grid{{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:20px}}.card{{overflow:hidden;background:white;border:1px solid #ddd;border-radius:10px}}.preview{{display:flex;align-items:center;justify-content:center;height:300px;background:#fafafa}}.preview img{{display:block;width:100%;height:100%;object-fit:contain}}.caption{{padding:14px 16px 16px}}h2{{margin:0;font-size:16px;line-height:1.5;font-weight:600;overflow-wrap:anywhere}}h2 span{{color:#777}}.caption p{{margin:8px 0 0;font-size:14px;color:#666}}a{{color:#2458b5;text-underline-offset:3px}}.empty{{grid-column:1/-1;color:#666}}@media(max-width:1050px){{.grid{{grid-template-columns:repeat(2,minmax(0,1fr))}}}}@media(max-width:650px){{main{{padding:24px 16px}}.grid{{grid-template-columns:1fr}}.preview{{height:280px}}}}
</style>
</head>
<body>
<main>
<header><h1>首页卡片 · 设计参考初筛</h1><p>{status}</p></header>
<div class="grid">
{content}
</div>
</main>
</body>
</html>
"""


if __name__ == "__main__":
    references = json.loads(SOURCE.read_text(encoding="utf-8")) if SOURCE.exists() else []
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(build_gallery(references), encoding="utf-8")
    print(f"Generated {OUTPUT} ({len(references)} references)")
