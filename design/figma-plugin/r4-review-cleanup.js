// Local R3 review repair. Never regenerate a section or traverse old interaction
// subtrees. All new roots are R4/ReviewRepair/*; the original 44 review roots stay.
// Run after account flows, account extras, supportOnlyStage and finalLinksStage.
// cleanupReviewStage(theme, start=0, count=1) is deliberately resumable by source.
const R4_REVIEW_CLEANUP_VERSION = '1';
const R4_REVIEW_CLEANUP_EXPECTED_CANDIDATES = 32;

function reviewCleanupKind(node) {
  const p = node.name.split('|');
  return p.length > 1 ? p[1] : node.name.split('/').pop();
}
function reviewCleanupState(node) {
  const p = node.name.split('|');
  return { kind: reviewCleanupKind(node), expanded: p[6] || '', status: p[8] || '', updated: p[5] === 'new', size: p[9] || 'small', platform: p[7] || '' };
}
function reviewCleanupRequired(node, what) {
  if (!node || node.removed) throw Error('Review cleanup missing ' + what);
  return node;
}
function reviewCleanupGet(e, key) {
  return reviewCleanupRequired(e.registry.get('R4/' + e.t + '/' + key), key);
}
function reviewCleanupReactions(node) {
  return jobs.has(node) ? jobs.get(node) : node.reactions || [];
}
function reviewCleanupActive(node, root) {
  for (let n = node; n; n = n.parent) {
    if (n.visible === false) return false;
    if (n === root) return true;
  }
  return false;
}
function reviewCleanupClearOne(node) { jobs.set(node, []); writes.add(node.id); }
function reviewCleanupProtected(e, root) {
  return [e.entry.id, e.dashboard.id, e.settings.id].includes(root.id) ||
    ['Tutorial1', 'Tutorial1b', 'Tutorial2', 'Tutorial2b', 'Help', 'Privacy', 'Licenses', 'License', 'LockNotification'].includes(reviewCleanupKind(root));
}
function reviewCleanupRoots(e) {
  return e.review.children.filter(n => n.type === 'FRAME' && n.visible && !n.name.startsWith('R4/'));
}
function reviewCleanupCandidates(e) { return reviewCleanupRoots(e).filter(n => !reviewCleanupProtected(e, n)); }
function reviewCleanupCards(root, includeHidden = false) {
  const body = one(root, 'Content');
  if (!body) return [];
  const result = [];
  for (const child of body.children) {
    if (!includeHidden && child.visible === false) continue;
    const childTexts = child.type === 'TEXT' ? [child] : (typeof child.findAllWithCriteria === 'function' ? txt(child) : []);
    const text = childTexts.map(n => n.characters).join('\n');
    const accounts = R4A.slice(0, 4).filter(a => text.includes(a.email));
    if (accounts.length === 1) result.push({ idx: accounts[0].idx, node: child });
    else if (accounts.length > 1) throw Error('Ambiguous direct account card in ' + root.name + ': ' + child.name);
  }
  if (new Set(result.map(x => x.idx)).size !== result.length) throw Error('Duplicate account identity in ' + root.name);
  return result;
}
function reviewCleanupFamily(root) {
  const s = reviewCleanupState(root);
  return 'Dashboard-' + (s.expanded || 'collapsed') + '-' + (s.status || 'normal') + '-' + (s.updated ? 'new' : 'old');
}
function reviewCleanupSpecial(root) {
  const s = reviewCleanupState(root);
  return s.updated || ['stale', 'nodata', 'expired', 'unavailable', 'unknown', 'unlimited', 'noreset', 'due'].includes(s.status);
}
function reviewCleanupAffected(root) {
  const s = reviewCleanupState(root);
  if (['nodata', 'expired', 'due'].includes(s.status)) return 0;
  if (['unavailable', 'unknown', 'unlimited', 'noreset'].includes(s.status)) return 3;
  return null;
}
function reviewCleanupSheetClose(root) {
  const x = one(root, 'Action/close');
  if (x) close(x);
  const shade = root.children.find(n => n.type === 'RECTANGLE' && Math.abs(n.width - root.width) < 1 && Math.abs(n.height - root.height) < 1);
  if (shade) close(shade);
  for (const caption of ['取消', '关闭']) { const b = button(root, caption); if (b) close(b); }
}
function reviewCleanupHomeBar(root) {
  return one(root, 'Home indicator') || root.children.find(n => n.type === 'RECTANGLE' && Math.abs(n.width - 134) < 1 && n.height < 8);
}
async function reviewCleanupReady(e, mask) {
  if (!e.branch.getPluginData('r4_wired_' + mask + '_ready')) throw Error('Ready account model ' + mask + ' must be wired before R3 cleanup');
  return await getAccountModel(e, mask);
}

