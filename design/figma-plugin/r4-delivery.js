// Bounded final canvas organization and native PNG delivery.
// No new roots, cloning, reparenting, component edits, or reaction edits.
// Read-only entry points never call env()/init(), load fonts, or select nodes.
const R4_DELIVERY_VERSION = '1';
const R4_DELIVERY_SCOPE = {
  Light: { review: '1:43251', branch: '1:43252', entry: '1:500', label: '浅色' },
  Dark: { review: '1:43253', branch: '1:43254', entry: '1:4088', label: '深色' },
};
const R4_DELIVERY_CACHE = new Map();
const R4_DELIVERY_PAGE_OBSERVERS = new Map(), R4_DELIVERY_OBSERVER_TRIED = new Set();
let R4_DELIVERY_GENERATION = 0;
const R4_DELIVERY_OWN_GEOMETRY = new Map(), R4_DELIVERY_EVENT_CHECKS = new Set();
function deliveryAck(status) { figma.ui.postMessage({ status, progress: true }); }
async function deliveryYield(status) { if (status) deliveryAck(status); await new Promise(resolve => setTimeout(resolve, 0)); }
function deliveryMeta(n, parentId) {
  return { id: n.id, type: n.type, name: n.name, visible: n.visible !== false,
    parentId: parentId === undefined ? n.parent?.id || null : parentId,
    width: n.width || 0, height: n.height || 0, x: n.x || 0, y: n.y || 0 };
}
function deliverySameMeta(a, b) { return ['id', 'type', 'name', 'visible', 'parentId', 'width', 'height', 'x', 'y'].every(k => a[k] === b[k]); }
function deliveryMarkStale(reason) { R4_DELIVERY_GENERATION++; for (const d of R4_DELIVERY_CACHE.values()) d.stale = reason; }
function deliveryHasObserver(d) { return d.review.parentId === d.branch.parentId && R4_DELIVERY_PAGE_OBSERVERS.has(d.review.parentId); }
function deliveryObserve(page) {
  if (!page || page.type !== 'PAGE') throw Error('Delivery sections require a Page parent.');
  const pageId = page.id;
  if (R4_DELIVERY_OBSERVER_TRIED.has(pageId)) return;
  R4_DELIVERY_OBSERVER_TRIED.add(pageId);
  try {
    if (typeof page.on !== 'function') throw Error('Page nodechange is unavailable.');
    const listener = event => {
      for (const change of event.nodeChanges || []) {
        const id = change.node?.id;
        const properties = change.properties || [];
        if (!id) { deliveryMarkStale('Page event has no node ID'); continue; }
        if (change.type === 'PROPERTY_CHANGE' && properties.length && properties.every(p => ['pluginData', 'sharedPluginData', 'flowStartingPoints'].includes(p))) continue;
        const expected = R4_DELIVERY_OWN_GEOMETRY.get(id);
        if (change.type !== 'PROPERTY_CHANGE' || !expected || !properties.length || !properties.every(p => ['x', 'y', 'width', 'height', 'name', 'relativeTransform', 'size', 'pluginData', 'sharedPluginData'].includes(p))) {
          deliveryMarkStale('Page changed: ' + id); continue;
        }
        // Own layout events may arrive after the write returns. Accept them only
        // while live metadata still exactly matches this module's final values.
        const check = (async () => {
          try { const n = await figma.getNodeByIdAsync(id), latest = R4_DELIVERY_OWN_GEOMETRY.get(id); if (!n || n.removed || !latest || !deliverySameMeta(deliveryMeta(n), latest)) deliveryMarkStale('Unexpected geometry change: ' + id); }
          catch (_) { deliveryMarkStale('Cannot verify changed root: ' + id); }
        })();
        R4_DELIVERY_EVENT_CHECKS.add(check); check.finally(() => R4_DELIVERY_EVENT_CHECKS.delete(check));
      }
    };
    // Page-scoped events work with dynamic-page without loading other pages.
    page.on('nodechange', listener); R4_DELIVERY_PAGE_OBSERVERS.set(pageId, listener);
    deliveryAck('当前页面变更监听已启用 · 缓存按根 ID 校验');
  } catch (error) {
    deliveryAck('页面监听不可用，将逐批完整核对根元数据 · ' + String(error));
  }
}
async function deliverySettleEvents() {
  await deliveryYield();
  while (R4_DELIVERY_EVENT_CHECKS.size) await Promise.all([...R4_DELIVERY_EVENT_CHECKS]);
}
function deliveryInvalidateCache(t) {
  if (t !== undefined && !R4_DELIVERY_SCOPE[t]) throw Error('Choose Light or Dark.');
  const themes = t ? [t] : ['Light', 'Dark'];
  for (const theme of themes) R4_DELIVERY_CACHE.delete(theme);
  return { status: '交付缓存已失效，下次将重新读取', themes, mutationCount: 0 };
}
async function deliveryRows(container, label) {
  const children = container.children, result = [];
  for (let i = 0; i < children.length; i++) {
    result.push(deliveryMeta(children[i], container.id));
    if ((i + 1) % 100 === 0) await deliveryYield(label + ' · 元数据 ' + (i + 1) + '/' + children.length);
  }
  return result;
}
async function deliveryValidateCache(d) {
  await deliverySettleEvents();
  if (d.stale) throw Error(d.stale + '; explicitly refresh delivery cache before continuing.');
  for (const [meta, rows] of [[d.review, d.reviewRows], [d.branch, d.branchRows]]) {
    const container = await figma.getNodeByIdAsync(meta.id);
    if (!container || container.removed || container.type !== 'SECTION' || !deliverySameMeta(deliveryMeta(container), meta)) { d.stale = 'Scoped section changed'; break; }
    const children = container.children;
    if (children.length !== rows.length) { d.stale = 'Root count changed'; break; }
    for (let i = 0; i < rows.length; i++) {
      if (children[i].id !== rows[i].id || (!deliveryHasObserver(d) && !deliverySameMeta(deliveryMeta(children[i], meta.id), rows[i]))) { d.stale = 'Root snapshot changed at ' + rows[i].id; break; }
      if ((i + 1) % 200 === 0) await deliveryYield();
    }
    if (d.stale) break;
  }
  await deliverySettleEvents();
  if (d.stale) throw Error(d.stale + '; explicitly refresh delivery cache before continuing.');
}

