// View-only foundation. Append after r4-live-core.js; no flows are generated.
// Index: 0=A, 1=B, 2=C, 3=D, 4=F, 5=E, 6=G. At most one extra exists.
const R4A = [
  { idx: 0, bit: 1, id: 'A', p: 'Claude', email: 'alin.claude@example.com', baseIx: 0, k: 'Claude', v: [39, 72], reset: ['4 天后 09:00', '3 小时后'], plan: 'Pro' },
  { idx: 1, bit: 2, id: 'B', p: 'Codex', email: 'alin.codex@example.com', baseIx: 1, k: 'Codex', v: [38, 64], reset: ['3 天后 09:00', '3 小时 34 分后'], plan: 'Plus' },
  { idx: 2, bit: 4, id: 'C', p: 'Codex', email: 'work.codex@example.com', baseIx: 2, k: 'Codex · work', v: [70, 85], reset: ['5 天后 09:00', '4 小时后'], plan: 'Plus' },
  { idx: 3, bit: 8, id: 'D', p: 'Cursor', email: 'alin.cursor@example.com', baseIx: 3, k: 'Cursor', v: [62], reset: ['12 天后'], plan: 'Pro', money: '剩余 $12.40 / $20.00' },
  { idx: 4, bit: 16, id: 'F', p: 'Claude', email: 'new.claude@example.com', baseIx: 0, k: 'Claude · new', v: [61, 47], reset: ['2 天后 09:00', '2 小时后'], plan: 'Pro' },
  { idx: 5, bit: 32, id: 'E', p: 'Codex', email: 'new.codex@example.com', baseIx: 1, k: 'Codex · new', v: [54, 91], reset: ['6 天后 09:00', '4 小时 30 分后'], plan: 'Plus' },
  { idx: 6, bit: 64, id: 'G', p: 'Cursor', email: 'new.cursor@example.com', baseIx: 3, k: 'Cursor · new', v: [28], reset: ['8 天后'], plan: 'Pro', money: '剩余 $5.60 / $20.00' }
];
const R4_ACCOUNT_ORDER = [0, 4, 1, 2, 5, 3, 6];
const R4_ACCOUNT_MASKS = [0, 16, 32, 64].flatMap(extra => Array.from({ length: 16 }, (_, base) => extra + base));
const R4_ACCOUNT_MODELS = new Map();
const R4_ACCOUNT_VIEW_VERSION = '1';
const R4_ACCOUNT_VIEW_TAG = 'r4_account_foundation_view';

function findCard(f, idx) {
  if (!R4A[idx]) throw Error('Unknown account index: ' + idx);
  return one(f, 'Quota/' + R4A[idx].k);
}

function findRow(f, idx) {
  if (!R4A[idx]) throw Error('Unknown account index: ' + idx);
  return one(f, 'Account row/' + R4A[idx].k);
}

function accountModelKey(mask, kind) { return 'Accounts/Set-' + mask + '/' + kind; }
function accountModelName(e, mask, kind) { return 'R4/' + e.t + '/' + accountModelKey(mask, kind); }
// Clones inherit plugin data, so readiness must include the current node ID.
function accountViewReady(n) { return n && n.getPluginData(R4_ACCOUNT_VIEW_TAG) === R4_ACCOUNT_VIEW_VERSION + ':' + n.id; }
function accountViewDone(n) { n.setPluginData(R4_ACCOUNT_VIEW_TAG, R4_ACCOUNT_VIEW_VERSION + ':' + n.id); }
function accountRequired(n, name) { if (!n) throw Error('Account foundation missing ' + name); return n; }
function accountVisible(n, visible) { if (n && n.visible !== visible) { n.visible = visible; writes.add(n.id); } }

function accountSetText(n, value) {
  if (n && n.characters !== value) change(n, value);
}