// The overlay stack is the source context. Shared failure panels never change
// quota, binding records, or timestamps, and therefore safely retain 09:11,
// 12:41, unlimited, unavailable-reset, and pending snapshots alike.
async function reviewCleanupCommon(e) {
  if (e.reviewCleanupCommon) return e.reviewCleanupCommon;
  const tag = 'r4_review_cleanup_common', raw = e.branch.getPluginData(tag);
  if (raw) {
    try {
      const saved = JSON.parse(raw), out = { q: {}, reconnect: {} };
      if (saved.version === R4_REVIEW_CLEANUP_VERSION) {
        for (const group of ['q', 'reconnect']) for (const [key, id] of Object.entries(saved[group] || {})) out[group][key] = await figma.getNodeByIdAsync(id);
        if (['all', 0, 1, 2, 3].every(k => out.q[k] && !out.q[k].removed) && [0, 1, 2, 3].every(k => out.reconnect[k] && !out.reconnect[k].removed)) {
          e.reviewCleanupCommon = out;
          return out;
        }
      }
    } catch (_) { /* Rehydrate the small local group after an interrupted run. */ }
  }
  const out = { q: {}, reconnect: {} };
  for (const scope of ['all', 0, 1, 2, 3]) {
    const who = scope === 'all' ? '当前全部已绑定账号' : R4A[scope].email;
    const key = 'ReviewRepair/Query/' + scope;
    const loading = panel(e, key + '/Loading', '正在查询额度', [who], ['取消']);
    progress(e, loading, 1); close(button(loading, '取消'));
    const failed = panel(e, key + '/Failed', '额度查询失败', [who, '平台暂未返回额度', '保留现有可信数据及上次成功时间'], ['重试', '关闭']);
    close(button(failed, '关闭'));
    put(loading, failed, 'SWAP', { timeout: 1 });
    const gate = await network(e, key, loading, who + '的额度查询');
    put(button(failed, '重试'), gate.start, 'SWAP');
    out.q[scope] = gate.start;
    if (scope !== 'all') {
      const login = root(e, e.logins[R4A[scope].p], 'ReviewRepair/Reconnect/' + scope);
      clear(login); fixLogin(e, login, R4A[scope].email);
      put(button(login, '继续'), gate.start, 'SWAP');
      out.reconnect[scope] = login;
    }
  }
  await flush();
  e.branch.setPluginData(tag, JSON.stringify({ version: R4_REVIEW_CLEANUP_VERSION,
    q: Object.fromEntries(Object.entries(out.q).map(([k, n]) => [k, n.id])),
    reconnect: Object.fromEntries(Object.entries(out.reconnect).map(([k, n]) => [k, n.id])) }));
  e.reviewCleanupCommon = out;
  return out;
}

