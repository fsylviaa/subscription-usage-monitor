// Finite notification/system states for already-wired account models.
// Append after core, foundation, flows, and r4-system.js. No old notification
// settings root is used as a source. Each model adds exactly nine roots.
const R4_ACCOUNT_SYSTEM_VERSION = '1';

function accountSystemRequired(node, description) {
  if (!node) throw Error('Account system missing ' + description);
  return node;
}
function accountSystemReactions(node) {
  return jobs.has(node) ? jobs.get(node) : node.reactions || [];
}
function accountSystemDestination(node) {
  if (!node) return null;
  for (const reaction of accountSystemReactions(node)) {
    for (const action of reaction.actions || (reaction.action ? [reaction.action] : [])) {
      if (action.type === 'NODE' && action.destinationId) return action.destinationId;
    }
  }
  return null;
}
function accountSystemToggleNode(frame) {
  return frame.findOne(node => node.type === 'INSTANCE' &&
    (node.name === 'System/Notification toggle' || /(?:^|,)\s*State=(?:Off|On)(?:,|$)/.test(node.name)));
}
function accountSystemScope(model) {
  return model.pendingIdx === undefined ? 'Set-' + model.mask : 'Pending-' + model.mask + '-' + model.pendingIdx;
}
function accountSystemTag(model) {
  return 'r4_account_system_' + model.mask + '_' + (model.pendingIdx === undefined ? 'ready' : model.pendingIdx);
}
function accountSystemDeniedHint(e, settings) {
  const group = accountSystemRequired(one(settings, 'Group/通用'), settings.name + ' general group');
  let box = one(group, 'Notification permission message');
  if (!box) {
    box = frame(group, 'Notification permission message', group.width);
    box.paddingLeft = box.paddingRight = 16;
    box.paddingBottom = 12;
    const hint = label(e, box, '系统通知权限未开启。点按开关可前往设置。', 12, 'Notification permission hint');
    hint.opacity = .68;
  }
  // The source general group contains a single 52 px row. Let the error text
  // participate in layout instead of obscuring the following support group.
  mark(group).primaryAxisSizingMode = 'AUTO';
}
function accountSystemHasAction(node, type, destinationId, navigation) {
  if (!node) return false;
  return accountSystemReactions(node).some(reaction => (reaction.actions || (reaction.action ? [reaction.action] : [])).some(action =>
    action.type === type && (destinationId === undefined || action.destinationId === destinationId) &&
    (navigation === undefined || action.navigation === navigation)));
}
function accountSystemValidateSupport(e) {
  // supportOnlyStage deliberately has no legacy system-stage completion tag.
  // Read the real return edges so both support entry points are supported.
  const tutorial = ['Tutorial1', 'Tutorial1b', 'Tutorial2', 'Tutorial2b'].map(key => systemKind(e, key));
  const pages = Object.fromEntries(['Help', 'Privacy', 'Licenses', 'License'].map(key => [key, systemKind(e, key)]));
  const valid = tutorial.every(item => accountSystemHasAction(one(item, 'Action/close'), 'CLOSE')) &&
    tutorial.slice(0, 2).every(item => accountSystemHasAction(button(item, '下一步'), 'NODE', tutorial[2].id, 'SWAP')) &&
    tutorial.slice(2).every(item => accountSystemHasAction(button(item, '完成'), 'CLOSE')) &&
    ['Help', 'Privacy', 'Licenses'].every(key => accountSystemHasAction(one(pages[key], 'Action/back'), 'CLOSE')) &&
    accountSystemHasAction(one(pages.Licenses, 'Row/CodexBar'), 'NODE', pages.License.id, 'SWAP') &&
    accountSystemHasAction(one(pages.License, 'Action/back'), 'NODE', pages.Licenses.id, 'SWAP');
  if (!valid) throw Error('Run supportOnlyStage or the shared tutorial/support system stage before account system models');
}

