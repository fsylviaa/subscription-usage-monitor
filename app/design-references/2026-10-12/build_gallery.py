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


def render_prototype(number, theme):
    if number > 3:
        return render_extra_prototype(number, theme)
    kind = {1: "skala", 2: "capsule", 3: "ticks"}[number]
    rows = []
    for key, name, remaining, reset in (
        ("week", "每周额度", 73, "10月19日 09:00"),
        ("five", "5小时额度", 50, "今日 23:30"),
    ):
        uid = f"q{number}-{key}-{theme}"
        width = remaining * 10
        defs = f'<clipPath id="{uid}-remaining"><rect data-remaining-clip x="0" y="0" width="{width}" height="80"/></clipPath>'
        defs += f'<clipPath id="{uid}-change"><rect data-accent-clip x="0" y="0" width="0" height="80"/></clipPath>'
        if kind == "capsule":
            defs += f'''<linearGradient id="{uid}-color" x1="0" x2="1000" gradientUnits="userSpaceOnUse"><stop stop-color="#9cee75"/><stop offset=".35" stop-color="#71e9c3"/><stop offset="1" stop-color="#b3f6e9"/></linearGradient>
<filter id="{uid}-blur" x="-30%" y="-100%" width="160%" height="300%"><feGaussianBlur stdDeviation="10"/></filter>
<clipPath id="{uid}-track"><rect x="0" y="22" width="1000" height="36" rx="18" ry="18" data-track-pill/></clipPath>'''
            drawing = f'''<rect x="0" y="22" width="1000" height="36" rx="18" ry="18" data-track-pill class="quota-neutral-pill" fill="#414744"/>
<g clip-path="url(#{uid}-remaining)"><g clip-path="url(#{uid}-track)">
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
                        neutral.append(shape + ' class="quota-neutral-grain" fill="#3c4048"/>')
                        elements.append(shape + f' fill="{palette[(column+row*2)%len(palette)]}"/>')
            else:
                for column in range(100):
                    x = column * (994 / 99)
                    shape = f'<rect x="{x:.3f}" y="14" width="6" height="52" rx="1"'
                    neutral.append(shape + ' class="quota-neutral-tick" fill="#36383c"/>')
                    elements.append(shape + ' fill="#e9ebee"/>')
            if kind == 'ticks':
                neutral.insert(0, '<rect class="quota-tick-bed" x="0" y="14" width="1000" height="52" rx="2" fill="none"/>')
            texture = ''.join(elements)
            accent_texture = texture.replace('#e9ebee', '#ffffff') if kind == 'ticks' else texture
            drawing = ''.join(neutral) + f'<g clip-path="url(#{uid}-remaining)"><g class="quota-surface">{texture}</g><g clip-path="url(#{uid}-change)"><g data-accent opacity="0">{accent_texture}</g></g></g>'
        rows.append(f'''<section class="quota-window" data-window="{key}" aria-label="{name}">