// A detail overlay contains only the clicked account copied from its actual
// static source. No standard-model quota, reset, or timestamp is substituted.
// Prune only locally-owned clone content. Removing an instance's internal
// child is not allowed by Figma; retain the previous hidden override there.
function reviewCleanupPruneCloneNode(cloneRoot, node) {
  if (!cloneRoot.name.startsWith('R4/') || !cloneRoot.name.includes('/ReviewRepair/') || node === cloneRoot) throw Error('Pruning requires a local review-repair clone child');
  let parent = node.parent, insideInstance = false;
  for (; parent && parent !== cloneRoot; parent = parent.parent) {
    if (parent.type === 'INSTANCE') insideInstance = true;
  }
  if (parent !== cloneRoot) throw Error('Pruning target is outside its review-repair clone');
  if (insideInstance) { node.visible = false; return; }
  for (const child of all(node)) jobs.delete(child);
  node.remove();
}
async function reviewCleanupDetail(e, source, idx) {
  const key = 'ReviewRepair/' + reviewCleanupFamily(source) + '/Detail-' + idx;
  const detail = root(e, source, key);
  clear(detail);
  const cards = reviewCleanupCards(detail, true), card = reviewCleanupRequired(cards.find(x => x.idx === idx), source.name + ' detail account ' + idx).node;
  card.visible = true;
  const body = one(detail, 'Content');
  // The source stays intact. This overlay never displays another card or
  // source-state banner, so those complete cloned subtrees are unnecessary.
  for (const child of [...body.children]) if (child !== card) reviewCleanupPruneCloneNode(detail, child);
  const expanded = one(card, 'Account details');
  if (expanded) expanded.visible = true;
  for (const name of ['R3/Header actions', 'Action/refresh', 'Action/link', 'Tab bar']) { const n = one(detail, name); if (n) reviewCleanupPruneCloneNode(detail, n); }
  const more = one(card, 'Action/more'); if (more) more.visible = false;
  const expand = one(card, 'Expand account'); if (expand) close(expand);
  const sourceExpanded = e.registry.get('R4/' + e.t + '/Accounts/Set-15/Expanded-0');
  const upInstance = sourceExpanded && one(one(sourceExpanded, 'Quota/Claude'), 'Icon/down');
  const targetChevron = one(card, 'Icon/down');
  if (targetChevron && upInstance && targetChevron.type === 'INSTANCE' && upInstance.type === 'INSTANCE') {
    const component = await upInstance.getMainComponentAsync(); if (component) targetChevron.swapComponent(component);
  }
  const template = e.roots.find(n => reviewCleanupKind(n) === 'WidgetReview' && n.name.endsWith('|small'));
  const navigation = reviewCleanupRequired(one(detail, 'Navigation'), detail.name + ' navigation');
  const sourceBack = reviewCleanupRequired(one(template, 'Action/back'), 'R3 review back');
  let backButton = one(navigation, 'Action/back');
  if (!backButton) backButton = clone(sourceBack, navigation, 'Action/back');
  backButton.x = 12; backButton.y = 2; backButton.visible = true; close(backButton);
  const title = navigation.children.find(n => n.type === 'TEXT'); if (title) { title.x = 74; title.resize(245, title.height); }
  const home = reviewCleanupHomeBar(detail); if (home) close(home);
  return detail;
}