function deliveryManifestSpec(t) {
  const n = (key, suffix) => t + ' · R4 NET · ' + key + ' · ' + suffix;
  const rows = [];
  const add = (group, slug, key, title, source = 'r4') => rows.push({ group, slug, key, title, source });
  add('overview', 'review', 'Review', 'R4 交互评审目录');
  add('overview', 'dashboard', 'Dashboard', '多账号与固定剩余看板', 'r3');
  add('overview', 'settings', 'Settings', '当前设置入口', 'r3');
  add('network', 'check-a', n('Review 51', '检查中 A'), '检查中 · 动画相位 A');
  add('network', 'check-b', n('Review 51', '检查中 B'), '检查中 · 动画相位 B');
  add('network', 'pass51', n('Review 51', '评分 51 · 检查通过'), '51 分通过后继续授权');
  add('network', 'score49', n('Review 49', '有效评分 49 · 已阻止'), '49 分阻止');
  add('network', 'score50', n('Review 50', '有效评分 50 · 已阻止'), '50 分阻止');
  for (const outcome of ['timeout', 'unavailable', 'invalid']) {
    add('network', outcome, n('Review ' + outcome, outcome + ' · 无法完成检查'),
      { timeout: '检查超时', unavailable: '评分网站不可用', invalid: '无有效评分' }[outcome]);
  }
  add('network', 'query-failed', 'Network/QueryFailed', '通过检查后额度查询失败');
  add('network', 'authorization-failed', 'Network/AuthFailed', '通过检查后授权失败');
  add('first-query', 'before-add-source', 'Review/BeforeAddFailedLaunch', '新增前失败保留已有账号');
  add('first-query', 'before-add49', n('Review before add preserve accounts', '有效评分 49 · 已阻止'), '新增前 49 分阻止');
  add('first-query', 'pending', 'Review/FirstQueryLaunch', '新增后尚未取得额度');
  add('first-query', 'failed', 'Review/FirstQuery/Failed', '首次查询失败 · 无可信旧额度');
  for (const [state, title] of [['CheckA', '进入 App 自动检查'], ['Failed', '超时，保留旧数据'], ['Passed', '51 分检查通过'], ['Querying', '正在查询额度'], ['Success', '成功更新至 09:45']]) {
    add('background', 'app-' + state.toLowerCase(), 'Background/App/' + state, '后台更新 · ' + title);
  }
  for (const [state, title] of [['Failed', '网站不可用，保留 09:41'], ['Querying', '正在查询额度'], ['Success', '成功更新至 09:45']]) {
    add('background', 'widget-' + state.toLowerCase(), 'Background/Widget/' + state, '小组件联网 · ' + title);
  }
  add('widgets', 'gallery-small', 'Widgets/Gallery/small', '小号小组件');
  add('widgets', 'gallery-medium', 'Widgets/Gallery/medium', '中号小组件');
  add('widgets', 'choose-work', 'Widgets/Config/small/C', '选择具体 work 账号');
  add('widgets', 'configured-pair', 'Widgets/Home/Config/small/C', 'work 与 Cursor 两个独立组件');
  add('widgets', 'same-platform', 'Widgets/Home/Fallback/ABD', '同平台回退至个人 Codex');
  add('widgets', 'cross-platform', 'Widgets/Home/Fallback/AD', '跨平台回退至 Claude');
  add('widgets', 'empty', 'Widgets/Home/Fallback/Empty', '全部断开后的无账号状态');
  add('widgets', 'multiple-candidates', 'Widgets/Home/MultipleCandidates', '多个同平台候选按列表次序选择');
  add('widgets', 'same-platform-pending', 'AccountWidgets/Set-10/Pending-1', '同平台回退 · 未获取额度');
  add('widgets', 'cross-platform-pending', 'AccountWidgets/Set-9/Pending-0', '跨平台回退 · 未获取额度');
  add('widgets', 'stale-target', 'Widgets/Stale/Pending-10-1', '旧组件缓存 · 点击进入当前账号状态');
  add('accounts', 'work-expanded', 'Accounts/Set-15/Expanded-2', '具体 work 账号展开');
  add('accounts', 'work-menu', 'AccountFlow/Set-15/d/Menu-2', '具体 work 账号操作菜单');
  add('accounts', 'work-disconnect', 'AccountFlow/Set-15/d/Disconnect-2', '断开具体 work 账号');
  add('system', 'permission', 'AccountSystem/Set-15/Permission', '系统通知权限');
  add('system', 'denied', 'AccountSystem/Set-15/Settings-denied', '通知拒绝后的设置');
  add('system', 'ios-on', 'AccountSystem/Set-15/iOS-on', '系统设置开启通知');
  add('system', 'notification', 'LockNotification', '点击通知进入具体账号', 'kind');
  add('system', 'notification-removed', 'Notifications/TargetRemoved', '通知目标已断开');
  add('system', 'tutorial', 'Tutorial1', '小组件教程与退出', 'kind');
  return rows;
}

