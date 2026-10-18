// Shared data and builders for the showcase images. Sample numbers are illustrative.
const PLATFORMS = [
  { id: "codex", name: "Codex", logo: "codex-color" },
  { id: "claude", name: "Claude", logo: "claude-color" },
  { id: "cursor", name: "Cursor", logo: "cursor" },
  { id: "grok", name: "Grok", logo: "grok" },
  { id: "antigravity", name: "Antigravity", logo: "antigravity-color" },
  { id: "kimi", name: "Kimi", logo: "kimi-color" },
  { id: "glm", name: "智谱 GLM", logo: "zhipu-color" },
  { id: "minimax", name: "MiniMax", logo: "minimax-color" },
  { id: "qoder", name: "Qoder", logo: "qoder-color" },
  { id: "deepseek", name: "DeepSeek", logo: "deepseek-color" },
  { id: "openrouter", name: "OpenRouter", logo: "openrouter" },
  { id: "opencode", name: "OpenCode", logo: "opencode" },
  { id: "muse", name: "Muse Code", logo: "meta-color" },
  { id: "commandcode", name: "Command Code", logo: "commandcode" },
];
const P = Object.fromEntries(PLATFORMS.map(p => [p.id, p]));

const GRAD = {
  mint: "linear-gradient(90deg,#1fbf86,#3ee6a8)",
  cyan: "linear-gradient(90deg,#2a8dff,#45c8ff)",
  violet: "linear-gradient(90deg,#6a4dff,#a48bff)",
  amber: "linear-gradient(90deg,#ff8a3d,#ffc35c)",
  coral: "linear-gradient(90deg,#ff5f7e,#ff9a8a)",
};
const COLOR = { mint: "#3ee6a8", cyan: "#45c8ff", violet: "#8d6bff", amber: "#ffb547", coral: "#ff7a8a" };

function tile(id, size, extra = "") {
  const p = P[id];
  return `<div class="tile" style="width:${size}px;height:${size}px;${extra}"><img src="logos/${p.logo}.svg" alt="${p.name}"></div>`;
}

function meter(label, pct, color) {
  return `<div class="meter">
    <div class="meter-row"><span>${label}</span><span>剩余 <b>${pct}%</b></span></div>
    <div class="bar"><i style="width:${pct}%;background:${GRAD[color]}"></i></div>
  </div>`;
}

function card({ id, who, tail = "", meters = [], balance }) {
  const body = balance
    ? `<div class="balance"><b>${balance}</b><span>账户余额</span></div>`
    : meters.map(m => meter(...m)).join("");
  return `<div class="card">
    <div class="card-top">${tile(id, 30)}
      <div><div class="name">${P[id].name}</div><div class="who">${who}</div></div>
      <div class="tail">${tail}</div>
    </div>${body}
  </div>`;
}

function phone({ left, top, rotate = 0, scale = 1, cards }) {
  return `<div class="phone" style="left:${left}px;top:${top}px;transform:rotate(${rotate}deg) scale(${scale});transform-origin:center">
    <div class="screen">
      <div class="island"></div>
      <div class="status"><span>9:41</span><span class="sys">
        <svg width="18" height="12" viewBox="0 0 18 12"><g fill="#fff"><rect x="0" y="8" width="3" height="4" rx="1"/><rect x="5" y="5.5" width="3" height="6.5" rx="1"/><rect x="10" y="3" width="3" height="9" rx="1"/><rect x="15" y="0" width="3" height="12" rx="1"/></g></svg>
        <span class="bat"><b></b></span></span></div>
      <div class="app-head"><div><h3>额度</h3><small>刚刚更新</small></div><div class="plus">+</div></div>
      ${cards.map(card).join("")}
    </div>
  </div>`;
}

const DEFAULT_CARDS = [
  { id: "codex", who: "工作账号", tail: "1 小时 52 分后重置", meters: [["5 小时", 72, "mint"], ["每周", 46, "cyan"]] },
  { id: "claude", who: "个人账号", tail: "3 小时后重置", meters: [["5 小时", 58, "coral"], ["每周", 81, "amber"]] },
  { id: "cursor", who: "Pro", tail: "11 月 2 日重置", meters: [["本月", 64, "violet"]] },
  { id: "openrouter", who: "API", balance: "$38.20" },
  { id: "deepseek", who: "API", balance: "¥126.40" },
];

// Concentric "activity" rings. Coloured arc = remaining, track = used.
function rings({ size, items, stroke = 14, gap = 5 }) {
  const c = size / 2;
  let out = "";
  items.forEach(([pct, color], i) => {
    const r = c - stroke / 2 - i * (stroke + gap);
    const len = 2 * Math.PI * r;
    out += `<circle cx="${c}" cy="${c}" r="${r}" fill="none" stroke="${color}" stroke-opacity=".18" stroke-width="${stroke}"/>
      <circle cx="${c}" cy="${c}" r="${r}" fill="none" stroke="${color}" stroke-width="${stroke}" stroke-linecap="round"
        stroke-dasharray="${len * pct / 100} ${len}" transform="rotate(-90 ${c} ${c})" style="filter:drop-shadow(0 0 6px ${color}88)"/>`;
  });
  return `<svg width="${size}" height="${size}" viewBox="0 0 ${size} ${size}">${out}</svg>`;
}