async function reviewCleanupDashboard(e, source, result) {
  const state = reviewCleanupState(source), cards = reviewCleanupCards(source), originalMask = cards.reduce((mask, item) => mask | R4A[item.idx].bit, 0);
  const common = await reviewCleanupCommon(e);
  const family = reviewCleanupFamily(source), special = reviewCleanupSpecial(source), affected = reviewCleanupAffected(source);
  // Resolve the sole R3 stale-time contradiction explicitly authorized for this
  // repair; do not normalize any other review frame's timestamp or quota.
  if (state.status === 'stale') for (const text of txt(source)) if (text.characters.includes('上次成功更新 09:41')) {
    change(text, text.characters.replace('上次成功更新 09:41', '上次成功更新 09:11'));
    result.textCorrections.push(text.id);
  }
  const contexts = new Map(), details = new Map();
  for (const { idx, node } of cards) if (one(node, 'Expand account')) details.set(idx, await reviewCleanupDetail(e, source, idx));
  for (let mask = 0; mask <= 15; mask++) {
    if ((mask & originalMask) !== mask) continue;
    const ready = await reviewCleanupReady(e, mask);
    const preserve = mask === originalMask || (special && mask !== 0 && (affected === null || (mask & R4A[affected].bit)));
    if (!preserve) { contexts.set(mask, { mask, d: ready.d, s: ready.s, readyD: ready.d, canonical: true }); continue; }
    const d = mask === originalMask ? source : root(e, source, 'ReviewRepair/' + family + '/Set-' + mask);
    clear(d);
    for (const item of reviewCleanupCards(d, true)) {
      const retained = !!(mask & R4A[item.idx].bit);
      if (d !== source && !retained) reviewCleanupPruneCloneNode(d, item.node);
      else item.node.visible = retained;
    }
    contexts.set(mask, { mask, d, s: ready.s, readyD: ready.d, canonical: false });
  }
  const tutorial = systemKind(e, 'Tutorial1');
  for (const context of contexts.values()) {
    if (context.canonical) continue;
    const f = context.d, chooser = reviewCleanupGet(e, 'AccountFlow/Set-' + context.mask + '/Connect');
    const link = one(f, 'Action/link'); if (link && reviewCleanupActive(link, f)) put(link, chooser, 'OVERLAY');
    for (const n of all(f)) if (reviewCleanupActive(n, f) && /^Button\/(?:连接账户|连接平台|添加账户)$/.test(n.name)) put(n, chooser, 'OVERLAY');
    const refresh = one(f, 'Action/refresh'); if (refresh && reviewCleanupActive(refresh, f)) put(refresh, common.q.all, 'OVERLAY');
    const latest = button(f, '查询最新额度'); if (latest && reviewCleanupActive(latest, f)) put(latest, common.q.all, 'OVERLAY');
    const st = one(f, 'Tab/设置'); if (st) put(st, context.s);
    const dt = one(f, 'Tab/额度'); if (dt) put(dt, f);
    const help = one(f, 'Action/如何添加小组件'); if (help) put(help, tutorial, 'OVERLAY');
    const home = reviewCleanupHomeBar(f), widget = e.registry.get('R4/' + e.t + '/AccountWidgets/Set-' + context.mask);
    if (home && widget && !special) put(home, widget);
    for (const item of reviewCleanupCards(f)) {
      const a = R4A[item.idx], idx = item.idx;
      const expand = one(item.node, 'Expand account');
      if (expand && details.has(idx)) {
        const open = one(item.node, 'Account details');
        if (open && open.visible && !special) put(expand, context.readyD, 'NAVIGATE', { smart: true });
        else put(expand, details.get(idx), 'OVERLAY');
      }
      const retry = button(item.node, '重试'); if (retry) put(retry, common.q[idx], 'OVERLAY');
      const reconnect = button(item.node, '重新连接'); if (reconnect) put(reconnect, common.reconnect[idx], 'OVERLAY');
      const more = one(item.node, 'Action/more');
      if (!more) continue;
      const key = 'ReviewRepair/' + family + '/Set-' + context.mask + '/Account-' + idx;
      const menu = panel(e, key + '/Menu', a.p + ' 账户', [a.email], ['刷新额度', '重新连接', '断开连接', '取消']);
      close(button(menu, '取消'));
      put(button(menu, '刷新额度'), common.q[idx], 'SWAP');
      put(button(menu, '重新连接'), common.reconnect[idx], 'SWAP');
      const confirmation = panel(e, key + '/Disconnect', '断开连接？', [a.email, '移除此账号的额度数据和待发提醒。平台订阅不会取消。'], ['断开连接', '取消']);
      close(button(confirmation, '取消'));
      const next = reviewCleanupRequired(contexts.get(context.mask & ~a.bit), 'remaining account context');
      put(button(confirmation, '断开连接'), next.d);
      put(button(menu, '断开连接'), confirmation, 'SWAP');
      put(more, menu, 'OVERLAY');
    }
  }
  result.sourceContexts = [...contexts.values()].filter(x => !x.canonical).map(x => ({ mask: x.mask, id: x.d.id }));
  result.navigationBoundary = 'Settings and successful addition use the existing same-binding R4 model. Query failure, cancellation, reconnect failure, expanded details, and disconnect retain the visual source data.';
}

