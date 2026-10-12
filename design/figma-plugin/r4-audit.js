// Read-only native Figma audit. This module never changes nodes, selection,
// plugin data, fonts, the current page, or prototype reactions.
// All new R4 roots and visible R3 review roots are inspected. Old interaction
// trees are opened only when a reachable edge leads to them, within a budget.
const R4_AUDIT_SCOPES = [
  { id: '1:43251', theme: 'Light', role: 'review' },
  { id: '1:43252', theme: 'Light', role: 'interaction' },
  { id: '1:43253', theme: 'Dark', role: 'review' },
  { id: '1:43254', theme: 'Dark', role: 'interaction' }
];

function r4AuditPlain(value) {
  if (value === undefined) return null;
  return JSON.parse(JSON.stringify(value));
}
function r4AuditRound(value) {
  return typeof value === 'number' ? Math.round(value * 1000) / 1000 : value;
}
function r4AuditBox(node) {
  const box = {};
  for (const key of ['x', 'y', 'width', 'height', 'rotation']) {
    if (typeof node[key] === 'number') box[key] = r4AuditRound(node[key]);
  }
  if (node.absoluteBoundingBox) {
    box.absolute = Object.fromEntries(Object.entries(node.absoluteBoundingBox).map(([key, value]) => [key, r4AuditRound(value)]));
  }
  return box;
}
function r4AuditCanonical(value) {
  return String(value).replace(/Light|Dark/g, '{theme}').replace(/浅色|深色/g, '{主题}');
}
function r4AuditActions(reaction) {
  return reaction.actions || (reaction.action ? [reaction.action] : []);
}
function r4AuditNodeActions(value, result = []) {
  if (!value || typeof value !== 'object') return result;
  if (Array.isArray(value)) {
    value.forEach(item => r4AuditNodeActions(item, result));
  } else {
    if (value.type === 'NODE') result.push(value);
    for (const [key, item] of Object.entries(value)) {
      if (key !== 'destinationId') r4AuditNodeActions(item, result);
    }
  }
  return result;
}
function r4AuditOldKind(name, text = '') {
  const reasons = [];
  if (/\|U\|/.test(name)) reasons.push('legacy-used-root');
  if (/(?:^|[\/|])Display(?:$|[\/|])/.test(name)) reasons.push('legacy-display-preferences-root');
  if (/^Row\/额度显示$|^Choice\/已用$|^Button\/查看(?:已用|剩余)状态$/.test(name)) reasons.push('legacy-display-control');
  if (/^(?:额度显示|显示偏好|显示已用|已用显示|查看已用状态|查看剩余状态)$/.test(text.trim())) reasons.push('legacy-display-text');
  return reasons;
}
function r4AuditRemovedText(text) {
  const deleted = [
    '开启后，在额度预计重置时收到提醒',
    '外观自动跟随 iPhone 系统',
    '选择平台添加账户。同一平台可继续添加其他账户。',
    '集中查看 Claude、Codex 和 Cursor 的订阅额度与重置时间。',
    '使用你的平台账户继续',
    '小组件会在下次系统更新后显示已断开。'
  ];
  return deleted.filter(value => text.includes(value)).concat(/^已添加\s*\d+\s*个$/.test(text.trim()) ? ['已添加 n 个'] : []);
}

