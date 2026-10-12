// Two exact roots per call; Light + Dark repairs four reviewed empty screens.
// No component or account-widget authoring source is changed.
async function repairEmptyWidgetCopyStage(theme) {
  const branches = { Light: '1:43252', Dark: '1:43254' };
  if (!branches[theme]) throw Error('Empty-copy repair theme must be Light or Dark.');
  const branch = await figma.getNodeByIdAsync(branches[theme]);
  if (!branch || branch.type !== 'SECTION') throw Error('Missing exact interaction section.');
  const keys = ['Widgets/Home/Fallback/Empty', 'AccountWidgets/Set-0'];
  const targets = keys.map(key => {
    const name = 'R4/' + theme + '/' + key;
    const candidates = branch.children.filter(n => n.name === name);
    if (candidates.length !== 1 || candidates[0].type !== 'FRAME') throw Error('Expected one exact empty root: ' + name);
    return candidates[0];
  });
  const current = '轻点小组件，打开对应账号';
  const historical = '轻点小组件，打开对应账户';
  const texts = node => node.findAllWithCriteria({ types: ['TEXT'] });
  const visibleIn = (node, root) => {
    for (let n = node; n; n = n.parent) {
      if (n.visible === false) return false;
      if (n === root) return true;
    }
    return false;
  };
  // Preflight both roots completely before deleting anything.
  const plans = targets.map((target, index) => {
    const body = target.findOne(n => n.name === 'Content');
    const widgets = target.findOne(n => n.name === 'Home widgets');
    if (!target.visible || !body || body.type !== 'FRAME' || body.layoutMode !== 'VERTICAL' || !widgets) throw Error('Unexpected empty layout: ' + target.name);
    const visibleWidgets = widgets.children.filter(n => n.visible !== false);
    if (visibleWidgets.length !== 2 || visibleWidgets.some(n => !texts(n).some(t => t.characters === '未连接账号，无数据'))) throw Error('Expected two empty widgets: ' + target.name);
    if (texts(target).some(n => visibleIn(n, target) && n.characters.includes('@'))) throw Error('Visible account identity remains in empty root: ' + target.name);
    if (index === 1) {
      let state;
      try { state = JSON.parse(target.getPluginData('r4_account_widget_state')); } catch (_) { throw Error('Set-0 has no valid account-widget state.'); }
      if (!state || state.mask !== 0 || !Array.isArray(state.order) || state.order.length !== 0 ||
        !Array.isArray(state.selected) || state.selected.length !== 2 || state.selected.some(x => x !== null) ||
        (state.pendingIdx !== null && state.pendingIdx !== undefined)) throw Error('Set-0 is not a verified no-account state.');
    }
    const matched = texts(target).filter(n => n.characters === current);
    if (matched.length > 1) throw Error('Ambiguous duplicate empty-widget hint: ' + target.name);
    if (texts(target).some(n => n.characters === historical)) throw Error('Unexpected historical hint; inspect before extending the repair.');
    const hint = matched[0] || null;
    if (hint && (hint.parent !== body || hint.reactions?.length)) throw Error('Hint is not the expected noninteractive direct Content child.');
    const following = hint && body.children[body.children.indexOf(hint) + 1];
    // Only the dedicated empty 1x14 Space adjacent to this line is removed.
    const spacer = following && following.type === 'FRAME' && following.name === 'Space' &&
      following.width === 1 && following.height === 14 && following.children.length === 0 &&
      (!following.reactions || following.reactions.length === 0) &&
      Array.isArray(following.fills) && following.fills.length === 0 ? following : null;
    return { target, body, hint, spacer, before: { contentHeight: body.height, itemSpacing: body.itemSpacing,
      root: { id: target.id, name: target.name, parent: target.parent.id, x: target.x, y: target.y, width: target.width, height: target.height } } };
  });
  const results = [];
  for (const { target, body, hint, spacer, before } of plans) {
    const removed = [];
    for (const node of [hint, spacer].filter(Boolean)) {
      removed.push({ id: node.id, name: node.name, type: node.type, text: node.type === 'TEXT' ? node.characters : null });
      if (typeof writes !== 'undefined') writes.add(node.id);
      node.remove();
    }
    if (hint) {
      body.primaryAxisSizingMode = 'AUTO';
      if (typeof writes !== 'undefined') writes.add(body.id);
    }
    results.push({ root: target.id, name: target.name, removed, before,
      after: { contentHeight: body.height, itemSpacing: body.itemSpacing,
        remainingHintCount: texts(target).filter(n => n.characters === current || n.characters === historical).length } });
  }
  if (results.some(x => x.removed.length)) figma.commitUndo();

  // Other empty candidates are read-only; the two-root allowlist stays fixed.
  const otherEmptyRoots = [];
  for (const root of branch.children) {
    if (targets.includes(root) || root.type !== 'FRAME' || !root.name.startsWith('R4/' + theme + '/')) continue;
    const key = root.name.slice(('R4/' + theme + '/').length);
    let state = null;
    if (key.startsWith('AccountWidgets/')) {
      try { state = JSON.parse(root.getPluginData('r4_account_widget_state') || 'null'); } catch (_) { state = null; }
    }
    const emptyByState = state && (state.mask === 0 || (Array.isArray(state.selected) && state.selected.length > 0 && state.selected.every(x => x === null)));
    const emptyByName = key === 'AccountWidgets/Set-0' || /(?:^|\/)Empty(?:$|\/)/.test(key) || key === 'Widgets/EmptyGuide';
    if (!emptyByState && !emptyByName) continue;
    const findings = texts(root).filter(n => n.characters === current || n.characters === historical)
      .map(n => ({ id: n.id, text: n.characters, visible: visibleIn(n, root) }));
    otherEmptyRoots.push({ id: root.id, name: root.name, visible: root.visible, mask: state?.mask ?? null,
      hintMatches: findings, changed: false });
  }
  return {
    status: results.some(x => x.removed.length) ? theme + ' 两个指定空小组件根已删除过时说明并收紧' : theme + ' 两个指定空小组件根已无该说明，未重复修改',
    roots: results,
    repairedRootCount: results.filter(x => x.removed.length).length,
    readOnlyOtherEmptyRoots: otherEmptyRoots,
    additionalRootsModified: 0,
    scope: 'Only Widgets/Home/Fallback/Empty and AccountWidgets/Set-0 direct hints and their exact adjacent empty 1x14 spacers. Both roots are preflighted before edits. Auto layout closes gaps; no replacement text, reaction, widget content, root geometry, or shared-component changes.',
  };
}
