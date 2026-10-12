// Local extension: Set-31 (Claude F already added) -> add Cursor G -> Set-95.
// Append after foundation, flows, account widgets/system, and integrate.
// No stage runs on load. Original 64 mask positions are never reordered.
const R4_CROSS_MASKS = Array.from({ length: 16 }, (_, base) => 80 + base);
const R4_CROSS_VERSION = '1';

function crossAddMasks() {
  const original = [0, 16, 32, 64].flatMap(extra => Array.from({ length: 16 }, (_, base) => extra + base));
  if (original.some((mask, i) => R4_ACCOUNT_MASKS[i] !== mask)) throw Error('Original account mask order changed');
  for (const mask of R4_CROSS_MASKS) if (!R4_ACCOUNT_MASKS.includes(mask)) R4_ACCOUNT_MASKS.push(mask);
  return R4_CROSS_MASKS;
}
function crossAddBatch(start, count, length) {
  if (!Number.isInteger(start) || start < 0 || start >= length || !Number.isInteger(count) || count < 1 || count > 4) throw Error('Cross-add batches require a valid start and count 1–4');
  return Math.min(start + count, length);
}
function crossAddPendingList(e, onlyUnwired = false) {
  const prefix = new RegExp('^R4/' + e.t + '/AccountFlow/Pending-(\\d+)-(\\d+)/Dashboard$');
  const found = new Map();
  for (const node of e.registry.values()) {
    const match = node.name.match(prefix);
    if (!match || !R4_CROSS_MASKS.includes(+match[1])) continue;
    const mask = +match[1], idx = +match[2];
    if (onlyUnwired && flowTag(e, 'r4_wired_' + mask + '_' + idx)) continue;
    found.set(mask + '/' + idx, { mask, idx });
  }
  return [...found.values()].sort((a, b) => a.mask - b.mask || a.idx - b.idx);
}
function crossAddExpectedPending() {
  // G is the newly added extra. Restoring a removed original account must also
  // remain actionable in the paired sets; these add 32 pending base-account
  // models. F never becomes pending in this one-direction example.
  return R4_CROSS_MASKS.flatMap(mask => [0, 1, 2, 3, 6].filter(idx => mask & R4A[idx].bit).map(idx => ({ mask, idx })));
}
function crossAddNode(e, key) { return e.registry.get('R4/' + e.t + '/' + key); }
function crossAddRequired(node, description) { if (!node || node.removed) throw Error('Cross-add missing ' + description); return node; }
function crossAddActions(node) {
  if (!node) return [];
  return (jobs.has(node) ? jobs.get(node) : node.reactions || []).flatMap(r => r.actions || (r.action ? [r.action] : []));
}
function crossAddEdge(node, target, navigation) {
  return !!node && !!target && crossAddActions(node).some(a => a.type === 'NODE' && a.destinationId === target.id && (!navigation || a.navigation === navigation));
}
function crossAddSnapshot(model) {
  return JSON.stringify({ mask: model.mask, accounts: model.accounts,
    dashboard: txt(model.d).map(n => [n.name, n.characters]),
    settings: txt(model.s).map(n => [n.name, n.characters]) });
}

// Prepare the gated addition and its pending launch without exposing an
// unfinished destination from any product control. Run before the ready batches.
async function accountCrossAddPrepareStage(t) {
  crossAddMasks();
  const e = await env(t), source = await getAccountModel(e, 31);
  if (!flowTag(e, 'r4_wired_31_ready')) throw Error('Wire original Set-31 before cross-add preparation');
  const chooser = crossAddRequired(crossAddNode(e, 'AccountFlow/Set-31/Connect'), 'Set-31 chooser');
  crossAddRequired(one(chooser, 'Connect/Cursor'), 'Set-31 Cursor choice');
  const key = 'r4_cross_add_source_snapshot';
  if (!e.branch.getPluginData(key)) e.branch.setPluginData(key, crossAddSnapshot(source));
  const c = await flowCommon(e), gate = await addition(e, source, 'Cursor', c);
  if (gate === c.addFail.Cursor) throw Error('Cross-add still resolves to the simulated authorization failure');
  await flowFlush(e);
  return { status: t + ' 连续添加路径已准备，尚未替换产品入口', source: source.d.id, sourceMask: 31, targetMask: 95,
    account: R4A[6].email, check: gate.id, readyMasks: R4_CROSS_MASKS, expectedNewPendingModels: 48,
    pendingRemaining: crossAddPendingList(e, true).length };
}