async function deliveryDirectory(t, options = {}) {
  deliveryAck(t + ' · 读取交付目录' + (options.refresh ? '（显式刷新）' : ''));
  const scope = R4_DELIVERY_SCOPE[t];
  if (!scope) throw Error('Delivery theme must be Light or Dark.');
  await deliverySettleEvents();
  if (options.refresh) deliveryInvalidateCache(t);
  const existing = R4_DELIVERY_CACHE.get(t);
  if (existing) { await deliveryValidateCache(existing); return existing; }
  const [review, branch, entry] = await Promise.all([scope.review, scope.branch, scope.entry].map(id => figma.getNodeByIdAsync(id)));
  if (!review || review.type !== 'SECTION' || !branch || branch.type !== 'SECTION' || !entry || entry.type !== 'FRAME') throw Error('Delivery scope missing.');
  const page = review.parent;
  if (!page || page.type !== 'PAGE' || branch.parent?.id !== page.id) throw Error('Delivery sections must share a Page.');
  deliveryObserve(page);
  await deliverySettleEvents();
  const generation = R4_DELIVERY_GENERATION;
  await deliveryYield(t + ' · 已取得评审区与交互区');
  const reviewRows = await deliveryRows(review, t + '评审区'), branchRows = await deliveryRows(branch, t + '交互区');
  const r3 = reviewRows.filter(n => n.type === 'FRAME' && n.visible);
  const r4 = branchRows.filter(n => n.type === 'FRAME' && n.name.startsWith('R4/' + t + '/'));
  const byName = new Map(), duplicates = [];
  for (const node of r4) {
    if (byName.has(node.name)) duplicates.push({ name: node.name, ids: [byName.get(node.name).id, node.id] });
    else byName.set(node.name, node);
  }
  const manifest = deliveryManifestSpec(t).map(item => {
    const node = item.source === 'r4' ? byName.get('R4/' + t + '/' + item.key) :
      item.source === 'r3' ? r3.find(n => n.name === t + '/' + item.key) :
      r3.find(n => n.name === t + '/' + item.key || n.name.split('|')[1] === item.key);
    return { ...item, node: node || null };
  });
  await deliverySettleEvents();
  if (generation !== R4_DELIVERY_GENERATION) throw Error('Document changed while reading delivery metadata; explicitly refresh.');
  const d = { t, scope, review: deliveryMeta(review), branch: deliveryMeta(branch), entry: deliveryMeta(entry),
    reviewRows, branchRows, r3, r4, byName, manifest, duplicates, generation, stale: null, layout: null,
    visibleLegacy: branchRows.filter(n => !n.name.startsWith('R4/') && n.visible) };
  R4_DELIVERY_CACHE.set(t, d);
  deliveryAck(t + ' · 目录元数据完成，R4 根 ' + r4.length);
  return d;
}

