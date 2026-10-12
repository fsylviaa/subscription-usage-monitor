// Prepared local repair. Not part of the running bundle until explicitly added.
// The IDs below come from the final native delivery manifests, not name guesses.
// Only two existing Home Action/back reactions may change. No env()/init(),
// fonts, cloning, node removal, pluginData, canvas selection or layout writes.
const R4_WIDGET_SHARED_HOME_BACK = [
  { theme: 'Light', section: '1:43252', home: '46:142410', config: '46:142344' },
  { theme: 'Dark', section: '1:43254', home: '46:152771', config: '46:152705' },
];
function widgetReturnActions(reaction) { return reaction.actions || (reaction.action ? [reaction.action] : []); }
function widgetReturnBackReaction() { return [{ trigger: { type: 'ON_CLICK' }, actions: [{ type: 'BACK' }] }]; }
function widgetReturnOnlyBack(reactions) {
  return reactions.length === 1 && reactions[0].trigger?.type === 'ON_CLICK' &&
    widgetReturnActions(reactions[0]).length === 1 && widgetReturnActions(reactions[0])[0].type === 'BACK';
}
async function widgetSharedHomeBackPlans() {
  if (typeof jobs !== 'undefined' && jobs.size) throw Error('Finish pending reaction writes before widget return repair.');
  const plans = [];
  for (const scope of R4_WIDGET_SHARED_HOME_BACK) {
    const prefix = 'R4/' + scope.theme + '/Widgets/';
    const [home, config] = await Promise.all([scope.home, scope.config].map(id => figma.getNodeByIdAsync(id)));
    for (const [node, key] of [[home, 'Home/Config/small/C'], [config, 'Config/small/C']]) {
      if (!node || node.removed || node.type !== 'FRAME' || node.name !== prefix + key || node.parent?.id !== scope.section || !node.visible) throw Error('Widget return scope mismatch: ' + scope.theme + '/' + key);
    }
    const nav = home.findAll(n => n.name === 'Navigation');
    if (nav.length !== 1) throw Error('Expected one Home Navigation: ' + scope.theme);
    const backs = nav[0].children.filter(n => n.name === 'Action/back');
    if (backs.length !== 1 || !backs[0].visible || typeof backs[0].setReactionsAsync !== 'function') throw Error('Expected one visible local Home return arrow: ' + scope.theme);
    const arrow = backs[0], before = JSON.parse(JSON.stringify(arrow.reactions || []));
    if (!widgetReturnOnlyBack(before)) {
      const a = before.length === 1 && before[0].trigger?.type === 'ON_CLICK' ? widgetReturnActions(before[0]) : [];
      if (a.length !== 1 || a[0].type !== 'NODE' || a[0].navigation !== 'NAVIGATE' || !a[0].destinationId) throw Error('Unexpected Home return behavior: ' + scope.theme);
      const target = await figma.getNodeByIdAsync(a[0].destinationId);
      if (!target || target.removed || target.parent?.id !== scope.section || ![prefix + 'Accounts/ABCD', prefix + 'Config/small/C'].includes(target.name)) throw Error('Unexpected Home return target: ' + scope.theme);
    }
    const finish = config.findAll(n => n.name === 'Button/完成');
    if (finish.length !== 1 || !(finish[0].reactions || []).some(r => r.trigger?.type === 'ON_CLICK' && widgetReturnActions(r).some(a => a.type === 'NODE' && a.navigation === 'NAVIGATE' && a.destinationId === home.id))) throw Error('Config completion must navigate to this Home: ' + scope.theme);
    const unaffected = [home, ...home.findAll()].filter(n => n.id !== arrow.id && 'reactions' in n).map(n => ({ node: n, reactions: JSON.stringify(n.reactions || []) }));
    plans.push({ scope, home, config, arrow, before, unaffected });
  }
  return plans;
}
function widgetSharedHomeBackSummary(plans) {
  return plans.map(p => ({ theme: p.scope.theme, rootId: p.home.id, root: p.home.name, arrowId: p.arrow.id, configId: p.config.id,
    before: p.before, after: widgetReturnBackReaction(), alreadyBack: widgetReturnOnlyBack(p.before) }));
}
async function planWidgetSharedHomeBackRepairStage() {
  const plans = await widgetSharedHomeBackPlans();
  return { status: '小组件共享 Home 返回修复方案（只读）', createdRootCount: 0, mutationCount: 0, plans: widgetSharedHomeBackSummary(plans),
    validationRequired: ['Config/small/C → 完成 → Home → 详情 OVERLAY → CLOSE → Home 返回，应回同一 Config。', 'Widgets/Review → 回退入口 → Home 返回，应回 Widgets/Review。', 'Home → App/账号列表 → 列表返回 Home → Home 返回，应回上一账号列表。', 'Home indicator 仍回原评审 Hub；直接从 Home 深链启动时用该既有出口。'] };
}
async function repairWidgetSharedHomeBackStage() {
  // Both themes must pass before the first native write.
  const plans = await widgetSharedHomeBackPlans(), changed = [];
  for (const p of plans) if (!widgetReturnOnlyBack(p.before)) {
    await p.arrow.setReactionsAsync(widgetReturnBackReaction());
    changed.push(p.arrow.id);
    if (typeof writes !== 'undefined') writes.add(p.arrow.id);
  }
  for (const p of plans) {
    if (!widgetReturnOnlyBack(p.arrow.reactions || [])) throw Error('BACK reaction verification failed: ' + p.scope.theme);
    for (const snapshot of p.unaffected) if (JSON.stringify(snapshot.node.reactions || []) !== snapshot.reactions) throw Error('Unrelated Home reaction changed: ' + snapshot.node.id);
  }
  if (changed.length) figma.commitUndo();
  return { status: '小组件共享 Home 已按来源返回，等待实际点击验证', createdRootCount: 0, mutationCount: changed.length,
    mutatedNodeIds: changed, plans: widgetSharedHomeBackSummary(plans), nativeClickValidation: 'pending' };
}