async function accountCrossAddReadyStage(t, start = 0, count = 1) {
  crossAddMasks();
  const end = crossAddBatch(start, count, 16), e = await env(t), c = await flowCommon(e), results = [];
  if (!flowTag(e, 'add_31_6')) throw Error('Prepare the cross-add path before wiring its closure');
  for (let i = start; i < end; i++) {
    const mask = R4_CROSS_MASKS[i], model = await getAccountModel(e, mask);
    figma.ui.postMessage({ status: t + ' 连续添加账号集合 ' + (i + 1) + '/16', progress: true });
    // Existing ready source sets are untouched. Missing original accounts in
    // this family may be added back through their own network-gated flows.
    await wireAccountModel(e, model, c, true);
    await flowFlush(e);
    results.push({ mask, dashboard: model.d.id, settings: model.s.id });
    await new Promise(resolve => setTimeout(resolve, 0));
  }
  return { status: t + ' 连续添加 ready 闭包批次完成', start, end, total: 16, models: results, pendingRemaining: crossAddPendingList(e, true).length };
}

// Drain only the new 80..95 family. It never takes work from the original
// 176 pending models, so this can coexist with their separately queued batches.
async function accountCrossAddPendingStage(t, count = 1) {
  crossAddMasks();
  if (!Number.isInteger(count) || count < 1 || count > 4) throw Error('Cross-add pending count must be 1–4');
  const e = await env(t), c = await flowCommon(e), results = [];
  if (R4_CROSS_MASKS.some(mask => !flowTag(e, 'r4_wired_' + mask + '_ready'))) throw Error('Finish all 16 cross-add ready models before draining pending models');
  for (let i = 0; i < count; i++) {
    const next = crossAddPendingList(e, true)[0];
    if (!next) break;
    const model = await pendingModel(e, next.mask, next.idx);
    figma.ui.postMessage({ status: t + ' 连续添加待获取额度 ' + next.mask + ' / ' + next.idx, progress: true });
    await wireAccountModel(e, model, c, false);
    await flowFlush(e);
    results.push({ mask: next.mask, pendingIdx: next.idx, dashboard: model.d.id, settings: model.s.id });
    await new Promise(resolve => setTimeout(resolve, 0));
  }
  return { status: t + ' 连续添加 pending 闭包批次完成', models: results,
    totalDiscovered: crossAddPendingList(e).length, expectedTotal: 48, remaining: crossAddPendingList(e, true).length };
}

async function accountCrossAddExtrasStage(t, start = 0, count = 1, pending = false) {
  crossAddMasks();
  const e = await env(t), list = pending ? crossAddPendingList(e) : R4_CROSS_MASKS.map(mask => ({ mask }));
  if (pending && (list.length !== 48 || crossAddPendingList(e, true).length)) throw Error('Finish the 48 local pending models before their widget/system extras');
  const end = crossAddBatch(start, count, list.length), results = [];
  for (let i = start; i < end; i++) {
    const item = list[i], state = pending ? item.idx : 'ready';
    if (!flowTag(e, 'r4_wired_' + item.mask + '_' + state)) throw Error('Unwired cross-add model ' + item.mask + '/' + state);
    const model = pending ? await pendingModel(e, item.mask, item.idx) : await getAccountModel(e, item.mask);
    figma.ui.postMessage({ status: t + ' 连续添加小组件与返回 ' + (i + 1) + '/' + list.length, progress: true });
    const result = await accountExtraModel(e, model);
    results.push(result || { mask: item.mask, pendingIdx: pending ? item.idx : undefined, skipped: true });
    await new Promise(resolve => setTimeout(resolve, 0));
  }
  return { status: t + ' 连续添加 extras 批次完成', start, end, total: list.length, pending, models: results };
}

