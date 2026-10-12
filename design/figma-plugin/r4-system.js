// Incremental system/notification authoring for the existing base R3 snapshots.
// No real permissions, account access, or changes to account-menu/refresh nodes.
// Append after r4-live-core.js. systemStage(theme) is the only stage entry point.

function systemRequired(node, description) {
  if (!node) throw Error('System stage missing ' + description);
  return node;
}

function systemKind(e, kind) {
  return systemRequired(e.roots.find(n =>
    n.name === e.t + '/' + kind || n.name.split('|')[1] === kind
  ), e.t + '/' + kind);
}

function systemSettingsState(e, state) {
  return systemRequired(e.roots.find(n => {
    const parts = n.name.split('|');
    return parts[1] === 'Settings' && parts[2] === '7' &&
      parts[3] === 'R' && parts[4] === String(state);
  }), e.t + '/Settings notification=' + state);
}

// root() deliberately clears inherited reactions. These base-dashboard/settings
// copies need their existing account actions preserved, then only system actions
// are overridden below. Copy by child position: source and fresh clone have the
// exact same tree before any component swaps or new content are introduced.
function systemCopyWithActions(e, source, key) {
  const name = 'R4/' + e.t + '/' + key;
  const existed = e.registry.has(name);
  const target = root(e, source, key);
  if (!existed) {
    const copy = (a, b) => {
      if ('reactions' in a && a.reactions.length) {
        // Keep only current API fields; older files can expose both the legacy
        // `action` and the modern `actions` fields when reactions are read.
        jobs.set(b, a.reactions.map(r => ({
          trigger: JSON.parse(JSON.stringify(r.trigger)),
          actions: JSON.parse(JSON.stringify(r.actions || (r.action ? [r.action] : [])))
        })));
      }
      if ('children' in a) {
        if (!('children' in b) || a.children.length !== b.children.length) {
          throw Error('Unexpected cloned system tree: ' + a.name);
        }
        a.children.forEach((child, i) => copy(child, b.children[i]));
      }
    };
    copy(source, target);
  }
  return target;
}

function systemSheetClose(frame) {
  close(systemRequired(one(frame, 'Action/close'), frame.name + ' close'));
  const shade = frame.children.find(n => n.type === 'RECTANGLE');
  close(systemRequired(shade, frame.name + ' scrim'));
}

function systemNotificationAction(settings, target, navigation) {
  put(systemRequired(one(settings, 'Toggle/通知'), settings.name + ' toggle'), target, navigation);
  const row = one(settings, 'Row/额度重置通知');
  if (row) put(row, target, navigation);
}

async function systemToggleComponents(instance, theme) {
  if (!instance || instance.type !== 'INSTANCE') throw Error('Notification toggle must be an instance');
  const main = await instance.getMainComponentAsync();
  if (!main) throw Error('Notification toggle has no main component');
  const siblings = main.parent && 'children' in main.parent ? main.parent.children : [main];
  const find = state => siblings.find(n => n.type === 'COMPONENT' &&
    n.name.split(',').some(p => p.trim() === 'Theme=' + theme) &&
    n.name.split(',').some(p => p.trim() === 'State=' + state));
  const on = find('On'), off = find('Off');
  if (!on || !off) throw Error('Missing native ' + theme + ' On/Off toggle components');
  return { on, off };
}

function systemSetToggle(instance, component, name) {
  systemRequired(instance, 'toggle instance').swapComponent(component);
  if (name) instance.name = name;
}

function systemSupportRoute(settings, pages) {
  for (const [label, kind] of [
    ['帮助与说明', 'Help'], ['隐私说明', 'Privacy'], ['开源许可', 'Licenses']
  ]) {
    const row = systemRequired(one(settings, 'Row/' + label), settings.name + ' ' + label);
    // Full-screen overlays keep the exact underlying settings snapshot, including
    // notification state and scrolling, without one help copy per source.
    put(row, pages[kind], 'OVERLAY');
  }
}

