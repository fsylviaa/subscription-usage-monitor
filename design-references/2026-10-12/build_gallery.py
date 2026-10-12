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
DETAILS_SOURCE = BASE / "adaptation-details.json"


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


def render_prototype(number):
    kind = {1: "skala", 2: "capsule", 3: "ticks"}[number]
    rows, controls = [], []
    for key, name, remaining, reset in (
        ("week", "每周额度", 73, "10月19日 09:00"),
        ("five", "5小时额度", 50, "今日 23:30"),
    ):
        uid = f"q{number}-{key}"
        width = (100 - remaining) * 10
        defs = f'<clipPath id="{uid}-used"><rect data-used-clip x="0" y="0" width="{width}" height="80"/></clipPath>'
        defs += f'<clipPath id="{uid}-change"><rect data-accent-clip x="0" y="0" width="0" height="80"/></clipPath>'
        if kind == "capsule":
            defs += f'''<linearGradient id="{uid}-color" x1="0" x2="1000" gradientUnits="userSpaceOnUse"><stop stop-color="#9cee75"/><stop offset=".35" stop-color="#71e9c3"/><stop offset="1" stop-color="#b3f6e9"/></linearGradient>
<filter id="{uid}-blur" x="-30%" y="-100%" width="160%" height="300%"><feGaussianBlur stdDeviation="10"/></filter>
<clipPath id="{uid}-track"><rect x="0" y="22" width="1000" height="36" rx="18" ry="18" data-track-pill/></clipPath>'''
            drawing = f'''<rect x="0" y="22" width="1000" height="36" rx="18" ry="18" data-track-pill fill="#414744"/>
<g clip-path="url(#{uid}-used)"><g clip-path="url(#{uid}-track)">
<rect data-pill x="0" y="22" width="{width}" height="36" rx="18" ry="18" fill="url(#{uid}-color)"/>
<rect data-glow x="0" y="29" width="1000" height="20" rx="10" fill="#ecfff3" filter="url(#{uid}-blur)" opacity=".25"/>
<path d="M 0 26 H 1000" stroke="#ffffff" opacity=".12"/></g></g>'''
        else:
            elements, neutral = [], []
            palette = ["#6fd8b4", "#7fcde4", "#7d8bdf", "#b688dd", "#f57ea5", "#e9d86d"]
            if kind == "skala":
                for column in range(32):
                    for row in range(3):
                        x = 16 + column * (968 / 31)
                        y = 12 + row * 22
                        shape = f'<rect x="{x-15:.3f}" y="{y}" width="30" height="6" rx="3" data-grain data-cx="{x:.3f}" data-cy="{y+3}" transform="rotate(45 {x:.3f} {y+3})"'
                        neutral.append(shape + ' fill="#3c4048"/>')
                        elements.append(shape + f' fill="{palette[(column+row*2)%len(palette)]}"/>')
            else:
                for column in range(100):
                    x = column * (994 / 99)
                    shape = f'<rect x="{x:.3f}" y="14" width="6" height="52" rx="1"'
                    neutral.append(shape + ' fill="#36383c"/>')
                    elements.append(shape + ' fill="#e9ebee"/>')
            texture = ''.join(elements)
            accent_texture = texture.replace('#e9ebee', '#ffffff') if kind == 'ticks' else texture
            drawing = ''.join(neutral) + f'<g clip-path="url(#{uid}-used)"><g class="quota-surface">{texture}</g><g clip-path="url(#{uid}-change)"><g data-accent opacity="0">{accent_texture}</g></g></g>'
        rows.append(f'''<section class="quota-window" data-window="{key}" aria-label="{name}">
<div class="quota-meta"><div><div class="quota-name">{name}</div><div class="quota-reset">预计重置 · {reset}</div></div><div class="quota-number"><small>剩余</small><strong data-number>{remaining}%</strong></div></div>
<svg class="quota-graph" viewBox="0 0 1000 80" preserveAspectRatio="none" role="slider" tabindex="0" aria-label="方案{number} {name}剩余百分比" aria-valuemin="0" aria-valuemax="100" aria-valuenow="{remaining}" aria-orientation="horizontal"><defs>{defs}</defs>{drawing}</svg>
</section>''')
        controls.append(f'''<label class="quota-control" for="{uid}-input"><span class="quota-control-line"><span>{name} · 剩余百分比</span><output data-output="{key}" for="{uid}-input">{remaining}%</output></span><input id="{uid}-input" data-control="{key}" type="range" min="0" max="100" step="0.1" value="{remaining}" aria-label="方案{number} {name}剩余百分比精调"></label>''')
    return f'''<div class="prototype-stage {kind}"><div class="quota-account"><div class="quota-head"><div><div class="quota-brand">Codex <span class="quota-plan">· Plus</span> <span class="quota-chevron" aria-hidden="true">⌄</span></div><div class="quota-email">preview@example.com</div></div><span class="quota-demo">模拟</span></div>{''.join(rows)}</div></div>
<div class="quota-controls">{''.join(controls)}<div class="quota-actions"><button class="quota-play" type="button" data-demo>演示变化</button><button class="adaptation-button quota-detail" type="button" data-detail-target="detail-{number}" aria-haspopup="dialog" aria-controls="detail-{number}">原图与适配说明</button></div><p class="quota-help">可拖动额度图形，滑块精调剩余。实色表示已用；时间与数值均为模拟。</p></div>'''


