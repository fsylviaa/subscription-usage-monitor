// Local review-entry repair. Dependencies: r4-live-core.js (env, root, one,
// txt, button, all, put, jobs, flush) and r4-account-flows.js (copyFlowTree).
// No generator, account-model builder, shared component, or existing gate edits.
// Run once per theme after final-links has set QueryFailed retry to q[2].
async function repairFailureSourceStage(theme) {
  if (!['Light', 'Dark'].includes(theme)) throw Error('Expected Light or Dark.');
  const e = await env(theme);
  if (jobs.size) throw Error('Flush or inspect pending authoring jobs before this local repair.');
  const prefix = 'R4/' + theme + '/';
  const required = (node, description) => {
    if (!node || node.removed) throw Error('Query-failure source repair missing ' + description);
    return node;
  };
  const exactRoot = key => {
    const matches = e.branch.children.filter(n => n.name === prefix + key);
    if (matches.length !== 1 || matches[0].type !== 'FRAME' || matches[0].visible === false) {
      throw Error('Expected one visible local frame: ' + prefix + key);
    }
    const node = matches[0];
    if (e.registry.get(node.name) !== node) throw Error('Stale registry for ' + node.name);
    return node;
  };
  const exactButton = (frame, caption) => {
    const matches = frame.findAll(n => n.name === 'Button/' + caption);
    if (matches.length !== 1) throw Error('Expected one ' + caption + ' button in ' + frame.name);
    const node = matches[0];
    if (!txt(node).some(n => n.characters === caption)) throw Error('Unexpected button label: ' + node.name);
    return node;
  };
  const action = (node, trigger) => {
    required(node, trigger + ' reaction source');
    const reactions = node.reactions || [];
    if (reactions.length !== 1 || reactions[0].trigger?.type !== trigger) {
      throw Error('Unexpected ' + trigger + ' reaction on ' + node.name);
    }
    const r = reactions[0], actions = r.actions || (r.action ? [r.action] : []);
    if (actions.length !== 1) throw Error('Expected one action on ' + node.name);
    return { r, a: actions[0] };
  };
  const nodeLink = (node, destination, navigation, trigger = 'ON_CLICK') => {
    const { r, a } = action(node, trigger);
    if (a.type !== 'NODE' || a.destinationId !== destination.id || a.navigation !== navigation) {
      throw Error('Unexpected destination or navigation on ' + node.name);
    }
    if (trigger === 'AFTER_TIMEOUT' && !(r.trigger.timeout > 0)) throw Error('Missing transition delay on ' + node.name);
  };
  const closeLink = (node, trigger = 'ON_CLICK') => {
    if (action(node, trigger).a.type !== 'CLOSE') throw Error('Expected overlay close on ' + node.name);
  };
  const net = (key, suffix) => exactRoot(theme + ' · R4 NET · ' + key + ' · ' + suffix);
  const passText = node => {
    if (!txt(node).some(n => n.characters === '当前评分 51，符合高于 50 的通过条件')) {
      throw Error('Expected valid score 51 pass condition in ' + node.name);
    }
  };
  const checkChain = (key, next) => {
    const a = net(key, '检查中 A'), b = net(key, '检查中 B');
    const passed = net(key, '评分 51 · 检查通过');
    nodeLink(a, b, 'SWAP', 'AFTER_TIMEOUT');
    nodeLink(b, passed, 'SWAP', 'AFTER_TIMEOUT');
    nodeLink(passed, next, 'SWAP', 'AFTER_TIMEOUT');
    closeLink(exactButton(a, '取消')); closeLink(exactButton(b, '取消'));
    passText(passed);
    return { a, b, passed };
  };
  const workSnapshot = source => {
    const content = required(one(source, 'Content'), source.name + ' Content');
    const cards = content.children.filter(n => n.name.startsWith('Quota/') && n.visible !== false);
    if (cards.length !== 4) throw Error('Expected the unchanged four-account source.');
    const identities = cards.map(card => txt(card).filter(n => n.characters.includes('@')).map(n => n.characters));
    for (const email of ['alin.claude@example.com', 'alin.codex@example.com', 'work.codex@example.com', 'alin.cursor@example.com']) {
      if (identities.filter(group => group.includes(email)).length !== 1) throw Error('Source account identity mismatch: ' + email);
    }
    const card = required(cards.find(n => n.name === 'Quota/Codex · work'), 'work Codex source card');
    const values = txt(card).filter(n => n.name.startsWith('Value/')).map(n => n.characters);
    if (JSON.stringify(values) !== JSON.stringify(['70%', '85%'])) throw Error('Source work quota is not 70% / 85%.');
    const updated = required(one(card, 'Detail updated'), 'work last successful update').characters;
    if (!updated.includes('上次成功更新 09:41')) throw Error('Source work update must remain 09:41.');
    return { accounts: identities.flat(), account: 'work.codex@example.com', values, updated };
  };

  // All existing nodes, score semantics and recovery links are checked before
  // any root is cloned. The cached q[2] index is read without flowCommon(),
  // whose fallback could otherwise generate unrelated account paths.
  const hub = exactRoot('Network/Review');
  if (!txt(hub).some(n => n.characters === '设计评审 · 所有结果均为模拟')) throw Error('Expected a design-review-only hub.');
  const opener = exactButton(hub, '检查通过后 · 额度查询失败');
  const querying = exactRoot('Network/Querying'), failed = exactRoot('Network/QueryFailed');
  if (!txt(querying).some(n => n.characters === 'work.codex@example.com') ||
      !txt(failed).some(n => n.characters === 'work.codex@example.com') ||
      !txt(failed).some(n => n.characters === '保留上次成功数据 · 09:41')) throw Error('Query-failure account or retained timestamp mismatch.');
  const gate = checkChain('Query failure', querying);
  nodeLink(querying, failed, 'SWAP', 'AFTER_TIMEOUT');
  closeLink(exactButton(querying, '取消')); closeLink(exactButton(failed, '关闭'));
  let common;
  try { common = JSON.parse(e.branch.getPluginData('r4_flow_common')); }
  catch (_) { throw Error('Missing completed shared query index.'); }
  const retryQuery = exactRoot('AccountFlow/Query/2'), retryDone = exactRoot('AccountFlow/Done/2');
  const retryGate = checkChain('Account query 2', retryQuery);
  if (common?.q?.[2] !== retryGate.a.id) throw Error('Cached q[2] does not identify the existing work-account gate.');
  nodeLink(exactButton(failed, '重试'), retryGate.a, 'SWAP');
  nodeLink(retryQuery, retryDone, 'SWAP', 'AFTER_TIMEOUT');
  closeLink(exactButton(retryQuery, '取消')); closeLink(exactButton(retryDone, '关闭'));
  closeLink(retryDone, 'AFTER_TIMEOUT');
  const source = required(e.dashboard, 'base15.d');
  if (source.name !== theme + '/Dashboard' || source.parent !== e.review) throw Error('Unexpected base15 source root.');
  const snapshot = workSnapshot(source);
  if ((source.reactions || []).some(r => r.trigger?.type === 'AFTER_TIMEOUT')) throw Error('Source has an unexpected automatic transition.');
  for (const name of ['Action/link', 'Action/refresh']) {
    const control = required(one(source, name), 'source ' + name);
    if (!(control.reactions || []).length) throw Error('Source control is not wired: ' + name);
  }
  for (const card of one(source, 'Content').children.filter(n => n.name.startsWith('Quota/') && n.visible !== false)) {
    for (const name of ['Action/more', 'Expand account']) {
      const control = required(one(card, name), card.name + ' ' + name);
      if (!(control.reactions || []).length) throw Error('Source account control is not wired: ' + card.name + ' ' + name);
    }
  }
  const key = 'Network/QueryFailureLaunch', name = prefix + key;
  const existing = e.branch.children.filter(n => n.name === name);
  if (existing.length) {
    const launch = exactRoot(key);
    nodeLink(opener, launch, 'NAVIGATE');
    nodeLink(launch, gate.a, 'OVERLAY', 'AFTER_TIMEOUT');
    workSnapshot(launch);
    return { status: theme + ' 查询失败来源修复已存在并通过预检', changed: false, launch: launch.id, source: source.id, gate: gate.a.id, snapshot };
  }
  nodeLink(opener, gate.a, 'OVERLAY');
  const sourceBefore = JSON.stringify(all(source).map(n => ({ id: n.id, text: n.type === 'TEXT' ? n.characters : null, reactions: n.reactions || [] })));
  const openerBefore = JSON.parse(JSON.stringify(opener.reactions));
  const rootCount = e.branch.children.length;
  const launch = root(e, source, key);
  await copyFlowTree(source, launch);
  // Replace only this new root's inherited root reaction. All cloned controls
  // keep their current account targets; the original source remains untouched.
  put(launch, gate.a, 'OVERLAY', { timeout: .15 });
  put(opener, launch, 'NAVIGATE');
  const allowed = new Set([opener, ...all(launch)]);
  if ([...jobs.keys()].some(n => !allowed.has(n))) throw Error('Unexpected pending write outside the local repair.');
  await flush();
  if (e.branch.children.length !== rootCount + 1) throw Error('Unexpected root count change.');
  if (sourceBefore !== JSON.stringify(all(source).map(n => ({ id: n.id, text: n.type === 'TEXT' ? n.characters : null, reactions: n.reactions || [] })))) throw Error('Original source changed unexpectedly.');
  return { status: theme + ' 查询失败现可在保留旧数据的来源上评审', changed: true,
    createdRootCount: 1, createdRoot: { id: launch.id, name: launch.name },
    existingControlsChanged: [{ id: opener.id, before: openerBefore, destination: launch.id, navigation: 'NAVIGATE' }],
    source: source.id, snapshot: workSnapshot(launch), gate: gate.a.id, passed: gate.passed.id,
    querying: querying.id, failed: failed.id, retry: retryGate.a.id, retrySuccess: retryDone.id,
    launchDelaySeconds: .15, closeBehavior: 'CLOSE keeps the launch background and its 70% / 85%, 09:41 snapshot.',
    preserved: ['base15 source', 'existing check/query/retry/close paths', 'product controls', 'shared components', 'delivery manifest'] };
}
