// Two representative pending-fallback stories plus one stale-cache Home/theme.
// Dependencies for repair: core + account-flows (copyFlowTree). No model builders.
// lookupPendingWidgetReviewStage is read-only and does not call env/init/fonts.
const R4_PENDING_WIDGET_STORIES = [
  { kind: 'samePlatform', caption: '同平台回退 · 未获取额度', before: 14, after: 10, pending: 1, key: 'Codex', email: 'alin.codex@example.com' },
  { kind: 'crossPlatform', caption: '跨平台回退 · 未获取额度', before: 13, after: 9, pending: 0, key: 'Claude', email: 'alin.claude@example.com' },
];
const R4_STALE_WIDGET_KEY = 'Widgets/Stale/Pending-10-1';
const R4_STALE_WIDGET_CAPTION = '旧组件画面 · 失效目标';

function pendingWidgetKeys(story) {
  const before = 'AccountFlow/Pending-' + story.before + '-' + story.pending;
  const after = 'AccountFlow/Pending-' + story.after + '-' + story.pending;
  return { beforeHome: 'AccountWidgets/Set-' + story.before + '/Pending-' + story.pending,
    beforeDashboard: before + '/Dashboard', menu: before + '/d/Menu-2', disconnect: before + '/d/Disconnect-2',
    home: 'AccountWidgets/Set-' + story.after + '/Pending-' + story.pending,
    dashboard: after + '/Dashboard', unknown: after + '/WidgetUnknown' };
}
async function lookupPendingWidgetReviewStage() {
  const results = [], missing = [], duplicates = [];
  for (const [theme, branchId] of [['Light', '1:43252'], ['Dark', '1:43254']]) {
    const branch = await figma.getNodeByIdAsync(branchId);
    if (!branch || branch.type !== 'SECTION') throw Error('Missing interaction section: ' + branchId);
    const get = key => {
      const name = 'R4/' + theme + '/' + key, nodes = branch.children.filter(n => n.name === name && n.type === 'FRAME');
      if (!nodes.length) missing.push(name);
      if (nodes.length > 1) duplicates.push({ name, ids: nodes.map(n => n.id) });
      return { key: name, id: nodes.length === 1 ? nodes[0].id : null, visible: nodes.length === 1 ? nodes[0].visible : null };
    };
    results.push({ theme, review: get('Widgets/Review'), stories: R4_PENDING_WIDGET_STORIES.map(story => ({
      kind: story.kind, account: story.email, ...Object.fromEntries(Object.entries(pendingWidgetKeys(story)).map(([key, name]) => [key, get(name)]))
    })), unaffectedCursorDetail: get('AccountFlow/Details/3'), stale: get(R4_STALE_WIDGET_KEY) });
  }
  return { status: '浅深待获取额度回退节点（只读）', results, missing, duplicates, mutationCount: 0 };
}