def render_selected_cards(references, second_references, selected_mappings, adaptation_details=()):
    batches = {
        1: {int(item["id"]): item for item in references},
        2: {int(item["id"]): item for item in second_references},
    }
    details = {int(item["id"]): item for item in adaptation_details}
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
        if number in (1, 2, 3) and number in details:
            kind = {1: "skala", 2: "capsule", 3: "ticks"}[number]
            cards.append(f"""<article class="card prototype-card" id="selected-reference-{number}" data-prototype="{kind}">
{render_prototype(number)}
  <div class="caption"><h2><span class="selection-number">{number}</span> {title}</h2><p class="origin">{batch_name} · 原编号 {original_number:02d}</p><p>{source} · <a href="{url}" target="_blank" rel="noopener noreferrer">查看原作 ↗</a></p></div>
</article>""")
        elif number in details:
            cards.append(f"""<article class="card selected-card" id="selected-reference-{number}" data-detail-target="detail-{number}" tabindex="0" aria-label="查看选中参考 {number} 的适配说明" aria-haspopup="dialog" aria-controls="detail-{number}">
  <button class="preview detail-preview" type="button" aria-label="查看选中参考 {number} 的适配说明"><img src="{image}" alt="选中 {number} · {title}" decoding="async"></button>
  <div class="caption"><h2><span class="selection-number">{number}</span> {title}</h2><p class="origin">{batch_name} · 原编号 {original_number:02d}</p><p>{source} · <a href="{url}" target="_blank" rel="noopener noreferrer">查看原作 ↗</a></p><p><button class="adaptation-button" type="button">查看适配说明</button></p></div>
</article>""")
        else:
            cards.append(f"""<article class="card" id="selected-reference-{number}">
  <a class="preview" href="{url}" target="_blank" rel="noopener noreferrer"><img src="{image}" alt="选中 {number} · {title}" decoding="async"></a>
  <div class="caption"><h2><span class="selection-number">{number}</span> {title}</h2><p class="origin">{batch_name} · 原编号 {original_number:02d}</p><p>{source} · <a href="{url}" target="_blank" rel="noopener noreferrer">查看原作 ↗</a></p></div>
</article>""")
    return "\n".join(cards) if cards else '<p class="empty">选中的参考将显示在这里。</p>'


