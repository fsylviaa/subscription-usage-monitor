// Prepared equivalent performance revision; replace the active module only after its run ends.
// Do not load this beside r4-audit-compact.js: both intentionally define the same API.
// Read-only, bounded native audit. No env(), fonts(), selection, page change,
// pluginData write, or reaction/node mutation. Progress exists in runtime only.
// Start after authoring/delivery has stopped; then batch each theme (<=200 roots).
let R4_COMPACT_AUDIT = null;
const R4_COMPACT_SCOPES = [
  { id: '1:43251', theme: 'Light', role: 'review' }, { id: '1:43252', theme: 'Light', role: 'interaction' },
  { id: '1:43253', theme: 'Dark', role: 'review' }, { id: '1:43254', theme: 'Dark', role: 'interaction' }
];
function r4cNorm(value) { return String(value).replace(/Light|Dark/g, '{theme}').replace(/浅色|深色/g, '{主题}'); }
function r4cShort(value, length = 180) { const s = String(value); return s.length > length ? s.slice(0, length) + '…' : s; }
function r4cBytes(value) { let n = 0; for (const c of String(value)) { const x = c.codePointAt(0); n += x < 128 ? 1 : x < 2048 ? 2 : x < 65536 ? 3 : 4; } return n; }
function r4cHash() { return { a: 2166136261, b: 5381, length: 0 }; }
function r4cFeed(h, value) { const s = String(value); h.length += s.length + 1; for (let i = 0; i <= s.length; i++) { const c = i === s.length ? 0 : s.charCodeAt(i); h.a = Math.imul(h.a ^ c, 16777619) >>> 0; h.b = (Math.imul(h.b, 33) ^ c) >>> 0; } }
function r4cDigest(h) { return [h.a.toString(16), h.b.toString(16), h.length].join(':'); }
function r4cStable(value) {
  if (Array.isArray(value)) return value.map(r4cStable);
  if (value && typeof value === 'object') { const out = {}; for (const k of Object.keys(value).sort()) out[k] = r4cStable(value[k]); return out; }
  return typeof value === 'string' ? r4cNorm(value) : typeof value === 'number' ? Math.round(value * 1000) / 1000 : value;
}
function r4cActions(r) { return r.actions || (r.action ? [r.action] : []); }
function r4cClickable(node) { return 'reactions' in node && (node.reactions || []).some(r => r.trigger?.type === 'ON_CLICK' && r4cActions(r).length > 0); }
function r4cVisible(node) { for (let n = node; n && n.type !== 'DOCUMENT'; n = n.parent) if (n.visible === false) return false; return true; }
function r4cOld(name, text = '') {
  const found = [];
  if (/\|U\||(?:^|[\/|])Display(?:$|[\/|])/.test(name)) found.push('used/display root');
  if (/^Row\/额度显示$|^Choice\/已用$|^Button\/查看(?:已用|剩余)状态$/.test(name)) found.push('display control');
  if (/^(?:额度显示|显示偏好|显示已用|已用显示|查看已用状态|查看剩余状态)$/.test(text.trim())) found.push('display text');
  return found;
}
function r4cRemoved(text) {
  const clean = text.replace(/\s+/g, ''), list = [
    ['TXT-01', '开启后，在额度预计重置时收到提醒'], ['TXT-02', '外观自动跟随iPhone系统'],
    ['TXT-03', '选择平台添加账户。同一平台可继续添加其他账户。'],
    ['TXT-04', '集中查看Claude、Codex和Cursor的订阅额度与重置时间。'],
    ['TXT-05', '使用你的平台账户继续'], ['TXT-06', '小组件会在下次系统更新后显示已断开。']
  ];
  const found = list.filter(([, phrase]) => clean.includes(phrase)).map(([id]) => id);
  if (/已添加\d+个/.test(clean)) found.push('TXT-03/count'); return found;
}
function r4cIssue(s, kind, data) {
  const bucket = s.issues[kind] || (s.issues[kind] = { count: 0, samples: [], omitted: 0 }); bucket.count++;
  const sample = { ...data };
  for (const k of ['root', 'path', 'target', 'text', 'reason', 'key']) if (sample[k] !== undefined) sample[k] = r4cShort(sample[k]);
  const bytes = r4cBytes(JSON.stringify(sample));
  if (bucket.samples.length < s.options.sampleCap && s.sampleBytes + bytes <= s.options.sampleBudgetBytes) { bucket.samples.push(sample); s.sampleBytes += bytes; }
  else bucket.omitted++;
}
function r4cOwner(s, node) { for (let n = node; n && n.type !== 'PAGE' && n.type !== 'DOCUMENT'; n = n.parent) if (s.byId.has(n.id)) return s.byId.get(n.id); return null; }
function r4cPath(node, ownerId) {
  const parts = []; for (let n = node; n && n.id !== ownerId; n = n.parent) {
    const peers = n.parent && 'children' in n.parent ? n.parent.children.filter(c => c.name === n.name) : [];
    const index = peers.findIndex(c => c.id === n.id); parts.push(n.name + (index > 0 ? '[' + index + ']' : ''));
  } return '$' + (parts.length ? '/' + parts.reverse().join('/') : '');
}
async function r4cTarget(s, id) {
  if (s.targets.has(id)) return s.targets.get(id);
  let node = null; try { if (typeof id === 'string') node = await figma.getNodeByIdAsync(id); } catch (_) {}
  if (!node || node.removed) { s.targets.set(id, null); return null; }
  const owner = r4cOwner(s, node), result = { id, type: node.type, visible: r4cVisible(node), owner: owner === null ? null : owner,
    canonical: owner === null ? 'EXTERNAL/' + r4cNorm(node.name) : s.directory[owner].canonical + '/' + r4cNorm(r4cPath(node, s.directory[owner].id)), name: node.name };
  s.targets.set(id, result); return result;
}
function r4cQueueLegacy(s, index) {
  const info = s.directory[index]; if (s.queued.has(index)) return;
  if (s.legacyQueued >= s.options.maxLegacyRoots) { s.legacyUnscanned.add(index); return; }
  s.legacyQueued++; s.queued.add(index); s.queue[info.theme].push(index);
}
function r4cGeometry(s, info, node, path, reactions) {
  if (node.id === info.id) return; // Authoring-canvas placement is not product overflow.
  if (node.type !== 'TEXT' && !reactions.length) return;
  const b = node.absoluteBoundingBox; if (!b || !b.width || !b.height) return;
  let scrollX = false, scrollY = false, reported = false;
  for (let p = node.parent; p && !reported; p = p.parent) {
    const dir = p.overflowDirection; scrollX ||= dir === 'HORIZONTAL' || dir === 'BOTH'; scrollY ||= dir === 'VERTICAL' || dir === 'BOTH';
    if (p.clipsContent || p.id === info.id || (node.type === 'TEXT' && p.name.startsWith('Button/'))) {
      const pb = p.absoluteBoundingBox;
      if (!pb) { if (p.id === info.id) break; continue; }
      const x = !scrollX && (b.x < pb.x - 1 || b.x + b.width > pb.x + pb.width + 1);
      const y = !scrollY && (b.y < pb.y - 1 || b.y + b.height > pb.y + pb.height + 1);
      if (x || y) { r4cIssue(s, 'geometryOverflow', { rootId: info.id, root: info.name, nodeId: node.id, path, clipId: p.id, clip: r4cShort(p.name), axes: [x ? 'x' : null, y ? 'y' : null].filter(Boolean), box: [b.x - pb.x, b.y - pb.y, b.width, b.height, pb.width, pb.height].map(v => Math.round(v * 10) / 10) }); reported = true; }
    }
    if (p.id === info.id) break;
  }
  if (node.type === 'TEXT') {
    let button = null, opacity = 1; for (let n = node; n; n = n.parent) { opacity *= typeof n.opacity === 'number' ? n.opacity : 1; if (n.name.startsWith('Button/')) { button = n; break; } if (n.id === info.id) break; }
    if (button && node.characters.trim() && opacity <= .01) r4cIssue(s, 'hiddenButtonText', { rootId: info.id, root: info.name, nodeId: node.id, path, text: node.characters, opacity });
  }
}
function r4cCounters() { return { roots: 0, primaryRoots: 0, legacyRoots: 0, visibleRoots: 0, nodes: 0, visibleNodes: 0, texts: 0, visibleTexts: 0, reactionLayers: 0, visibleReactionLayers: 0, reactions: 0, nodeActions: 0, visibleNodeActions: 0, closeBackActions: 0 }; }
function r4cSummary(s) { return { runId: s.runId, started: s.started, counts: s.counts, queues: Object.fromEntries(['Light', 'Dark'].map(t => [t, { processed: s.cursor[t], queued: s.queue[t].length, remaining: s.queue[t].length - s.cursor[t] }])), issueCounts: Object.fromEntries(Object.entries(s.issues).map(([k, v]) => [k, v.count])), incompleteRoots: s.incomplete.size, legacyUnscanned: s.legacyUnscanned.size }; }