async function reviewCleanupReplaceChildren(e, destination, source) {
  // Keep the original review root, URL, position and visibility. Its replacement
  // content is the already-validated R4 equivalent, never an old settings tree.
  clear(destination);
  for (const child of [...destination.children]) child.remove();
  for (const child of source.children) clone(child, destination, child.name);
  await copyFlowTree(source, destination);
}

async function reviewCleanupStaticRoot(e, root, result) {
  const state = reviewCleanupState(root), kind = state.kind;
  if (!['Dashboard', 'Settings', 'Connect', 'Menu', 'Login', 'Connecting', 'Failed', 'Disconnect', 'Permission', 'System', 'WidgetReview', 'WidgetConfig', 'SystemHome', 'WidgetState', 'StateReview'].includes(kind)) {
    throw Error('R3 review kind requires a specific plan before edits: ' + kind);
  }
  if (kind === 'Dashboard') { await reviewCleanupDashboard(e, root, result); return; }
  if (kind === 'Settings') {
    const n = root.name.split('|')[4], suffix = n === '1' ? 'on' : n === '2' ? 'denied' : null;
    if (!suffix) throw Error('Unrecognized R3 notification settings: ' + root.name);
    await reviewCleanupReplaceChildren(e, root, reviewCleanupGet(e, 'AccountSystem/Set-15/Settings-' + suffix));
    result.replacedChildren = true;
    return;
  }
  const saved = all(root).filter(n => 'reactions' in n && n.reactions.length).map(n => ({ n, reactions: n.reactions }));
  const base = await reviewCleanupReady(e, 15), common = await reviewCleanupCommon(e);
  clear(root);
  const idx = { Claude: 0, Codex: 1, Cursor: 3 }[state.platform || 'Claude'];
  if (['Connect', 'Menu', 'Login', 'Connecting', 'Failed', 'Disconnect', 'Permission'].includes(kind)) reviewCleanupSheetClose(root);
  if (kind === 'Connect' || kind === 'Failed') {
    const chooser = reviewCleanupGet(e, 'AccountFlow/Set-15/Connect');
    for (const platform of kind === 'Connect' ? ['Claude', 'Codex', 'Cursor'] : [state.platform || 'Claude']) {
      const from = reviewCleanupRequired(one(chooser, 'Connect/' + platform), 'current add action');
      const reaction = reviewCleanupReactions(from).find(r => (r.actions || []).some(a => a.type === 'NODE'));
      const action = reaction && reaction.actions.find(a => a.type === 'NODE');
      const destination = action && await figma.getNodeByIdAsync(action.destinationId);
      put(kind === 'Connect' ? one(root, 'Connect/' + platform) : button(root, '重新尝试'), reviewCleanupRequired(destination, 'network-gated add ' + platform), 'SWAP');
    }
  } else if (kind === 'Menu') {
    put(one(root, 'Row/刷新额度'), common.q[idx], 'SWAP');
    put(one(root, 'Row/重新连接'), common.reconnect[idx], 'SWAP');
    put(one(root, 'Row/断开连接'), reviewCleanupGet(e, 'AccountFlow/Set-15/d/Disconnect-' + idx), 'SWAP');
  } else if (kind === 'Login') {
    put(button(root, '继续'), common.q[idx], 'SWAP');
  } else if (kind === 'Connecting') {
    // This retained R3 loading illustration is no longer an authorization or
    // account-creation shortcut. Its existing close/cancel controls stay live.
    result.staticLoadingIllustration = true;
  } else if (kind === 'Disconnect') {
    put(button(root, '断开连接'), (await reviewCleanupReady(e, 15 & ~R4A[idx].bit)).d);
  } else if (kind === 'Permission') {
    put(button(root, '允许'), reviewCleanupGet(e, 'AccountSystem/Set-15/Settings-on'));
    put(button(root, '不允许'), reviewCleanupGet(e, 'AccountSystem/Set-15/Settings-denied'));
  } else if (kind === 'System') {
    const toggle = reviewCleanupRequired(accountSystemToggleNode(root), 'R3 system toggle');
    put(toggle, reviewCleanupGet(e, 'AccountSystem/Set-15/iOS-on'), 'NAVIGATE', { smart: true });
    put(one(root, 'Action/back'), reviewCleanupGet(e, 'AccountSystem/Set-15/Settings-denied'));
  } else if (kind === 'WidgetReview') {
    put(one(root, 'Action/back'), e.entry);
    for (const [label, size] of [['小号', 'small'], ['中号', 'medium']]) { const b = button(root, label); if (b) put(b, reviewCleanupGet(e, 'Widgets/Gallery/' + size)); }
    for (const label of ['添加小组件', '编辑小组件']) put(button(root, label), reviewCleanupGet(e, 'Widgets/Config/' + state.size + '/A'));
    for (const n of all(root)) if (/^Button\/查看(?:已用|剩余)状态$/.test(n.name) || n.name.startsWith('显示切换仅为评审入口')) { n.visible = false; reviewCleanupClearOne(n); }
  } else if (kind === 'WidgetConfig') {
    put(one(root, 'Action/back'), reviewCleanupGet(e, 'Widgets/Gallery/' + state.size));
    for (const [label, key] of [['Claude', 'A'], ['Codex', 'B'], ['Codex · work', 'C'], ['Cursor', 'D']]) put(one(root, 'Account/' + label), reviewCleanupGet(e, 'Widgets/Config/' + state.size + '/' + key));
    put(button(root, '完成'), reviewCleanupGet(e, 'Widgets/Home/Config/' + state.size + '/A'));
  } else if (kind === 'SystemHome') {
    put(one(root, 'Widget/Claude'), reviewCleanupGet(e, 'Widgets/Detail/A'), 'OVERLAY');
    put(one(root, 'Action/back'), reviewCleanupGet(e, 'Widgets/Gallery/' + state.size));
    const home = reviewCleanupHomeBar(root); if (home) put(home, base.d);
  } else if (kind === 'WidgetState') {
    const groups = root.findAll(n => n.name === 'Card');
    const matching = caption => reviewCleanupRequired(groups.find(n => txt(n).some(tx => tx.characters === caption)), 'widget status ' + caption);
    // The root argument is the retained review frame; the helper creates only
    // the separate R4 configuration view whose selection is initially empty.
    const config = await reviewCleanupUnselected(e, root);
    put(matching('尚未选择账户'), config);
    put(matching('账户已断开'), reviewCleanupGet(e, 'AccountWidgets/Set-13'));
    put(matching('需要重新连接'), common.reconnect[1], 'OVERLAY');
    put(matching('暂时无法更新'), common.q[1], 'OVERLAY');
    put(one(root, 'Action/back'), systemKind(e, 'StateReview'));
  } else if (kind === 'StateReview') {
    // Its existing status entries still point to the visible R3 screenshots.
    // Preserve those exact review destinations, including error illustrations.
    const visibleIds = new Set(reviewCleanupRoots(e).map(n => n.id));
    for (const item of saved) if (reviewCleanupActive(item.n, root)) {
      const reactions = item.reactions.map(r => ({ trigger: JSON.parse(JSON.stringify(r.trigger)), actions: JSON.parse(JSON.stringify(r.actions || (r.action ? [r.action] : []))) }));
      if (reactions.some(r => r.actions.some(a => a.type === 'NODE' && !visibleIds.has(a.destinationId)))) throw Error('Unexpected non-review StateReview destination');
      jobs.set(item.n, reactions); writes.add(item.n.id);
    }
    put(one(root, 'Action/back'), e.entry);
  } else throw Error('R3 review kind requires a specific plan: ' + kind);
}