// A completion tag alone is insufficient: base R3 settings could have been
// modified by an older system stage. Validate the concrete account menu edges.
function accountSystemValidateModel(e, model) {
  const state = model.pendingIdx === undefined ? 'ready' : model.pendingIdx;
  if (!e.branch.getPluginData('r4_wired_' + model.mask + '_' + state)) {
    throw Error('Wire and flush account model ' + model.mask + ' / ' + state + ' before its system stage');
  }
  if (model.pendingIdx !== undefined && !model.accounts.includes(model.pendingIdx)) throw Error('Pending account is absent from the source model');
  for (const [kind, frame] of [['d', model.d], ['s', model.s]]) {
    accountSystemRequired(one(frame, 'Tab/额度'), frame.name + ' quota tab');
    accountSystemRequired(one(frame, 'Tab/设置'), frame.name + ' settings tab');
    for (const idx of model.accounts) {
      const item = kind === 'd' ? findCard(frame, idx) : findRow(frame, idx);
      const more = accountSystemRequired(one(item, 'Action/more'), frame.name + ' account menu ' + idx);
      const expected = e.registry.get('R4/' + e.t + '/AccountFlow/' + accountSystemScope(model) + '/' + kind + '/Menu-' + idx);
      if (!expected || accountSystemDestination(more) !== expected.id) {
        throw Error('Account system source still has a stale menu: mask ' + model.mask + ', ' + kind + ', account ' + idx);
      }
    }
  }
  accountSystemRequired(one(model.s, 'Toggle/通知'), model.s.name + ' notification toggle');
  accountSystemRequired(one(model.s, 'Group/通用'), model.s.name + ' general group');
}

async function accountSystemExisting(e, model) {
  const stored = e.branch.getPluginData(accountSystemTag(model));
  if (!stored) return null;
  try {
    const value = JSON.parse(stored);
    if (value.version !== R4_ACCOUNT_SYSTEM_VERSION || value.mask !== model.mask || value.pendingIdx !== model.pendingIdx || value.theme !== e.t) return null;
    const ids = [...Object.values(value.settings || {}), ...Object.values(value.dashboards || {}), value.permission, ...Object.values(value.system || {})];
    if (ids.length !== 9 || new Set(ids).size !== 9 || ids.some(id => typeof id !== 'string')) return null;
    const prefix = 'R4/' + e.t + '/AccountSystem/' + accountSystemScope(model) + '/';
    for (const id of ids) {
      const node = await figma.getNodeByIdAsync(id);
      if (!node || node.removed || node.type !== 'FRAME' || !node.name.startsWith(prefix)) return null;
    }
    return value;
  } catch (_) { return null; }
}

function accountSystemSupport(e, frame, kind, state, dashboards, settings, tutorial, pages) {
  put(accountSystemRequired(one(frame, 'Tab/额度'), frame.name + ' quota tab'), dashboards[state]);
  put(accountSystemRequired(one(frame, 'Tab/设置'), frame.name + ' settings tab'), settings[state]);
  for (const name of ['Action/如何添加小组件', 'Row/如何添加小组件']) {
    const entry = one(frame, name);
    if (entry) put(entry, tutorial, 'OVERLAY');
  }
  if (kind === 's') {
    for (const [label, key] of [['帮助与说明', 'Help'], ['隐私说明', 'Privacy'], ['开源许可', 'Licenses']]) {
      put(accountSystemRequired(one(frame, 'Row/' + label), frame.name + ' ' + label), pages[key], 'OVERLAY');
    }
  }
}

