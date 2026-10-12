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

// Prepared local repair. Not part of the running bundle until explicitly added.
// The IDs below come from the final native delivery manifests, not name guesses.
// Only two existing Home Action/back reactions may change. No env()/init(),
// fonts, cloning, node removal, pluginData, canvas selection or layout writes.
const R4_WIDGET_SHARED_HOME_BACK = [
  { theme: 'Light', section: '1:43252', home: '46:142410', config: '46:142344' },
  { theme: 'Dark', section: '1:43254', home: '46:152771', config: '46:152705' },
];
function widgetReturnActions(reaction) { return reaction.actions || (reaction.action ? [reaction.action] : []); }
function widgetReturnBackReaction() { return [{ trigger: { type: 'ON_CLICK' }, actions: [{ type: 'BACK' }] }]; }
function widgetReturnOnlyBack(reactions) {
  return reactions.length === 1 && reactions[0].trigger?.type === 'ON_CLICK' &&
    widgetReturnActions(reactions[0]).length === 1 && widgetReturnActions(reactions[0])[0].type === 'BACK';
}
async function widgetSharedHomeBackPlans() {
  if (typeof jobs !== 'undefined' && jobs.size) throw Error('Finish pending reaction writes before widget return repair.');
  const plans = [];
  for (const scope of R4_WIDGET_SHARED_HOME_BACK) {
    const prefix = 'R4/' + scope.theme + '/Widgets/';
    const [home, config] = await Promise.all([scope.home, scope.config].map(id => figma.getNodeByIdAsync(id)));
    for (const [node, key] of [[home, 'Home/Config/small/C'], [config, 'Config/small/C']]) {
      if (!node || node.removed || node.type !== 'FRAME' || node.name !== prefix + key || node.parent?.id !== scope.section || !node.visible) throw Error('Widget return scope mismatch: ' + scope.theme + '/' + key);
    }
    const nav = home.findAll(n => n.name === 'Navigation');
    if (nav.length !== 1) throw Error('Expected one Home Navigation: ' + scope.theme);
    const backs = nav[0].children.filter(n => n.name === 'Action/back');
    if (backs.length !== 1 || !backs[0].visible || typeof backs[0].setReactionsAsync !== 'function') throw Error('Expected one visible local Home return arrow: ' + scope.theme);
    const arrow = backs[0], before = JSON.parse(JSON.stringify(arrow.reactions || []));
    if (!widgetReturnOnlyBack(before)) {
      const a = before.length === 1 && before[0].trigger?.type === 'ON_CLICK' ? widgetReturnActions(before[0]) : [];
      if (a.length !== 1 || a[0].type !== 'NODE' || a[0].navigation !== 'NAVIGATE' || !a[0].destinationId) throw Error('Unexpected Home return behavior: ' + scope.theme);
      const target = await figma.getNodeByIdAsync(a[0].destinationId);
      if (!target || target.removed || target.parent?.id !== scope.section || ![prefix + 'Accounts/ABCD', prefix + 'Config/small/C'].includes(target.name)) throw Error('Unexpected Home return target: ' + scope.theme);
    }
    const finish = config.findAll(n => n.name === 'Button/完成');
    if (finish.length !== 1 || !(finish[0].reactions || []).some(r => r.trigger?.type === 'ON_CLICK' && widgetReturnActions(r).some(a => a.type === 'NODE' && a.navigation === 'NAVIGATE' && a.destinationId === home.id))) throw Error('Config completion must navigate to this Home: ' + scope.theme);
    const unaffected = [home, ...home.findAll()].filter(n => n.id !== arrow.id && 'reactions' in n).map(n => ({ node: n, reactions: JSON.stringify(n.reactions || []) }));
    plans.push({ scope, home, config, arrow, before, unaffected });
  }
  return plans;
}
function widgetSharedHomeBackSummary(plans) {
  return plans.map(p => ({ theme: p.scope.theme, rootId: p.home.id, root: p.home.name, arrowId: p.arrow.id, configId: p.config.id,
    before: p.before, after: widgetReturnBackReaction(), alreadyBack: widgetReturnOnlyBack(p.before) }));
}
async function planWidgetSharedHomeBackRepairStage() {
  const plans = await widgetSharedHomeBackPlans();
  return { status: '小组件共享 Home 返回修复方案（只读）', createdRootCount: 0, mutationCount: 0, plans: widgetSharedHomeBackSummary(plans),
    validationRequired: ['Config/small/C → 完成 → Home → 详情 OVERLAY → CLOSE → Home 返回，应回同一 Config。', 'Widgets/Review → 回退入口 → Home 返回，应回 Widgets/Review。', 'Home → App/账号列表 → 列表返回 Home → Home 返回，应回上一账号列表。', 'Home indicator 仍回原评审 Hub；直接从 Home 深链启动时用该既有出口。'] };
}
async function repairWidgetSharedHomeBackStage() {
  // Both themes must pass before the first native write.
  const plans = await widgetSharedHomeBackPlans(), changed = [];
  for (const p of plans) if (!widgetReturnOnlyBack(p.before)) {
    await p.arrow.setReactionsAsync(widgetReturnBackReaction());
    changed.push(p.arrow.id);
    if (typeof writes !== 'undefined') writes.add(p.arrow.id);
  }
  for (const p of plans) {
    if (!widgetReturnOnlyBack(p.arrow.reactions || [])) throw Error('BACK reaction verification failed: ' + p.scope.theme);
    for (const snapshot of p.unaffected) if (JSON.stringify(snapshot.node.reactions || []) !== snapshot.reactions) throw Error('Unrelated Home reaction changed: ' + snapshot.node.id);
  }
  if (changed.length) figma.commitUndo();
  return { status: '小组件共享 Home 已按来源返回，等待实际点击验证', createdRootCount: 0, mutationCount: changed.length,
    mutatedNodeIds: changed, plans: widgetSharedHomeBackSummary(plans), nativeClickValidation: 'pending' };
}