async function auditR4CompactStart(options = {}) {
  if (R4_COMPACT_AUDIT && !options.reset) return { status: '已有只读审计；继续批次，或显式reset重新取快照', ...r4cSummary(R4_COMPACT_AUDIT) };
  const s = { runId: 'r4compact-' + Date.now(), started: new Date().toISOString(), options: {
    sampleCap: Math.max(1, Math.min(150, options.sampleCap || 80)), sampleBudgetBytes: 1200000,
    maxLegacyRoots: Math.max(0, Math.min(256, Number.isInteger(options.maxLegacyRoots) ? options.maxLegacyRoots : 64)),
    maxNodesPerRoot: 50000, timeBudgetMs: Math.max(1000, Math.min(20000, options.timeBudgetMs || 8000))
  }, directory: [], byId: new Map(), sections: [], queue: { Light: [], Dark: [] }, cursor: { Light: 0, Dark: 0 },
    counts: { Light: r4cCounters(), Dark: r4cCounters() }, queued: new Set(), records: new Map(), targets: new Map(), issues: {}, sampleBytes: 0,
    legacyQueued: 0, legacyUnscanned: new Set(), incomplete: new Set(), configured: [], configuredDeclared: 0, finalized: null };
  let sourcePage;
  for (const scope of R4_COMPACT_SCOPES) {
    const section = await figma.getNodeByIdAsync(scope.id);
    if (!section || section.type !== 'SECTION') { r4cIssue(s, 'missingSections', { id: scope.id }); continue; }
    sourcePage ||= section.parent;
    const snapshot = { ...scope, name: section.name, childCount: section.children.length, frameCount: 0, visibleFrameCount: 0, primaryRootCount: 0, directoryHash: r4cHash() };
    for (const n of section.children) {
      r4cFeed(snapshot.directoryHash, JSON.stringify([n.id, n.name, n.visible !== false]));
      if (n.type !== 'FRAME') continue;
      const index = s.directory.length, primary = n.name.startsWith('R4/') || (scope.role === 'review' && n.visible !== false);
      const info = { index, id: n.id, name: n.name, canonical: scope.role + '/' + r4cNorm(n.name), theme: scope.theme, role: scope.role,
        section: scope.id, primary, visible: r4cVisible(n), r4: n.name.startsWith('R4/') };
      s.directory.push(info); s.byId.set(n.id, index); snapshot.frameCount++; if (n.visible !== false) snapshot.visibleFrameCount++;
      if (primary) { snapshot.primaryRootCount++; s.queue[scope.theme].push(index); s.queued.add(index); }
    }
    snapshot.directoryHash = r4cDigest(snapshot.directoryHash); s.sections.push(snapshot);
  }
  for (const point of sourcePage && sourcePage.flowStartingPoints || []) {
    s.configuredDeclared++; const target = await r4cTarget(s, point.nodeId);
    if (target && target.owner !== null) { s.configured.push(target.owner); if (!s.queued.has(target.owner)) r4cQueueLegacy(s, target.owner); }
    else r4cIssue(s, 'invalidOrUnscopedFlowStart', { id: point.nodeId, name: r4cShort(point.name || ''), reason: target ? 'outside audited sections' : 'missing target' });
  }
  R4_COMPACT_AUDIT = s;
  return { status: '只读目录快照完成；每theme批次最多200根', ...r4cSummary(s), sections: s.sections };
}

