// Scoped notification-mode preservation for finite review stories.
// Append after core, foundation, flows, account-system, integrate, cross-add.
// No code runs on load; this never changes canonical/initial account controls.
const R4_PERMISSION_READY_MASKS = [...Array.from({ length: 16 }, (_, i) => i), 31, 47, 79, 95];
const R4_PERMISSION_ADD_ROUTES = [
  { source: 15, idx: 4, next: 31 }, { source: 15, idx: 5, next: 47 },
  { source: 15, idx: 6, next: 79 }, { source: 31, idx: 6, next: 95 }
];
const R4_PERMISSION_MODES = ['on', 'off', 'denied'];
const R4_PERMISSION_VERSION = '1';

function permissionPreservePlan() {
  return { readyMasks: R4_PERMISSION_READY_MASKS, modes: R4_PERMISSION_MODES, additionRoutes: R4_PERMISSION_ADD_ROUTES,
    estimatedNewFramesPerTheme: { readyMenusAndConfirmations: 636, pendingQueries: 192, pendingMenusAndReconnect: 48, additionChains: 72, choosers: 6, total: 954 },
    boundaries: [
      'Disconnect destinations outside the 20 ready masks retain the same mode, but their subsequent account controls are not repaired by this module.',
      'Pending repair covers only the four declared new-account models: details, all/pending-account query, query cancellation/retry and the pending-account reconnect.',
      'Disconnects and further additions from these pending views remain outside this scoped repair.',
      'Successful additions other than Set15 → 31/47/79 and Set31 → 95 are outside this mode-preservation story.',
      'System Home/widget navigation and separate notification/background review stories remain outside this module.'
    ] };
}
function permissionRequired(node, description) { if (!node || node.removed) throw Error('Permission preservation missing ' + description); return node; }
function permissionNode(e, key) { return e.registry.get('R4/' + e.t + '/' + key); }
function permissionScope(model) { return model.pendingIdx === undefined ? 'Set-' + model.mask : 'Pending-' + model.mask + '-' + model.pendingIdx; }
function permissionViews(e, model, mode) {
  const key = 'AccountSystem/' + permissionScope(model);
  return { d: permissionRequired(permissionNode(e, key + '/Dashboard-' + mode), key + ' dashboard ' + mode),
    s: permissionRequired(permissionNode(e, key + '/Settings-' + mode), key + ' settings ' + mode) };
}
function permissionModelRefs(e, mask, pendingIdx) {
  const accounts = R4_ACCOUNT_ORDER.filter(i => mask & R4A[i].bit);
  const model = { mask, accounts, pendingIdx };
  if (pendingIdx !== undefined && !accounts.includes(pendingIdx)) throw Error('Pending account is not in model');
  return model;
}
function permissionActions(node) { return node ? (jobs.has(node) ? jobs.get(node) : node.reactions || []).flatMap(r => r.actions || (r.action ? [r.action] : [])) : []; }
function permissionEdge(node, target, navigation) { return !!target && permissionActions(node).some(a => a.type === 'NODE' && a.destinationId === target.id && a.navigation === navigation); }
function permissionClosed(node) { return permissionActions(node).some(a => a.type === 'CLOSE'); }
function permissionFlowScope(model) { return model.pendingIdx === undefined ? 'AccountFlow/Set-' + model.mask : pendingKey(model.mask, model.pendingIdx); }
function permissionAddControl(view) {
  return one(view, 'Action/link') || one(view, 'Row/连接账户') || view.findOne(n => n.name.startsWith('Button/') && txt(n).some(t => /^连接平台$|^连接账户$/.test(t.characters)));
}
function permissionBatch(start, count, length) {
  if (!Number.isInteger(start) || start < 0 || start >= length || !Number.isInteger(count) || count < 1 || count > 2) throw Error('Permission batches require valid start and count 1–2');
  return Math.min(start + count, length);
}
async function permissionCopyRoot(e, source, key) {
  const dest = root(e, permissionRequired(source, key + ' source'), key);
  await copyFlowTree(source, dest);
  return dest;
}
function permissionPreserveDetails(e, model, views, common) {
  for (const origin of ['d', 's']) for (const idx of model.accounts) {
    const item = origin === 'd' ? findCard(views[origin], idx) : findRow(views[origin], idx);
    const trigger = one(item, origin === 'd' ? 'Expand account' : 'Account identity');
    if (!trigger) continue;
    const target = model.pendingIdx === idx ? permissionNode(e, permissionFlowScope(model) + '/WidgetUnknown') || permissionNode(e, permissionFlowScope(model) + '/PendingDetails') : common.detail[idx];
    put(trigger, permissionRequired(target, 'specific cached/pending account detail ' + idx), 'OVERLAY');
  }
}