// Standalone bounded READ-ONLY resume inspection. Not added to r4-live.js.
// Call inspectR4ResumeTargets() after loading this module exactly once.
// Only figma.getNodeByIdAsync and local node reads; no env/init/font/page,
// canvas selection, pluginData, reaction writes, cloning, removal or layout edits.
// Scope: 37 saved R4 bad-source nodes; 22 exact roots including both Settings-denied
// roots and both shared Home/Config pairs. No old full Audit.
const R4_RESUME_INSPECT_ROOTS = [{"id": "46:140983", "name": "R4/Light/Widgets/Detail/B"}, {"id": "46:141286", "name": "R4/Light/Widgets/Detail/C"}, {"id": "46:141589", "name": "R4/Light/Widgets/Detail/D"}, {"id": "46:144327", "name": "R4/Light/Widgets/Accounts/ABCD"}, {"id": "46:144914", "name": "R4/Light/Widgets/Accounts/ABD"}, {"id": "46:145413", "name": "R4/Light/Widgets/Accounts/AD"}, {"id": "46:146479", "name": "R4/Light/Widgets/Accounts/ABCDE"}, {"id": "46:147154", "name": "R4/Light/Widgets/Accounts/ABDE"}, {"id": "53:893425", "name": "R4/Light/AccountSystem/Set-15/Settings-denied"}, {"id": "46:151344", "name": "R4/Dark/Widgets/Detail/B"}, {"id": "46:151647", "name": "R4/Dark/Widgets/Detail/C"}, {"id": "46:151950", "name": "R4/Dark/Widgets/Detail/D"}, {"id": "46:154688", "name": "R4/Dark/Widgets/Accounts/ABCD"}, {"id": "46:155275", "name": "R4/Dark/Widgets/Accounts/ABD"}, {"id": "46:155774", "name": "R4/Dark/Widgets/Accounts/AD"}, {"id": "46:156840", "name": "R4/Dark/Widgets/Accounts/ABCDE"}, {"id": "46:157515", "name": "R4/Dark/Widgets/Accounts/ABDE"}, {"id": "53:895028", "name": "R4/Dark/AccountSystem/Set-15/Settings-denied"}, {"id": "46:142410", "name": "R4/Light/Widgets/Home/Config/small/C"}, {"id": "46:142344", "name": "R4/Light/Widgets/Config/small/C"}, {"id": "46:152771", "name": "R4/Dark/Widgets/Home/Config/small/C"}, {"id": "46:152705", "name": "R4/Dark/Widgets/Config/small/C"}];
const R4_RESUME_INSPECT_SOURCES = [{"rootId": "46:140983", "root": "R4/Light/Widgets/Detail/B", "nodeId": "46:147874", "path": "$/Scroll viewport/Content/Quota/Codex/Card header/Expand account", "sourceVisible": true, "destinationId": "14:42236", "navigation": "NAVIGATE", "group": "visible_widget_detail_expand"}, {"rootId": "46:140983", "root": "R4/Light/Widgets/Detail/B", "nodeId": "46:147882", "path": "$/Scroll viewport/Content/Quota/Codex/Card header/Action/more", "sourceVisible": false, "destinationId": "14:42237", "navigation": "OVERLAY", "group": "hidden_widget_more"}, {"rootId": "46:141286", "root": "R4/Light/Widgets/Detail/C", "nodeId": "46:147966", "path": "$/Scroll viewport/Content/Quota/Codex · work/Card header/Expand account", "sourceVisible": true, "destinationId": "14:42236", "navigation": "NAVIGATE", "group": "visible_widget_detail_expand"}, {"rootId": "46:141286", "root": "R4/Light/Widgets/Detail/C", "nodeId": "46:147974", "path": "$/Scroll viewport/Content/Quota/Codex · work/Card header/Action/more", "sourceVisible": false, "destinationId": "14:42237", "navigation": "OVERLAY", "group": "hidden_widget_more"}, {"rootId": "46:141589", "root": "R4/Light/Widgets/Detail/D", "nodeId": "46:148048", "path": "$/Scroll viewport/Content/Quota/Cursor/Card header/Expand account", "sourceVisible": true, "destinationId": "14:42238", "navigation": "NAVIGATE", "group": "visible_widget_detail_expand"}, {"rootId": "46:141589", "root": "R4/Light/Widgets/Detail/D", "nodeId": "46:148056", "path": "$/Scroll viewport/Content/Quota/Cursor/Card header/Action/more", "sourceVisible": false, "destinationId": "14:42239", "navigation": "OVERLAY", "group": "hidden_widget_more"}, {"rootId": "46:144327", "root": "R4/Light/Widgets/Accounts/ABCD", "nodeId": "46:149137", "path": "$/Scroll viewport/Content/Quota/Codex/Card header/Action/more", "sourceVisible": false, "destinationId": "14:42237", "navigation": "OVERLAY", "group": "hidden_widget_more"}, {"rootId": "46:144327", "root": "R4/Light/Widgets/Accounts/ABCD", "nodeId": "46:149303", "path": "$/Scroll viewport/Content/Quota/Cursor/Card header/Action/more", "sourceVisible": false, "destinationId": "14:42239", "navigation": "OVERLAY", "group": "hidden_widget_more"}, {"rootId": "46:144914", "root": "R4/Light/Widgets/Accounts/ABD", "nodeId": "46:149558", "path": "$/Scroll viewport/Content/Quota/Cursor/Card header/Action/more", "sourceVisible": false, "destinationId": "14:42239", "navigation": "OVERLAY", "group": "hidden_widget_more"}, {"rootId": "46:145413", "root": "R4/Light/Widgets/Accounts/AD", "nodeId": "46:149725", "path": "$/Scroll viewport/Content/Quota/Cursor/Card header/Action/more", "sourceVisible": false, "destinationId": "14:42239", "navigation": "OVERLAY", "group": "hidden_widget_more"}, {"rootId": "46:146479", "root": "R4/Light/Widgets/Accounts/ABCDE", "nodeId": "46:150169", "path": "$/Scroll viewport/Content/Quota/Codex/Card header/Action/more", "sourceVisible": false, "destinationId": "14:42237", "navigation": "OVERLAY", "group": "hidden_widget_more"}, {"rootId": "46:146479", "root": "R4/Light/Widgets/Accounts/ABCDE", "nodeId": "46:150335", "path": "$/Scroll viewport/Content/Quota/Cursor/Card header/Action/more", "sourceVisible": false, "destinationId": "14:42239", "navigation": "OVERLAY", "group": "hidden_widget_more"}, {"rootId": "46:146479", "root": "R4/Light/Widgets/Accounts/ABCDE", "nodeId": "46:150405", "path": "$/Scroll viewport/Content/Quota/Codex · backup/Card header/Expand account", "sourceVisible": true, "destinationId": "14:42236", "navigation": "NAVIGATE", "group": "visible_backup_expand"}, {"rootId": "46:146479", "root": "R4/Light/Widgets/Accounts/ABCDE", "nodeId": "46:150413", "path": "$/Scroll viewport/Content/Quota/Codex · backup/Card header/Action/more", "sourceVisible": false, "destinationId": "14:42237", "navigation": "OVERLAY", "group": "hidden_widget_more"}, {"rootId": "46:147154", "root": "R4/Light/Widgets/Accounts/ABDE", "nodeId": "46:150600", "path": "$/Scroll viewport/Content/Quota/Codex/Card header/Action/more", "sourceVisible": false, "destinationId": "14:42237", "navigation": "OVERLAY", "group": "hidden_widget_more"}, {"rootId": "46:147154", "root": "R4/Light/Widgets/Accounts/ABDE", "nodeId": "46:150678", "path": "$/Scroll viewport/Content/Quota/Cursor/Card header/Action/more", "sourceVisible": false, "destinationId": "14:42239", "navigation": "OVERLAY", "group": "hidden_widget_more"}, {"rootId": "46:147154", "root": "R4/Light/Widgets/Accounts/ABDE", "nodeId": "46:150748", "path": "$/Scroll viewport/Content/Quota/Codex · backup/Card header/Expand account", "sourceVisible": true, "destinationId": "14:42236", "navigation": "NAVIGATE", "group": "visible_backup_expand"}, {"rootId": "46:147154", "root": "R4/Light/Widgets/Accounts/ABDE", "nodeId": "46:150756", "path": "$/Scroll viewport/Content/Quota/Codex · backup/Card header/Action/more", "sourceVisible": false, "destinationId": "14:42237", "navigation": "OVERLAY", "group": "hidden_widget_more"}, {"rootId": "53:893425", "root": "R4/Light/AccountSystem/Set-15/Settings-denied", "nodeId": "53:893478", "path": "$/Scroll viewport/Content/Group/通用/Row/额度显示", "sourceVisible": false, "destinationId": "1:2249", "navigation": "OVERLAY", "group": "hidden_display_preference"}, {"rootId": "46:151344", "root": "R4/Dark/Widgets/Detail/B", "nodeId": "46:151601", "path": "$/Scroll viewport/Content/Quota/Codex/Card header/Expand account", "sourceVisible": true, "destinationId": "14:42698", "navigation": "NAVIGATE", "group": "visible_widget_detail_expand"}, {"rootId": "46:151344", "root": "R4/Dark/Widgets/Detail/B", "nodeId": "46:151609", "path": "$/Scroll viewport/Content/Quota/Codex/Card header/Action/more", "sourceVisible": false, "destinationId": "14:42699", "navigation": "OVERLAY", "group": "hidden_widget_more"}, {"rootId": "46:151647", "root": "R4/Dark/Widgets/Detail/C", "nodeId": "46:151904", "path": "$/Scroll viewport/Content/Quota/Codex · work/Card header/Expand account", "sourceVisible": true, "destinationId": "14:42698", "navigation": "NAVIGATE", "group": "visible_widget_detail_expand"}, {"rootId": "46:151647", "root": "R4/Dark/Widgets/Detail/C", "nodeId": "46:151912", "path": "$/Scroll viewport/Content/Quota/Codex · work/Card header/Action/more", "sourceVisible": false, "destinationId": "14:42699", "navigation": "OVERLAY", "group": "hidden_widget_more"}, {"rootId": "46:151950", "root": "R4/Dark/Widgets/Detail/D", "nodeId": "46:152197", "path": "$/Scroll viewport/Content/Quota/Cursor/Card header/Expand account", "sourceVisible": true, "destinationId": "14:42700", "navigation": "NAVIGATE", "group": "visible_widget_detail_expand"}, {"rootId": "46:151950", "root": "R4/Dark/Widgets/Detail/D", "nodeId": "46:152205", "path": "$/Scroll viewport/Content/Quota/Cursor/Card header/Action/more", "sourceVisible": false, "destinationId": "14:42701", "navigation": "OVERLAY", "group": "hidden_widget_more"}, {"rootId": "46:154688", "root": "R4/Dark/Widgets/Accounts/ABCD", "nodeId": "46:155045", "path": "$/Scroll viewport/Content/Quota/Codex/Card header/Action/more", "sourceVisible": false, "destinationId": "14:42699", "navigation": "OVERLAY", "group": "hidden_widget_more"}, {"rootId": "46:154688", "root": "R4/Dark/Widgets/Accounts/ABCD", "nodeId": "46:155211", "path": "$/Scroll viewport/Content/Quota/Cursor/Card header/Action/more", "sourceVisible": false, "destinationId": "14:42701", "navigation": "OVERLAY", "group": "hidden_widget_more"}, {"rootId": "46:155275", "root": "R4/Dark/Widgets/Accounts/ABD", "nodeId": "46:155710", "path": "$/Scroll viewport/Content/Quota/Cursor/Card header/Action/more", "sourceVisible": false, "destinationId": "14:42701", "navigation": "OVERLAY", "group": "hidden_widget_more"}, {"rootId": "46:155774", "root": "R4/Dark/Widgets/Accounts/AD", "nodeId": "46:156121", "path": "$/Scroll viewport/Content/Quota/Cursor/Card header/Action/more", "sourceVisible": false, "destinationId": "14:42701", "navigation": "OVERLAY", "group": "hidden_widget_more"}, {"rootId": "46:156840", "root": "R4/Dark/Widgets/Accounts/ABCDE", "nodeId": "46:157197", "path": "$/Scroll viewport/Content/Quota/Codex/Card header/Action/more", "sourceVisible": false, "destinationId": "14:42699", "navigation": "OVERLAY", "group": "hidden_widget_more"}, {"rootId": "46:156840", "root": "R4/Dark/Widgets/Accounts/ABCDE", "nodeId": "46:157363", "path": "$/Scroll viewport/Content/Quota/Cursor/Card header/Action/more", "sourceVisible": false, "destinationId": "14:42701", "navigation": "OVERLAY", "group": "hidden_widget_more"}, {"rootId": "46:156840", "root": "R4/Dark/Widgets/Accounts/ABCDE", "nodeId": "46:157433", "path": "$/Scroll viewport/Content/Quota/Codex · backup/Card header/Expand account", "sourceVisible": true, "destinationId": "14:42698", "navigation": "NAVIGATE", "group": "visible_backup_expand"}, {"rootId": "46:156840", "root": "R4/Dark/Widgets/Accounts/ABCDE", "nodeId": "46:157441", "path": "$/Scroll viewport/Content/Quota/Codex · backup/Card header/Action/more", "sourceVisible": false, "destinationId": "14:42699", "navigation": "OVERLAY", "group": "hidden_widget_more"}, {"rootId": "46:157515", "root": "R4/Dark/Widgets/Accounts/ABDE", "nodeId": "46:157872", "path": "$/Scroll viewport/Content/Quota/Codex/Card header/Action/more", "sourceVisible": false, "destinationId": "14:42699", "navigation": "OVERLAY", "group": "hidden_widget_more"}, {"rootId": "46:157515", "root": "R4/Dark/Widgets/Accounts/ABDE", "nodeId": "46:157950", "path": "$/Scroll viewport/Content/Quota/Cursor/Card header/Action/more", "sourceVisible": false, "destinationId": "14:42701", "navigation": "OVERLAY", "group": "hidden_widget_more"}, {"rootId": "46:157515", "root": "R4/Dark/Widgets/Accounts/ABDE", "nodeId": "46:158020", "path": "$/Scroll viewport/Content/Quota/Codex · backup/Card header/Expand account", "sourceVisible": true, "destinationId": "14:42698", "navigation": "NAVIGATE", "group": "visible_backup_expand"}, {"rootId": "46:157515", "root": "R4/Dark/Widgets/Accounts/ABDE", "nodeId": "46:158028", "path": "$/Scroll viewport/Content/Quota/Codex · backup/Card header/Action/more", "sourceVisible": false, "destinationId": "14:42699", "navigation": "OVERLAY", "group": "hidden_widget_more"}];
function r4ResumeVisible(node) {
  for (let n = node; n && n.type !== 'DOCUMENT'; n = n.parent) if (n.visible === false) return false;
  return true;
}
function r4ResumePath(node, rootId) {
  const parts = [];
  for (let n = node; n && n.id !== rootId && n.type !== 'DOCUMENT'; n = n.parent) {
    const peers = n.parent && 'children' in n.parent ? n.parent.children.filter(c => c.name === n.name) : [];
    const i = peers.findIndex(c => c.id === n.id);
    parts.push(n.name + (i > 0 ? '[' + i + ']' : ''));
  }
  return '$' + (parts.length ? '/' + parts.reverse().join('/') : '');
}
function r4ResumeNorm(value) { return String(value).replace(/Light|Dark/g, '{theme}').replace(/浅色|深色/g, '{主题}'); }
function r4ResumeStable(value) {
  if (Array.isArray(value)) return value.map(r4ResumeStable);
  if (value && typeof value === 'object') {
    const out = {}; for (const k of Object.keys(value).sort()) out[k] = r4ResumeStable(value[k]); return out;
  }
  return typeof value === 'string' ? r4ResumeNorm(value) : value;
}
async function inspectR4ResumeTargets() {
  const started = new Date().toISOString(), sections = {Light:'1:43252',Dark:'1:43254'};
  const targets = new Map(), results = [], sourceResults = [], allSources = new Map(R4_RESUME_INSPECT_SOURCES.map(s => [s.nodeId,s]));
  async function destination(id) {
    if (targets.has(id)) return targets.get(id);
    let n = null; try { n = await figma.getNodeByIdAsync(id); } catch (_) {}
    if (!n || n.removed) { const v = {id,missing:true}; targets.set(id,v); return v; }
    let owner = n;
    while (owner.parent && !['PAGE','SECTION','DOCUMENT'].includes(owner.parent.type)) owner = owner.parent;
    const v = {id,name:n.name,type:n.type,visible:r4ResumeVisible(n),localVisible:n.visible !== false,
      parentId:n.parent?.id,ownerId:owner.id,owner:owner.name,path:r4ResumePath(n,owner.id),
      canonical:r4ResumeNorm(owner.name)+'/'+r4ResumeNorm(r4ResumePath(n,owner.id))};
    targets.set(id,v); return v;
  }
  async function actionInfo(value, canonicalOnly = false) {
    if (Array.isArray(value)) { const out = []; for (const v of value) out.push(await actionInfo(v,canonicalOnly)); return out; }
    if (!value || typeof value !== 'object') return canonicalOnly ? r4ResumeStable(value) : value;
    const out = {};
    for (const k of Object.keys(value).sort()) {
      if (k === 'destinationId') {
        const t = await destination(value[k]);
        if (canonicalOnly) out.destination = t.missing ? 'MISSING/'+value[k] : t.canonical;
        else { out.destinationId = value[k]; out.destination = t; }
      } else out[k] = await actionInfo(value[k],canonicalOnly);
    }
    return out;
  }
  for (const spec of R4_RESUME_INSPECT_ROOTS) {
    const root = await figma.getNodeByIdAsync(spec.id), theme = spec.name.includes('/Light/') ? 'Light' : 'Dark';
    if (!root || root.removed) { results.push({id:spec.id,expectedName:spec.name,missing:true}); continue; }
    const result = {id:root.id,name:root.name,type:root.type,localVisible:root.visible !== false,visible:r4ResumeVisible(root),parentId:root.parent?.id,
      scopeMatches:root.name === spec.name && root.type === 'FRAME' && root.parent?.id === sections[theme],
      size:[root.width,root.height],nodes:0,visibleTexts:[],reactions:[],context:[]};
    const stack = [{n:root,path:'$',ancestorVisible:r4ResumeVisible(root.parent)}];
    while (stack.length) {
      if (result.nodes >= 12000) throw Error('Unexpected >12000 nodes in bounded root '+root.id+'; no partial result accepted');
      const item = stack.pop(), n = item.n, visible = item.ancestorVisible && n.visible !== false;
      result.nodes++;
      const reactions = 'reactions' in n ? n.reactions || [] : [];
      const loc = {id:n.id,name:n.name,path:item.path,type:n.type,localVisible:n.visible !== false,visible};
      if (n.type === 'TEXT' && visible) result.visibleTexts.push({id:n.id,path:item.path,text:n.characters});
      if (/^(Navigation|Action\/back|Action\/close|Row\/额度显示|Group\/通用|Expand account|Action\/more|Icon\/down|Account details|Home indicator|Home widgets|App\/订阅额度|Button\/完成|Quota\/|Account\/)/.test(n.name)) {
        result.context.push({...loc,reactionCount:reactions.length,children:'children' in n?n.children.map(c=>({id:c.id,name:c.name,type:c.type,localVisible:c.visible!==false})):undefined});
      }
      if (reactions.length) {
        result.reactions.push({...loc,reactions:await actionInfo(reactions),canonicalReactions:await actionInfo(reactions,true)});
      }
      if (allSources.has(n.id)) {
        const saved = allSources.get(n.id), actions = [];
        for (const r of reactions) for (const a of r.actions || (r.action ? [r.action] : [])) actions.push(a);
        sourceResults.push({saved,current:{...loc,rootId:root.id,reactions:await actionInfo(reactions)},
          savedDestinationStillPresent:actions.some(a=>a.type==='NODE'&&a.destinationId===saved.destinationId&&a.navigation===saved.navigation),
          savedVisibilityMatches:visible===saved.sourceVisible});
      }
      if ('children' in n) {
        const names = new Map(), children = [];
        for (const child of n.children) { const count = names.get(child.name)||0; names.set(child.name,count+1);children.push({n:child,path:item.path+'/'+child.name+(count?'['+count+']':''),ancestorVisible:visible}); }
        for (let i=children.length-1;i>=0;i--) stack.push(children[i]);
      }
    }
    results.push(result);
  }
  const [light,dark] = ['53:893425','53:895028'].map(id=>results.find(r=>r.id===id));
  const themeReactionDiff = [];
  if (light?.reactions && dark?.reactions) {
    const map = root=>new Map(root.reactions.map(r=>[r4ResumeNorm(r.path),r]));
    const lm=map(light),dm=map(dark);
    for (const path of new Set([...lm.keys(),...dm.keys()])) {
      const a=lm.get(path),b=dm.get(path);
      const av=a?{visible:a.visible,reactions:a.canonicalReactions}:null,bv=b?{visible:b.visible,reactions:b.canonicalReactions}:null;
      if(JSON.stringify(r4ResumeStable(av))!==JSON.stringify(r4ResumeStable(bv))) themeReactionDiff.push({path,light:a?{id:a.id,...av}:null,dark:b?{id:b.id,...bv}:null});
    }
  }
  return {status:'Bounded read-only resume inspection; no repair or click validation',started,finished:new Date().toISOString(),
    requestedRootCount:R4_RESUME_INSPECT_ROOTS.length,readRootCount:results.filter(r=>!r.missing).length,
    requestedSourceCount:R4_RESUME_INSPECT_SOURCES.length,foundSourceCount:sourceResults.length,
    missingSourceIds:R4_RESUME_INSPECT_SOURCES.filter(s=>!sourceResults.some(r=>r.saved.nodeId===s.nodeId)).map(s=>s.nodeId),
    mutationCount:0,sampleTruncation:0,results,sourceResults,themeReactionDiff};
}