async function auditR4(options = {}) {
  const maxLegacyRoots = Number.isInteger(options.maxLegacyRoots) ? Math.max(0, Math.min(128, options.maxLegacyRoots)) : 64;
  const maxLegacyNodes = Number.isInteger(options.maxLegacyNodes) ? Math.max(0, Math.min(30000, options.maxLegacyNodes)) : 12000;
  const started = new Date().toISOString();
  const directory = new Map(), nodes = new Map(), owners = new Map(), paths = new Map();
  const inspected = new Map(), edges = new Map(), targetCache = new Map();
  const invalidTargets = [], selfLinks = [], externalTargets = [], legacyBoundaries = [];
  const sections = [], missingSections = [];
  let legacyNodeCount = 0, legacyRootCount = 0;
  const legacyUnscanned = new Set(), incompleteRoots = new Set();

  for (const scope of R4_AUDIT_SCOPES) {
    const section = await figma.getNodeByIdAsync(scope.id);
    if (!section || section.type !== 'SECTION') {
      missingSections.push(scope.id);
      continue;
    }
    sections.push({ ...scope, node: section });
    // This is a shallow directory; never call findAll on an old section.
    for (const root of section.children) {
      directory.set(root.id, { node: root, ...scope });
      nodes.set(root.id, root);
      owners.set(root.id, root.id);
      paths.set(root.id, '$');
    }
  }

  function owner(node) {
    if (!node) return null;
    if (owners.has(node.id)) return owners.get(node.id);
    for (let current = node; current && current.type !== 'PAGE' && current.type !== 'DOCUMENT'; current = current.parent) {
      if (directory.has(current.id)) {
        owners.set(node.id, current.id);
        return current.id;
      }
    }
    return null;
  }
  function rootName(id) {
    return directory.has(id) ? directory.get(id).node.name : null;
  }
  function collect(rootInfo, legacy = false) {
    const root = rootInfo.node;
    if (inspected.has(root.id)) return inspected.get(root.id);
    const record = {
      id: root.id, name: root.name, theme: rootInfo.theme, sectionId: rootInfo.id,
      role: rootInfo.role, generation: root.name.startsWith('R4/') ? 'R4' : 'R3-or-legacy',
      visible: root.visible !== false, bounds: r4AuditBox(root), legacyTraversal: legacy,
      complete: true, nodeCount: 0, texts: [], reactions: [], legacyMarkers: [], removedText: []
    };
    const rootReasons = r4AuditOldKind(root.name);
    if (rootReasons.length) record.legacyMarkers.push({ id: root.id, path: '$', visible: root.visible !== false, reasons: rootReasons });
    const stack = [{ node: root, path: '$', visible: rootInfo.node.parent.visible !== false }];
    while (stack.length) {
      if (legacy && legacyNodeCount >= maxLegacyNodes) {
        record.complete = false;
        incompleteRoots.add(root.id);
        break;
      }
      const item = stack.pop(), node = item.node;
      // A transparent hotspot can still be clickable in a prototype. Only
      // the visibility flag excludes it from the conservative link graph.
      const visible = item.visible && node.visible !== false;
      record.nodeCount++;
      if (legacy) legacyNodeCount++;
      nodes.set(node.id, node);
      owners.set(node.id, root.id);
      paths.set(node.id, item.path);
      if (node.type === 'TEXT') {
        record.texts.push({ id: node.id, name: node.name, path: item.path, text: node.characters, visible, opacity: node.opacity, bounds: r4AuditBox(node) });
        const removed = r4AuditRemovedText(node.characters);
        if (removed.length && visible) record.removedText.push({ id: node.id, path: item.path, text: node.characters, matches: removed });
      }
      const reasons = r4AuditOldKind(node.name, node.type === 'TEXT' ? node.characters : '');
      if (node.id !== root.id && reasons.length) record.legacyMarkers.push({ id: node.id, path: item.path, visible, reasons });
      if ('reactions' in node && node.reactions.length) {
        record.reactions.push({
          id: node.id, name: node.name, path: item.path, visible, opacity: node.opacity, bounds: r4AuditBox(node),
          reactions: node.reactions.map(reaction => ({ trigger: r4AuditPlain(reaction.trigger), actions: r4AuditPlain(r4AuditActions(reaction)) }))
        });
      }
      if ('children' in node) {
        const seen = new Map(), children = [];
        for (const child of node.children) {
          const occurrence = seen.get(child.name) || 0;
          seen.set(child.name, occurrence + 1);
          // Ordinals only distinguish equal sibling names; light/dark IDs differ.
          children.push({ node: child, path: item.path + '/' + child.name + (occurrence ? '[' + occurrence + ']' : ''), visible });
        }
        for (let i = children.length - 1; i >= 0; i--) stack.push(children[i]);
      }
    }
    inspected.set(root.id, record);
    return record;
  }

  async function target(id) {
    if (!id || typeof id !== 'string') return null;
    if (targetCache.has(id)) return targetCache.get(id);
    let node = nodes.get(id) || null;
    if (!node) {
      try { node = await figma.getNodeByIdAsync(id); } catch (_) { node = null; }
    }
    if (node && node.removed) node = null;
    const result = node ? { id: node.id, name: node.name, type: node.type, rootId: owner(node), visible: node.visible !== false } : null;
    targetCache.set(id, result);
    return result;
  }

  async function connect(record) {
    if (edges.has(record.id)) return;
    const result = [], seen = new Set();
    for (const layer of record.reactions) for (let index = 0; index < layer.reactions.length; index++) {
      const reaction = layer.reactions[index];
      for (const action of r4AuditNodeActions(reaction.actions)) {
        const destination = await target(action.destinationId);
        const edge = {
          sourceRootId: record.id, sourceNodeId: layer.id, sourcePath: layer.path, visible: layer.visible,
          reactionIndex: index, trigger: reaction.trigger, navigation: action.navigation,
          transition: r4AuditPlain(action.transition), destinationId: action.destinationId || null,
          destinationRootId: destination ? destination.rootId : null,
          destinationName: destination ? destination.name : null
        };
        result.push(edge);
        if (!destination) invalidTargets.push(edge);
        else if (destination.rootId === record.id) selfLinks.push(edge);
        else if (!destination.rootId) externalTargets.push({ ...edge, destinationType: destination.type });
        else {
          const info = directory.get(destination.rootId);
          if (info.role === 'interaction' && !info.node.name.startsWith('R4/')) {
            const key = layer.id + '/' + destination.rootId;
            if (!seen.has(key)) legacyBoundaries.push({ ...edge, legacyKind: r4AuditOldKind(info.node.name) });
            seen.add(key);
          }
        }
      }
    }
    edges.set(record.id, result);
  }

  const primaryIds = [];
  for (const info of directory.values()) {
    if (info.node.name.startsWith('R4/') || (info.role === 'review' && info.node.type === 'FRAME' && info.node.visible !== false)) {
      primaryIds.push(info.node.id);
      collect(info);
    }
  }
  for (let i = 0; i < primaryIds.length; i++) {
    await connect(inspected.get(primaryIds[i]));
    if (i % 12 === 11) await new Promise(resolve => setTimeout(resolve, 0));
  }

  const sourcePage = sections.length ? sections[0].node.parent : null;
  const configured = sourcePage && 'flowStartingPoints' in sourcePage ? r4AuditPlain(sourcePage.flowStartingPoints) : [];
  const configuredIds = [];
  for (const point of configured || []) {
    const destination = await target(point.nodeId);
    if (destination && destination.rootId) configuredIds.push(destination.rootId);
  }
  const reviewIds = primaryIds.filter(id => {
    const info = directory.get(id);
    return info.node.visible !== false && (info.role === 'review' || /\/(?:Review|StateReview)$/.test(info.node.name));
  });

  async function trace(entryIds) {
    const queue = [...new Set(entryIds)], previous = new Map(queue.map(id => [id, null]));
    const blocked = new Set();
    for (let cursor = 0; cursor < queue.length; cursor++) {
      const id = queue[cursor], info = directory.get(id);
      if (!info) continue;
      if (!inspected.has(id)) {
        if (legacyRootCount >= maxLegacyRoots || legacyNodeCount >= maxLegacyNodes) {
          legacyUnscanned.add(id);
          blocked.add(id);
          continue;
        }
        legacyRootCount++;
        collect(info, true);
        await connect(inspected.get(id));
      }
      const record = inspected.get(id);
      if (!record.complete) blocked.add(id);
      for (const edge of edges.get(id) || []) {
        if (!edge.visible || !edge.destinationRootId || previous.has(edge.destinationRootId)) continue;
        previous.set(edge.destinationRootId, { rootId: id, sourceNodeId: edge.sourceNodeId, navigation: edge.navigation });
        queue.push(edge.destinationRootId);
      }
    }
    function pathTo(id) {
      const path = [];
      for (let current = id; current; current = previous.get(current)?.rootId) {
        const step = previous.get(current);
        path.push({ id: current, name: rootName(current), via: step ? { sourceNodeId: step.sourceNodeId, navigation: step.navigation } : null });
      }
      return path.reverse();
    }
    const oldUsedOrPreferences = [];
    for (const id of previous.keys()) {
      const record = inspected.get(id), rootReasons = r4AuditOldKind(rootName(id) || '');
      const markers = record ? record.legacyMarkers.filter(marker => marker.visible) : [];
      if (rootReasons.length || markers.length) oldUsedOrPreferences.push({ id, name: rootName(id), rootReasons, markers, path: pathTo(id) });
    }
    return {
      entryIds: [...new Set(entryIds)], reachableRootIds: [...previous.keys()], complete: blocked.size === 0,
      blockedRootIds: [...blocked], oldUsedOrPreferences,
      reachableInvalidTargets: invalidTargets.filter(edge => edge.visible && previous.has(edge.sourceRootId))
    };
  }

  // Configured flows get the legacy budget first. The broader review sweep
  // includes every visible review frame so a static evaluation entry is clear.
  const configuredReachability = await trace(configuredIds);
  const reviewReachability = await trace(reviewIds);

  function canonicalAction(value) {
    if (Array.isArray(value)) return value.map(canonicalAction);
    if (!value || typeof value !== 'object') return typeof value === 'string' ? r4AuditCanonical(value) : r4AuditRound(value);
    const result = {};
    for (const key of Object.keys(value).sort()) {
      if (key === 'destinationId') {
        const destination = targetCache.get(value[key]);
        result.destination = destination ? r4AuditCanonical((destination.rootId ? rootName(destination.rootId) : 'EXTERNAL/' + destination.name) + '/' + (paths.get(value[key]) || '$')) : 'MISSING';
      } else result[key] = canonicalAction(value[key]);
    }
    return result;
  }
  function fingerprint(record) {
    return {
      geometry: { width: record.bounds.width, height: record.bounds.height, visible: record.visible },
      text: record.texts.map(item => ({ path: r4AuditCanonical(item.path), visible: item.visible, text: r4AuditCanonical(item.text) })),
      reactions: record.reactions.map(item => ({ path: r4AuditCanonical(item.path), visible: item.visible, reactions: canonicalAction(item.reactions) }))
    };
  }
  const byTheme = { Light: new Map(), Dark: new Map() };
  for (const id of primaryIds) {
    const record = inspected.get(id), key = r4AuditCanonical(record.name);
    const group = byTheme[record.theme].get(key) || [];
    group.push(record);
    byTheme[record.theme].set(key, group);
  }
  const symmetry = { pairedCount: 0, missingLight: [], missingDark: [], duplicates: [], geometry: [], text: [], reactions: [] };
  for (const key of new Set([...byTheme.Light.keys(), ...byTheme.Dark.keys()])) {
    const light = byTheme.Light.get(key) || [], dark = byTheme.Dark.get(key) || [];
    if (!light.length) symmetry.missingLight.push({ key, ids: dark.map(item => item.id) });
    if (!dark.length) symmetry.missingDark.push({ key, ids: light.map(item => item.id) });
    if (light.length > 1 || dark.length > 1) symmetry.duplicates.push({ key, lightIds: light.map(item => item.id), darkIds: dark.map(item => item.id) });
    if (light.length !== 1 || dark.length !== 1) continue;
    symmetry.pairedCount++;
    const a = fingerprint(light[0]), b = fingerprint(dark[0]);
    for (const field of ['geometry', 'text', 'reactions']) {
      if (JSON.stringify(a[field]) !== JSON.stringify(b[field])) symmetry[field].push({ key, lightId: light[0].id, darkId: dark[0].id });
    }
  }

  const roots = [...inspected.values()];
  return {
    status: '只读审计完成；结果不代表已经实际点击验证', schemaVersion: 1, started, finished: new Date().toISOString(),
    scope: sections.map(({ node, ...scope }) => ({ ...scope, name: node.name, rootCount: node.children.length, bounds: r4AuditBox(node) })),
    missingSections, budgets: { maxLegacyRoots, maxLegacyNodes, legacyRootCount, legacyNodeCount },
    coverage: {
      primaryRootCount: primaryIds.length, inspectedRootCount: roots.length,
      inspectedNodeCount: roots.reduce((sum, root) => sum + root.nodeCount, 0),
      legacyUnscanned: [...legacyUnscanned].map(id => ({ id, name: rootName(id) })), incompleteRoots: [...incompleteRoots],
      allPrimaryRootsComplete: primaryIds.every(id => inspected.get(id).complete)
    },
    configuredFlowStartingPoints: configured, roots,
    edges: [...edges.values()].flat(), invalidTargets, selfLinks, externalTargets, legacyBoundaries,
    removedText: roots.flatMap(root => root.removedText.map(item => ({ rootId: root.id, rootName: root.name, ...item }))),
    reachability: { configured: configuredReachability, visibleReview: reviewReachability }, symmetry,
    limitations: [
      'Reachability is a conservative graph of visible prototype NODE actions; conditions are treated as possible branches.',
      'Zero-opacity hotspots remain in the link graph because opacity does not disable prototype interaction.',
      'CLOSE and BACK return to the runtime overlay/navigation stack and have no fixed destination in this static audit.',
      'Legacy reachability is incomplete whenever blockedRootIds or incompleteRoots are nonempty.',
      'Text, animation, return-path intent, and actual tappable areas still require prototype clicks and screenshots.'
    ]
  };
}