async function permissionReadyModel(e, mask, common) {
  const tag = 'r4_permission_ready_' + mask;
  if (e.branch.getPluginData(tag) === R4_PERMISSION_VERSION) return { mask, skipped: true };
  const model = permissionModelRefs(e, mask), key = 'PermissionKeep/Set-' + mask, boundaries = [];
  if (!e.branch.getPluginData('r4_wired_' + mask + '_ready')) throw Error('Ready account flow not complete: ' + mask);
  // Preflight every source/destination before creating the first local menu.
  for (const mode of R4_PERMISSION_MODES) {
    permissionViews(e, model, mode);
    for (const idx of model.accounts) permissionViews(e, permissionModelRefs(e, mask & ~R4A[idx].bit), mode);
  }
  for (const mode of R4_PERMISSION_MODES) {
    const views = permissionViews(e, model, mode);
    permissionPreserveDetails(e, model, views, common);
    for (const origin of ['d', 's']) {
      const refresh = one(views[origin], 'Action/refresh');
      if (refresh) put(refresh, common.q.all, 'OVERLAY');
      for (const idx of model.accounts) {
        const sourceKey = permissionFlowScope(model) + '/' + origin;
        const sourceMenu = permissionNode(e, sourceKey + '/Menu-' + idx), sourceConfirm = permissionNode(e, sourceKey + '/Disconnect-' + idx);
        const menu = await permissionCopyRoot(e, sourceMenu, key + '/' + mode + '/' + origin + '/Menu-' + idx);
        const confirm = await permissionCopyRoot(e, sourceConfirm, key + '/' + mode + '/' + origin + '/Disconnect-' + idx);
        const next = mask & ~R4A[idx].bit, target = permissionViews(e, permissionModelRefs(e, next), mode)[origin];
        put(button(menu, '刷新额度'), common.q[idx], 'SWAP');
        put(button(menu, '重新连接'), common.reconnect[idx], 'SWAP');
        put(button(menu, '断开连接'), confirm, 'SWAP');
        put(button(confirm, '断开连接'), target);
        close(button(menu, '取消')); close(button(confirm, '取消'));
        const item = origin === 'd' ? findCard(views[origin], idx) : findRow(views[origin], idx);
        put(permissionRequired(one(item, 'Action/more'), 'specific source menu ' + idx), menu, 'OVERLAY');
        if (!R4_PERMISSION_READY_MASKS.includes(next)) boundaries.push({ mode, origin, removedIdx: idx, nextMask: next, destination: target.id });
      }
    }
  }
  await flush();
  e.branch.setPluginData(tag, R4_PERMISSION_VERSION); figma.commitUndo();
  return { mask, accountCount: model.accounts.length, addedMenuAndConfirmFrames: model.accounts.length * 12, boundaryDestinations: boundaries };
}

// Stage A: 20 ready models only. Existing on/off/denied system views receive
// local menus; their initial/canonical siblings and shared menus stay untouched.
async function permissionPreserveReadyStage(t, start = 0, count = 1) {
  const end = permissionBatch(start, count, R4_PERMISSION_READY_MASKS.length), e = await env(t), common = await flowCommon(e), results = [];
  for (let i = start; i < end; i++) {
    figma.ui.postMessage({ status: t + ' 保留通知状态 · ready ' + (i + 1) + '/20', progress: true });
    results.push(await permissionReadyModel(e, R4_PERMISSION_READY_MASKS[i], common));
    await new Promise(resolve => setTimeout(resolve, 0));
  }
  return { status: t + ' 定域 ready 通知状态保持完成', start, end, total: 20, models: results, boundaries: permissionPreservePlan().boundaries };
}

async function permissionPendingQuery(e, model, mode, origin, scope) {
  const key = 'PermissionKeep/' + permissionScope(model) + '/' + mode + '/Query-' + origin + '-' + scope;
  const tag = 'r4_permission_query_' + model.mask + '_' + model.pendingIdx + '_' + mode + '_' + origin + '_' + scope;
  const stored = await flowStoredNode(e, tag); if (stored) return stored;
  const who = scope === 'all' ? '全部已绑定账号' : R4A[model.pendingIdx].email;
  const target = permissionViews(e, permissionModelRefs(e, model.mask), mode)[origin];
  const loading = panel(e, key + '/Loading', '正在查询额度', [who], ['取消']);
  progress(e, loading, 1); close(button(loading, '取消'));
  put(loading, target, 'NAVIGATE', { timeout: 1 });
  const gate = await network(e, key, loading, who + (scope === 'all' ? ' 的额度查询' : ' 的首次额度查询'));
  flowSaveTag(e, tag, gate.start.id); return gate.start;
}