async function repairPendingWidgetReviewStage() {
  const environments = [await env('Light'), await env('Dark')];
  if (jobs.size) throw Error('Inspect or flush pending jobs before this local repair.');
  const need = (node, what) => { if (!node || node.removed) throw Error('Pending-widget review missing ' + what);return node; };
  const visibleTexts = root => txt(root).filter(n => {
    for (let p = n; p; p = p.parent) { if (p.visible === false) return false;if (p === root) break; }return true;
  }).map(n => n.characters);
  const values = widget => visibleTexts(widget).filter(s => /^剩余 \d+%$/.test(s));
  // R3 review-r3.js:widget() intentionally hides header TEXTs after the title.
  // accountWidgetHome updates the stored time without making that layer visible.
  // Validate this retained data independently from the visible quota/unknown text.
  const headerData = widget => txt(need(one(widget, 'Widget header'), 'widget header')).map(n => n.characters);
  const link = (node, target, navigation) => {
    need(node, 'reaction source');
    const r = node.reactions || [], a = r.length === 1 ? r[0].actions || (r[0].action ? [r[0].action] : []) : [];
    if (r.length !== 1 || r[0].trigger?.type !== 'ON_CLICK' || a.length !== 1 || a[0].type !== 'NODE' ||
        a[0].destinationId !== target.id || a[0].navigation !== navigation) throw Error('Unexpected widget-story link: ' + node.name);
  };
  const closeOnly = node => {
    need(node, 'close control');const r = node.reactions || [], a = r.flatMap(x => x.actions || (x.action ? [x.action] : []));
    if (r.length !== 1 || r[0].trigger?.type !== 'ON_CLICK' || a.length !== 1 || a[0].type !== 'CLOSE') throw Error('Unexpected close control: ' + node.name);
  };
  const bar = frame => one(frame, 'Home indicator') || frame.children.find(n => n.type === 'RECTANGLE' && Math.abs(n.width - 134) < 1 && n.height < 8);
  const identity = (widget, email) => {
    if (one(widget, 'Widget account')?.characters !== email.split('@')[0]) throw Error('Wrong widget identity: ' + widget.name);
  };
  const currentControls = (home, dashboard) => {
    const app = need(one(home, 'App/订阅额度'), 'current App icon'), back = need(one(home, 'Action/back'), 'current Home back');
    const indicator = need(bar(home), 'current Home indicator');
    for (const control of [app, back, indicator]) link(control, dashboard, 'NAVIGATE');
    return { app, back, indicator };
  };
  const dataSnapshot = root => JSON.stringify(all(root).map(n => ({ name: n.name, text: n.type === 'TEXT' ? n.characters : null,
    visible: n.visible, width: n.width, height: n.height, reactions: n.reactions || [] })));
  const safeStaleTargets = (root, dashboard, cursorDetail) => {
    const allowed = new Set([dashboard.id, cursorDetail.id]);
    for (const node of all(root)) for (const reaction of node.reactions || []) {
      for (const a of reaction.actions || (reaction.action ? [reaction.action] : [])) {
        if (a.type !== 'NODE' || !allowed.has(a.destinationId)) throw Error('Stale cache still points outside the current account state.');
      }
    }
  };

  // Both themes and all source/target roots are checked before the first clone.
  const plans = environments.map(e => {
    const get = (key, optional = false) => {
      const name = 'R4/' + e.t + '/' + key, nodes = e.branch.children.filter(n => n.name === name);
      if (optional && !nodes.length) return null;
      if (nodes.length !== 1 || nodes[0].type !== 'FRAME' || nodes[0].visible === false || e.registry.get(name) !== nodes[0]) throw Error('Expected one current root: ' + name);
      return nodes[0];
    };
    const hub = get('Widgets/Review'), body = need(one(hub, 'Content'), 'widget review body');
    if (body.layoutMode !== 'VERTICAL' || !visibleTexts(hub).includes('设计评审 · 系统界面与数据均为模拟')) throw Error('Expected widget design-review directory.');
    const returnButton = need(button(hub, '返回评审入口'), 'widget review return');
    if (returnButton.parent !== body) throw Error('Unexpected review return placement.');
    const cursorDetail = get('AccountFlow/Details/3'), workDetail = get('AccountFlow/Details/2');
    if (!visibleTexts(cursorDetail).includes('alin.cursor@example.com') || !visibleTexts(cursorDetail).some(s => s.includes('剩余 62%')) ||
        !visibleTexts(cursorDetail).includes('上次成功更新 09:41') || !visibleTexts(workDetail).includes('上次成功更新 09:41')) throw Error('Unexpected retained detail data/time.');
    const stories = R4_PENDING_WIDGET_STORIES.map(story => {
      const nodes = Object.fromEntries(Object.entries(pendingWidgetKeys(story)).map(([key, name]) => [key, get(name)]));
      const validateHome = (home, mask, selected, dashboard) => {
        let state;try { state = JSON.parse(home.getPluginData('r4_account_widget_state')); } catch (_) { throw Error('Missing widget state on ' + home.name); }
        const order = mask === story.before ? [story.pending, 2, 3] : [story.pending, 3];
        if (state.mask !== mask || state.pendingIdx !== story.pending || JSON.stringify(state.order) !== JSON.stringify(order) || JSON.stringify(state.selected) !== JSON.stringify(selected)) throw Error('Unexpected widget binding state: ' + home.name);
        const container = need(one(home, 'Home widgets'), 'Home widgets');
        const widgets = container.children.filter(n => n.visible !== false);
        if (widgets.length !== 2 || state.widgets?.[0] !== widgets[0].id || state.widgets?.[1] !== widgets[1].id) throw Error('Unexpected Home widget count/identity.');
        identity(widgets[1], 'alin.cursor@example.com');
        const cursorValues = values(widgets[1]), cursorHeader = one(widgets[1], 'Widget header');
        const cursorHeaderTexts = cursorHeader ? headerData(widgets[1]) : [];
        if (JSON.stringify(cursorValues) !== JSON.stringify(['剩余 62%']) || !cursorHeaderTexts.includes('09:41')) {
          throw Error('Cursor widget data changed: ' + JSON.stringify({ home: home.id, name: home.name,
            widget: widgets[1].id, values: cursorValues, header: cursorHeader?.id || null,
            headerTexts: cursorHeaderTexts, rawTexts: txt(widgets[1]).map(n => n.characters) }));
        }
        link(widgets[1], cursorDetail, 'OVERLAY');currentControls(home, dashboard);
        return widgets;
      };
      const beforeWidgets = validateHome(nodes.beforeHome, story.before, [2, 3], nodes.beforeDashboard);
      const afterWidgets = validateHome(nodes.home, story.after, [story.pending, 3], nodes.dashboard);
      identity(beforeWidgets[0], 'work.codex@example.com');
      if (JSON.stringify(values(beforeWidgets[0])) !== JSON.stringify(['剩余 70%', '剩余 85%']) || !headerData(beforeWidgets[0]).includes('09:41')) throw Error('Old work cache must be 70% / 85%, 09:41.');
      link(beforeWidgets[0], workDetail, 'OVERLAY');
      identity(afterWidgets[0], story.email);
      if (!visibleTexts(afterWidgets[0]).includes('未获取额度') || !headerData(afterWidgets[0]).includes('未获取') || values(afterWidgets[0]).length || afterWidgets[0].children.some(n => n.name.startsWith('Widget window/'))) throw Error('Pending widget must contain no old quota windows.');
      link(afterWidgets[0], nodes.unknown, 'OVERLAY');
      const unknownBody = need(one(one(nodes.unknown, 'Sheet'), 'Content'), 'unknown detail content');
      const unknownTexts = visibleTexts(unknownBody);
      if (!unknownTexts.includes(story.email) || !unknownTexts.includes('尚未获取额度') || unknownTexts.some(s => /%|09:41|work\.codex/.test(s))) throw Error('Unknown detail contains stale identity/quota.');
      closeOnly(button(nodes.unknown, '关闭'));
      for (const [dashboard, expected] of [[nodes.beforeDashboard, [story.pending, 2, 3]], [nodes.dashboard, [story.pending, 3]]]) {
        const names = expected.map(idx => ['Quota/Claude', 'Quota/Codex', 'Quota/Codex · work', 'Quota/Cursor'][idx]);
        const cards = one(dashboard, 'Content').children.filter(n => n.name.startsWith('Quota/') && n.visible !== false);
        if (JSON.stringify(cards.map(n => n.name)) !== JSON.stringify(names)) throw Error('Dashboard binding set mismatch.');
        const pendingCard = need(cards.find(n => n.name === 'Quota/' + story.key), 'pending account card');
        if (!visibleTexts(pendingCard).includes(story.email) || txt(pendingCard).filter(n => n.name.startsWith('Value/')).some(n => n.characters !== '—') || one(pendingCard, 'Detail updated')?.characters !== '尚未获取额度') throw Error('Pending dashboard quota mismatch.');
      }
      link(one(one(nodes.beforeDashboard, 'Quota/Codex · work'), 'Action/more'), nodes.menu, 'OVERLAY');
      link(button(nodes.menu, '断开连接'), nodes.disconnect, 'SWAP');
      link(button(nodes.disconnect, '断开连接'), nodes.dashboard, 'NAVIGATE');closeOnly(button(nodes.disconnect, '取消'));
      link(bar(nodes.dashboard), nodes.home, 'NAVIGATE');
      return { ...story, ...nodes, beforeWidgets, afterWidgets };
    });
    const stale = get(R4_STALE_WIDGET_KEY, true), captions = [...stories.map(s => s.caption), R4_STALE_WIDGET_CAPTION];
    const existingButtons = captions.map(caption => {
      const matches = body.children.filter(n => n.name === 'Button/' + caption);
      if (matches.length > 1) throw Error('Duplicate pending-widget review entry.');return matches[0] || null;
    });
    if (existingButtons[0]) link(existingButtons[0], stories[0].beforeHome, 'NAVIGATE');
    if (existingButtons[1]) link(existingButtons[1], stories[1].beforeHome, 'NAVIGATE');
    if (existingButtons[2]) { if (!stale) throw Error('Stale review button exists without its frame.');link(existingButtons[2], stale, 'NAVIGATE'); }
    if (stale) {
      if (stale.getPluginData('r4_stale_widget_review') !== 'v1:10:1') throw Error('Inspect an unrecognized existing stale frame.');
      const w = one(stale, 'Home widgets')?.children;
      if (!w || w.length !== 2) throw Error('Invalid stale Home widget count.');
      identity(w[0], 'work.codex@example.com');link(w[0], stories[0].dashboard, 'NAVIGATE');
      if (JSON.stringify(values(w[0])) !== JSON.stringify(['剩余 70%', '剩余 85%']) || !headerData(w[0]).includes('09:41') || dataSnapshot(w[1]) !== dataSnapshot(stories[0].afterWidgets[1])) throw Error('Stale Home data changed.');
      currentControls(stale, stories[0].dashboard);safeStaleTargets(stale, stories[0].dashboard, cursorDetail);
    }
    return { e, hub, body, returnButton, stories, stale, captions, existingButtons, rootCount: e.branch.children.length,
      sourceSnapshots: stories.flatMap(s => [s.beforeHome, s.home, s.beforeDashboard, s.dashboard, s.unknown]).map(n => [n, dataSnapshot(n)]),
      existingReviewActions: body.children.map(n => [n, JSON.stringify(n.reactions || [])]) };
  });

  let createdRootCount = 0, createdReviewButtonCount = 0;const results = [];
  for (const p of plans) {
    const same = p.stories[0];let stale = p.stale;
    if (!stale) {
      stale = root(p.e, same.home, R4_STALE_WIDGET_KEY);await copyFlowTree(same.home, stale);
      const container = one(stale, 'Home widgets');container.children[0].remove();
      const cached = clone(same.beforeWidgets[0], container, 'AccountWidget/0/2');container.insertChild(0, cached);
      put(cached, same.dashboard, 'NAVIGATE');
      // This is a cached presentation of a deleted identity, not an AccountWidgets
      // model. Do not inherit a signature claiming the pixels show current B.
      stale.setPluginData('r4_account_widget_state', '');stale.setPluginData('r4_account_widget_signature', '');
      stale.setPluginData('r4_stale_widget_review', 'v1:10:1');
      stale.setPluginData('r4_stale_widget_current', JSON.stringify({ mask: 10, pendingIdx: 1, bound: [1, 3], currentSelected: [1, 3], cachedDisplay: [2, 3], staleTapTarget: same.dashboard.id }));
      createdRootCount++;
    }
    const targets = [same.beforeHome, p.stories[1].beforeHome, stale], entries = [];
    for (let i = 0; i < targets.length; i++) {
      let control = p.existingButtons[i];
      if (!control) { control = addButton(p.e, p.body, p.captions[i]);p.body.insertChild(p.body.children.indexOf(p.returnButton), control);put(control, targets[i], 'NAVIGATE');createdReviewButtonCount++; }
      entries.push({ caption: p.captions[i], button: control.id, destination: targets[i].id });
    }
    results.push({ theme: p.e.t, review: p.hub.id, stale: stale.id, staleTarget: same.dashboard.id, entries });
  }
  if (createdRootCount || createdReviewButtonCount) await flush();
  for (const p of plans) {
    if (p.e.branch.children.length !== p.rootCount + (p.stale ? 0 : 1)) throw Error('Unexpected root count change.');
    for (const [n, before] of p.sourceSnapshots) if (dataSnapshot(n) !== before) throw Error('Existing story data or reactions changed.');
    for (const [n, before] of p.existingReviewActions) if (JSON.stringify(n.reactions || []) !== before) throw Error('Existing review action changed.');
    const stale = p.e.registry.get('R4/' + p.e.t + '/' + R4_STALE_WIDGET_KEY), widgets = one(stale, 'Home widgets').children;
    link(widgets[0], p.stories[0].dashboard, 'NAVIGATE');currentControls(stale, p.stories[0].dashboard);
    safeStaleTargets(stale, p.stories[0].dashboard, p.e.registry.get('R4/' + p.e.t + '/AccountFlow/Details/3'));
    if (dataSnapshot(widgets[1]) !== dataSnapshot(p.stories[0].afterWidgets[1])) throw Error('Unaffected Cursor widget changed.');
  }
  return { status: '浅深未获取额度回退与旧组件目标的评审入口已补齐', createdRootCount, createdReviewButtonCount,
    results, lookup: await lookupPendingWidgetReviewStage(), actualClickValidation: 'pending',
    scope: 'At most one stale Home and three widget-review buttons per theme; current account sets, unknown details, disconnect paths, Cursor widget, product controls and shared components are preserved.' };
}