async function r4cScanRoot(s, index) {
  const info = s.directory[index], node = await figma.getNodeByIdAsync(info.id);
  if (!node || node.removed) { s.incomplete.add(index); r4cIssue(s, 'changedSnapshot', { rootId: info.id, root: info.name, reason: 'root removed during audit' }); return; }
  const c = s.counts[info.theme], record = { index, nodes: 0, textCount: 0, reactionCount: 0, visible: r4cVisible(node), width: Math.round(node.width * 100) / 100, height: Math.round(node.height * 100) / 100, text: r4cHash(), reactions: r4cHash(), outgoing: new Set(), directExit: false, hasVisibleAction: false };
  const stack = [{ node, path: '$', visible: r4cVisible(node.parent), ancestorAction: false }];
  while (stack.length) {
    if (record.nodes >= s.options.maxNodesPerRoot) { s.incomplete.add(index); r4cIssue(s, 'rootNodeBudget', { rootId: info.id, root: info.name, scanned: record.nodes }); break; }
    const item = stack.pop(), n = item.node, visible = item.visible && n.visible !== false;
    record.nodes++; c.nodes++; if (visible) c.visibleNodes++;
    const reactions = 'reactions' in n ? n.reactions || [] : [];
    if (n.type === 'TEXT') {
      c.texts++; record.textCount++; if (visible) c.visibleTexts++;
      r4cFeed(record.text, JSON.stringify([r4cNorm(item.path), visible, r4cNorm(n.characters)]));
      if (visible) { const matches = r4cRemoved(n.characters); if (matches.length) r4cIssue(s, 'removedText', { rootId: info.id, root: info.name, nodeId: n.id, path: item.path, text: n.characters, matches }); }
    }
    if (visible) {
      const old = r4cOld(n.name, n.type === 'TEXT' ? n.characters : ''); if (old.length) r4cIssue(s, 'visibleLegacy', { rootId: info.id, root: info.name, nodeId: n.id, path: item.path, reasons: old });
      r4cGeometry(s, info, n, item.path, reactions);
      if (/^(?:Action\/(?:close|back)|Button\/(?:取消|关闭|返回|返回评审入口))$/.test(n.name) && !r4cClickable(n) && !item.ancestorAction && !('findOne' in n && n.findOne(r4cClickable))) r4cIssue(s, 'missingHotspotActions', { rootId: info.id, root: info.name, nodeId: n.id, path: item.path });
    }
    if (reactions.length) { c.reactionLayers++; if (visible) c.visibleReactionLayers++; record.reactionCount += reactions.length; c.reactions += reactions.length; }
    for (const reaction of reactions) {
      async function actionSummary(value) {
        if (Array.isArray(value)) { const out = []; for (const v of value) out.push(await actionSummary(v)); return out; }
        if (!value || typeof value !== 'object') return r4cStable(value);
        const out = {};
        if (value.type === 'NODE') {
          c.nodeActions++; if (visible) { c.visibleNodeActions++; record.hasVisibleAction = true; }
          const target = await r4cTarget(s, value.destinationId), edge = { rootId: info.id, root: info.name, nodeId: n.id, path: item.path, sourceVisible: visible,
            destinationId: value.destinationId || null, navigation: value.navigation, trigger: r4cStable(reaction.trigger), transition: r4cStable(value.transition || null) };
          if (!target) r4cIssue(s, 'invalidTargets', edge);
          else {
            if (!target.visible) r4cIssue(s, 'hiddenTargets', { ...edge, target: target.name });
            if (target.owner === null) { r4cIssue(s, 'externalTargets', { ...edge, target: target.name, targetType: target.type }); if (visible) record.directExit = true; }
            else {
              if (visible) record.outgoing.add(target.owner);
              if (target.owner === index && value.navigation === 'NAVIGATE') r4cIssue(s, 'selfNavigation', edge);
              const targetInfo = s.directory[target.owner];
              if (targetInfo.role === 'interaction' && !targetInfo.r4) { r4cIssue(s, 'legacyTargets', { ...edge, target: targetInfo.name }); if (visible) r4cQueueLegacy(s, target.owner); }
            }
          }
          out.destination = target ? target.canonical : 'MISSING';
        } else if (['CLOSE', 'BACK', 'URL'].includes(value.type) && visible) { record.directExit = true; record.hasVisibleAction = true; if (value.type !== 'URL') c.closeBackActions++; }
        for (const key of Object.keys(value).sort()) if (key !== 'destinationId') out[key] = await actionSummary(value[key]);
        return out;
      }
      r4cFeed(record.reactions, JSON.stringify([r4cNorm(item.path), visible, r4cStable(reaction.trigger), await actionSummary(r4cActions(reaction))]));
    }
    if ('children' in n) {
      const names = new Map(), children = [];
      const ancestorAction = item.ancestorAction || reactions.some(r => r.trigger?.type === 'ON_CLICK' && r4cActions(r).length > 0);
      for (const child of n.children) { const name = child.name, occurrence = names.get(name) || 0; names.set(name, occurrence + 1); children.push({ node: child, path: item.path + '/' + name + (occurrence ? '[' + occurrence + ']' : ''), visible, ancestorAction }); }
      for (let i = children.length - 1; i >= 0; i--) stack.push(children[i]);
    }
  }
  record.text = r4cDigest(record.text); record.reactions = r4cDigest(record.reactions); s.records.set(index, record);
  c.roots++; c[info.primary ? 'primaryRoots' : 'legacyRoots']++; if (record.visible) c.visibleRoots++;
}