async function permissionPendingModel(e, route, common) {
  const model = permissionModelRefs(e, route.next, route.idx), tag = 'r4_permission_pending_' + route.next + '_' + route.idx;
  if (e.branch.getPluginData(tag) === R4_PERMISSION_VERSION) return model;
  const scope = permissionFlowScope(model), key = 'PermissionKeep/' + permissionScope(model);
  if (!e.branch.getPluginData('r4_wired_' + route.next + '_' + route.idx)) throw Error('Representative pending flow not complete');
  for (const mode of R4_PERMISSION_MODES) { permissionViews(e, model, mode); permissionViews(e, permissionModelRefs(e, route.next), mode); }
  for (const mode of R4_PERMISSION_MODES) {
    const views = permissionViews(e, model, mode); permissionPreserveDetails(e, model, views, common);
    for (const origin of ['d', 's']) {
      const allQuery = await permissionPendingQuery(e, model, mode, origin, 'all');
      const firstQuery = await permissionPendingQuery(e, model, mode, origin, 'pending');
      const refresh = one(views[origin], 'Action/refresh'); if (refresh) put(refresh, allQuery, 'OVERLAY');
      const sourceMenu = permissionNode(e, scope + '/' + origin + '/Menu-' + route.idx);
      const menu = await permissionCopyRoot(e, sourceMenu, key + '/' + mode + '/' + origin + '/Menu-' + route.idx);
      const sourceLogin = permissionNode(e, scope + '/' + origin + '/Reconnect-' + route.idx);
      const login = await permissionCopyRoot(e, sourceLogin, key + '/' + mode + '/' + origin + '/Reconnect-' + route.idx);
      put(button(menu, '刷新额度'), firstQuery, 'SWAP');
      put(button(menu, '重新连接'), login, 'SWAP'); put(button(login, '继续'), firstQuery, 'SWAP');
      close(button(menu, '取消')); close(button(login, '取消'));
      const item = origin === 'd' ? findCard(views[origin], route.idx) : findRow(views[origin], route.idx);
      put(permissionRequired(one(item, 'Action/more'), 'pending account menu'), menu, 'OVERLAY');
      // The inherited Disconnect action deliberately remains a declared
      // boundary. No further pending deletion permutations are generated.
    }
  }
  await flowFlush(e); e.branch.setPluginData(tag, R4_PERMISSION_VERSION); figma.commitUndo(); return model;
}

async function permissionChooser(e, source, mode) {
  const key = 'PermissionKeep/Set-' + source + '/' + mode + '/Connect';
  const chooser = root(e, permissionRequired(permissionNode(e, 'AccountFlow/Set-' + source + '/Connect'), 'source chooser'), key);
  // Preserve other representative provider routes when another B batch reuses
  // this chooser. Only its first creation copies the original provider edges.
  const tag = 'r4_permission_chooser_' + source + '_' + mode;
  if (flowTag(e, tag) !== chooser.id) {
    await copyFlowTree(permissionNode(e, 'AccountFlow/Set-' + source + '/Connect'), chooser);
    flowSaveTag(e, tag, chooser.id);
  }
  return chooser;
}