<div class="quota-meta"><div><div class="quota-name">{name}</div><div class="quota-reset">下次重置 · {reset}</div></div><div class="quota-number"><small>剩余</small><strong data-number>{remaining}%</strong></div></div>
<svg class="quota-graph" viewBox="0 0 1000 80" preserveAspectRatio="none" role="slider" tabindex="0" aria-label="方案{number} {'暗色' if theme == 'dark' else '亮色'} {name}剩余百分比" aria-valuemin="0" aria-valuemax="100" aria-valuenow="{remaining}" aria-orientation="horizontal"><defs>{defs}</defs>{drawing}</svg>
</section>''')
    return f"""<div class="prototype-stage {kind}"><div class="quota-account"><div class="quota-head"><div class="quota-brand">Codex <span class="quota-plan">· Plus</span></div></div>{''.join(rows)}</div></div>"""



def render_extra_prototype(number, theme):
    """Eight distinct geometries; old 1–3 rendering stays byte-for-byte unchanged."""
    kinds = {4:'dials', 5:'island', 6:'blocks', 7:'liquid', 8:'ticket', 9:'journal', 10:'glass', 11:'panels'}
    kind = kinds[number]
    rows = []
    for key, name, value, reset in (("week", "每周额度", 73, "10月19日 09:00"), ("five", "5小时额度", 50, "今日 23:30")):
        uid = f'q{number}-{key}-{theme}'
        meta = f'<div class="quota-meta"><div><div class="quota-name">{name}</div><div class="quota-reset">下次重置 · {reset}</div></div><div class="quota-number"><small>剩余</small><strong data-number>{value}%</strong></div></div>'
        defs, art = '', ''
        box, orientation = '0 0 1000 160', 'horizontal'
        if kind == 'dials':
            box = '0 0 240 220'
            # 270 degrees, clockwise from the lower left. pathLength uses exact percent arc length.
            arc = 'M 56.3604 179.6396 A 90 90 0 1 1 183.6396 179.6396'
            defs = f'<mask id="{uid}-arc" maskUnits="userSpaceOnUse" x="0" y="0" width="240" height="220"><path d="{arc}" fill="none" stroke="white" stroke-width="44" pathLength="100" stroke-dasharray="{value} 100" data-dial-fill/></mask>'
            ticks = []
            import math
            for i in range(61):
                a = math.radians(135+i*4.5); r = 99 if i%5==0 else 102
                ticks.append(f'<line x1="{120+r*math.cos(a):.4f}" y1="{116+r*math.sin(a):.4f}" x2="{120+109*math.cos(a):.4f}" y2="{116+109*math.sin(a):.4f}" stroke-width="{2 if i%5==0 else 1}"/>')
            art = f'<circle cx="120" cy="116" r="81" class="dial-face"/><path d="{arc}" fill="none" class="extra-neutral" stroke-width="10"/><g class="dial-muted">{"".join(ticks)}</g><path d="{arc}" fill="none" class="dial-active" stroke-width="10" pathLength="100" stroke-dasharray="{value} 100" data-dial-fill/><g class="dial-active" mask="url(#{uid}-arc)">{"".join(ticks)}</g><g data-needle transform="rotate({135+value*2.7} 120 116)"><path d="M 192 116 L 217 116" class="dial-needle" stroke-width="3"/></g><circle cx="120" cy="116" r="65" class="dial-inner"/>'
        elif kind == 'liquid':
            box, orientation = '0 0 160 240', 'vertical'
            defs = f'<linearGradient id="{uid}-fluid" x1="0" y1="0" x2="0" y2="1"><stop stop-color="#93f47e"/><stop offset=".5" stop-color="#48c570"/><stop offset="1" stop-color="#187b63"/></linearGradient><clipPath id="{uid}-vessel"><rect x="28" y="20" width="104" height="200"/></clipPath><clipPath id="{uid}-fluid-area"><path data-liquid-clip d="M28 {220-value*2} H132 V220 H28 Z"/></clipPath>'
            art = f'<rect x="20" y="12" width="120" height="216" rx="25" class="vessel-shell"/><rect x="28" y="20" width="104" height="200" class="liquid-used extra-neutral"/><g clip-path="url(#{uid}-vessel)"><path data-liquid d="M28 {220-value*2} H132 V220 H28 Z" fill="url(#{uid}-fluid)"/><path data-meniscus fill="none" stroke="#c3ffc0" stroke-width="1.5"/><g clip-path="url(#{uid}-fluid-area)"><g data-fluid-bubbles fill="#ddffd3" opacity=".28"><circle cx="53" cy="183" r="3"/><circle cx="98" cy="158" r="2"/></g><path data-liquid-shine d="M35 25 H41 V220 H35 Z" fill="white" opacity=".12"/></g></g><path d="M24 190 V42 Q24 20 43 17" fill="none" class="vessel-shine" stroke-width="2"/>'
        else:
            # Active coordinate span is exactly 0..1000. Shells and caps are excluded.
            defs = f'<clipPath id="{uid}-remaining"><rect data-extra-clip x="0" y="0" width="{value*10}" height="160"/></clipPath><clipPath id="{uid}-change"><rect data-extra-change x="0" y="0" width="0" height="160"/></clipPath>'
            if kind == 'island':
                art = f'<rect x="0" y="75" width="1000" height="10" rx="5" class="extra-neutral"/><g clip-path="url(#{uid}-remaining)"><rect x="0" y="75" width="1000" height="10" rx="5" class="island-energy"/><rect data-island-light x="0" y="75" width="1000" height="10" fill="#d6ffc2" opacity="0"/></g><line data-boundary x1="{value*10}" x2="{value*10}" y1="74" y2="86" class="island-tip" stroke-width="2"/>'
            elif kind == 'blocks':
                blocks = ''.join(f'<rect x="{i*206}" y="24" width="176" height="112" rx="20"/>' for i in range(5))
                # Five equal blocks, with the last ending exactly at 1000.
                art = f'<rect x="0" y="24" width="1000" height="112" rx="20" class="segment-bed extra-neutral"/><g class="blocks-muted">{blocks}</g><g clip-path="url(#{uid}-remaining)"><g class="blocks-active">{blocks}</g><g clip-path="url(#{uid}-change)" data-extra-accent opacity="0" class="blocks-flash">{blocks}</g></g>'
            elif kind == 'ticket':
                stripes = ''.join(f'<path d="M{i*130-50} 32 H{i*130+55} L{i*130+20} 128 H{i*130-85} Z"/>' for i in range(9))
                art = f'<rect x="0" y="32" width="1000" height="96" class="ticket-bed"/><g class="ticket-muted">{stripes}</g><g clip-path="url(#{uid}-remaining)"><g class="ticket-active">{stripes}</g><g clip-path="url(#{uid}-change)" class="ticket-flash" data-extra-accent opacity="0">{stripes}</g></g>'
            elif kind == 'journal':
                strokes = ''.join(f'<path d="M{i*42+8} {40+(i%3)*3} Q{i*42+3} 80 {i*42+9} {119-(i%4)*3} L{i*42+26} {121-(i%3)*2} Q{i*42+31} 80 {i*42+25} {39+(i%4)*2} Z"/>' for i in range(24))
                art = f'<g class="journal-muted">{strokes}</g><g clip-path="url(#{uid}-remaining)"><g class="journal-active">{strokes}</g><g data-journal-ink opacity="0" class="journal-ink">{strokes}</g></g><path d="M0 21 Q480 12 1000 24 Q997 79 1000 137 Q500 149 0 139 Q4 80 0 21" class="journal-edge" fill="none" stroke-width="9"/>'
            elif kind == 'glass':
                defs += f'<linearGradient id="{uid}-blue" x1="0" y1="0" x2="0" y2="1"><stop stop-color="#d6f5ff"/><stop offset=".2" stop-color="#83dcff"/><stop offset=".55" stop-color="#388af0"/><stop offset="1" stop-color="#78c4ff"/></linearGradient><clipPath id="{uid}-tube"><rect x="0" y="40" width="1000" height="80" rx="40" ry="40" data-tube-pill/></clipPath>'
                art = f'<rect x="0" y="40" width="1000" height="80" rx="40" ry="40" data-tube-pill class="glass-used extra-neutral"/><g clip-path="url(#{uid}-tube)"><g clip-path="url(#{uid}-remaining)"><rect x="0" y="40" width="1000" height="80" fill="url(#{uid}-blue)"/><path d="M0 54 H1000" stroke="white" stroke-width="3" opacity=".6"/><g data-glass-spark opacity=".25" fill="white"><circle cx="125" cy="73" r="3"/><circle cx="460" cy="98" r="2"/><circle cx="640" cy="68" r="2"/></g><rect data-glass-cap x="{value*10-16}" y="45" width="16" height="70" rx="8" fill="#d2f1ff" opacity=".75"/></g></g><rect x="0" y="40" width="1000" height="80" rx="40" ry="40" data-tube-pill class="glass-outline" fill="none" stroke-width="4"/>'
            elif kind == 'panels':
                ticks = ''.join(f'<rect x="{i*25}" y="32" width="13" height="96" rx="3"/>' for i in range(40))
                art = f'<rect x="0" y="32" width="1000" height="96" rx="3" class="panel-bed extra-neutral"/><g class="panel-muted">{ticks}</g><g clip-path="url(#{uid}-remaining)"><g class="panel-active">{ticks}</g><g data-extra-accent opacity="0" clip-path="url(#{uid}-change)" class="panel-flash">{ticks}</g></g>'
        graph = f'<svg class="quota-graph extra-graph" viewBox="{box}" preserveAspectRatio="{ "xMidYMid meet" if kind in ("dials","liquid") else "none" }" role="slider" tabindex="0" aria-label="方案{number} {"暗色" if theme=="dark" else "亮色"} {name}剩余百分比" aria-valuemin="0" aria-valuemax="100" aria-valuenow="{value}" aria-orientation="{orientation}"><defs>{defs}</defs>{art}</svg>'
        if kind == 'dials':
            # Stable central readout, while name and reset stay above the dial.
            meta = f'<div class="quota-name">{name}</div><div class="quota-reset">下次重置 · {reset}</div>'
            graph = f'<div class="dial-wrap">{graph}<div class="dial-readout"><small>剩余</small><strong data-number>{value}%</strong></div></div>'
        if kind == 'island':
            # Rail and readout share a shell, but only the green rail responds to dragging.
            number_markup = f'<div class="quota-number"><small>剩余</small><strong data-number>{value}%</strong></div>'
            meta = f'<div class="quota-name">{name}</div><div class="quota-reset">下次重置 · {reset}</div>'
            graph = f'<div class="island-shell">{graph}{number_markup}</div>'
        rows.append(f'<section class="quota-window extra-window" data-window="{key}" aria-label="{name}">{meta}{graph}</section>')
    return f'<div class="prototype-stage extra-stage {kind}"><div class="quota-account"><div class="quota-head"><div class="quota-brand">Codex <span class="quota-plan">· Plus</span></div></div><div class="extra-windows">{"".join(rows)}</div></div></div>'


def render_prototype_controls(number):
    controls = []
    for key, name, remaining in (("week", "每周额度", 73), ("five", "5小时额度", 50)):
        uid = f"q{number}-{key}"
        controls.append(f"""<label class="quota-control" for="{uid}-input"><span class="quota-control-line"><span>{name} · 剩余百分比</span><output data-output="{key}" for="{uid}-input">{remaining}%</output></span><input id="{uid}-input" data-control="{key}" type="range" min="0" max="100" step="0.1" value="{remaining}" aria-label="方案{number} {name}剩余百分比精调"></label>""")
    help_text = "明暗两版共用数值。亮色表示剩余，灰色表示已用；可拖动图形或精调滑块，时间与数值均为模拟。" if number <= 3 else "明暗两版共用数值。实体／强调部分表示剩余，灰色表示已用；可拖动图形或精调滑块，时间与数值均为模拟。"
    return f"""<div class="quota-controls">{''.join(controls)}<div class="quota-actions"><button class="quota-play" type="button" data-demo>演示变化</button><button class="adaptation-button quota-detail" type="button" data-detail-target="detail-{number}" aria-haspopup="dialog" aria-controls="detail-{number}">原图与适配说明</button></div><p class="quota-help">{help_text}</p></div>"""


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
        if number in range(1, 12) and number in details:
            kind = {1:"skala",2:"capsule",3:"ticks",4:"dials",5:"island",6:"blocks",7:"liquid",8:"ticket",9:"journal",10:"glass",11:"panels"}[number]
            prototype_attr = "data-prototype" if number <= 3 else "data-extra-prototype"
            cards.append(f"""<article class="card prototype-card" id="selected-reference-{number}" {prototype_attr}="{kind}">
<div class="prototype-comparison"><div class="prototype-pair">
<div class="prototype-variant" data-theme="dark"><p class="quota-theme">暗色</p>{render_prototype(number, "dark")}</div>
<div class="prototype-variant" data-theme="light"><p class="quota-theme">亮色</p>{render_prototype(number, "light")}</div>
</div></div>
{render_prototype_controls(number)}
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
        notice = ("已制作网页交互样机，正式 App 尚未采用；此处保留原图和原适配说明。本轮网页明暗并排，数字与亮色均表示剩余、灰色表示已用；旧正文的实色已用、邮箱及箭头建议为历史方案，以当前样机为准。拖动与滑块仅用于网页，原作动画未验证。" if number in (1, 2, 3) else "已制作网页交互样机，正式 App 尚未采用；原图与详细历史说明保留。最新要求：明暗并排、Codex · Plus精简头部、下次重置在窗口名下；数字与实体／强调部分均表示剩余，灰色表示已用，第8款亮版黑色斜块表示剩余。旧正文中的实色已用、邮箱／箭头等建议已被取代；拖动与精调仅属网页模拟，原作动画未验证。")
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


def render_watermark_prototype(theme):
    """Screenshot-inspired candidate 12; isolated from the original eleven."""
    logo = (BASE / "watermark-logo.svg").read_text(encoding="utf-8")
    rows = []
    clock = '<svg class="watermark-clock" viewBox="0 0 24 24" aria-hidden="true"><path d="M3 11a9 9 0 1 1 2.4 7M3 5v6h6M12 7v5l3 2" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg>'
    for key, name, value, reset in (("week", "每周", 73, "3天后 09:57"), ("five", "5 小时", 50, "3小时0分后")):
        uid = f"q12-{key}-{theme}"
        rows.append(f'''<section class="quota-window watermark-window" data-window="{key}" aria-label="{name}额度">