function deliveryArchiveGroup(t, name) {
  const key = name.slice(('R4/' + t + '/').length);
  const pending = key.match(/(?:Accounts|AccountFlow|AccountWidgets|AccountSystem)\/Pending-(\d+)-(\d+)/);
  if (pending) return '40 · 待获取集合 ' + pending[1].padStart(3, '0') + ' / 账号 ' + pending[2];
  const set = key.match(/(?:Accounts|AccountFlow|AccountWidgets|AccountSystem)\/Set-(\d+)/);
  if (set) return '30 · 账号集合 ' + set[1].padStart(3, '0');
  if (key.includes('· R4 NET ·') || key.startsWith('Network/')) return '10 · 网络检查完整分支';
  if (key.startsWith('Widgets/') || key.startsWith('AccountWidgets/')) return '11 · 小组件完整分支';
  if (key.startsWith('Background/')) return '12 · 后台与小组件更新完整分支';
  if (key.startsWith('Notifications/') || key.startsWith('AccountSystem/') || key.startsWith('System/')) return '13 · 通知与系统完整分支';
  if (key.startsWith('ReviewRepair/')) return '50 · 原评审画面的保留数据分支';
  if (key.startsWith('AccountFlow/')) return '20 · 账号新增与共享查询分支';
  return '60 · 其他已建 R4 状态';
}