async function permissionAddRoute(e, route, common) {
  const tag = 'r4_permission_add_' + route.source + '_' + route.idx;
  if (e.branch.getPluginData(tag) === R4_PERMISSION_VERSION) return { ...route, skipped: true };
  if (e.branch.getPluginData('r4_permission_ready_' + route.source) !== R4_PERMISSION_VERSION || e.branch.getPluginData('r4_permission_ready_' + route.next) !== R4_PERMISSION_VERSION) throw Error('Complete stage A for source and destination before this addition');
  const pending = await permissionPendingModel(e, route, common), source = permissionModelRefs(e, route.source), a = R4A[route.idx], results = [];
  for (const mode of R4_PERMISSION_MODES) {
    const key = 'PermissionKeep/Add-' + route.source + '-' + route.idx + '/' + mode;
    const sourceViews = permissionViews(e, source, mode), pendingViews = permissionViews(e, pending, mode);
    const first = await permissionPendingQuery(e, pending, mode, 'd', 'pending');
    const bound = await permissionCopyRoot(e, pendingViews.d, key + '/Bound');
    put(bound, first, 'OVERLAY', { timeout: .15 });
    const auth = panel(e, key + '/Authorization', '正在连接 ' + a.p, ['平台授权 · 交互示意'], ['取消']);
    progress(e, auth, 1); close(button(auth, '取消')); put(auth, bound, 'NAVIGATE', { timeout: 1 });
    const login = root(e, e.logins[a.p], key + '/Login'); fixLogin(e, login, a.email); put(button(login, '继续'), auth, 'SWAP');
    const gate = await network(e, key + '/BeforeAdd', login, '添加 ' + a.p + ' 账号');
    flowSaveTag(e, 'r4_permission_add_gate_' + route.source + '_' + route.idx + '_' + mode, gate.start.id);
    const chooser = await permissionChooser(e, route.source, mode);
    put(permissionRequired(one(chooser, 'Connect/' + a.p), 'provider choice'), gate.start, 'SWAP');
    for (const origin of ['d', 's']) put(permissionRequired(permissionAddControl(sourceViews[origin]), 'mode-preserving add entry'), chooser, 'OVERLAY');
    results.push({ mode, chooser: chooser.id, check: gate.start.id, login: login.id, authorization: auth.id, bound: bound.id,
      firstQuery: first.id, success: permissionViews(e, permissionModelRefs(e, route.next), mode).d.id });
  }
  await flowFlush(e); e.branch.setPluginData(tag, R4_PERMISSION_VERSION); figma.commitUndo();
  return { ...route, modes: results };
}

// Stage B: 0=15→31, 1=15→47, 2=15→79, 3=31→95. Each batch first
// prepares that route's pending cancellation/retry states, then exposes entry.
async function permissionPreserveAddStage(t, start = 0, count = 1) {
  const end = permissionBatch(start, count, 4), e = await env(t), common = await flowCommon(e), results = [];
  for (let i = start; i < end; i++) {
    figma.ui.postMessage({ status: t + ' 保留通知状态 · 连续添加 ' + (i + 1) + '/4', progress: true });
    results.push(await permissionAddRoute(e, R4_PERMISSION_ADD_ROUTES[i], common));
    await new Promise(resolve => setTimeout(resolve, 0));
  }
  return { status: t + ' 定域新增通知状态保持完成', start, end, total: 4, routes: results, boundaries: permissionPreservePlan().boundaries };
}