async function auditR4CompactBatch(theme, count = 200) {
  const s = R4_COMPACT_AUDIT; if (!s) throw Error('Run auditR4CompactStart first'); if (s.finalized) return { status: '审计已汇总；新快照需start({reset:true})', ...r4cSummary(s) };
  if (!['Light', 'Dark'].includes(theme) || !Number.isInteger(count) || count < 1 || count > 200) throw Error('Use Light/Dark and count 1–200');
  const start = Date.now(), initial = s.cursor[theme];
  while (s.cursor[theme] < s.queue[theme].length && s.cursor[theme] - initial < count) {
    const index = s.queue[theme][s.cursor[theme]]; await r4cScanRoot(s, index); s.cursor[theme]++;
    if (Date.now() - start >= s.options.timeBudgetMs) break;
    if ((s.cursor[theme] - initial) % 10 === 0) await new Promise(resolve => setTimeout(resolve, 0));
  }
  return { status: theme + ' 只读审计批次完成', processedThisBatch: s.cursor[theme] - initial, elapsedMs: Date.now() - start, ...r4cSummary(s) };
}

async function auditR4CompactFinish() {
  const s = R4_COMPACT_AUDIT; if (!s) throw Error('Run auditR4CompactStart first'); if (s.finalized) return s.finalized;
  if (['Light', 'Dark'].some(t => s.cursor[t] < s.queue[t].length)) return { status: '尚有批次未扫描；继续两theme批次', ...r4cSummary(s) };
  for (const snapshot of s.sections) {
    const section = await figma.getNodeByIdAsync(snapshot.id), h = r4cHash();
    if (section) for (const node of section.children) r4cFeed(h, JSON.stringify([node.id, node.name, node.visible !== false]));
    if (!section || r4cDigest(h) !== snapshot.directoryHash) r4cIssue(s, 'changedSnapshot', { id: snapshot.id, reason: 'section root IDs/names/visibility changed during audit; restart after authoring stops' });
  }
  const pairs = new Map(), reverse = new Map(), incoming = new Set();
  for (const [index, r] of s.records) {
    const info = s.directory[index]; if (info.primary) { const p = pairs.get(info.canonical) || { Light: [], Dark: [] }; p[info.theme].push(index); pairs.set(info.canonical, p); }
    for (const target of r.outgoing) { incoming.add(target); const sources = reverse.get(target) || []; sources.push(index); reverse.set(target, sources); }
  }
  let paired = 0;
  for (const [key, pair] of pairs) {
    if (!pair.Light.length || !pair.Dark.length) r4cIssue(s, 'themeMissing', { key, missing: pair.Light.length ? 'Dark' : 'Light', ids: [...pair.Light, ...pair.Dark].slice(0, 5).map(i => s.directory[i].id) });
    if (pair.Light.length > 1 || pair.Dark.length > 1) r4cIssue(s, 'themeDuplicate', { key, lightCount: pair.Light.length, darkCount: pair.Dark.length, ids: [...pair.Light, ...pair.Dark].slice(0, 5).map(i => s.directory[i].id) });
    if (pair.Light.length !== 1 || pair.Dark.length !== 1) continue;
    paired++; const a = s.records.get(pair.Light[0]), b = s.records.get(pair.Dark[0]), refs = { key, lightId: s.directory[a.index].id, darkId: s.directory[b.index].id };
    if (a.text !== b.text || a.textCount !== b.textCount) r4cIssue(s, 'themeTextMismatch', { ...refs, light: a.text, dark: b.text });
    if (a.reactions !== b.reactions || a.reactionCount !== b.reactionCount) r4cIssue(s, 'themeReactionMismatch', { ...refs, light: a.reactions, dark: b.reactions });
    if (a.width !== b.width || a.height !== b.height || a.visible !== b.visible) r4cIssue(s, 'themeGeometryMismatch', { ...refs, light: [a.width, a.height, a.visible], dark: [b.width, b.height, b.visible] });
  }
  const canExit = new Set(), queue = [];
  for (const [i, r] of s.records) if (r.directExit) { canExit.add(i); queue.push(i); }
  for (let cursor = 0; cursor < queue.length; cursor++) for (const prev of reverse.get(queue[cursor]) || []) if (!canExit.has(prev)) { canExit.add(prev); queue.push(prev); }
  const entries = [...new Set([...s.configured, ...s.directory.filter(i => i.primary && i.visible && (i.role === 'review' || /\/(?:Review|StateReview)$/.test(i.name))).map(i => i.index)])];
  const reachable = new Set(entries), visit = [...entries];
  for (let cursor = 0; cursor < visit.length; cursor++) for (const target of s.records.get(visit[cursor])?.outgoing || []) if (!reachable.has(target)) { reachable.add(target); visit.push(target); }
  for (const [index, r] of s.records) if (r.visible && (incoming.has(index) || entries.includes(index)) && !canExit.has(index) && (incoming.has(index) || r.hasVisibleAction)) r4cIssue(s, 'noExitCandidates', { rootId: s.directory[index].id, root: s.directory[index].name, reachable: reachable.has(index), outgoingRootCount: r.outgoing.size, reason: 'No reachable visible CLOSE/BACK/URL/external escape in the scanned graph; inspect runtime stack and intended static-only screens' });
  const result = { status: '只读分批审计汇总；不代表实际点击验证', schemaVersion: 1, ...r4cSummary(s), finished: new Date().toISOString(),
    sections: s.sections, comparison: { pairedRoots: paired, primaryCanonicalNames: pairs.size, normalization: 'Theme-normalized root/path/text; NODE destination canonical root/path; full sorted trigger/action/transition values; dual incremental 32-bit hashes plus length/counts. No per-text geometry dump.' },
    graph: { configuredDeclaredCount: s.configuredDeclared, configuredEntryCount: s.configured.length, reviewAndConfiguredEntryCount: entries.length, reachableRoots: reachable.size, inspectedReachableRoots: [...reachable].filter(i => s.records.has(i)).length, rootsWithKnownEscape: canExit.size },
    issues: s.issues, truncation: { sampleCapPerCategory: s.options.sampleCap, sampleBudgetBytes: s.options.sampleBudgetBytes, sampleBytesRetained: s.sampleBytes, issueCountTotalsAreUntruncated: true, outputBytes: 0, outputCapBytes: 1800000 },
    limitations: [
      'Freeze authoring during all batches. Directory changes are detected; in-place content changes between batches are not versioned by this read-only audit.',
      'Only R4 roots and visible R3 review frames are primary; visible edges may add up to the declared legacy-root budget. Unscanned legacy targets are counted.',
      'Theme equality uses dual hashes plus lengths/counts rather than retaining every normalized text/reaction object. Hash equality is practical evidence, not a mathematical collision proof.',
      'Visible means inherited visible flags. Zero opacity does not disable a clickable hotspot. Background/overlay runtime stack behavior needs actual click validation.',
      'Geometry flags focus on text/click targets clipped or outside root/button bounds; legitimate scroll axes are excluded. Occlusion, font rendering and semantic TXT synonyms need screenshots.',
      'No-exit candidates are conservative: CLOSE/BACK/URL/external actions and paths to them count as escape. Conditional branches are treated as possible.'
    ] };
  // Hard final-size guard; retain every category's exact total and omission count.
  let encoded = JSON.stringify(result);
  while (r4cBytes(encoded) > result.truncation.outputCapBytes) {
    const bucket = Object.values(result.issues).filter(b => b.samples.length).sort((a, b) => b.samples.length - a.samples.length)[0];
    if (!bucket) break; bucket.samples.pop(); bucket.omitted++; encoded = JSON.stringify(result);
  }
  result.truncation.sampleBytesRetained = Object.values(result.issues).reduce((sum, b) => sum + b.samples.reduce((n, sample) => n + r4cBytes(JSON.stringify(sample)), 0), 0);
  for (let i = 0; i < 4; i++) { const size = r4cBytes(JSON.stringify(result)); if (result.truncation.outputBytes === size) break; result.truncation.outputBytes = size; }
  s.finalized = result; return result;
}