async function deliveryLayout(directory) {
  if (directory.stale) throw Error('Delivery layout cache is stale; refresh first.');
  if (directory.layout) return directory.layout;
  await deliveryYield(directory.t + ' · 准备缓存布局');
  const order = ['overview', 'network', 'first-query', 'background', 'widgets', 'accounts', 'system'];
  const labels = { overview: '评审目录', network: '网络检查', 'first-query': '新增前检查与首次查询', background: '后台与小组件联网', widgets: '小组件配置与回退', accounts: '具体账号操作', system: '通知与教程' };
  const selected = new Set(), groups = [];
  for (let i = 0; i < order.length; i++) {
    const key = order[i], nodes = [];
    for (const item of directory.manifest.filter(x => x.group === key && x.source === 'r4' && x.node)) {
      if (!selected.has(item.node.id)) { selected.add(item.node.id); nodes.push(item.node); }
    }
    if (nodes.length) groups.push({ name: '0' + i + ' · 关键评审 · ' + labels[key], key, columns: 8, nodes });
  }
  const archive = new Map();
  let prepared = 0;
  for (const node of directory.r4) {
    if (selected.has(node.id)) continue;
    const group = deliveryArchiveGroup(directory.t, node.name);
    if (!archive.has(group)) archive.set(group, []);
    archive.get(group).push(node);
    if (++prepared % 500 === 0) await deliveryYield();
  }
  for (const key of [...archive.keys()].sort()) {
    groups.push({ name: key, key, columns: 16,
      nodes: archive.get(key).sort((a, b) => a.name < b.name ? -1 : a.name > b.name ? 1 : 0) });
    await deliveryYield();
  }
  const placements = [], summaries = [];
  const cellWidth = Math.ceil(directory.r4.reduce((width, n) => Math.max(width, n.width), 393)) + 32;
  let y = 96, right = 0;
  for (const group of groups) {
    const startY = y;
    for (let offset = 0; offset < group.nodes.length; offset += group.columns) {
      const row = group.nodes.slice(offset, offset + group.columns);
      const rowHeight = Math.ceil(Math.max(...row.map(n => n.height)));
      row.forEach((node, column) => {
        const x = 48 + column * cellWidth;
        placements.push({ node, x, y, group: group.name });
        right = Math.max(right, x + node.width);
      });
      y += rowHeight + 56;
      if (placements.length % 256 < group.columns) await deliveryYield();
    }
    summaries.push({ name: group.name, count: group.nodes.length, top: startY, bottom: y - 56,
      first: group.nodes[0].id, last: group.nodes[group.nodes.length - 1].id });
    y += 128;
  }
  await deliverySettleEvents();
  if (directory.stale) throw Error('Document changed while preparing delivery layout; refresh first.');
  directory.layout = { placements, groups: summaries, width: right + 48, height: y, cellWidth };
  return directory.layout;
}

// Shallow, read-only counts/manifest. This does not replace auditR4 or clicking.
async function deliveryReadOnlyStage(t, options = {}) {
  deliveryAck(t + ' · 开始只读交付检查');
  const d = await deliveryDirectory(t, options), layout = await deliveryLayout(d);
  return { status: t + ' 交付清单与排布计划（只读）', version: R4_DELIVERY_VERSION,
    counts: { originalVisibleReview: d.r3.length, expectedOriginalVisibleReview: 44,
      r4Roots: d.r4.length, r4Visible: d.r4.filter(n => n.visible !== false).length,
      legacyVisible: d.visibleLegacy.length, curated: d.manifest.filter(x => x.node).length },
    duplicates: d.duplicates,
    missingCurated: d.manifest.filter(x => !x.node).map(({ node, ...item }) => item),
    groups: layout.groups, plannedBounds: { width: layout.width, height: layout.height },
    manifest: d.manifest.filter(x => x.node).map(({ node, ...item }) => ({ ...item, id: node.id, name: node.name,
      filename: t.toLowerCase() + '-' + item.group + '-' + item.slug + '.png',
      section: node.parentId, width: node.width, height: node.height })),
    entries: { original: d.entry.id, r4: d.byName.get('R4/' + t + '/Review')?.id || null },
    cache: { generation: d.generation, metadataCached: true, documentObserver: false, pageObserver: deliveryHasObserver(d), observedPageId: deliveryHasObserver(d) ? d.review.parentId : null, validation: deliveryHasObserver(d) ? 'root IDs plus page nodechange observer' : 'root IDs plus full metadata fallback' },
    limitations: ['只浅读根节点与导出清单；不验证文字遮挡、反应目标、动画或实际点击。', '排布不会改变任何根名称、父级、可见性或原型反应。'] };
}