// Read-only native-edge audit. It reports boundaries explicitly and does not
// treat structural checks as an actual click test.
async function permissionPreserveAuditStage(t) {
  const e = await env(t), common = { q: {}, reconnect: {}, detail: {} }, stored = e.branch.getPluginData('r4_flow_common');
  if (!stored) throw Error('Audit requires the existing shared flow index; it will not create one');
  const shared = JSON.parse(stored);
  for (const group of Object.keys(common)) for (const [key, id] of Object.entries(shared[group] || {})) common[group][key] = permissionRequired(await figma.getNodeByIdAsync(id), 'existing shared ' + group + '/' + key);
  const errors = [], boundaries = [], expect = (ok, reason) => { if (!ok) errors.push(reason); };
  for (const mask of R4_PERMISSION_READY_MASKS) {
    const model = permissionModelRefs(e, mask);
    expect(e.branch.getPluginData('r4_permission_ready_' + mask) === R4_PERMISSION_VERSION, 'Ready stage complete ' + mask);
    for (const mode of R4_PERMISSION_MODES) {
      let views; try { views = permissionViews(e, model, mode); } catch (error) { errors.push(error.message); continue; }
      for (const origin of ['d', 's']) for (const idx of model.accounts) {
        const item = origin === 'd' ? findCard(views[origin], idx) : findRow(views[origin], idx);
        const detailTrigger = one(item, origin === 'd' ? 'Expand account' : 'Account identity');
        if (detailTrigger) expect(permissionEdge(detailTrigger, common.detail[idx], 'OVERLAY'), 'Cached detail preserves mode ' + [mask, mode, origin, idx].join('/'));
        const key = 'PermissionKeep/Set-' + mask + '/' + mode + '/' + origin;
        const menu = permissionNode(e, key + '/Menu-' + idx), confirm = permissionNode(e, key + '/Disconnect-' + idx);
        const next = mask & ~R4A[idx].bit;
        expect(permissionEdge(one(item, 'Action/more'), menu, 'OVERLAY'), 'Scoped menu ' + key + '/' + idx);
        expect(permissionEdge(menu && button(menu, '刷新额度'), common.q[idx], 'SWAP'), 'Query preserves source ' + key + '/' + idx);
        expect(permissionEdge(menu && button(menu, '重新连接'), common.reconnect[idx], 'SWAP'), 'Reconnect preserves source ' + key + '/' + idx);
        expect(permissionEdge(menu && button(menu, '断开连接'), confirm, 'SWAP'), 'Disconnect opens scoped confirmation ' + key + '/' + idx);
        try { expect(permissionEdge(confirm && button(confirm, '断开连接'), permissionViews(e, permissionModelRefs(e, next), mode)[origin], 'NAVIGATE'), 'Disconnect retains mode ' + key + '/' + idx); } catch (error) { errors.push(error.message); }
        expect(permissionClosed(menu && button(menu, '取消')) && permissionClosed(confirm && button(confirm, '取消')), 'Cancel retains source ' + key + '/' + idx);
        if (!R4_PERMISSION_READY_MASKS.includes(next)) boundaries.push({ mask, mode, origin, removedIdx: idx, nextMask: next });
      }
    }
  }
  for (const route of R4_PERMISSION_ADD_ROUTES) {
    expect(e.branch.getPluginData('r4_permission_add_' + route.source + '_' + route.idx) === R4_PERMISSION_VERSION, 'Addition stage complete ' + route.source + '/' + route.idx);
    const model = permissionModelRefs(e, route.next, route.idx);
    for (const mode of R4_PERMISSION_MODES) {
      const key = 'PermissionKeep/Add-' + route.source + '-' + route.idx + '/' + mode;
      const login = permissionNode(e, key + '/Login'), auth = permissionNode(e, key + '/Authorization'), bound = permissionNode(e, key + '/Bound');
      const gateId = e.branch.getPluginData('r4_permission_add_gate_' + route.source + '_' + route.idx + '_' + mode);
      const gate = gateId && await figma.getNodeByIdAsync(gateId);
      const chooser = permissionNode(e, 'PermissionKeep/Set-' + route.source + '/' + mode + '/Connect');
      expect(permissionEdge(chooser && one(chooser, 'Connect/' + R4A[route.idx].p), gate, 'SWAP'), 'Addition choice begins with network check ' + key);
      try { const sources = permissionViews(e, permissionModelRefs(e, route.source), mode);
        for (const origin of ['d', 's']) expect(permissionEdge(permissionAddControl(sources[origin]), chooser, 'OVERLAY'), 'Mode-specific add chooser ' + key + '/' + origin);
      } catch (error) { errors.push(error.message); }
      expect(permissionClosed(login && button(login, '取消')) && permissionClosed(auth && button(auth, '取消')), 'Add cancellation preserves source ' + key);
      expect(permissionEdge(login && button(login, '继续'), auth, 'SWAP') && permissionEdge(auth, bound, 'NAVIGATE'), 'Authorization order ' + key);
      const card = bound && findCard(bound, route.idx);
      expect(!!card && txt(card).filter(n => n.name.startsWith('Value/')).every(n => n.characters === '—'), 'Bound has no fabricated quota ' + key);
      for (const origin of ['d', 's']) for (const scope of ['all', 'pending']) {
        const qkey = 'PermissionKeep/' + permissionScope(model) + '/' + mode + '/Query-' + origin + '-' + scope;
        const loading = permissionNode(e, qkey + '/Loading');
        const queryId = e.branch.getPluginData('r4_permission_query_' + route.next + '_' + route.idx + '_' + mode + '_' + origin + '_' + scope);
        const query = queryId && await figma.getNodeByIdAsync(queryId);
        expect(permissionClosed(loading && button(loading, '取消')), 'First-query cancellation ' + qkey);
        expect(!!query && !query.removed, 'Retry has its own network-check start ' + qkey);
        if (origin === 'd' && scope === 'pending') expect(permissionEdge(bound, query, 'OVERLAY'), 'Bound checks before first quota query ' + key);
        try { expect(permissionEdge(loading, permissionViews(e, permissionModelRefs(e, route.next), mode)[origin], 'NAVIGATE'), 'Query completion retains mode and ready data ' + qkey); } catch (error) { errors.push(error.message); }
      }
    }
  }
  return { status: t + ' 通知状态定域静态审查', passed: errors.length === 0, errors, readyModelCount: 20, additionRouteCount: 4,
    modeBoundaryDestinations: boundaries, declaredBoundaries: permissionPreservePlan().boundaries,
    actualClickRequired: ['on/off/denied: Set15 work disconnect → Set11 same mode', 'Known account details/query/reconnect → close returns same mode', 'Set15 three additions and Set31 Cursor: before-add/auth cancel preserves source and account count', 'First-query cancel retains bound unknown account and mode; retry checks before correct ready mode', 'Denied target toggle opens system settings; off target toggle enables without re-requesting permission'] };
}