// Static audit only; no missing frame is materialized here. Dynamic prototype
// clicks (especially overlay Cancel) remain a separate acceptance requirement.
async function accountCrossAddAuditStage(t) {
  const e = await env(t), errors = [], models = [];
  const expect = (ok, description) => { if (!ok) errors.push(description); };
  const checkModel = (mask, pendingIdx) => {
    const isPending = pendingIdx !== undefined, state = isPending ? pendingIdx : 'ready';
    const key = isPending ? pendingKey(mask, pendingIdx) : accountModelKey(mask, '').replace(/\/$/, '');
    const d = crossAddNode(e, key + '/Dashboard'), s = crossAddNode(e, key + '/Settings');
    expect(!!d && !!s, key + ' dashboard/settings exist');
    expect(!!flowTag(e, 'r4_wired_' + mask + '_' + state), key + ' reactions flushed');
    expect(!!e.branch.getPluginData('r4_extra_' + mask + '_' + state), key + ' widget/system extras complete');
    if (!d || !s) return;
    const accounts = R4_ACCOUNT_ORDER.filter(idx => mask & R4A[idx].bit);
    for (const idx of accounts) {
      const a = R4A[idx], card = findCard(d, idx), row = findRow(s, idx);
      expect(!!card && card.visible !== false && !!row && row.visible !== false, key + ' visible account ' + a.email);
      if (card) {
        expect(txt(card).some(n => n.characters === a.email), key + ' exact identity ' + idx);
        const values = txt(card).filter(n => n.name.startsWith('Value/')).map(n => n.characters);
        expect(JSON.stringify(values) === JSON.stringify(isPending && pendingIdx === idx ? a.v.map(() => '—') : a.v.map(v => v + '%')), key + ' correct quota ' + idx);
        if (isPending && pendingIdx === idx) expect(card.findAll(n => n.name.startsWith('Bar/') && n.visible !== false).length === 0, key + ' pending has no quota bar');
      }
      for (const [origin, view] of [['d', d], ['s', s]]) {
        const scope = isPending ? key : 'AccountFlow/Set-' + mask;
        const menu = crossAddNode(e, scope + '/' + origin + '/Menu-' + idx);
        const confirm = crossAddNode(e, scope + '/' + origin + '/Disconnect-' + idx);
        const more = one(origin === 'd' ? findCard(view, idx) : findRow(view, idx), 'Action/more');
        expect(crossAddEdge(more, menu, 'OVERLAY'), key + ' precise menu ' + origin + '/' + idx);
        expect(crossAddEdge(menu && button(menu, '断开连接'), confirm, 'SWAP'), key + ' disconnect overlay ' + origin + '/' + idx);
        const next = mask & ~a.bit;
        const nextKey = isPending && pendingIdx !== idx ? pendingKey(next, pendingIdx) : accountModelKey(next, '').replace(/\/$/, '');
        const destination = crossAddNode(e, nextKey + (origin === 's' ? '/Settings' : '/Dashboard'));
        expect(crossAddEdge(confirm && button(confirm, '断开连接'), destination, 'NAVIGATE'), key + ' disconnect preserves source/data ' + origin + '/' + idx);
        expect(!!confirm && crossAddActions(button(confirm, '取消')).some(action => action.type === 'CLOSE'), key + ' disconnect cancel closes ' + origin + '/' + idx);
      }
    }
    expect(crossAddEdge(one(d, 'Tab/设置'), s, 'NAVIGATE'), key + ' settings tab');
    expect(crossAddEdge(one(s, 'Tab/额度'), d, 'NAVIGATE'), key + ' quota tab');
    models.push({ mask, pendingIdx, accounts, dashboard: d.id, settings: s.id });
  };
  R4_CROSS_MASKS.forEach(mask => checkModel(mask));
  const pending = crossAddExpectedPending();
  pending.forEach(item => checkModel(item.mask, item.idx));
  const sourceD = crossAddNode(e, 'Accounts/Set-31/Dashboard'), sourceS = crossAddNode(e, 'Accounts/Set-31/Settings');
  if (sourceD && sourceS) expect(e.branch.getPluginData('r4_cross_add_source_snapshot') === crossAddSnapshot({ mask: 31, accounts: R4_ACCOUNT_ORDER.filter(idx => 31 & R4A[idx].bit), d: sourceD, s: sourceS }), 'Original Set-31 identity/quota/settings text unchanged');
  else errors.push('Original Set-31 source missing');
  const gateId = flowTag(e, 'add_31_6'), gate = gateId && await figma.getNodeByIdAsync(gateId);
  const chooser = crossAddNode(e, 'AccountFlow/Set-31/Connect');
  const active = !!gate && crossAddEdge(chooser && one(chooser, 'Connect/Cursor'), gate, 'SWAP');
  const login = crossAddNode(e, 'AccountFlow/Add-31-6/Login');
  const authorization = crossAddNode(e, 'AccountFlow/Add-31-6/Authorization');
  const bound = crossAddNode(e, 'AccountFlow/Add-31-6/Bound');
  const firstId = flowTag(e, 'pending_q_95_6_d_pending');
  const first = firstId && await figma.getNodeByIdAsync(firstId);
  const loading = crossAddNode(e, pendingKey(95, 6) + '/FirstQuery-d-pending/Loading');
  expect(!!gate && !gate.removed, 'Representative add begins at a real network-check frame');
  expect(crossAddEdge(login && button(login, '继续'), authorization, 'SWAP'), 'Representative login continues to authorization');
  for (const [name, frame] of [['login', login], ['authorization', authorization]]) expect(!!frame && crossAddActions(button(frame, '取消')).some(a => a.type === 'CLOSE'), 'Representative ' + name + ' Cancel preserves overlay source');
  expect(crossAddEdge(authorization, bound, 'NAVIGATE'), 'Successful authorization creates the bound pending source');
  expect(crossAddEdge(bound, first, 'OVERLAY'), 'Bound source begins a separate first-query check');
  expect(crossAddEdge(loading, crossAddNode(e, 'Accounts/Set-95/Dashboard'), 'NAVIGATE'), 'First-query completion opens ready Set-95');
  const boundCard = bound && findCard(bound, 6);
  expect(!!boundCard && txt(boundCard).filter(n => n.name.startsWith('Value/')).every(n => n.characters === '—'), 'Launch copy has no fabricated Cursor quota');
  expect(crossAddEdge(bound && nativeHomeBar(bound), crossAddNode(e, 'AccountWidgets/Set-95/Pending-6'), 'NAVIGATE'), 'First-query Cancel retains a working pending widget return');
  return { status: t + ' 连续添加静态审查', passed: errors.length === 0, activated: active, errors,
    sourceMask: 31, targetMask: 95, readyModels: 16, expectedPendingModels: 48, pendingDiscovered: crossAddPendingList(e).length,
    pendingRemaining: crossAddPendingList(e, true).length, models,
    unverified: ['Actual click: both pre-add/authorization Cancel return to unchanged Set-31', 'Actual click: cancel first quota query leaves G bound with no quota', 'Actual click: query retry checks again before Set-95', 'Actual click: disconnect G returns Set-31; disconnect F returns Set-79; deleting originals preserves both extras', 'Actual click: widget Cursor fallback to G uses G identity, quota or pending state, and click target'] };
}

// The only rewired existing product node is Set-31's Cursor provider choice.
// Run last, after the local audit is complete; all its callers share this chooser.
async function accountCrossAddActivateStage(t) {
  crossAddMasks();
  const audit = await accountCrossAddAuditStage(t);
  if (!audit.passed) throw Error('Cross-add not activated: ' + audit.errors.slice(0, 8).join('; '));
  const e = await env(t), chooser = crossAddRequired(crossAddNode(e, 'AccountFlow/Set-31/Connect'), 'source chooser');
  const gate = crossAddRequired(await flowStoredNode(e, 'add_31_6'), 'gated addition');
  const entry = crossAddRequired(one(chooser, 'Connect/Cursor'), 'Cursor choice');
  put(entry, gate, 'SWAP');
  await flowFlush(e);
  const result = { version: R4_CROSS_VERSION, sourceMask: 31, targetMask: 95, provider: 'Cursor', account: R4A[6].email,
    source: entry.id, check: gate.id, readyModels: 16, pendingModels: 48, originalModelBatchesRerun: 0 };
  e.branch.setPluginData('r4_cross_add_active', JSON.stringify(result));
  figma.commitUndo();
  return { status: t + ' Claude 后继续添加 Cursor 的代表性路径已接入', ...result };
}