// Resumable, deterministic batches. The caller repeats using nextIndex.
async function arrangeDeliveryStage(t, start = 0, count = 200) {
  deliveryAck(t + ' · 开始排布批次 ' + start);
  if (!Number.isInteger(start) || start < 0 || !Number.isInteger(count) || count < 1 || count > 400) throw Error('Delivery batches require start>=0 and count 1–400.');
  const d = await deliveryDirectory(t);
  if (d.r3.length !== 44) throw Error('Expected 44 visible original review roots.');
  if (d.visibleLegacy.length) throw Error('Finish reviewed legacy cleanup before moving R4 roots to the top.');
  if (d.duplicates.length) throw Error('Duplicate R4 root names require inspection before arrangement.');
  if (d.manifest.some(x => !x.node)) throw Error('Missing curated root; run deliveryReadOnlyStage for exact keys.');
  const layout = await deliveryLayout(d), end = Math.min(start + count, layout.placements.length);
  if (start > layout.placements.length) throw Error('Delivery start exceeds root count.');
  // Width stays within the existing side-by-side section spacing in this file.
  if (layout.width > 9000) throw Error('Unexpected wide root: inspect layout before changing section bounds.');
  const neededHeight = d.branchRows.reduce((height, n) => n.name.startsWith('R4/') ? height : Math.max(height, n.y + n.height + 48), layout.height);
  const [branch, review] = await Promise.all([d.branch.id, d.review.id].map(id => figma.getNodeByIdAsync(id)));
  if (!branch || !review || branch.removed || review.removed) throw Error('Delivery sections disappeared.');
  const own = (node, meta) => { const current = deliveryMeta(node); Object.assign(meta, current); R4_DELIVERY_OWN_GEOMETRY.set(node.id, { ...current }); };
  // Preflight only this batch's live roots. Sorting and target coordinates use
  // the single cached plan; no global native name/size reads recur per batch.
  const batch = [];
  for (let i = start; i < end; i++) {
    const placement = layout.placements[i], node = await figma.getNodeByIdAsync(placement.node.id);
    if (!node || node.removed || !deliverySameMeta(deliveryMeta(node), placement.node)) { d.stale = 'Live root differs from cached layout'; throw Error(d.stale + '; refresh before writing.'); }
    batch.push({ placement, node });
    if ((i - start + 1) % 80 === 0) await deliveryYield(t + ' · 排布预检 ' + (i + 1) + '/' + layout.placements.length);
  }
  await deliverySettleEvents(); if (d.stale) throw Error(d.stale + '; refresh before writing.');
  branch.resizeWithoutConstraints(Math.max(branch.width, layout.width), Math.max(branch.height, neededHeight)); own(branch, d.branch);
  if (typeof writes !== 'undefined') writes.add(branch.id);
  let moved = 0;
  for (let i = 0; i < batch.length; i++) {
    const { placement, node } = batch[i], { x, y } = placement;
    if (node.x !== x || node.y !== y) { node.x = x; node.y = y; own(node, placement.node); moved++; if (typeof writes !== 'undefined') writes.add(node.id); }
    if ((i + 1) % 80 === 0) {
      await deliveryYield(t + ' 排布 ' + (start + i + 1) + '/' + layout.placements.length);
    }
  }
  const remaining = end === layout.placements.length ? layout.placements.findIndex(x => x.node.x !== x.x || x.node.y !== x.y) : -1;
  const complete = end === layout.placements.length && remaining === -1;
  const nextIndex = end === layout.placements.length && !complete ? remaining : end;
  branch.setPluginData('r4_delivery_layout_batch', JSON.stringify({ version: R4_DELIVERY_VERSION, nextIndex, total: layout.placements.length }));
  if (complete) {
    review.name = d.scope.label + ' · R4 画面评审 · 保留 44 页'; own(review, d.review);
    branch.name = d.scope.label + ' · R4 交互状态与返回路径 · 关键评审置顶'; own(branch, d.branch);
    if (typeof writes !== 'undefined') writes.add(d.review.id);
    branch.resizeWithoutConstraints(Math.max(branch.width, layout.width), neededHeight); own(branch, d.branch);
    branch.setPluginData('r4_delivery_layout_complete', JSON.stringify({ version: R4_DELIVERY_VERSION, total: layout.placements.length, groups: layout.groups }));
  }
  figma.commitUndo();
  await deliverySettleEvents(); if (d.stale) throw Error(d.stale + '; inspect the completed batch before refreshing.');
  return { status: complete ? t + ' 画布排布完成' : t + ' 画布排布批次完成',
    start, end, nextIndex, total: layout.placements.length, moved, complete,
    scope: '只移动当前交互区现有 R4 根；不改原 44 页坐标，不改根名称、父级、反应或组件。' };
}