// Diagnostic only: reports raw and visible strings separately, including the
// intentionally hidden R3 header time layer and its visibility ancestry.
async function inspectPendingWidgetDataStage() {
  const lookup = await lookupPendingWidgetReviewStage(), homes = [];
  const textNodes = node => node ? node.findAllWithCriteria({ types: ['TEXT'] }) : [];
  const trace = (text, root) => {
    const path = [];let visible = true, reachedByReference = false, reachedById = false;
    for (let p = text; p; p = p.parent) {
      path.push({ id: p.id, name: p.name, type: p.type, visible: p.visible });
      if (p.id === root.id) reachedById = true;
      if (p.visible === false) { visible = false;break; }
      if (p === root) { reachedByReference = true;break; }
    }
    return { visible, reachedByReference, reachedById, path };
  };
  const texts = root => textNodes(root).map(n => ({ id: n.id, name: n.name, text: n.characters, ...trace(n, root) }));
  for (const theme of lookup.results) for (const story of theme.stories) for (const role of ['beforeHome', 'home']) {
    const ref = story[role];if (!ref.id) { homes.push({ theme: theme.theme, kind: story.kind, role, ...ref });continue; }
    const home = await figma.getNodeByIdAsync(ref.id), containers = home.findAll(n => n.name === 'Home widgets');
    const container = containers[0];
    const widgets = (container?.children || []).filter(n => n.visible !== false).map(widget => {
      const raw = texts(widget), headers = widget.findAll(n => n.name === 'Widget header');
      const header = headers[0], headerTexts = header ? texts(header) : [];
      const selected = raw.filter(n => n.visible).map(n => n.text), headerSelected = headerTexts.filter(n => n.visible).map(n => n.text);
      return { id: widget.id, name: widget.name,
        rawTexts: raw.map(({ id, name, text }) => ({ id, name, text })), visibleTexts: selected,
        matchedValues: selected.filter(s => /^剩余 \d+%$/.test(s)),
        headers: headers.map(n => ({ id: n.id, name: n.name, type: n.type })), headerTexts: headerSelected,
        visibilityExceptions: [...raw, ...headerTexts].filter(n => !n.visible || !n.reachedByReference),
        headerTextDetails: headerTexts };
    });
    homes.push({ theme: theme.theme, kind: story.kind, role, ...ref, containerIds: containers.map(n => n.id), widgets });
  }
  return { status: '待获取回退小组件预检诊断（只读，区分原始与可见文字）', homes, mutationCount: 0 };
}