function systemIndexHeading(e, parent, text, size) {
  const node = figma.createText();
  parent.appendChild(node);
  made.add(node.id);
  node.name = text;
  node.fontName = { family: 'PingFang SC', style: 'Regular' };
  node.fontSize = size;
  node.lineHeight = { unit: 'PIXELS', value: Math.ceil(size * 1.45) };
  const c = e.t === 'Dark' ? .94 : .09;
  node.fills = [{ type: 'SOLID', color: { r: c, g: c, b: c } }];
  node.characters = text;
  node.textAutoResize = 'HEIGHT';
  node.resize(parent.width - (parent.paddingLeft || 0) - (parent.paddingRight || 0), node.height);
  return node;
}

async function systemStage(t) {
  const e = await env(t);
  const completionKey = 'r4_system_complete_' + t;
  if (e.branch.getPluginData(completionKey)) {
    return JSON.parse(e.branch.getPluginData(completionKey));
  }

  // Validate all existing templates and toggle variants before creating nodes.
  const initial = e.settings;
  const on = systemSettingsState(e, 1);
  const denied = systemSettingsState(e, 2);
  const permission = systemKind(e, 'Permission');
  const systemOff = systemKind(e, 'System');
  const tutorial = ['Tutorial1', 'Tutorial1b', 'Tutorial2', 'Tutorial2b'].map(k => systemKind(e, k));
  const pages = Object.fromEntries(['Help', 'Privacy', 'Licenses', 'License'].map(k => [k, systemKind(e, k)]));
  const variants = await systemToggleComponents(systemRequired(one(initial, 'Toggle/通知'), 'base toggle'), t);
  const isSystemToggle = n => n.type === 'INSTANCE' && (n.name === 'System/Notification toggle' ||
    /(?:^|,)\s*State=(?:Off|On)(?:,|$)/.test(n.name));
  const sourceSystemToggle = systemRequired(systemOff.findOne(isSystemToggle), 'iOS permission toggle');
  for (const s of [initial, on, denied]) {
    systemRequired(one(s, 'Tab/额度'), s.name + ' quota tab');
    systemRequired(one(s, 'Toggle/通知'), s.name + ' notification toggle');
  }

  // Off after permission was granted is distinct from the initial, unasked state.
  const off = systemCopyWithActions(e, initial, 'System/NotificationsOff');
  const systemOn = root(e, systemOff, 'System/iOSNotificationsOn');
  const systemOnToggle = systemRequired(systemOn.findOne(isSystemToggle), 'iOS On toggle');
  systemSetToggle(one(initial, 'Toggle/通知'), variants.off, 'Toggle/通知');
  systemSetToggle(one(off, 'Toggle/通知'), variants.off, 'Toggle/通知');
  systemSetToggle(one(on, 'Toggle/通知'), variants.on, 'Toggle/通知');
  systemSetToggle(one(denied, 'Toggle/通知'), variants.off, 'Toggle/通知');
  systemSetToggle(sourceSystemToggle, variants.off, 'System/Notification toggle');
  systemSetToggle(systemOnToggle, variants.on, 'System/Notification toggle');

  clear(permission);
  systemSheetClose(permission);
  put(systemRequired(button(permission, '允许'), 'permission allow'), on);
  put(systemRequired(button(permission, '不允许'), 'permission deny'), denied);
  systemNotificationAction(initial, permission, 'OVERLAY');
  systemNotificationAction(on, off, 'NAVIGATE');
  systemNotificationAction(off, on, 'NAVIGATE');
  systemNotificationAction(denied, systemOff, 'NAVIGATE');

  // iOS setting changes remain on the iOS screen until its back action is used.
  put(sourceSystemToggle, systemOn, 'NAVIGATE', { smart: true });
  put(systemOnToggle, systemOff, 'NAVIGATE', { smart: true });
  put(systemRequired(one(systemOff, 'Action/back'), 'iOS Off back'), denied);
  put(systemRequired(one(systemOn, 'Action/back'), 'iOS On back'), on);

  // A single set of tutorial overlays serves every dashboard/settings source.
  tutorial.forEach(f => { clear(f); systemSheetClose(f); });
  for (const f of tutorial.slice(0, 2)) put(systemRequired(button(f, '下一步'), 'tutorial next'), tutorial[2], 'SWAP', { smart: true });
  for (const f of tutorial.slice(2)) close(systemRequired(button(f, '完成'), 'tutorial finish'));
  put(tutorial[0], tutorial[1], 'SWAP', { timeout: .9, smart: true });
  put(tutorial[2], tutorial[3], 'SWAP', { timeout: .9, smart: true });

  // Support pages use overlay-close for their caller and a swap within the
  // license drill-down, so License → Licenses → caller is deterministic.
  for (const k of ['Help', 'Privacy', 'Licenses']) {
    clear(pages[k]);
    close(systemRequired(one(pages[k], 'Action/back'), k + ' back'));
  }
  clear(pages.License);
  put(systemRequired(one(pages.Licenses, 'Row/CodexBar'), 'license row'), pages.License, 'SWAP');
  put(systemRequired(one(pages.License, 'Action/back'), 'license detail back'), pages.Licenses, 'SWAP');

  // These three base-snapshot dashboard copies preserve all existing account
  // actions. Only tab destinations and tutorial entry points change here.
  const dashboardByState = {
    initial: e.dashboard,
    on: systemCopyWithActions(e, e.dashboard, 'System/DashboardNotificationsOn'),
    off: systemCopyWithActions(e, e.dashboard, 'System/DashboardNotificationsOff'),
    denied: systemCopyWithActions(e, e.dashboard, 'System/DashboardNotificationsDenied')
  };
  const settingsByState = { initial, on, off, denied };
  for (const [state, settings] of Object.entries(settingsByState)) {
    const dashboard = dashboardByState[state];
    put(systemRequired(one(settings, 'Tab/额度'), state + ' quota tab'), dashboard);
    put(systemRequired(one(dashboard, 'Tab/设置'), state + ' settings tab'), settings);
    const dashboardTab = one(dashboard, 'Tab/额度');
    if (dashboardTab) put(dashboardTab, dashboard);
    const settingsTab = one(settings, 'Tab/设置');
    if (settingsTab) put(settingsTab, settings);
    const dashboardTutorial = one(dashboard, 'Action/如何添加小组件');
    if (dashboardTutorial) put(dashboardTutorial, tutorial[0], 'OVERLAY');
    put(systemRequired(one(settings, 'Row/如何添加小组件'), state + ' tutorial row'), tutorial[0], 'OVERLAY');
    systemSupportRoute(settings, pages);
  }

  const index = root(e, e.entry, 'System/Review');
  const body = systemRequired(one(index, 'Content'), 'system review content');
  for (const child of [...body.children]) child.remove();
  body.itemSpacing = 8;
  systemIndexHeading(e, body, '通知、教程与返回路径', 22);
  systemIndexHeading(e, body, '设计评审 · 系统权限与系统设置均为交互示意', 12);
  const entries = [];
  for (const [label, destination] of [
    ['首次请求通知权限', initial], ['通知已开启', on],
    ['已允许权限 · App 通知关闭', off], ['系统通知权限拒绝', denied],
    ['从看板查看小组件教程', e.dashboard], ['从设置查看小组件教程', initial]
  ]) {
    put(addButton(e, body, label), destination);
    entries.push({ label, id: destination.id });
  }
  put(addButton(e, body, '返回评审入口'), e.entry);
  const backButton = one(index, 'Action/back');
  if (backButton) put(backButton, e.entry);
  const viewport = one(index, 'Scroll viewport');
  if (viewport) viewport.overflowDirection = 'VERTICAL';

  await flush();
  const result = {
    status: t + ' 系统、通知与教程阶段完成',
    stage: t + '/system',
    index: index.id,
    entries,
    settings: Object.fromEntries(Object.entries(settingsByState).map(([k, n]) => [k, n.id])),
    dashboards: Object.fromEntries(Object.entries(dashboardByState).map(([k, n]) => [k, n.id])),
    permission: permission.id,
    system: { off: systemOff.id, on: systemOn.id },
    tutorial: tutorial.map(n => n.id),
    support: Object.fromEntries(Object.entries(pages).map(([k, n]) => [k, n.id])),
    createdFrameCount: 6,
    scope: 'Base R3 account snapshot only. Account menu and refresh nodes are unchanged.'
  };
  e.branch.setPluginData(completionKey, JSON.stringify(result));
  figma.commitUndo();
  return result;
}
