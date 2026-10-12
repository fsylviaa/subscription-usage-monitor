// Existing-state review entry only. Preflights both themes before writing.
// Dependencies: r4-live-core.js. Creates at most four review buttons, no roots,
// state chains, product controls, component masters, or account data.
async function repairAppAutoEntryStage() {
  const caption = '进入 App · 自动更新';
  const retainedCaption = '后台更新 · 超时后重试';
  const environments = [await env('Light'), await env('Dark')];
  if (jobs.size) throw Error('Inspect or flush pending jobs before adding review entries.');
  const actions = r => r.actions || (r.action ? [r.action] : []);
  const requireLink = (source, target, trigger = 'ON_CLICK') => {
    const reactions = source && source.reactions || [];
    const a = reactions.length === 1 ? actions(reactions[0]) : [];
    if (reactions.length !== 1 || reactions[0].trigger?.type !== trigger || a.length !== 1 ||
        a[0].type !== 'NODE' || a[0].navigation !== 'NAVIGATE' || a[0].destinationId !== target.id) {
      throw Error('Unexpected existing navigation: ' + (source?.name || 'missing source'));
    }
  };
  const plans = environments.map(e => {
    const get = key => {
      const name = 'R4/' + e.t + '/' + key;
      const matches = e.branch.children.filter(n => n.name === name && n.type === 'FRAME' && n.visible !== false);
      if (matches.length !== 1 || e.registry.get(name) !== matches[0]) throw Error('Expected one current root: ' + name);
      return matches[0];
    };
    const states = Object.fromEntries(['CheckA', 'CheckB', 'Passed', 'Querying', 'Success', 'Failed']
      .map(state => [state, get('Background/App/' + state)]));
    for (const [from, to] of [['CheckA', 'CheckB'], ['CheckB', 'Passed'], ['Passed', 'Querying'], ['Querying', 'Success']]) {
      requireLink(states[from], states[to], 'AFTER_TIMEOUT');
    }
    const statusText = (state, expected) => {
      const inline = one(states[state], 'R4/Background inline status');
      if (!inline || !txt(inline).some(n => n.characters === expected)) throw Error('Unexpected inline App state: ' + e.t + '/' + state);
    };
    statusText('CheckA', '正在检查网络'); statusText('CheckB', '正在检查网络');
    statusText('Passed', '网络检查通过 · 当前评分 51');
    statusText('Querying', '正在查询额度'); statusText('Success', '上次成功更新 09:45');
    statusText('Failed', '未更新 · 网络检查超时');
    const directories = [get('Review'), e.entry].map(directory => {
      if (!directory || directory.type !== 'FRAME' || directory.visible === false) throw Error('Missing current review directory.');
      if (!txt(directory).some(n => n.characters.includes('设计评审专用') && n.characters.includes('不属于产品界面'))) {
        throw Error('Expected the final design-review directory: ' + directory.name);
      }
      const body = one(directory, 'Content');
      if (!body || body.layoutMode !== 'VERTICAL') throw Error('Unexpected review layout: ' + directory.name);
      const old = body.children.filter(n => n.name === 'Button/' + retainedCaption);
      const existing = body.children.filter(n => n.name === 'Button/' + caption);
      if (old.length !== 1 || existing.length > 1) throw Error('Unexpected review-entry count: ' + directory.name);
      requireLink(old[0], states.Failed);
      if (existing.length) requireLink(existing[0], states.CheckA);
      return { directory, body, retained: old[0], before: JSON.stringify(old[0].reactions), existing: existing[0] || null };
    });
    return { e, states, directories, rootCount: e.branch.children.length };
  });
  const entries = [], added = [];
  for (const p of plans) for (const d of p.directories) {
    let control = d.existing;
    if (!control) {
      control = addButton(p.e, d.body, caption);
      d.body.insertChild(d.body.children.indexOf(d.retained), control);
      put(control, p.states.CheckA, 'NAVIGATE'); added.push(control.id);
    }
    entries.push({ theme: p.e.t, directory: d.directory.id, button: control.id, label: caption,
      target: p.states.CheckA.id, targetName: p.states.CheckA.name, navigation: 'NAVIGATE',
      retainedTimeoutButton: d.retained.id, retainedTimeoutTarget: p.states.Failed.id,
      passed: p.states.Passed.id, querying: p.states.Querying.id, success: p.states.Success.id,
      created: !d.existing });
  }
  if (added.length) await flush();
  for (const p of plans) {
    if (p.e.branch.children.length !== p.rootCount) throw Error('Unexpected state-root creation.');
    for (const d of p.directories) if (JSON.stringify(d.retained.reactions) !== d.before) throw Error('Existing timeout entry changed.');
  }
  return { status: '浅深进入 App 自动更新的设计评审入口已补齐', createdRootCount: 0,
    createdReviewButtonCount: added.length, entries,
    scope: 'Only a new review button in each existing original/R4 directory. Existing CheckA → CheckB → Passed → Querying → Success chain and timeout/retry entry are unchanged.',
    actualClickValidation: 'pending; this native write receipt does not establish an observed prototype run' };
}