def render_detail_dialogs(references, second_references, selected_mappings, adaptation_details):
    batches = {
        1: {int(item["id"]): item for item in references},
        2: {int(item["id"]): item for item in second_references},
    }
    details = {int(item["id"]): item for item in adaptation_details}
    dialogs = []
    for selection in selected_mappings:
        number = int(selection["id"])
        if number not in details:
            continue
        detail = details[number]
        batch = int(selection["batch"])
        original_number = int(selection["original_id"])
        original = batches[batch][original_number]
        title = escape(str(original["title"]))
        source = escape(str(original["source"]))
        url = escape(str(original["url"]), quote=True)
        image = escape(str(original["image"]), quote=True)
        batch_name = "第一批" if batch == 1 else "第二批"
        direction = escape(str(detail["direction"]))
        summary = escape(str(detail["summary"]))
        figma_prompt = escape(str(detail["figma_prompt"]))
        sections = []
        for section in detail["sections"]:
            section_title = escape(str(section["title"]))
            paragraphs = "\n".join(f"<p>{escape(str(paragraph))}</p>" for paragraph in section["paragraphs"])
            sections.append(f"<section class=\"adaptation-section\"><h3>{section_title}</h3>{paragraphs}</section>")
        sections_html = "\n".join(sections)
        notice = ("已制作网页交互样机，正式 App 尚未采用；此处保留原图和原适配说明。拖动与滑块仅用于网页模拟，数字显示剩余、实色表示已用；下文禁止拖动指正式 App，原作动画未验证。" if number in (1, 2, 3) else "文字方案待选，尚未制作适配原型；示例非实时数据。数字显示剩余，实色表示已用；动效仅为建议，原作动画未验证，不新增 App 功能。")
        dialogs.append(f"""<dialog class="detail-dialog" id="detail-{number}" aria-labelledby="detail-title-{number}" aria-describedby="detail-note-{number}">
<div class="detail-shell">
  <header class="detail-header"><h2 id="detail-title-{number}"><span class="selection-number">{number}</span> {title}</h2><button class="detail-close" type="button" data-close-dialog autofocus aria-label="关闭参考 {number} 的适配说明">关闭</button></header>
  <div class="detail-body">
    <p class="detail-origin">{batch_name} · 原编号 {original_number:02d} · {source} · <a href="{url}" target="_blank" rel="noopener noreferrer">查看原作 ↗</a></p>
    <p class="detail-notice" id="detail-note-{number}">{notice}</p>
    <a class="detail-image-link" href="{url}" target="_blank" rel="noopener noreferrer"><img class="detail-image" src="{image}" alt="参考 {number} · {title} 原作截图" decoding="async"></a>
    <div class="adaptation-text"><p class="detail-direction"><strong>适配方向：</strong>{direction}</p><p class="detail-summary">{summary}</p>
{sections_html}
      <section class="adaptation-section"><h3>后续 Figma 绘制描述</h3><p class="figma-description">{figma_prompt}</p></section>
    </div>
  </div>
</div>
</dialog>""")
    return "\n".join(dialogs)