async function reviewCleanupUnselected(e, source) {
  const config = root(e, reviewCleanupGet(e, 'Widgets/Config/small/A'), 'ReviewRepair/WidgetUnselectedConfig');
  clear(config);
  for (const check of config.findAll(n => n.name === 'Icon/check')) check.visible = false;
  const finish = button(config, '完成'); if (finish) finish.visible = false;
  for (const [label, key] of [['Claude', 'A'], ['Codex', 'B'], ['Codex · work', 'C'], ['Cursor', 'D']]) put(one(config, 'Account/' + label), reviewCleanupGet(e, 'Widgets/Config/small/' + key));
  put(one(config, 'Action/back'), source);
  return config;
}

async function reviewCleanupLegacyEdges(e) {
  const legacy = new Set(e.branch.children.filter(n => !n.name.startsWith('R4/')).map(n => n.id)), result = [], cache = new Map();
  for (const source of reviewCleanupRoots(e)) for (const node of all(source)) {
    if (!reviewCleanupActive(node, source) || !('reactions' in node)) continue;
    for (const reaction of reviewCleanupReactions(node)) for (const action of reaction.actions || (reaction.action ? [reaction.action] : [])) {
      if (action.type !== 'NODE' || !action.destinationId) continue;
      if (!cache.has(action.destinationId)) {
        let target = await figma.getNodeByIdAsync(action.destinationId), old = null;
        for (let n = target; n && n.type !== 'PAGE'; n = n.parent) if (legacy.has(n.id)) { old = n; break; }
        cache.set(action.destinationId, { target, old });
      }
      const value = cache.get(action.destinationId);
      if (!value.target || value.old || reviewCleanupKind(value.target) === 'Display' || /\|U\|/.test(value.target.name)) result.push({ source: source.id, node: node.id, nodeName: node.name, destination: action.destinationId, target: value.target?.name || null, protected: reviewCleanupProtected(e, source) });
    }
  }
  return result;
}

