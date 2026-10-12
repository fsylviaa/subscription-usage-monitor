// R4 background/network author stage. Uses only the helpers in r4-live-core.js.
// No scoring request, account access, app code, or source-component mutation.
// Each appearance adds exactly 12 roots: 6 App states and 6 widget states.
// Failure is the review starting point. The separate review retry entry models
// a new automatic/widget update; it is not a product simulation control.
async function backgroundStage(t) {
  const e = await env(t);
  if (e.registry.has('R4/' + t + '/Background/App/Failed')) {
    throw Error('Background stage exists. Inspect before retry.');
  }
  const home = e.roots.find(n => n.name.includes('|SystemHome|') && n.name.endsWith('|medium'));
  if (!home || !one(home, 'Widget/Claude')) throw Error('Missing R3 medium Claude SystemHome template.');

  const screens = [];
  const widgetTargets = [];
  const states = ['Failed', 'CheckA', 'CheckB', 'Passed', 'Querying', 'Success'];
  const makeRoot = (src, key) => {
    const n = root(e, src, 'Background/' + key);
    screens.push(n);
    const viewport = one(n, 'Scroll viewport');
    if (viewport) viewport.overflowDirection = 'VERTICAL';
    return n;
  };
  const addDots = (parent, phase) => {
    const row = frame(parent, 'Network progress', parent.width - (parent.paddingLeft || 0) - (parent.paddingRight || 0));
    row.layoutMode = 'HORIZONTAL';
    row.primaryAxisSizingMode = 'FIXED';
    row.counterAxisSizingMode = 'AUTO';
    row.itemSpacing = 5;
    const shade = t === 'Dark' ? .94 : .09;
    for (let i = 0; i < 3; i++) {
      const dot = figma.createEllipse();
      row.appendChild(dot);
      made.add(dot.id);
      dot.name = 'Progress dot ' + i;
      dot.resize(4, 4);
      dot.fills = [{ type: 'SOLID', color: { r: shade, g: shade, b: shade } }];
      dot.opacity = i === phase ? 1 : .22;
    }
  };
  const buttonRow = parent => {
    const row = frame(parent, 'Network actions', parent.width - (parent.paddingLeft || 0) - (parent.paddingRight || 0));
    row.layoutMode = 'HORIZONTAL';
    row.primaryAxisSizingMode = 'FIXED';
    row.counterAxisSizingMode = 'AUTO';
    row.itemSpacing = 8;
    return row;
  };
  const compactButton = (row, title) => {
    const b = addButton(e, row, title, false);
    b.resize(76, 36);
    return b;
  };
  const appText = {
    Failed: ['未更新 · 网络检查超时', '无法完成网络检查 · 上次成功更新 09:41'],
    CheckA: ['正在检查网络', 'Net.Coffee · Claude AI 信任评分 · 上次成功 09:41'],
    CheckB: ['正在检查网络', 'Net.Coffee · Claude AI 信任评分 · 上次成功 09:41'],
    Passed: ['网络检查通过 · 当前评分 51', '符合高于 50 的条件，继续查询 · 上次成功 09:41'],
    Querying: ['正在查询额度', '上次成功更新 09:41'],
    Success: ['已更新', '上次成功更新 09:45'],
  };
  const app = {};
  for (const state of states) {
    const n = makeRoot(e.dashboard, 'App/' + state);
    app[state] = n;
    const body = one(n, 'Content');
    if (!body || body.layoutMode !== 'VERTICAL') throw Error('App content must use vertical auto layout.');
    body.primaryAxisSizingMode = 'AUTO';
    const block = frame(body, 'R4/Background inline status', 361);
    body.insertChild(0, block);
    block.itemSpacing = 4;
    block.paddingLeft = block.paddingRight = 12;
    block.paddingTop = block.paddingBottom = 10;
    block.cornerRadius = 12;
    const fill = t === 'Dark' ? .16 : .95;
    block.fills = [{ type: 'SOLID', color: { r: fill, g: fill, b: fill } }];
    if (state === 'CheckA' || state === 'CheckB' || state === 'Querying') addDots(block, state === 'CheckA' ? 0 : 1);
    label(e, block, appText[state][0], 13, 'Network status title');
    label(e, block, appText[state][1], 11, 'Network status detail');
    if (state === 'Failed') {
      const actions = buttonRow(block);
      compactButton(actions, '重试');
      compactButton(actions, '关闭');
    }
    if (state === 'Success') {
      for (const text of txt(n)) {
        if (text.characters.includes('上次成功更新 09:41')) change(text, text.characters.replace('上次成功更新 09:41', '上次成功更新 09:45'));
      }
    }
    const settings = one(n, 'Tab/设置');
    if (settings) put(settings, e.settings);
    const link = one(n, 'Action/link');
    if (link) put(link, e.connect, 'OVERLAY');
    const tutorial = one(n, 'Action/如何添加小组件');
    const tutorialTarget = e.roots.find(r => r.name.includes('|Tutorial1a|'));
    if (tutorial && tutorialTarget) put(tutorial, tutorialTarget);
  }
  put(button(app.Failed, '重试'), app.CheckA);
  // Closing this inline error restores the original cached dashboard. It does
  // not clear its accounts, quota values, or 09:41 last-success timestamps.
  put(button(app.Failed, '关闭'), e.dashboard);
  for (const n of Object.values(app)) {
    const refresh = one(n, 'Action/refresh');
    if (refresh) put(refresh, app.CheckA);
  }
  put(app.CheckA, app.CheckB, 'NAVIGATE', { timeout: .45, smart: true });
  put(app.CheckB, app.Passed, 'NAVIGATE', { timeout: .55, smart: true });
  put(app.Passed, app.Querying, 'NAVIGATE', { timeout: .35 });
  put(app.Querying, app.Success, 'NAVIGATE', { timeout: .9 });

  const widgetText = {
    Failed: '未更新 · 评分网站不可用 · 上次成功 09:41',
    CheckA: '检查网络 ···  上次成功 09:41',
    CheckB: '检查网络 ···  上次成功 09:41',
    Passed: '评分 51 > 50 · 检查通过 · 上次成功 09:41',
    Querying: '正在查询额度 · 上次成功 09:41',
    Success: '已更新 · 09:45',
  };
  const widget = {};
  for (const state of states) {
    const n = makeRoot(home, 'Widget/' + state);
    widget[state] = n;
    let content = one(n, 'Widget/Claude');
    if (!content) throw Error('Missing widget in cloned SystemHome.');
    // Detach only this newly-created local instance, never its shared master.
    // The existing 164px widget has room for one small footer row.
    if (content.type === 'INSTANCE') {
      content = content.detachInstance();
      all(content).forEach(v => made.add(v.id));
    }
    content.name = 'Widget/Claude';
    content.itemSpacing = 5;
    const footer = frame(content, 'R4/Widget update status', content.width - content.paddingLeft - content.paddingRight);
    footer.itemSpacing = 2;
    if (state === 'CheckA' || state === 'CheckB' || state === 'Querying') addDots(footer, state === 'CheckA' ? 0 : 1);
    label(e, footer, widgetText[state], 9, 'Widget network status');
    // Keep the footer within the original widget footprint. This changes only
    // the detached review instance and leaves quota content and bar ratios intact.
    const used = content.children.filter(x => x.visible).reduce((sum, x) => sum + x.height, 0)
      + Math.max(0, content.children.filter(x => x.visible).length - 1) * content.itemSpacing
      + content.paddingTop + content.paddingBottom;
    if (used > content.height + .5) content.itemSpacing = 3;
    const widgetUsed = content.children.filter(x => x.visible).reduce((sum, x) => sum + x.height, 0)
      + Math.max(0, content.children.filter(x => x.visible).length - 1) * content.itemSpacing
      + content.paddingTop + content.paddingBottom;
    if (widgetUsed > content.height + .5) throw Error('Widget inline state exceeds original footprint: ' + state);
    const oldTime = one(one(content, 'Widget header'), '刚刚');
    if (oldTime) change(oldTime, state === 'Success' ? '09:45' : '09:41');
    put(content, e.dashboard);
    widgetTargets.push({ node: content.id, destination: e.dashboard.id, account: 'alin.claude@example.com', state });
    const returnButton = one(n, 'Action/back');
    if (returnButton) put(returnButton, e.entry);
  }
  put(widget.CheckA, widget.CheckB, 'NAVIGATE', { timeout: .45, smart: true });
  put(widget.CheckB, widget.Passed, 'NAVIGATE', { timeout: .55, smart: true });
  put(widget.Passed, widget.Querying, 'NAVIGATE', { timeout: .35 });
  put(widget.Querying, widget.Success, 'NAVIGATE', { timeout: .9 });

  const entries = [
    { label: '进入 App · 后台检查超时', start: app.Failed.id, result: app.Failed.id, retryStart: app.CheckA.id, passed: app.Passed.id, querying: app.Querying.id, success: app.Success.id, closeTarget: e.dashboard.id, mode: 'background' },
    { label: '小组件 · 检查网站不可用', start: widget.Failed.id, result: widget.Failed.id, retryStart: widget.CheckA.id, passed: widget.Passed.id, querying: widget.Querying.id, success: widget.Success.id, mode: 'widget' },
    { label: '小组件 · 系统再次更新后评分 51', start: widget.CheckA.id, reviewOnly: true, mode: 'widget' },
  ];
  await flush();
  report.stages.push(t + '/background');
  return {
    status: t + ' 后台与小组件更新阶段完成',
    entries,
    widgetTargets,
    screens: screens.map(n => ({ id: n.id, name: n.name })),
    createdNodeIds: [...made],
    mutatedNodeIds: [...writes],
    reviewNote: '入口直接展示已失败状态；重试完整表达检查 A/B、51 通过、额度查询中和成功。小组件再次联网由评审入口模拟系统调度，产品组件内没有模拟或重试绕过按钮。',
  };
}
