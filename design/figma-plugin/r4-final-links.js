// Final, bounded integration for the already-authored R4 stages.
// This module changes only review-directory contents and the explicit links
// listed below. It does not regenerate account models or modify shared masters.
// Run after accountSystemStage has authored Set-15 and the account flows exist.
async function finalLinksStage(t) {
  const e = await env(t);
  const doneKey = 'r4_final_links_complete';
  const saved = e.branch.getPluginData(doneKey);
  if (saved) return JSON.parse(saved);
  const required = (n, description) => {
    if (!n || n.removed) throw Error('Final links missing ' + description);
    return n;
  };
  const get = key => required(e.registry.get('R4/' + t + '/' + key), key);

  // Validate exact roots first, so a missing stage is reported before edits.
  const networkHub = get('Network/Review');
  const networkLogin = get('Network/Login');
  const networkQueryFailure = get('Network/QueryFailed');
  const widgetHub = get('Widgets/Review');
  const widgetDetail = get('Widgets/Detail/A');
  const backgroundApp = get('Background/App/Failed');
  const backgroundWidgets = Object.fromEntries(
    ['Failed', 'CheckA', 'CheckB', 'Passed', 'Querying', 'Success'].map(state =>
      [state, get('Background/Widget/' + state)]));
  const systemSettings = {
    on: get('AccountSystem/Set-15/Settings-on'),
    off: get('AccountSystem/Set-15/Settings-off'),
    denied: get('AccountSystem/Set-15/Settings-denied'),
  };
  get('Accounts/Set-0/Dashboard');
  get('AccountFlow/Pending-47-5/Dashboard');
  const addCodexLogin = get('AccountFlow/Add-15-5/Login');
  if (!e.branch.getPluginData('r4_flow_common')) throw Error('Final links require completed shared account flows.');
  const lock = required(e.roots.find(n => n.name === t + '/LockNotification' || n.name.split('|')[1] === 'LockNotification'), 'R3 LockNotification');
  const notification = required(one(lock, 'Notification heading'), 'notification heading').parent;
  const tutorial = required(e.roots.find(n => n.name === t + '/Tutorial1' || n.name.split('|')[1] === 'Tutorial1'), 'R3 Tutorial1');
  const opposite = await env(t === 'Light' ? 'Dark' : 'Light');
  const base = await getAccountModel(e, 15);
  const empty = await getAccountModel(e, 0);
  const pending = await pendingModel(e, 47, 5);
  const c = await flowCommon(e);
  required(c.q[0], 'Claude network-gated query');
  required(c.q[2], 'work Codex network-gated query');
  required(base.details[0], 'Claude expanded account view');
  for (const [state, n] of Object.entries(backgroundWidgets)) required(one(n, 'Widget/Claude'), 'background widget ' + state);

  const before = new Set(e.registry.keys());
  const changedLinks = [];
  const connect = (source, target, navigation = 'NAVIGATE', options = {}) => {
    required(source, 'source for ' + target.name);
    put(source, target, navigation, options);
    changedLinks.push({ source: source.id, destination: target.id, navigation, timeout: options.timeout || null });
  };
  const review = root(e, e.entry, 'Review');
  const systemReview = root(e, e.entry, 'Review/System');

  // The original prototype URLs stay valid: the existing review frame receives
  // the same current directory as R4/Review, with all historical links removed.
  const prepareDirectory = (n, heading, note) => {
    clear(n);
    const body = required(one(n, 'Content'), n.name + ' Content');
    for (const child of [...body.children]) child.remove();
    body.primaryAxisSizingMode = 'AUTO';
    body.itemSpacing = 8;
    label(e, body, heading, 22);
    label(e, body, note, 12);
    const navigation = one(n, 'Navigation');
    const title = navigation && navigation.children.find(x => x.type === 'TEXT');
    if (title) change(title, '设计评审');
    const viewport = one(n, 'Scroll viewport');
    if (viewport) viewport.overflowDirection = 'VERTICAL';
    return body;
  };

  // This is the only change to the already-authored Network login surface.
  // fixLogin restores the literal Cancel label/contrast and closes the actual
  // overlay. Its Continue action and authorization-failure branch remain intact.
  fixLogin(e, networkLogin, 'backup.codex@example.com');
  connect(required(button(networkQueryFailure, '重试'), 'query-failure retry'), c.q[2], 'SWAP');

  // Viewing a widget's cached data does not start another query. Both details
  // are account-specific overlays, so Close returns to the precise Home state.
  const updatedDetail = root(e, widgetDetail, 'Background/Widget/Detail-0945');
  await copyFlowTree(widgetDetail, updatedDetail);
  for (const text of txt(updatedDetail)) {
    if (text.characters.includes('上次成功更新 09:41')) change(text, text.characters.replace('上次成功更新 09:41', '上次成功更新 09:45'));
  }
  const widgetTargets = [];
  for (const [state, n] of Object.entries(backgroundWidgets)) {
    const widget = one(n, 'Widget/Claude');
    const destination = state === 'Success' ? updatedDetail : widgetDetail;
    connect(widget, destination, 'OVERLAY');
    widgetTargets.push({ widget: widget.id, account: 'alin.claude@example.com', state, destination: destination.id, updated: state === 'Success' ? '09:45' : '09:41' });
    const backButton = one(n, 'Action/back');
    if (backButton) connect(backButton, review);
  }

  // Notification opening is separate from permission toggles. The native
  // notification card opens its exact account, then checks before querying.
  const notificationLaunch = root(e, base.details[0], 'Notifications/Launch-ClaudeA');
  await copyFlowTree(base.details[0], notificationLaunch);
  connect(notificationLaunch, c.q[0], 'OVERLAY', { timeout: .15 });
  connect(notification, notificationLaunch);
  const notificationBack = one(lock, 'Action/back');
  if (notificationBack) connect(notificationBack, review);
  const removedTarget = panel(e, 'Notifications/TargetRemoved', '账号已断开', [
    'alin.claude@example.com',
    '无法更新此账号的额度。',
  ], ['关闭']);
  close(required(button(removedTarget, '关闭'), 'removed-notification close'));

  // First query has no trusted prior quota. Its overlay failures retain the
  // already-bound pending account and never claim a 09:41 successful snapshot.
  const firstQueryLaunch = root(e, pending.d, 'Review/FirstQueryLaunch');
  await copyFlowTree(pending.d, firstQueryLaunch);
  const firstQueryLoading = panel(e, 'Review/FirstQuery/Querying', '正在查询额度', [
    R4A[5].email,
  ], ['取消']);
  progress(e, firstQueryLoading, 1);
  close(button(firstQueryLoading, '取消'));
  const firstQueryFailed = panel(e, 'Review/FirstQuery/Failed', '首次额度查询失败', [
    R4A[5].email,
    '平台暂未返回额度，尚未获取额度。',
  ], ['重试', '关闭']);
  close(button(firstQueryFailed, '关闭'));
  connect(firstQueryLoading, firstQueryFailed, 'SWAP', { timeout: 1 });
  const firstQueryGate = await network(e, 'Review first query failure', firstQueryLoading,
    R4A[5].email + ' 的首次额度查询');
  connect(firstQueryLaunch, firstQueryGate.start, 'OVERLAY', { timeout: .15 });
  const firstQueryRetry = await pendingQuery(e, pending, 'd');
  connect(button(firstQueryFailed, '重试'), firstQueryRetry, 'SWAP');

  // The 49-score review story starts over a real four-account source so that
  // cancellation visibly proves no fifth record has been created. Only its
  // review entry selects the mocked result; product add actions are unchanged.
  const beforeAddLaunch = root(e, base.d, 'Review/BeforeAddFailedLaunch');
  await copyFlowTree(base.d, beforeAddLaunch);
  const beforeAddGate = await network(e, 'Review before add preserve accounts',
    addCodexLogin, '添加 Codex 账号', '49');
  connect(beforeAddLaunch, beforeAddGate.start, 'OVERLAY', { timeout: .15 });

  const systemBody = prepareDirectory(systemReview, '通知权限、教程与返回路径',
    '设计评审 · 系统权限与系统设置为交互示意。允许通知不会直接查询额度。');
  const systemEntries = [
    ['首次请求通知权限', base.s],
    ['通知已开启', systemSettings.on],
    ['已允许权限 · App 通知关闭', systemSettings.off],
    ['系统通知权限拒绝 · 前往设置', systemSettings.denied],
  ];
  for (const [caption, destination] of systemEntries) connect(addButton(e, systemBody, caption), destination);
  connect(addButton(e, systemBody, '添加小组件教程'), tutorial, 'OVERLAY');
  connect(addButton(e, systemBody, '返回评审目录'), review);

  const mainEntries = [
    { label: '从无账号开始', target: empty.d },
    { label: '多账号 · 刷新、重连与断开', target: base.d },
    { label: '网络检查 · 49、50、51 与失败', target: networkHub },
    { label: '新增前检查失败 · 保留现有账号', target: beforeAddLaunch },
    { label: '新增后 · 首次查询失败', target: firstQueryLaunch },
    { label: '小组件 · 配置、点击与回退', target: widgetHub },
    { label: '后台更新 · 超时后重试', target: backgroundApp },
    { label: '小组件更新 · 网站不可用', target: backgroundWidgets.Failed },
    { label: '小组件更新 · 系统再次查询', target: backgroundWidgets.CheckA },
    { label: '通知权限、教程与返回路径', target: systemReview },
    { label: '点击通知 · 查询 Claude 账号', target: lock },
    { label: '通知目标已断开', target: removedTarget, navigation: 'OVERLAY' },
    { label: t === 'Light' ? '查看深色评审目录' : '查看浅色评审目录', target: opposite.entry },
  ];
  for (const index of [review, e.entry]) {
    const body = prepareDirectory(index, 'R4 · 交互状态与返回路径',
      '设计评审专用 · 所有账号、评分与结果均为模拟。以下情景入口不属于产品界面。');
    for (const item of mainEntries) connect(addButton(e, body, item.label), item.target, item.navigation || 'NAVIGATE');
  }

  // Subdirectories explicitly return to the current review tree, never to
  // an old single-account or display-preference branch.
  for (const h of [networkHub, widgetHub]) {
    const returnButton = button(h, '返回评审入口');
    if (returnButton) connect(returnButton, review);
    const backButton = one(h, 'Action/back');
    if (backButton) connect(backButton, review);
  }
  await flowFlush(e);
  const result = {
    status: t + ' 最终评审目录与局部连线完成',
    review: review.id,
    originalReview: e.entry.id,
    systemReview: systemReview.id,
    entries: mainEntries.map(x => ({ label: x.label, destination: x.target.id, navigation: x.navigation || 'NAVIGATE' })),
    queryRetry: { source: button(networkQueryFailure, '重试').id, destination: c.q[2].id, account: 'work.codex@example.com' },
    widgetTargets,
    notification: { source: lock.id, card: notification.id, launch: notificationLaunch.id, check: c.q[0].id, account: 'alin.claude@example.com', removedTarget: removedTarget.id },
    firstQueryFailure: { source: pending.d.id, launch: firstQueryLaunch.id, account: R4A[5].email, check: firstQueryGate.start.id, querying: firstQueryLoading.id, failed: firstQueryFailed.id, retry: firstQueryRetry.id, success: pending.ready.d.id },
    beforeAddFailure: { source: base.d.id, launch: beforeAddLaunch.id, check: beforeAddGate.start.id, failed: beforeAddGate.result.id, score: 49, sourceAccounts: base.accounts, nextAfterPassingRetry: addCodexLogin.id },
    newScreens: [...e.registry].filter(([key]) => !before.has(key)).map(([name, n]) => ({ name, id: n.id })),
    changedLinks,
    scope: 'Review contents; Network/Login cancel appearance and close; Network/QueryFailed retry; six background widget click targets/back controls; original LockNotification card/back. No permission-toggle, account-menu, shared-component, or core mutations.',
  };
  e.branch.setPluginData(doneKey, JSON.stringify(result));
  figma.commitUndo();
  return result;
}