async function planReviewCleanupStage(t) {
  const e = await env(t), roots = reviewCleanupRoots(e), candidates = reviewCleanupCandidates(e);
  return { status: t + ' R3 局部修复方案（未写入）', visibleReviewCount: roots.length,
    candidateCount: candidates.length, expectedCandidateCount: R4_REVIEW_CLEANUP_EXPECTED_CANDIDATES,
    eligibleForMutation: roots.length === 44 && candidates.length === R4_REVIEW_CLEANUP_EXPECTED_CANDIDATES,
    protected: roots.filter(n => reviewCleanupProtected(e, n)).map(n => ({ id: n.id, name: n.name })),
    candidates: candidates.map((n, index) => ({ index, id: n.id, name: n.name, kind: reviewCleanupKind(n), specialData: reviewCleanupSpecial(n), key: reviewCleanupFamily(n) })),
    rules: ['保留 44 个原 review root、位置和可见性；仅两个旧通知设置根替换为对应当前 R4 子树。', '查询只模拟检查后失败，CLOSE 保留来源、身份、可信数据与成功时间；每次重试重新检查。', '特殊状态的断开副本只删除指定账号；剩余账号仍用来源数据。', '仅旧 stale 页成功时间统一为其既有说明中的 09:11。', '最终只浅层隐藏非 R4 interaction 根，不删除或遍历其子树。'],
    remainingLegacyEdges: await reviewCleanupLegacyEdges(e) };
}