// Exact-source local correction after saved/live comparison on 2026-10-09.
// No node creation/deletion, layout/text/style changes or legacy R2 edits.
async function r4ResumeLocalPlan() {
 const homePlans=await widgetSharedHomeBackPlans();
 const plans=[];
 for(const spec of R4_RESUME_INSPECT_SOURCES){
  const root=await figma.getNodeByIdAsync(spec.rootId),node=await figma.getNodeByIdAsync(spec.nodeId);
  if(!root||!node||root.name!==spec.root||root.type!=='FRAME'||root.parent?.id!==(spec.root.includes('/Light/')?'1:43252':'1:43254')||r4ResumePath(node,root.id)!==spec.path)throw Error('Source scope changed '+spec.nodeId);
  const before=JSON.parse(JSON.stringify(node.reactions||[]));
  if(before.length){const actions=before.flatMap(r=>r.actions||(r.action?[r.action]:[]));if(before.length!==1||before[0].trigger?.type!=='ON_CLICK'||actions.length!==1||actions[0].type!=='NODE'||actions[0].destinationId!==spec.destinationId||actions[0].navigation!==spec.navigation)throw Error('Source reaction changed '+spec.nodeId);}
  if(r4ResumeVisible(node)!==spec.sourceVisible)throw Error('Visibility changed '+spec.nodeId);
  let reason;
  if(spec.sourceVisible){
   let card=node;while(card&&card.id!==root.id&&!card.name.startsWith('Quota/'))card=card.parent;
   const details=card?.children?.filter(n=>n.name==='Account details')||[];
   const icons=node.findAll(n=>n.name==='Icon/down');
   if(details.length!==1||!r4ResumeVisible(details[0])||icons.length!==1||icons[0].visible!==false)throw Error('Expanded static header precondition failed '+spec.nodeId);
   reason='Already expanded account details; disclosure icon hidden. Remove stale navigation hotspot, preserve all visible identity/quota/detail content.';
  }else reason='Hidden obsolete control; clear legacy reaction only.';
  plans.push({node,root,spec,before,reason});
 }
 const roots=await Promise.all(R4_RESUME_INSPECT_ROOTS.map(s=>figma.getNodeByIdAsync(s.id)));
 const allowed=new Set([...plans.map(p=>p.node.id),...homePlans.map(p=>p.arrow.id)]);
 const snapshots=roots.flatMap(r=>[r,...r.findAll()].map(n=>({n,value:JSON.stringify({id:n.id,name:n.name,visible:n.visible,x:n.x,y:n.y,w:n.width,h:n.height,text:n.type==='TEXT'?n.characters:null,reactions:allowed.has(n.id)?null:('reactions'in n?n.reactions:[])})})));
 return {plans,homePlans,snapshots};
}
function r4ResumePlanSummary(p){return {status:'精确局部修复预检通过；未修改',mutationCount:0,createdNodeIds:[],removedNodeIds:[],clearReactions:p.plans.map(x=>({rootId:x.root.id,root:x.root.name,nodeId:x.node.id,path:x.spec.path,before:x.before,reason:x.reason})),homePlans:widgetSharedHomeBackSummary(p.homePlans)};}
async function planR4ResumeLocalRepair(){return r4ResumePlanSummary(await r4ResumeLocalPlan());}
async function applyR4ResumeLocalRepair(){
 const p=await r4ResumeLocalPlan(),mutated=[];
 for(const x of p.plans)if(x.before.length){await x.node.setReactionsAsync([]);mutated.push(x.node.id);}
 for(const x of p.homePlans)if(!widgetReturnOnlyBack(x.before)){await x.arrow.setReactionsAsync(widgetReturnBackReaction());mutated.push(x.arrow.id);}
 for(const x of p.plans)if(x.node.reactions.length)throw Error('Clear verification failed '+x.node.id);
 for(const x of p.homePlans)if(!widgetReturnOnlyBack(x.arrow.reactions))throw Error('BACK verification failed '+x.arrow.id);
 for(const s of p.snapshots){const n=s.n;const current=JSON.stringify({id:n.id,name:n.name,visible:n.visible,x:n.x,y:n.y,w:n.width,h:n.height,text:n.type==='TEXT'?n.characters:null,reactions:([...p.plans.map(x=>x.node.id),...p.homePlans.map(x=>x.arrow.id)].includes(n.id))?null:('reactions'in n?n.reactions:[])});if(current!==s.value)throw Error('Unrelated property changed '+n.id);}
 if(mutated.length)figma.commitUndo();
 return {...r4ResumePlanSummary(p),status:'39处以内精确局部修复完成，待新审计与实际点击',mutationCount:mutated.length,mutatedNodeIds:mutated,unrelatedNodeSnapshotsVerified:p.snapshots.length,actualClickValidation:'pending'};
}


