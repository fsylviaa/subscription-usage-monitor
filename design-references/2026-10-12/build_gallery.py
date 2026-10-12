#!/usr/bin/env python3
"""Generate a local reference gallery from two independent JSON batches."""

import json
from html import escape
from pathlib import Path


BASE = Path(__file__).resolve().parent
OUTPUT = BASE / "dist" / "index.html"
SOURCE = BASE / "references.json"
SECOND_SOURCE = BASE / "references-batch-2.json"
SELECTED_SOURCE = BASE / "selected-references.json"


def render_cards(references, id_prefix="reference"):
    cards = []
    for item in references:
        number = f"{int(item['id']):02d}"
        title = escape(str(item["title"]))
        source = escape(str(item["source"]))
        url = escape(str(item["url"]), quote=True)
        image = escape(str(item["image"]), quote=True)
        cards.append(f"""<article class="card" id="{id_prefix}-{number}">
  <a class="preview" href="{url}" target="_blank" rel="noopener noreferrer"><img src="{image}" alt="{number} · {title}" decoding="async"></a>
  <div class="caption"><h2><span>{number}</span> {title}</h2><p>{source} · <a href="{url}" target="_blank" rel="noopener noreferrer">查看原作 ↗</a></p></div>
</article>""")

    return "\n".join(cards) if cards else '<p class="empty">原作截图和链接整理后将显示在这里。</p>'


def render_selected_cards(references, second_references, selected_mappings):
    batches = {
        1: {int(item["id"]): item for item in references},
        2: {int(item["id"]): item for item in second_references},
    }
    cards = []
    for selection in selected_mappings:
        number = int(selection["id"])
        batch = int(selection["batch"])
        original_number = int(selection["original_id"])
        item = batches[batch][original_number]
        title = escape(str(item["title"]))
        source = escape(str(item["source"]))
        url = escape(str(item["url"]), quote=True)
        image = escape(str(item["image"]), quote=True)
        batch_name = "第一批" if batch == 1 else "第二批"
        cards.append(f"""<article class="card" id="selected-reference-{number}">
  <a class="preview" href="{url}" target="_blank" rel="noopener noreferrer"><img src="{image}" alt="选中 {number} · {title}" decoding="async"></a>
  <div class="caption"><h2><span class="selection-number">{number}</span> {title}</h2><p class="origin">{batch_name} · 原编号 {original_number:02d}</p><p>{source} · <a href="{url}" target="_blank" rel="noopener noreferrer">查看原作 ↗</a></p></div>
</article>""")
    return "\n".join(cards) if cards else '<p class="empty">选中的参考将显示在这里。</p>'