function watch({ left, top, scale = 1, face }) {
  return `<div class="watch" style="left:${left}px;top:${top}px;transform:scale(${scale});transform-origin:center">
    <div class="band top"></div><div class="band bottom"></div>
    <div class="case"><div class="face">${face}</div></div>
    <div class="crown"></div><div class="button"></div>
  </div>`;
}

const FACE_RINGS = `
  <div style="position:absolute;top:14px;left:0;right:0;text-align:center;font-size:15px;font-weight:600;color:${COLOR.mint}">10:09</div>
  <div style="position:absolute;left:50%;top:54%;transform:translate(-50%,-50%)">${rings({ size: 156, stroke: 11, gap: 3, items: [[72, COLOR.mint], [58, COLOR.coral], [64, COLOR.violet]] })}</div>
  <div style="position:absolute;left:50%;top:54%;transform:translate(-50%,-50%);text-align:center">
    <div style="font-size:23px;font-weight:700;letter-spacing:-.03em;line-height:1">72%</div>
    <div style="font-size:9px;color:rgba(255,255,255,.55);margin-top:3px">Codex</div>
  </div>`;

const FACE_LIST = (() => {
  const rows = [["codex", 72, "mint"], ["claude", 58, "coral"], ["cursor", 64, "violet"]];
  return `<div style="padding:16px 14px 0">
    <div style="display:flex;justify-content:space-between;font-size:13px;font-weight:600;margin-bottom:12px"><span style="color:${COLOR.cyan}">额度</span><span>10:09</span></div>
    ${rows.map(([id, pct, c]) => `
      <div style="display:flex;align-items:center;gap:8px;margin-bottom:11px">
        ${tile(id, 24, "border-radius:7px;box-shadow:none")}
        <div style="flex:1">
          <div style="display:flex;justify-content:space-between;font-size:11.5px;margin-bottom:4px"><span>${P[id].name}</span><b>${pct}%</b></div>
          <div class="bar" style="height:5px"><i style="width:${pct}%;background:${GRAD[c]}"></i></div>
        </div>
      </div>`).join("")}
    <div style="display:flex;align-items:center;gap:8px;margin-top:2px">
      ${tile("openrouter", 24, "border-radius:7px;box-shadow:none")}
      <div style="flex:1;display:flex;justify-content:space-between;align-items:baseline;font-size:11.5px"><span>OpenRouter</span><b style="font-size:15px">$38.20</b></div>
    </div>
  </div>`;
})();

// Brand mark: three open arcs inside a dark squircle.
function mark(size) {
  const s = 100;
  const arc = (r, pct, color, w) => {
    const len = 2 * Math.PI * r;
    return `<circle cx="50" cy="50" r="${r}" fill="none" stroke="${color}" stroke-opacity=".16" stroke-width="${w}"/>
      <circle cx="50" cy="50" r="${r}" fill="none" stroke="url(#${color.slice(1)})" stroke-width="${w}" stroke-linecap="round" stroke-dasharray="${len * pct} ${len}" transform="rotate(-90 50 50)"/>`;
  };
  return `<svg width="${size}" height="${size}" viewBox="0 0 ${s} ${s}">
    <defs>
      <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#1d1a33"/><stop offset="1" stop-color="#05060a"/></linearGradient>
      <radialGradient id="glow" cx=".3" cy=".2" r=".9"><stop offset="0" stop-color="#8d6bff" stop-opacity=".45"/><stop offset="1" stop-color="#8d6bff" stop-opacity="0"/></radialGradient>
      <linearGradient id="3ee6a8"><stop offset="0" stop-color="#1fbf86"/><stop offset="1" stop-color="#7cf5c8"/></linearGradient>
      <linearGradient id="45c8ff"><stop offset="0" stop-color="#2a8dff"/><stop offset="1" stop-color="#8ee0ff"/></linearGradient>
      <linearGradient id="8d6bff"><stop offset="0" stop-color="#6a4dff"/><stop offset="1" stop-color="#c2b2ff"/></linearGradient>
    </defs>
    <rect width="100" height="100" rx="23" fill="url(#bg)"/>
    <rect width="100" height="100" rx="23" fill="url(#glow)"/>
    <rect x=".5" y=".5" width="99" height="99" rx="22.5" fill="none" stroke="#fff" stroke-opacity=".1"/>
    ${arc(33, .78, "#3ee6a8", 8)}${arc(22, .6, "#45c8ff", 8)}${arc(11, .42, "#8d6bff", 8)}
  </svg>`;
}