figma.showUI(__html__,{width:600,height:520});
let resumeBusy=false;
async function resumeInspect(ids) {
 const out=[];
 for(const id of ids) {const n=await figma.getNodeByIdAsync(id);if(!n){out.push({id,missing:true});continue;}
 const nodes=[n,...('findAll' in n?n.findAll():[])];
 const reactions=[];for(const c of nodes)if('reactions'in c&&c.reactions.length){const targets=[];for(const r of c.reactions)for(const a of r.actions||[r.action])if(a&&a.destinationId){const t=await figma.getNodeByIdAsync(a.destinationId);targets.push({id:a.destinationId,name:t?.name,visible:t?r4cVisible(t):false,parent:t?.parent?.id});}reactions.push({id:c.id,name:c.name,path:r4cPath(c,n.id),visible:r4cVisible(c),reactions:c.reactions,targets});}
 out.push({id:n.id,name:n.name,parent:n.parent?.id,visible:r4cVisible(n),children:n.children?.map(c=>({id:c.id,name:c.name,visible:c.visible})),texts:n.type==='FRAME'?nodes.filter(c=>c.type==='TEXT').map(c=>({id:c.id,text:c.characters,visible:r4cVisible(c)})):[],reactions});
 }
 return {status:'定向只读读取完成',nodes:out};
}
figma.ui.onmessage=async m=>{if(resumeBusy)return;resumeBusy=true;try{
 let result;const parts=(m.target||'').split('/');
 if(m.type==='inspect')result=await resumeInspect(m.target.split(',').map(s=>s.trim()));
 else if(m.type==='apply'&&parts[0]==='resumeinspect')result=await inspectR4ResumeTargets();
 else if(m.type==='apply'&&parts[0]==='localplan')result=await planR4ResumeLocalRepair();
 else if(m.type==='apply'&&parts[0]==='localfix')result=await applyR4ResumeLocalRepair();
 else if(m.type==='apply'&&parts[0]==='homeplan')result=await planWidgetSharedHomeBackRepairStage();
 else if(m.type==='apply'&&parts[0]==='homefix')result=await repairWidgetSharedHomeBackStage();
 else if(m.type==='apply'&&parts[0]==='compact'){
 if(parts[1]==='start')result=await auditR4CompactStart({reset:true});
 else if(parts[1]==='batch')result=await auditR4CompactBatch(parts[2],Number(parts[3]||200));
 else if(parts[1]==='theme'){let x;do{x=await auditR4CompactBatch(parts[2],200);figma.ui.postMessage({...x,progress:true});}while(x.queues[parts[2]].remaining>0);result=x;}
 else if(parts[1]==='finish')result=await auditR4CompactFinish();
 else result=auditR4CompactProgress();
 }else if(m.type==='gallery'){const gallery=[];for(const id of m.target.split(',')){const n=await figma.getNodeByIdAsync(id.trim());gallery.push({id:n.id,name:n.name,bytes:Array.from(await n.exportAsync({format:'PNG',constraint:{type:'SCALE',value:1}}))});}result={status:'定向截图完成',gallery};}
 else throw Error('本恢复工具只开放定向读取、已预检Home修复及新版分批审计。旧生成、清理、全量Audit已禁用。');
 figma.ui.postMessage(result);
 }catch(e){figma.ui.postMessage({status:'停止：'+String(e),error:String(e),stack:e.stack});}finally{resumeBusy=false}};