function accountNormalizeCard(card, idx) {
  const a = R4A[idx];
  for (const text of txt(card)) if (text.characters.includes('@')) accountSetText(text, a.email);
  accountSetText(one(card, 'Last updated'), a.email);
  accountSetText(one(card, 'Detail updated'), '套餐 ' + a.plan + ' · 上次成功更新 09:41');
  const windows = card.children.filter(n => n.name.startsWith('Window/'));
  if (windows.length !== a.v.length) throw Error('Quota window mismatch for ' + a.email);
  windows.forEach((w, i) => {
    const key = w.name.slice('Window/'.length);
    accountSetText(accountRequired(one(w, 'Value/' + key), a.email + ' value'), a.v[i] + '%');
    accountSetText(one(w, 'Reset/' + key), a.reset[i]);
    const track = accountRequired(one(w, 'Track/' + key), a.email + ' track');
    const bar = accountRequired(one(w, 'Bar/' + key), a.email + ' used bar');
    const width = track.width * (100 - a.v[i]) / 100;
    if (Math.abs(bar.width - width) > .02) { bar.resize(width, bar.height); writes.add(bar.id); }
    accountVisible(bar, true);
  });
  if (a.money) for (const text of txt(card)) if (/^剩余\s*\$/.test(text.characters)) accountSetText(text, a.money);
  accountVisible(one(card, 'Account details'), false);
}

function accountCloneExtra(e, f, idx, card) {
  const record = R4A[idx];
  const source = card ? findCard(e.dashboard, record.baseIx) : findRow(e.settings, record.baseIx);
  accountRequired(source, 'R3 template ' + record.p);
  const parent = card ? one(f, 'Content') : one(f, 'Group/账户');
  let n = clone(source, accountRequired(parent, 'account container'), (card ? 'Quota/' : 'Account row/') + record.k);
  // Only added cards are detached. Their distinct metric widths cannot change a
  // shared R3 card component or later snap back to its original account values.
  if (card && n.type === 'INSTANCE') {
    n = n.detachInstance();
    n.name = 'Quota/' + record.k;
    for (const child of all(n)) made.add(child.id);
    clear(n);
  }
  return n;
}

function accountArrangeSettings(e, f, accounts) {
  const group = accountRequired(one(f, 'Group/账户'), 'settings account group');
  const add = accountRequired(one(group, 'Row/连接账户'), 'settings add-account row');
  const dividers = group.children.filter(n => n.name === 'Inset divider');
  dividers.forEach(n => accountVisible(n, false));
  for (let idx = 0; idx < R4A.length; idx++) {
    let row = findRow(f, idx);
    if (accounts.includes(idx) && !row) row = accountCloneExtra(e, f, idx, false);
    if (row) {
      accountVisible(row, accounts.includes(idx));
      for (const text of txt(row)) if (text.characters.includes('@')) accountSetText(text, R4A[idx].email);
    }
  }
  let position = 0;
  accounts.forEach((idx, i) => {
    const row = accountRequired(findRow(f, idx), 'row ' + idx);
    group.insertChild(position++, row);
    let divider = dividers[i];
    if (!divider && dividers[0]) {
      divider = clone(dividers[0], group, 'Inset divider');
      dividers.push(divider);
    }
    if (divider) { accountVisible(divider, true); group.insertChild(position++, divider); }
  });
  accountVisible(add, true);
  group.insertChild(position, add);
  const preference = one(f, 'Row/额度显示');
  accountVisible(preference, false);
  const viewport = one(f, 'Scroll viewport');
  if (viewport) viewport.overflowDirection = 'VERTICAL';
}

function accountArrangeDashboard(e, f, accounts) {
  if (!accounts.length) return; // The dedicated R3 empty-screen template is used.
  const body = accountRequired(one(f, 'Content'), 'dashboard content');
  const oldCards = body.children.filter(n => n.name.startsWith('Quota/'));
  let position = oldCards.length ? body.children.indexOf(oldCards[0]) : 0;
  for (let idx = 0; idx < R4A.length; idx++) {
    let card = findCard(f, idx);
    if (accounts.includes(idx) && !card) card = accountCloneExtra(e, f, idx, true);
    if (card) {
      accountVisible(card, accounts.includes(idx));
      if (accounts.includes(idx)) accountNormalizeCard(card, idx);
    }
  }
  for (const idx of accounts) body.insertChild(position++, accountRequired(findCard(f, idx), 'card ' + idx));
  const viewport = one(f, 'Scroll viewport');
  if (viewport) viewport.overflowDirection = 'VERTICAL';
}

async function accountUpComponent(e) {
  if (e.accountFoundationUp) return e.accountFoundationUp;
  const arrow = one(findCard(e.dashboard, 0), 'Icon/down');
  if (!arrow || arrow.type !== 'INSTANCE') return null;
  const down = await arrow.getMainComponentAsync();
  const parent = down && down.parent;
  if (parent && parent.type === 'PAGE' && typeof parent.loadAsync === 'function') await parent.loadAsync();
  const up = parent && 'children' in parent && parent.children.find(n =>
    n.type === 'COMPONENT' && n.name === 'R2/Icon/' + e.t + '/up');
  if (up) e.accountFoundationUp = up;
  return up || null;
}