async function cleanupReviewStage(t, start = 0, count = 1) {
  const e = await env(t), roots = reviewCleanupRoots(e), candidates = reviewCleanupCandidates(e);
  if (roots.length !== 44) throw Error('Expected exactly 44 visible R3 review frames, got ' + roots.length);
  if (candidates.length !== R4_REVIEW_CLEANUP_EXPECTED_CANDIDATES) throw Error('Expected exactly 32 reviewed cleanup candidates (indexes 0–31), got ' + candidates.length + '; inspect cleanupplan before mutation');
  if (!Number.isInteger(start) || start < 0 || start >= candidates.length || !Number.isInteger(count) || count < 1 || count > 4) throw Error('Review cleanup requires a valid source index and batch count 1–4');
  for (let mask = 0; mask <= 15; mask++) if (!e.branch.getPluginData('r4_wired_' + mask + '_ready')) throw Error('Complete ready model ' + mask + ' before starting R3 review cleanup');
  const results = [];
  for (let index = start; index < Math.min(start + count, candidates.length); index++) {
    const source = candidates[index], tag = 'r4_review_cleanup_' + source.id.replace(/:/g, '_');
    const done = e.branch.getPluginData(tag);
    if (done === R4_REVIEW_CLEANUP_VERSION) { results.push({ index, id: source.id, skipped: true }); continue; }
    const before = e.registry.size, result = { index, id: source.id, name: source.name, textCorrections: [] };
    figma.ui.postMessage({ status: t + ' 整理 R3 评审路径 ' + (index + 1) + '/' + candidates.length, progress: true });
    await reviewCleanupStaticRoot(e, source, result);
    // Even invisible historical controls cannot carry obsolete reactions into
    // later clones. Protected roots are inspected elsewhere, not modified here.
    for (const node of all(source)) if ('reactions' in node && !reviewCleanupActive(node, source)) reviewCleanupClearOne(node);
    await flush();
    if (!source.visible || roots.some(n => n.removed || !n.visible)) throw Error('R3 review visibility changed unexpectedly');
    e.branch.setPluginData(tag, R4_REVIEW_CLEANUP_VERSION); figma.commitUndo();
    result.createdRootCount = e.registry.size - before;
    results.push(result);
    await new Promise(resolve => setTimeout(resolve, 0));
  }
  const complete = candidates.every(n => e.branch.getPluginData('r4_review_cleanup_' + n.id.replace(/:/g, '_')) === R4_REVIEW_CLEANUP_VERSION);
  let remainingLegacyEdges = null, hiddenLegacyRootIds = [];
  if (complete) {
    remainingLegacyEdges = await reviewCleanupLegacyEdges(e);
    if (!remainingLegacyEdges.length) {
      const restoreKey = 'r4_review_cleanup_old_visible', previous = e.branch.getPluginData(restoreKey);
      hiddenLegacyRootIds = e.branch.children.filter(n => !n.name.startsWith('R4/') && n.visible).map(n => n.id);
      if (!previous) e.branch.setPluginData(restoreKey, JSON.stringify(hiddenLegacyRootIds));
      for (const n of e.branch.children) if (!n.name.startsWith('R4/') && n.visible) { n.visible = false; writes.add(n.id); }
      figma.commitUndo();
    }
  }
  return { status: complete && !remainingLegacyEdges?.length ? t + ' R3 评审路径清理完成' : t + ' R3 评审路径批次完成',
    start, end: Math.min(start + count, candidates.length), nextIndex: Math.min(start + count, candidates.length), total: candidates.length,
    complete: complete && !remainingLegacyEdges?.length, results, remainingLegacyEdges, hiddenLegacyRootIds,
    preservedReviewRootIds: roots.map(n => n.id), protectedRootIds: roots.filter(n => reviewCleanupProtected(e, n)).map(n => n.id) };
}
