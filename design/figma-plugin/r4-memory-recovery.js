// Standalone READ-ONLY recovery planning. No core/env/model dependencies.
// No delete, create, visibility, selection, pluginData, undo or page-load writes.
// Runtime state stores IDs, counts and small graph edges; never Figma nodes.
// Reloading the plugin discards the scan. Freeze all editing until finish.
let R4_MEMORY_RECOVERY = null;
const R4_MEMORY_SCOPES = {
  Light: { review: '1:43251', branch: '1:43252', protected: ['1:500', '1:536', '1:2169'] },
  Dark: { review: '1:43253', branch: '1:43254', protected: ['1:4088', '1:4124', '1:5757'] },
};
const R4_MEMORY_FILE_KEY = 'LwH8GU8iQfxhxIT3YXAcyR';

function memoryRecoveryIssue(s, key, sample) {
  const issue = s.issues[key] || (s.issues[key] = { count: 0, samples: [], omitted: 0 });
  issue.count++;
  if (issue.samples.length < 30) issue.samples.push(sample); else issue.omitted++;
}
function memoryRecoveryHash(values) {
  let hash = 2166136261, length = 0;
  for (const value of values) {
    const text = String(value); length += text.length + 1;
    for (let i = 0; i <= text.length; i++) hash = Math.imul(hash ^ (i === text.length ? 0 : text.charCodeAt(i)), 16777619) >>> 0;
  }
  return hash.toString(16) + ':' + length;
}
function memoryRecoveryDirectoryHash(node) {
  const values = [node.id, node.name, node.type];
  for (const child of node.children) values.push(child.id, child.type, child.name, child.visible !== false);
  if (node.type === 'PAGE') for (const start of node.flowStartingPoints || []) values.push('flow', start.nodeId, start.name);
  return memoryRecoveryHash(values);
}
function memoryRecoveryProgress() {
  const s = R4_MEMORY_RECOVERY;
  if (!s) return { status: '尚未建立只读恢复扫描' };
  return { status: s.finalized ? '只读恢复计划已汇总' : '只读恢复扫描进度', runId: s.runId, theme: s.theme,
    includeHiddenReactions: s.includeHiddenReactions, directory: s.directoryCounts, cleanupGate: s.cleanupGate,
    scannedRoots: s.cursor, totalRoots: s.roots.length, remainingRoots: s.roots.length - s.cursor,
    activeRoot: s.active ? { id: s.roots[s.active.index].id, scannedNodes: s.active.nodes, remainingNodeIds: s.active.stack.length } : null,
    scannedNodes: s.scannedNodes, scannedReactionLayers: s.reactionLayers, inspectedActions: s.actions,
    externalReferencesToLegacy: s.externalReferenceCount, legacyInternalEdges: s.internalEdgeCount,
    mutationEventsObserved: s.mutationEvents, issueCounts: Object.fromEntries(Object.entries(s.issues).map(([k, v]) => [k, v.count])),
    mutationCount: 0, deletionImplemented: false };
}
function memoryRecoverySeed(s, id, reason) {
  if (!s.seeds.has(id)) s.seeds.set(id, new Set()); s.seeds.get(id).add(reason);
}
async function memoryRecoveryOwner(s, id) {
  if (s.rootIndex.has(id)) return { rootId: id };
  if (s.targetCache.has(id)) return s.targetCache.get(id);
  let node;
  try { node = await figma.getNodeByIdAsync(id); }
  catch (error) { memoryRecoveryIssue(s, 'unreadableTarget', { id, reason: String(error) }); return { unknown: true }; }
  if (!node || node.removed) return { missing: true };
  let found = null;
  for (let current = node; current && current.type !== 'DOCUMENT'; current = current.parent) {
    if (s.rootIndex.has(current.id)) { found = { rootId: current.id }; break; }
    if (current.type === 'PAGE') { found = { pageId: current.id }; break; }
  }
  if (!found) { memoryRecoveryIssue(s, 'unownedTarget', { id }); found = { unknown: true }; }
  // Most prototype targets are roots and need no cache. Bound descendant cache.
  if (s.targetCache.size >= 2000) s.targetCache.clear();
  s.targetCache.set(id, found); return found;
}
async function memoryRecoveryReference(s, source, sourceNodeId, targetId, kind, visible) {
  if (typeof targetId !== 'string' || !targetId) {
    memoryRecoveryIssue(s, 'unresolvedDestination', { source: source.id, sourceNodeId, kind }); return;
  }
  const owner = await memoryRecoveryOwner(s, targetId);
  if (owner.missing) { memoryRecoveryIssue(s, 'missingTarget', { source: source.id, sourceNodeId, destinationId: targetId }); return; }
  if (!owner.rootId || !s.candidates.has(owner.rootId)) return;
  if (s.candidates.has(source.id)) {
    const edges = s.edges.get(source.id) || new Set();
    if (!edges.has(owner.rootId)) { edges.add(owner.rootId); s.internalEdgeCount++; }
    s.edges.set(source.id, edges);
  } else {
    s.externalReferenceCount++; memoryRecoverySeed(s, owner.rootId, kind);
    memoryRecoveryIssue(s, 'externalReference', { source: source.id, sourceNodeId, destinationId: targetId,
      legacyRoot: owner.rootId, kind, sourceVisibleWithinRoot: visible });
  }
}
async function memoryRecoveryAction(s, source, sourceNodeId, value, visible) {
  if (Array.isArray(value)) { for (const item of value) await memoryRecoveryAction(s, source, sourceNodeId, item, visible); return; }
  if (!value || typeof value !== 'object') return;
  if (value.type) s.actions++;
  if ('destinationId' in value && value.destinationId !== null) await memoryRecoveryReference(s, source, sourceNodeId, value.destinationId, 'prototype', visible);
  if (value.type === 'URL' && typeof value.url === 'string' && value.url.includes(R4_MEMORY_FILE_KEY)) {
    const match = value.url.match(/[?&#]node-id=([^&#]+)/);
    if (match) {
      let id = ''; try { id = decodeURIComponent(match[1]).replace(/^(\d+)-(\d+)$/, '$1:$2'); } catch (_) {}
      if (/^\d+:\d+$/.test(id)) await memoryRecoveryReference(s, source, sourceNodeId, id, 'sameFileUrl', visible);
      else memoryRecoveryIssue(s, 'unparsedSameFileUrl', { source: source.id, sourceNodeId, url: value.url.slice(0, 200) });
    }
  }
  for (const [key, child] of Object.entries(value)) if (key !== 'destinationId' && key !== 'url' && child && typeof child === 'object') await memoryRecoveryAction(s, source, sourceNodeId, child, visible);
}

// No automatic loadAllPagesAsync: if recovery has not loaded a page, the plan
// stays unproven. Loading pages can itself raise memory use and needs judgment.
async function memoryRecoveryStart(theme = 'Light', options = {}) {
  if (!R4_MEMORY_SCOPES[theme]) throw Error('Choose exact theme Light or Dark.');
  if (R4_MEMORY_RECOVERY && !options.reset) throw Error('A scan exists; continue it or explicitly reset.');
  if (R4_MEMORY_RECOVERY?.listener && typeof figma.off === 'function') figma.off('documentchange', R4_MEMORY_RECOVERY.listener);
  const s = { runId: 'r4memory-' + Date.now(), theme, started: new Date().toISOString(), includeHiddenReactions: options.includeHiddenReactions === true,
    roots: [], rootIndex: new Map(), candidates: new Set(), snapshots: [], pages: [], targetCache: new Map(),
    seeds: new Map(), edges: new Map(), cursor: 0, active: null, scannedNodes: 0, reactionLayers: 0, actions: 0,
    externalReferenceCount: 0, internalEdgeCount: 0, mutationEvents: 0, listener: null, issues: {}, finalized: null,
    directoryCounts: { pages: 0, containers: 0, roots: 0, currentR4Roots: 0, reviewRoots: 0, otherRoots: 0, candidateLegacyRoots: 0 },
    cleanupGate: null, backupEvidence: options.backupEvidence || null };
  R4_MEMORY_RECOVERY = s;
  if (figma.skipInvisibleInstanceChildren === true) memoryRecoveryIssue(s, 'invisibleInstanceChildrenSkipped', { reason: 'Disable this optimization in a fresh read-only plugin before proving full coverage.' });
  if (typeof figma.on !== 'function' || typeof figma.off !== 'function') memoryRecoveryIssue(s, 'mutationObserverUnavailable', {});
  else {
    try {
      const listener = event => { s.mutationEvents++; s.finalized = null; if (s.mutationEvents <= 30) memoryRecoveryIssue(s, 'documentChangedDuringScan', { event: s.mutationEvents, changeCount: event?.documentChanges?.length ?? null }); };
      figma.on('documentchange', listener); s.listener = listener;
    } catch (error) { memoryRecoveryIssue(s, 'mutationObserverUnavailable', { reason: String(error) }); }
  }
  const scope = R4_MEMORY_SCOPES[theme];
  const review = await figma.getNodeByIdAsync(scope.review), branch = await figma.getNodeByIdAsync(scope.branch);
  if (!review || review.type !== 'SECTION' || !branch || branch.type !== 'SECTION') throw Error('Missing fixed target scope. No deletion plan can be produced.');
  const originals = review.children.filter(n => n.type === 'FRAME' && n.visible !== false && !n.name.startsWith('R4/'));
  const protectedKinds = new Set(['Tutorial1', 'Tutorial1b', 'Tutorial2', 'Tutorial2b', 'Help', 'Privacy', 'Licenses', 'License', 'LockNotification']);
  const eligible = originals.filter(n => !scope.protected.includes(n.id) && !protectedKinds.has(n.name.includes('|') ? n.name.split('|')[1] : n.name.split('/').pop()));
  const incompleteIds = eligible.filter(n => branch.getPluginData('r4_review_cleanup_' + n.id.replace(/:/g, '_')) !== '1').map(n => n.id);
  s.cleanupGate = { reviewSection: scope.review, interactionSection: scope.branch,
    originalVisibleReviewCount: originals.length, preservedReviewIds: originals.map(n => n.id),
    expectedReviewCount: 44, cleanupCandidateCount: eligible.length, expectedCleanupCount: 32,
    incompleteCleanupIds: incompleteIds, passed: originals.length === 44 && eligible.length === 32 && incompleteIds.length === 0 };
  if (!s.cleanupGate.passed) memoryRecoveryIssue(s, 'cleanupNotComplete', { theme, count: eligible.length, incompleteIds });
  // Traversal begins at every document page. Sections are shallow roots of
  // their own (for any references on a container); each child is scanned once.
  async function directory(container) {
    let children;
    try { children = container.children; s.snapshots.push({ id: container.id, hash: memoryRecoveryDirectoryHash(container) }); }
    catch (error) { memoryRecoveryIssue(s, 'unreadableDirectory', { id: container.id, reason: String(error) }); return; }
    s.directoryCounts.containers++;
    for (const n of children) {
      const candidate = container.id === scope.branch && n.type === 'FRAME' && !n.name.startsWith('R4/');
      const info = { id: n.id, parentId: container.id, type: n.type, name: n.name.slice(0, 180), visible: n.visible !== false,
        shallow: n.type === 'SECTION', candidate, nodes: 0, complete: false };
      s.rootIndex.set(info.id, s.roots.length); s.roots.push(info);
      if (candidate) {
        s.candidates.add(n.id); s.directoryCounts.candidateLegacyRoots++;
        if (n.visible !== false) { memoryRecoverySeed(s, n.id, 'visibleLegacyRoot'); memoryRecoveryIssue(s, 'visibleLegacyRoot', { id: n.id, name: info.name }); }
      }
      if (n.name.startsWith('R4/')) s.directoryCounts.currentR4Roots++;
      else if (Object.values(R4_MEMORY_SCOPES).some(x => x.review === container.id)) s.directoryCounts.reviewRoots++;
      else s.directoryCounts.otherRoots++;
      if (n.type === 'SECTION') await directory(n);
    }
  }
  const pages = figma.root.children;
  s.documentHash = memoryRecoveryHash(pages.map(p => p.id));
  for (const p of pages) {
    s.pages.push(p.id); s.directoryCounts.pages++; await directory(p);
  }
  s.directoryCounts.roots = s.roots.length;
  for (const pageId of s.pages) {
    try {
      const p = await figma.getNodeByIdAsync(pageId);
      for (const point of p.flowStartingPoints || []) await memoryRecoveryReference(s, { id: pageId }, pageId, point.nodeId, 'flowStartingPoint', true);
    } catch (error) { memoryRecoveryIssue(s, 'unreadableFlowStarts', { id: pageId, reason: String(error) }); }
  }
  return { ...memoryRecoveryProgress(), status: '全文件只读目录已建立；尚未证明可移除',
    capabilities: { documentChangeObserver: !!s.listener, automaticPageLoading: false, nodeReferencesRetained: false,
      scope: 'All accessible pages and scene trees, including both themes and roots outside the four sections.' } };
}

// A root can pause mid-tree. Only its IDs/visible flags survive the batch.
// Hidden ROOT frames still count as possible prototype scenes; child visibility
// controls the default visible-reaction scan. Strict mode checks both.
async function memoryRecoveryBatch(maxRoots = 20, nodeBudget = 3000, timeBudgetMs = 5000) {
  const s = R4_MEMORY_RECOVERY; if (!s) throw Error('Run memoryRecoveryStart first.');
  if (s.finalized) return memoryRecoveryProgress();
  if (![maxRoots, nodeBudget, timeBudgetMs].every(Number.isInteger) || maxRoots < 1 || maxRoots > 100 || nodeBudget < 1 || nodeBudget > 10000 || timeBudgetMs < 100 || timeBudgetMs > 10000) throw Error('Use maxRoots 1–100, nodes 1–10000, time 100–10000ms.');
  const began = Date.now(), initial = s.cursor; let visited = 0;
  while (s.cursor < s.roots.length && s.cursor - initial < maxRoots && visited < nodeBudget && Date.now() - began < timeBudgetMs) {
    const info = s.roots[s.cursor];
    if (!s.active) s.active = { index: s.cursor, stack: [{ id: info.id, visible: true, isRoot: true }], nodes: 0 };
    const item = s.active.stack.pop(); let n;
    try {
      n = await figma.getNodeByIdAsync(item.id);
      if (!n || n.removed) throw Error('Node removed or unavailable');
      const visible = item.visible && (item.isRoot || n.visible !== false);
      visited++; s.scannedNodes++; s.active.nodes++;
      if (info.candidate && ['COMPONENT', 'COMPONENT_SET'].includes(n.type)) memoryRecoverySeed(s, info.id, 'containsComponentMaster');
      if ('reactions' in n) {
        const reactions = n.reactions || [];
        if (reactions.length && !visible && !s.includeHiddenReactions) memoryRecoveryIssue(s, 'uninspectedHiddenReactions', { rootId: info.id, nodeId: n.id, count: reactions.length });
        else if (reactions.length) {
          s.reactionLayers++;
          for (const reaction of reactions) await memoryRecoveryAction(s, info, n.id, reaction.actions || (reaction.action ? [reaction.action] : []), visible);
        }
      }
      // A component used outside a legacy tree cannot be deleted with that tree.
      // Candidate component masters were conservatively protected above.
      for (const key of ['connectorStart', 'connectorEnd']) if (key in n) {
        const endpoint = n[key]; if (endpoint?.endpointNodeId) await memoryRecoveryReference(s, info, n.id, endpoint.endpointNodeId, 'connectorEndpoint', visible);
      }
      if (!info.shallow && 'children' in n) {
        const children = n.children;
        for (let i = children.length - 1; i >= 0; i--) s.active.stack.push({ id: children[i].id, visible, isRoot: false });
      }
    } catch (error) { memoryRecoveryIssue(s, 'unreadableNode', { rootId: info.id, nodeId: item.id, reason: String(error) }); }
    n = null;
    if (!s.active.stack.length) { info.nodes = s.active.nodes; info.complete = true; s.active = null; s.cursor++; }
    if (visited && visited % 100 === 0) await new Promise(resolve => setTimeout(resolve, 0));
  }
  return { ...memoryRecoveryProgress(), status: '只读恢复扫描批次完成', processedRootsThisBatch: s.cursor - initial, nodesThisBatch: visited, elapsedMs: Date.now() - began };
}

async function memoryRecoveryFinish() {
  const s = R4_MEMORY_RECOVERY; if (!s) throw Error('Run memoryRecoveryStart first.');
  if (s.finalized) return s.finalized;
  if (s.cursor < s.roots.length || s.active) return { ...memoryRecoveryProgress(), referenceProofPassed: false, safeRemovalRootIds: [], status: '扫描未完成，不提供可移除根' };
  if (memoryRecoveryHash(figma.root.children.map(p => p.id)) !== s.documentHash) memoryRecoveryIssue(s, 'changedDirectory', { id: 'document' });
  for (const snapshot of s.snapshots) {
    try { const n = await figma.getNodeByIdAsync(snapshot.id); if (!n || memoryRecoveryDirectoryHash(n) !== snapshot.hash) memoryRecoveryIssue(s, 'changedDirectory', { id: snapshot.id }); }
    catch (error) { memoryRecoveryIssue(s, 'changedDirectory', { id: snapshot.id, reason: String(error) }); }
  }
  const retained = new Set(s.seeds.keys()), queue = [...retained];
  for (let i = 0; i < queue.length; i++) for (const target of s.edges.get(queue[i]) || []) if (!retained.has(target)) { retained.add(target); queue.push(target); }
  const blockers = ['cleanupNotComplete', 'unreadableDirectory', 'unreadableFlowStarts', 'mutationObserverUnavailable', 'invisibleInstanceChildrenSkipped',
    'unreadableNode', 'unreadableTarget', 'unownedTarget', 'unresolvedDestination', 'unparsedSameFileUrl', 'uninspectedHiddenReactions', 'changedDirectory', 'documentChangedDuringScan'];
  const failed = blockers.filter(k => s.issues[k]?.count);
  if (s.mutationEvents && !failed.includes('documentChangedDuringScan')) failed.push('documentChangedDuringScan');
  const proof = s.cleanupGate.passed && failed.length === 0;
  const removable = s.roots.filter(n => n.candidate && !retained.has(n.id));
  const plan = removable.map(n => ({ id: n.id, name: n.name, type: n.type, visible: n.visible, nodeCount: n.nodes }));
  s.finalized = { ...memoryRecoveryProgress(), status: proof ? '只读引用证明完成；移除计划待人工审核' : '引用证明未通过，不提供可执行移除列表',
    schemaVersion: 1, finished: new Date().toISOString(), referenceProofPassed: proof, blockers: failed,
    safeRemovalRootIds: proof ? plan.map(n => n.id) : [], proposedUnreferencedRootCount: plan.length,
    plan: proof ? plan : [], estimatedRemovedNodeCount: proof ? plan.reduce((sum, n) => sum + n.nodeCount, 0) : null,
    preservedLegacyRoots: s.roots.filter(n => n.candidate && retained.has(n.id)).map(n => ({ id: n.id, name: n.name,
      directReasons: [...(s.seeds.get(n.id) || [])], transitivelyReachable: !s.seeds.has(n.id), nodeCount: n.nodes })),
    issues: s.issues, backupEvidence: s.backupEvidence, nativeBackupVerifiedByThisModule: false,
    deletionAuthorized: false, deletionImplemented: false,
    limitations: ['No removal is performed or implemented. Save and verify a native backup, review exact IDs, then revalidate before a separately authorized mutation.',
      'Proof covers references exposed by the current file: prototype actions, same-file node URLs, flow starts, connector endpoints; legacy roots containing component masters are retained.',
      'External files, comments, cloud history and future edits are not inspectable references. No page is automatically loaded to avoid raising memory usage.',
      'Default visible-layer mode refuses proof if hidden layers have reactions; strict includeHiddenReactions scans their target IDs without retaining node objects.',
      'Root visibility is not used to exclude an existing scene. Closure keeps every legacy root reachable from any external reference, including other pages and the opposite theme.',
      'The full scan must stay in one plugin runtime without editing. A saved plan is evidence, not a durable lock or future deletion permission.'] };
  return s.finalized;
}

function memoryRecoveryDispose() {
  if (R4_MEMORY_RECOVERY?.listener && typeof figma.off === 'function') figma.off('documentchange', R4_MEMORY_RECOVERY.listener);
  R4_MEMORY_RECOVERY = null;
  return { status: '只读恢复扫描内存已释放', mutationCount: 0, deletionImplemented: false };
}