async function getAccountModel(e, mask) {
  if (!Number.isInteger(mask) || !R4_ACCOUNT_MASKS.includes(mask)) {
    throw Error('Unsupported account set ' + mask + '; use one of the 64 declared masks');
  }
  const cacheKey = e.t + '/' + mask;
  if (R4_ACCOUNT_MODELS.has(cacheKey)) return R4_ACCOUNT_MODELS.get(cacheKey);
  const accounts = R4_ACCOUNT_ORDER.filter(idx => mask & R4A[idx].bit);
  const empty = accountRequired(e.roots.find(n => n.name.includes('|Dashboard|0|') &&
    !n.name.includes('|initial|')), 'R3 empty dashboard');
  for (let i = 0; i < 4; i++) {
    accountRequired(findCard(e.dashboard, i), 'base card ' + i);
    accountRequired(findRow(e.settings, i), 'base settings row ' + i);
  }
  const d = mask === 15 ? e.dashboard : root(e, mask === 0 ? empty : e.dashboard, accountModelKey(mask, 'Dashboard'));
  const s = mask === 15 ? e.settings : root(e, e.settings, accountModelKey(mask, 'Settings'));
  // Base15 is reused without clearing or changing any existing reactions.
  if (mask !== 15 && !accountViewReady(d)) { accountArrangeDashboard(e, d, accounts); accountViewDone(d); }
  if (mask !== 15 && !accountViewReady(s)) { accountArrangeSettings(e, s, accounts); accountViewDone(s); }
  const details = {};
  const up = accounts.length ? await accountUpComponent(e) : null;
  for (const idx of accounts) {
    const expanded = root(e, d, accountModelKey(mask, 'Expanded-' + idx));
    if (!accountViewReady(expanded)) {
      for (const other of accounts) accountVisible(one(findCard(expanded, other), 'Account details'), other === idx);
      const arrow = one(findCard(expanded, idx), 'Icon/down');
      if (up && arrow && arrow.type === 'INSTANCE') arrow.swapComponent(up);
      const viewport = one(expanded, 'Scroll viewport');
      if (viewport) viewport.overflowDirection = 'VERTICAL';
      accountViewDone(expanded);
    }
    details[idx] = expanded;
  }
  const model = { mask, d, s, details, accounts };
  R4_ACCOUNT_MODELS.set(cacheKey, model);
  return model;
}

async function accountFoundationStage(t, start = 0, count = 8) {
  if (!Number.isInteger(start) || start < 0 || start >= R4_ACCOUNT_MASKS.length) throw Error('start must be a model index from 0 to 63');
  if (!Number.isInteger(count) || count < 1 || count > 8) throw Error('Generate 1–8 account models per batch');
  const e = await env(t);
  const end = Math.min(start + count, R4_ACCOUNT_MASKS.length);
  const before = e.registry.size;
  const models = [];
  for (let i = start; i < end; i++) {
    figma.ui.postMessage({ status: t + ' 账号视图 ' + (i + 1) + '/64', progress: true });
    models.push(await getAccountModel(e, R4_ACCOUNT_MASKS[i]));
    await new Promise(resolve => setTimeout(resolve, 0));
  }
  // Only inherited reactions on newly cloned views are cleared by core helpers.
  // No action destinations are authored, and Base15 actions remain untouched.
  await flush();
  const completedRoots = models.flatMap(m => [m.d, m.s, ...Object.values(m.details)]);
  const result = {
    status: t + ' 账号视图批次完成（尚未连接流程）',
    start, end, totalModels: 64,
    completedModels: models.length,
    completedRootCount: completedRoots.length,
    createdRootCount: e.registry.size - before,
    models: models.map(m => ({
      mask: m.mask, d: m.d.id, s: m.s.id, accounts: m.accounts,
      details: Object.fromEntries(Object.entries(m.details).map(([idx, n]) => [idx, n.id]))
    }))
  };
  e.branch.setPluginData('r4_account_foundation_last_batch', JSON.stringify({ start, end }));
  figma.commitUndo();
  return result;
}