// Preserve both original entry URLs. Unrelated flow-starting points on the
// same page are retained; only starts within these four scoped sections change.
async function finalizeDeliveryEntriesStage() {
  deliveryAck('开始核对两套原型起点');
  const light = await deliveryDirectory('Light'), dark = await deliveryDirectory('Dark');
  for (const d of [light, dark]) {
    const branch = await figma.getNodeByIdAsync(d.branch.id);
    if (!branch?.getPluginData('r4_final_links_complete') || !d.byName.has('R4/' + d.t + '/Review')) throw Error('Complete both final review directories before publishing flow-starting points.');
  }
  const p = await figma.getNodeByIdAsync(light.review.parentId);
  if (light.review.parentId !== dark.review.parentId || !p || p.type !== 'PAGE') throw Error('Delivery sections must share a page.');
  const scopedSections = new Set([light, dark].flatMap(d => [d.review.id, d.branch.id]));
  const scopedRoots = new Set([light, dark].flatMap(d => [...d.reviewRows, ...d.branchRows].map(n => n.id)));
  const previous = p.flowStartingPoints.map(x => ({ nodeId: x.nodeId, name: x.name }));
  const unrelated = [];
  for (const point of previous) {
    if (scopedRoots.has(point.nodeId)) continue;
    let owned = false;
    const node = await figma.getNodeByIdAsync(point.nodeId);
    for (let parent = node; parent && parent.type !== 'PAGE'; parent = parent.parent) if (scopedSections.has(parent.id)) { owned = true; break; }
    if (!owned) unrelated.push(point);
  }
  p.flowStartingPoints = unrelated.concat([
    { nodeId: light.entry.id, name: 'R4 · 浅色 · 交互状态与返回路径' },
    { nodeId: dark.entry.id, name: 'R4 · 深色 · 交互状态与返回路径' },
  ]);
  figma.commitUndo();
  return { status: '原型起点已更新，原链接保留', previous, current: p.flowStartingPoints,
    entries: { Light: light.entry.id, Dark: dark.entry.id } };
}

// Export only a small native gallery batch. No section-wide bitmap, composite,
// temporary frames, or screenshots produced by redrawing the Figma content.
async function deliveryGalleryStage(t, group = 'network', start = 0, count = 4) {
  deliveryAck(t + ' · 开始导出批次 ' + group + '/' + start);
  if (!Number.isInteger(start) || start < 0 || !Number.isInteger(count) || count < 1 || count > 4) throw Error('Export 1–4 selected frames per batch.');
  const d = await deliveryDirectory(t), selected = d.manifest.filter(x => group === 'all' || x.group === group);
  if (!selected.length) throw Error('Unknown or empty delivery group: ' + group);
  const batch = selected.slice(start, start + count);
  if (batch.some(x => !x.node)) throw Error('Selected export target missing; inspect deliveryReadOnlyStage.');
  const gallery = [];
  for (const item of batch) {
    figma.ui.postMessage({ status: '导出 ' + t + ' · ' + item.title, progress: true });
    const node = await figma.getNodeByIdAsync(item.node.id);
    if (!node || node.removed || !deliverySameMeta(deliveryMeta(node), item.node)) { d.stale = 'Export target changed'; throw Error(d.stale + '; refresh before exporting.'); }
    const bytes = await node.exportAsync({ format: 'PNG', constraint: { type: 'SCALE', value: 1 } });
    gallery.push({ id: item.node.id, name: item.node.name, title: item.title,
      filename: t.toLowerCase() + '-' + item.group + '-' + item.slug + '.png', bytes: Array.from(bytes) });
  }
  return { status: t + ' ' + group + ' 原生静态截图完成', group, start, end: start + batch.length,
    total: selected.length, complete: start + batch.length >= selected.length, gallery };
}