// Run separately after the background and account-flow stages have completed.
// Keeps the existing inline refresh sequence and its 09:41/09:45 snapshots.
// New roots are bounded to 8 expanded views + 2 source-specific settings views.
async function repairBackgroundAccountControls(t) {
  const e = await env(t);
  const tag = 'r4_background_account_controls_repaired';
  const saved = e.branch.getPluginData(tag);
  if (saved) return JSON.parse(saved);
  const required = (node, description) => {
    if (!node || node.removed) throw Error('Background controls missing ' + description);
    return node;
  };
  const get = key => required(e.registry.get('R4/' + t + '/' + key), key);
  const sources = {
    Failed: get('Background/App/Failed'),
    Success: get('Background/App/Success'),
  };
  const loading = ['CheckA', 'CheckB', 'Passed', 'Querying'].map(state => get('Background/App/' + state));
  const chooser = get('AccountFlow/Set-15/Connect');
  const emptyChooser = get('AccountFlow/Set-0/Connect');
  const menus = { d: {}, s: {} };
  for (const origin of ['d', 's']) for (let i = 0; i < 4; i++) menus[origin][i] = get('AccountFlow/Set-15/' + origin + '/Menu-' + i);
  const emptyGuide = get('Widgets/EmptyGuide');
  const tutorial = required(e.roots.find(n => n.name === t + '/Tutorial1' || n.name.split('|')[1] === 'Tutorial1'), 'R3 Tutorial1');
  const connectEmpty = required(button(emptyGuide, '连接平台') || button(emptyGuide, '连接账户') ||
    emptyGuide.findOne(n => n.name.startsWith('Button/') && txt(n).some(x => /连接|添加/.test(x.characters))) ||
    one(emptyGuide, 'Action/link'), 'empty-widget connect control');
  const tutorialEmpty = one(emptyGuide, 'Action/如何添加小组件') || one(emptyGuide, 'Row/如何添加小组件');
  const base = await getAccountModel(e, 15);
  for (const [state, source] of Object.entries(sources)) {
    required(one(source, 'Action/link'), state + ' add-account control');
    required(one(source, 'Tab/设置'), state + ' settings tab');
    for (let i = 0; i < 4; i++) {
      const card = required(findCard(source, i), state + ' card ' + i);
      required(one(card, 'Account details'), state + ' account details ' + i);
      required(one(card, 'Expand account'), state + ' expand ' + i);
      required(one(card, 'Action/more'), state + ' menu ' + i);
      required(findRow(base.s, i), 'base settings row ' + i);
    }
  }

  const before = new Set(e.registry.keys());
  const links = [], disabled = [], models = [];
  const link = (node, destination, navigation = 'NAVIGATE', options = {}) => {
    required(node, 'control for ' + destination.name);
    put(node, destination, navigation, options);
    links.push({ source: node.id, destination: destination.id, navigation });
  };
  // Only copy descendants. A source root's AFTER_TIMEOUT trigger must never be
  // inherited by a view reached through account expansion or the Settings tab.
  const copyDescendantControls = async (source, destination) => {
    if (source.children.length !== destination.children.length) throw Error('Background control tree mismatch: ' + source.name);
    for (let i = 0; i < source.children.length; i++) await copyFlowTree(source.children[i], destination.children[i]);
    jobs.set(destination, []);
    writes.add(destination.id);
  };
  const up = await accountUpComponent(e);
  for (const [state, source] of Object.entries(sources)) {
    const key = 'Background/Controls/' + state;
    const settings = root(e, base.s, key + '/Settings');
    await copyDescendantControls(base.s, settings);
    const expanded = {};
    for (let i = 0; i < 4; i++) {
      const n = root(e, source, key + '/Expanded-' + i);
      await copyDescendantControls(source, n);
      for (let j = 0; j < 4; j++) {
        const details = one(findCard(n, j), 'Account details');
        details.visible = i === j;
        writes.add(details.id);
      }
      const arrow = one(findCard(n, i), 'Icon/down');
      if (up && arrow && arrow.type === 'INSTANCE') { arrow.swapComponent(up); writes.add(arrow.id); }
      const viewport = one(n, 'Scroll viewport');
      if (viewport) viewport.overflowDirection = 'VERTICAL';
      expanded[i] = n;
    }
    for (const [index, n] of [[null, source], ...Object.entries(expanded).map(([i, n]) => [Number(i), n])]) {
      link(one(n, 'Action/link'), chooser, 'OVERLAY');
      link(one(n, 'Tab/设置'), settings);
      const quotaTab = one(n, 'Tab/额度');
      if (quotaTab && n !== source) link(quotaTab, source);
      for (let i = 0; i < 4; i++) {
        const card = findCard(n, i);
        link(one(card, 'Action/more'), menus.d[i], 'OVERLAY');
        link(one(card, 'Expand account'), index === i ? source : expanded[i], 'NAVIGATE', { smart: true });
      }
      const teaching = one(n, 'Action/如何添加小组件');
      if (teaching) link(teaching, tutorial, 'OVERLAY');
      // Deliberately do not write Action/refresh: it retains its original
      // inline CheckA -> CheckB -> Passed -> Querying -> Success sequence.
    }
    link(one(settings, 'Tab/额度'), source);
    const settingsTab = one(settings, 'Tab/设置');
    if (settingsTab) { jobs.set(settingsTab, []); writes.add(settingsTab.id); }
    const settingsAdd = one(settings, 'Row/连接账户') || one(settings, 'Action/link');
    if (settingsAdd) link(settingsAdd, chooser, 'OVERLAY');
    const settingsTutorial = one(settings, 'Row/如何添加小组件');
    if (settingsTutorial) link(settingsTutorial, tutorial, 'OVERLAY');
    for (let i = 0; i < 4; i++) {
      const row = findRow(settings, i);
      const identity = one(row, 'Account identity') || row;
      link(identity, expanded[i]);
      const more = one(row, 'Action/more');
      if (more) link(more, menus.s[i], 'OVERLAY');
    }
    models.push({ state, source: source.id, settings: settings.id,
      updated: state === 'Success' ? '09:45' : '09:41',
      expanded: Object.fromEntries(Object.entries(expanded).map(([i, n]) => [i, n.id])) });
  }

  // These four short-lived views retain their existing timer, refresh, and
  // return controls. Disable just add/menu/expand actions during the in-flight
  // background sequence so they cannot open historical account surfaces.
  for (const n of loading) {
    const controls = [one(n, 'Action/link')];
    for (let i = 0; i < 4; i++) {
      const card = findCard(n, i);
      if (card) controls.push(one(card, 'Action/more'), one(card, 'Expand account'));
    }
    for (const control of controls.filter(Boolean)) {
      clear(control);
      writes.add(control.id);
      disabled.push(control.id);
    }
  }
  link(connectEmpty, emptyChooser, 'OVERLAY');
  if (tutorialEmpty) link(tutorialEmpty, tutorial, 'OVERLAY');
  await flush();
  const result = {
    status: t + ' 后台账号控件与空小组件入口已修复',
    models,
    links,
    disabledDuringLoading: disabled,
    emptyWidget: { source: emptyGuide.id, connect: connectEmpty.id, chooser: emptyChooser.id,
      tutorialControl: tutorialEmpty ? tutorialEmpty.id : null, tutorial: tutorial.id },
    newScreens: [...e.registry].filter(([key]) => !before.has(key)).map(([name, n]) => ({ name, id: n.id })),
    scope: 'Background/App Failed and Success descendant controls; 8 local expanded copies and 2 settings copies; loading add/menu/expand controls only; Widgets/EmptyGuide connect/tutorial. Root timers, existing inline refresh reactions, original account menus, and snapshot timestamps are unchanged.',
  };
  e.branch.setPluginData(tag, JSON.stringify(result));
  figma.commitUndo();
  return result;
}