<div class="quota-name">{name}</div><div class="watermark-number"><strong data-number>{value}%</strong></div>
<svg class="quota-graph watermark-graph" viewBox="0 0 1000 28" preserveAspectRatio="none" role="slider" tabindex="0" aria-label="方案12 {"暗色" if theme == "dark" else "亮色"} {name}剩余百分比" aria-valuemin="0" aria-valuemax="100" aria-valuenow="{value}" aria-orientation="horizontal"><defs><clipPath id="{uid}-track"><rect data-watermark-track width="1000" height="28" rx="14"/></clipPath></defs><rect data-watermark-track class="watermark-used" width="1000" height="28" rx="14"/><g clip-path="url(#{uid}-track)"><rect data-watermark-fill class="watermark-fill" width="{value*10}" height="28" rx="14"/></g></svg>
<div class="quota-reset watermark-reset">{clock}<span>{reset}</span></div></section>''')
    return f'''<div class="prototype-stage watermark-stage"><div class="quota-account watermark-account">
<div class="watermark-decoration" aria-hidden="true">{logo}</div>
<div class="quota-head"><div class="quota-brand"><span class="watermark-brand-icon" aria-hidden="true">{logo}</span><span>Codex <span class="quota-plan">· Plus</span></span></div></div>
<div class="watermark-windows">{''.join(rows)}</div></div></div>'''


def render_watermark_card():
    variants = ''.join(f'<div class="prototype-variant" data-theme="{theme}"><p class="quota-theme">{label}</p>{render_watermark_prototype(theme)}</div>' for theme, label in (("dark", "暗色"), ("light", "亮色")))
    return f'''<article class="card prototype-card" id="selected-reference-12" data-watermark-prototype>