def build_gallery(references, second_references, selected_mappings=()):
    count = len(references) + len(second_references)
    status = f"{count} 个原作参考 · 选中 {len(selected_mappings)} 个 · 点击截图或原作链接查看详情" if count else "正在搜集原作参考"
    first_content = render_cards(references)
    second_content = render_cards(second_references, "reference-batch-2")
    selected_content = render_selected_cards(references, second_references, selected_mappings)
    return f"""<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>首页卡片 · 设计参考初筛</title>
<style>
*{{box-sizing:border-box}}body{{margin:0;background:#f4f4f4;color:#202020;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}}main{{max-width:1560px;margin:auto;padding:32px 24px}}header{{margin-bottom:24px}}h1{{margin:0 0 8px;font-size:26px}}header p{{margin:0;color:#666;font-size:15px}}.grid{{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:20px}}.card{{overflow:hidden;background:white;border:1px solid #ddd;border-radius:10px}}.preview{{display:flex;align-items:center;justify-content:center;height:300px;background:#fafafa}}.preview img{{display:block;width:100%;height:100%;object-fit:contain}}.caption{{padding:14px 16px 16px}}h2{{margin:0;font-size:16px;line-height:1.5;font-weight:600;overflow-wrap:anywhere}}h2 span{{color:#777}}.caption p{{margin:8px 0 0;font-size:14px;color:#666}}a{{color:#2458b5;text-underline-offset:3px}}.empty{{grid-column:1/-1;color:#666}}@media(max-width:1050px){{.grid{{grid-template-columns:repeat(2,minmax(0,1fr))}}}}@media(max-width:650px){{main{{padding:24px 16px}}.grid{{grid-template-columns:1fr}}.preview{{height:280px}}}}
.tabs{{display:flex;gap:8px;margin-bottom:20px}}.tab{{padding:10px 16px;border:1px solid #ccc;border-radius:8px;background:transparent;color:#555;font:inherit;cursor:pointer}}.tab[aria-selected="true"]{{background:#202020;border-color:#202020;color:white}}.tab:focus-visible{{outline:2px solid #2458b5;outline-offset:3px}}
h2 .selection-number{{display:inline-flex;align-items:center;justify-content:center;min-width:30px;height:30px;margin-right:4px;padding:0 6px;border-radius:6px;background:#202020;color:white;font-size:18px;vertical-align:middle}}.caption .origin{{font-size:13px}}
</style>
</head>
<body>
<main>
<header><h1>首页卡片 · 设计参考初筛</h1><p>{status}</p></header>
<div class="tabs" role="tablist" aria-label="参考批次">
<button class="tab" type="button" role="tab" id="batch-1-tab" aria-controls="batch-1" aria-selected="false" tabindex="-1">第一批30个</button>
<button class="tab" type="button" role="tab" id="batch-2-tab" aria-controls="batch-2" aria-selected="false" tabindex="-1">第二批30个</button>
<button class="tab" type="button" role="tab" id="selected-tab" aria-controls="selected" aria-selected="true" tabindex="0">选中的</button>
</div>
<section role="tabpanel" id="batch-1" aria-labelledby="batch-1-tab" hidden>
<div class="grid">
{first_content}
</div>
</section>
<section role="tabpanel" id="batch-2" aria-labelledby="batch-2-tab" hidden>
<div class="grid">
{second_content}
</div>
</section>
<section role="tabpanel" id="selected" aria-labelledby="selected-tab">
<div class="grid">
{selected_content}
</div>
</section>
</main>
<script>
{{
  const tabs = Array.from(document.querySelectorAll('[role="tab"]'));
  function selectTab(selected) {{
    tabs.forEach(tab => {{
      const active = tab === selected;
      tab.setAttribute('aria-selected', String(active));
      tab.tabIndex = active ? 0 : -1;
      document.getElementById(tab.getAttribute('aria-controls')).hidden = !active;
    }});
  }}
  tabs.forEach((tab, index) => {{
    tab.addEventListener('click', () => selectTab(tab));
    tab.addEventListener('keydown', event => {{
      let next;
      if (event.key === 'ArrowRight') next = (index + 1) % tabs.length;
      else if (event.key === 'ArrowLeft') next = (index - 1 + tabs.length) % tabs.length;
      else if (event.key === 'Home') next = 0;
      else if (event.key === 'End') next = tabs.length - 1;
      else return;
      event.preventDefault();
      selectTab(tabs[next]);
      tabs[next].focus();
    }});
  }});
}}
</script>
</body>
</html>
"""


if __name__ == "__main__":
    references = json.loads(SOURCE.read_text(encoding="utf-8")) if SOURCE.exists() else []
    second_references = json.loads(SECOND_SOURCE.read_text(encoding="utf-8")) if SECOND_SOURCE.exists() else []
    selected_mappings = json.loads(SELECTED_SOURCE.read_text(encoding="utf-8")) if SELECTED_SOURCE.exists() else []
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(build_gallery(references, second_references, selected_mappings), encoding="utf-8")
    print(f"Generated {OUTPUT} ({len(references)} + {len(second_references)} references; {len(selected_mappings)} selected)")