function auditR4CompactProgress() { if (!R4_COMPACT_AUDIT) return { status: '尚未开始' }; return { status: '只读审计进度', ...r4cSummary(R4_COMPACT_AUDIT) }; }

// Optional bounded drill-down for a reported pair/anomaly. This never changes
// aggregate counts, queues or nodes. Use exact root IDs from the summary.
async function auditR4CompactInspect(rootIds) {
  const s = R4_COMPACT_AUDIT;
  if (!s || !Array.isArray(rootIds) || !rootIds.length || rootIds.length > 4) throw Error('Start an audit, then inspect 1–4 exact root IDs');
  const results = []; let bytes = 0;
  async function summarize(value) {
    if (Array.isArray(value)) { const out = []; for (const v of value) out.push(await summarize(v)); return out; }
    if (!value || typeof value !== 'object') return r4cStable(value);
    const out = {}; for (const key of Object.keys(value).sort()) {
      if (key === 'destinationId') { const target = await r4cTarget(s, value[key]); out.destination = target ? target.canonical : 'MISSING'; }
      else out[key] = await summarize(value[key]);
    } return out;
  }
  for (const id of rootIds) {
    const index = s.byId.get(id); if (index === undefined) throw Error('Root was not in the directory snapshot: ' + id);
    const node = await figma.getNodeByIdAsync(id); if (!node || node.removed) { results.push({ id, missing: true }); continue; }
    const result = { id, canonical: s.directory[index].canonical, texts: [], reactions: [], omitted: 0 }, stack = [{ node, path: '$', visible: r4cVisible(node.parent) }];
    while (stack.length) {
      const item = stack.pop(), n = item.node, visible = item.visible && n.visible !== false;
      const add = (key, value) => { const size = r4cBytes(JSON.stringify(value)); if (result.texts.length + result.reactions.length < 400 && bytes + size < 500000) { result[key].push(value); bytes += size; } else result.omitted++; };
      if (n.type === 'TEXT') add('texts', { id: n.id, path: r4cShort(r4cNorm(item.path), 300), visible, text: r4cShort(r4cNorm(n.characters), 500) });
      if ('reactions' in n) for (const reaction of n.reactions || []) add('reactions', { id: n.id, path: r4cShort(r4cNorm(item.path), 300), visible, trigger: r4cStable(reaction.trigger), actions: await summarize(r4cActions(reaction)) });
      if ('children' in n) { const names = new Map(), children = []; for (const child of n.children) { const occurrence = names.get(child.name) || 0; names.set(child.name, occurrence + 1); children.push({ node: child, path: item.path + '/' + child.name + (occurrence ? '[' + occurrence + ']' : ''), visible }); } for (let i = children.length - 1; i >= 0; i--) stack.push(children[i]); }
    }
    results.push(result);
  }
  return { status: '指定根的只读规范摘要', results, payloadBytes: bytes, capBytes: 500000, aggregateAuditCountsChanged: false };
}