<div class="prototype-comparison"><div class="prototype-pair">{variants}</div></div>
{render_prototype_controls(12)}
<div class="caption"><h2><span class="selection-number">12</span> Codex · 右下角图标水印</h2><p class="origin">用户截图 · 新增方案</p><p>左右双栏 · 大百分比 · 蓝色进度条 · 裁切水印</p></div></article>'''


def render_watermark_detail():
    return '''<dialog class="detail-dialog" id="detail-12" aria-labelledby="detail-title-12" aria-describedby="detail-note-12"><div class="detail-shell">
<header class="detail-header"><h2 id="detail-title-12"><span class="selection-number">12</span> Codex · 右下角图标水印</h2><button class="detail-close" type="button" data-close-dialog autofocus aria-label="关闭参考 12 的适配说明">关闭</button></header>
<div class="detail-body"><p class="detail-origin">来源：用户提供的“截屏 2026-10-13 09.57.25.jpeg”。</p>
<p class="detail-notice" id="detail-note-12">网页候选，正式 App 尚未采用。数字和蓝色均表示剩余，灰色表示已用；默认每周73%、5小时50%，时间与额度均为模拟。原截图中的“8分钟前”和“重置次数”仅留在原图中，候选卡片按用户要求省略。</p>
<img class="detail-image" src="screenshots-user/12.jpeg" alt="用户提供的水印卡片原截图" decoding="async">
<div class="adaptation-text"><p class="detail-direction"><strong>适配方向：</strong>保留截图整体排布，突出右下角低对比度图标水印。</p>
<section class="adaptation-section"><h3>卡片排布</h3><p>顶部是结形图标与Codex · Plus。每周在左，5 小时在右；各栏依次是窗口名称、大百分比、蓝色圆角进度条和带时钟图标的下次重置时间。两栏属于同一账户，不添加更新时间、重置次数、邮箱、下拉箭头或额外操作。</p></section>
<section class="adaptation-section"><h3>水印与明暗</h3><p>复用项目既有结形矢量图标。大图标固定在卡片右下角，超出右边和下边的部分由卡片圆角裁切；图标在文字和进度条后面，低对比度、静止且不接收点击或焦点。暗版为黑色底和微亮水印，亮版为浅底和微暗水印。</p></section>
<section class="adaptation-section"><h3>比例与网页演示</h3><p>蓝色长度精确表达剩余，灰色表达已用，0%无蓝色、100%整条蓝色；小数连续显示。明暗两版共用每周和5小时两个独立数值，可直接拖动蓝条或使用精调滑块、方向键及Home／End。演示变化仅在点击时播放，拖动立即接管相应窗口，时间固定、不自动补满。</p></section>
<section class="adaptation-section"><h3>范围</h3><p>此款只增加到本地设计参考网页。原11款、原两批参考和说明保持；不代表App视觉定稿，不实施SwiftUI或Figma修改。</p></section></div></div></div></dialog>'''


def build_gallery(references, second_references, selected_mappings=(), adaptation_details=()):
    count = len(references) + len(second_references)
    guidance = "方案1—12可拖动预览（含新增截图方案）；原图与适配说明见独立入口" if adaptation_details else "点击截图或原作链接查看详情"
    status = f"{count} 个原作参考 · 选中 {len(selected_mappings)} 个原作 + 1 个截图方案 · {guidance}" if count else "正在搜集原作参考"
    first_content = render_cards(references)
    second_content = render_cards(second_references, "reference-batch-2")
    selected_content = render_selected_cards(references, second_references, selected_mappings, adaptation_details) + "\n" + render_watermark_card()
    detail_dialogs = render_detail_dialogs(references, second_references, selected_mappings, adaptation_details) + "\n" + render_watermark_detail()
    prototype_css = (BASE / "prototype.css").read_text(encoding="utf-8")
    prototype_js = (BASE / "prototype.js").read_text(encoding="utf-8")
    watermark_css = (BASE / "watermark.css").read_text(encoding="utf-8")
    watermark_js = (BASE / "watermark.js").read_text(encoding="utf-8")
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
{watermark_css}
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
{watermark_js}
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
    print(f"Generated {OUTPUT} ({len(references)} + {len(second_references)} references; {len(selected_mappings)} selected originals + screenshot candidate 12; {len(adaptation_details)+1} details)")