def build_gallery(references, second_references, selected_mappings=(), adaptation_details=()):
    count = len(references) + len(second_references)
    guidance = "选中1—3可拖动预览；原图与适配说明见独立入口" if adaptation_details else "点击截图或原作链接查看详情"
    status = f"{count} 个原作参考 · 选中 {len(selected_mappings)} 个 · {guidance}" if count else "正在搜集原作参考"
    first_content = render_cards(references)
    second_content = render_cards(second_references, "reference-batch-2")
    selected_content = render_selected_cards(references, second_references, selected_mappings, adaptation_details)
    detail_dialogs = render_detail_dialogs(references, second_references, selected_mappings, adaptation_details)
    prototype_css = (BASE / "prototype.css").read_text(encoding="utf-8")
    prototype_js = (BASE / "prototype.js").read_text(encoding="utf-8")
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
.selected-card{{cursor:pointer}}.selected-card:focus-visible{{outline:2px solid #2458b5;outline-offset:3px}}.detail-preview{{width:100%;border:0;padding:0;cursor:pointer}}.adaptation-button{{border:0;padding:0;background:none;color:#2458b5;text-decoration:underline;text-underline-offset:3px;font:inherit;cursor:pointer}}.detail-dialog{{width:min(1040px,calc(100vw - 32px));max-width:calc(100vw - 32px);max-height:calc(100dvh - 32px);padding:0;border:1px solid #ddd;border-radius:12px;color:#202020;overflow:hidden}}.detail-dialog::backdrop{{background:rgba(0,0,0,.45)}}.detail-shell{{display:flex;flex-direction:column;max-height:calc(100dvh - 32px)}}.detail-header{{display:flex;align-items:center;justify-content:space-between;gap:16px;flex:none;margin:0;padding:16px 20px;border-bottom:1px solid #ddd;background:white}}.detail-header h2{{font-size:18px}}.detail-close{{flex:none;padding:9px 16px;border:1px solid #bbb;border-radius:7px;background:white;color:#202020;font:inherit;cursor:pointer}}.detail-close:focus-visible,.detail-preview:focus-visible,.adaptation-button:focus-visible{{outline:2px solid #2458b5;outline-offset:3px}}.detail-body{{min-height:0;overflow:auto;overscroll-behavior:contain;padding:20px 24px 32px;line-height:1.75}}.detail-origin{{margin:0 0 12px;color:#666;font-size:14px}}.detail-notice{{margin:0 0 20px;padding:12px 16px;border:1px solid #ddd;border-radius:8px;background:#f7f7f7;font-size:14px;color:#555}}.detail-image-link{{display:block;margin-bottom:24px;background:#fafafa}}.detail-image{{display:block;width:100%;height:auto;max-height:260px;object-fit:contain}}.adaptation-text{{max-width:760px;margin:auto}}.detail-direction{{margin:0 0 10px;font-size:18px}}.detail-summary{{margin:0 0 24px}}.adaptation-section{{margin-top:24px}}.adaptation-section h3{{margin:0 0 8px;font-size:18px}}.adaptation-section p{{margin:0 0 10px;overflow-wrap:anywhere}}.figma-description{{white-space:pre-wrap;padding:14px 16px;background:#f7f7f7;border:1px solid #ddd;border-radius:8px}}@media(max-width:650px){{.detail-header{{padding:12px 14px;gap:10px}}.detail-header h2{{font-size:16px}}.detail-close{{padding:8px 12px}}.detail-body{{padding:16px 16px 24px}}}}
{prototype_css}
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
{detail_dialogs}
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
  const dialogOpeners = new WeakMap();
  function openDetail(id, opener) {{
    const dialog = document.getElementById(id);
    if (!dialog || dialog.open) return;
    dialogOpeners.set(dialog, {{ opener, overflow: document.body.style.overflow }});
    dialog.showModal();
    document.body.style.overflow = 'hidden';
    dialog.querySelector('.detail-body').scrollTop = 0;
    dialog.querySelector('[data-close-dialog]').focus();
  }}
  document.querySelectorAll('[data-detail-target]').forEach(card => {{
    card.addEventListener('click', event => {{
      if (event.target.closest('a[href]')) return;
      openDetail(card.dataset.detailTarget, event.target.closest('button') || card);
    }});
    card.addEventListener('keydown', event => {{
      if (event.target !== card || !['Enter', ' '].includes(event.key)) return;
      event.preventDefault();
      openDetail(card.dataset.detailTarget, card);
    }});
  }});
  document.querySelectorAll('.detail-dialog').forEach(dialog => {{
    dialog.querySelector('[data-close-dialog]').addEventListener('click', () => dialog.close());
    dialog.addEventListener('click', event => {{
      if (event.target !== dialog) return;
      const bounds = dialog.getBoundingClientRect();
      if (event.clientX < bounds.left || event.clientX > bounds.right || event.clientY < bounds.top || event.clientY > bounds.bottom) dialog.close();
    }});
    dialog.addEventListener('close', () => {{
      const state = dialogOpeners.get(dialog);
      if (!state) return;
      document.body.style.overflow = state.overflow;
      if (state.opener && state.opener.isConnected) state.opener.focus({{ preventScroll: true }});
      dialogOpeners.delete(dialog);
    }});
  }});
}}
{prototype_js}
</script>
</body>
</html>
"""


if __name__ == "__main__":
    references = json.loads(SOURCE.read_text(encoding="utf-8")) if SOURCE.exists() else []
    second_references = json.loads(SECOND_SOURCE.read_text(encoding="utf-8")) if SECOND_SOURCE.exists() else []
    selected_mappings = json.loads(SELECTED_SOURCE.read_text(encoding="utf-8")) if SELECTED_SOURCE.exists() else []
    adaptation_details = json.loads(DETAILS_SOURCE.read_text(encoding="utf-8")) if DETAILS_SOURCE.exists() else []
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(build_gallery(references, second_references, selected_mappings, adaptation_details), encoding="utf-8")
    print(f"Generated {OUTPUT} ({len(references)} + {len(second_references)} references; {len(selected_mappings)} selected; {len(adaptation_details)} details)")