async function wireAccountSystem(e, model) {
  accountSystemValidateSupport(e);
  accountSystemValidateModel(e, model);
  const existing = await accountSystemExisting(e, model);
  if (existing) return { ...existing, skipped: true, createdFrameCount: 0 };

  // Validate all shared visual sources and destinations before creating roots.
  const permissionSource = systemKind(e, 'Permission');
  const systemSource = systemKind(e, 'System');
  const tutorial = systemKind(e, 'Tutorial1');
  const pages = Object.fromEntries(['Help', 'Privacy', 'Licenses'].map(key => [key, systemKind(e, key)]));
  accountSystemRequired(button(permissionSource, '允许'), 'permission Allow button');
  accountSystemRequired(button(permissionSource, '不允许'), 'permission Deny button');
  accountSystemRequired(one(permissionSource, 'Action/close'), 'permission close');
  accountSystemRequired(permissionSource.children.find(node => node.type === 'RECTANGLE'), 'permission scrim');
  accountSystemRequired(accountSystemToggleNode(systemSource), 'system notification toggle');
  accountSystemRequired(one(systemSource, 'Action/back'), 'system back');
  const variants = await systemToggleComponents(one(model.s, 'Toggle/通知'), e.t);
  const key = 'AccountSystem/' + accountSystemScope(model);
  const before = e.registry.size, settings = {}, dashboards = {};

  for (const state of ['on', 'off', 'denied']) {
    settings[state] = root(e, model.s, key + '/Settings-' + state);
    dashboards[state] = root(e, model.d, key + '/Dashboard-' + state);
    // This runs for new and incomplete roots. root() clears cloned reactions;
    // copying the completed ready model restores only current account actions.
    await copyFlowTree(model.s, settings[state]);
    await copyFlowTree(model.d, dashboards[state]);
    systemSetToggle(one(settings[state], 'Toggle/通知'), state === 'on' ? variants.on : variants.off, 'Toggle/通知');
    if (state === 'denied') accountSystemDeniedHint(e, settings[state]);
  }
  const permission = root(e, permissionSource, key + '/Permission');
  const system = {
    off: root(e, systemSource, key + '/iOS-off'),
    on: root(e, systemSource, key + '/iOS-on')
  };
  clear(permission);
  systemSheetClose(permission);
  put(button(permission, '允许'), settings.on);
  put(button(permission, '不允许'), settings.denied);

  // Initial means the permission has not been requested. Off means permission
  // was granted and the App switch was subsequently turned off.
  systemSetToggle(one(model.s, 'Toggle/通知'), variants.off, 'Toggle/通知');
  systemNotificationAction(model.s, permission, 'OVERLAY');
  systemNotificationAction(settings.on, settings.off, 'NAVIGATE');
  systemNotificationAction(settings.off, settings.on, 'NAVIGATE');
  systemNotificationAction(settings.denied, system.off, 'NAVIGATE');

  for (const state of ['off', 'on']) {
    const frame = system[state];
    clear(frame);
    const toggle = accountSystemRequired(accountSystemToggleNode(frame), frame.name + ' toggle');
    systemSetToggle(toggle, state === 'on' ? variants.on : variants.off, 'System/Notification toggle');
    put(toggle, state === 'on' ? system.off : system.on, 'NAVIGATE', { smart: true });
    put(one(frame, 'Action/back'), state === 'on' ? settings.on : settings.denied);
  }
  for (const state of ['on', 'off', 'denied']) {
    accountSystemSupport(e, settings[state], 's', state, dashboards, settings, tutorial, pages);
    accountSystemSupport(e, dashboards[state], 'd', state, dashboards, settings, tutorial, pages);
  }
  // The original ready pair remains the unasked-permission state. Use the same
  // per-model tab and overlay routes, including base mask 15.
  accountSystemSupport(e, model.s, 's', 'initial', { initial: model.d }, { initial: model.s }, tutorial, pages);
  accountSystemSupport(e, model.d, 'd', 'initial', { initial: model.d }, { initial: model.s }, tutorial, pages);

  const result = {
    version: R4_ACCOUNT_SYSTEM_VERSION, theme: e.t, mask: model.mask, pendingIdx: model.pendingIdx,
    settings: Object.fromEntries(Object.entries(settings).map(([state, node]) => [state, node.id])),
    dashboards: Object.fromEntries(Object.entries(dashboards).map(([state, node]) => [state, node.id])),
    permission: permission.id,
    system: Object.fromEntries(Object.entries(system).map(([state, node]) => [state, node.id]))
  };
  await flush();
  // Persist only after all native reactions have successfully committed.
  e.branch.setPluginData(accountSystemTag(model), JSON.stringify(result));
  figma.commitUndo();
  return { ...result, skipped: false, createdFrameCount: e.registry.size - before };
}

async function accountSystemStage(t, start = 0, count = 4) {
  if (!Number.isInteger(start) || start < 0 || start >= 64 || !Number.isInteger(count) || count < 1 || count > 4) {
    throw Error('Account system batches require model index 0–63 and count 1–4');
  }
  const e = await env(t), results = [];
  // supportOnlyStage/systemStage supplies caller-preserving support overlays.
  // Old notification settings roots are never read or copied by this module.
  accountSystemValidateSupport(e);
  for (let index = start; index < Math.min(start + count, 64); index++) {
    const mask = R4_ACCOUNT_MASKS[index];
    if (!e.branch.getPluginData('r4_wired_' + mask + '_ready')) {
      throw Error('Ready account model ' + mask + ' is not yet wired and flushed');
    }
    const model = await getAccountModel(e, mask);
    figma.ui.postMessage({ status: t + ' 通知与系统返回 ' + (index + 1) + '/64', progress: true });
    results.push(await wireAccountSystem(e, model));
    await new Promise(resolve => setTimeout(resolve, 0));
  }
  return {
    status: t + ' 当前账号集合的通知与系统路径批次完成', start, end: Math.min(start + count, 64),
    createdFrameCount: results.reduce((sum, result) => sum + result.createdFrameCount, 0), models: results,
    scope: 'Ready account sets only. Tabs and shared support/tutorial overlays preserve notification state. Account mutations continue through ready account paths.'
  };
}
