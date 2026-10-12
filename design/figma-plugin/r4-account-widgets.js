// Append after r4-live-core.js and r4-account-foundation.js.
// One ready Home per mask and a separate Home per pending account; caller flushes.
async function accountWidgetHome(e, m) {
  const records = Array.isArray(R4A) ? R4A : R4A.records;
  if (!e || !m || !Number.isInteger(m.mask) || !Array.isArray(m.accounts) || !records) throw Error('Invalid account widget model');
  const required = (n, what) => { if (!n) throw Error('Account widget missing ' + what); return n; };
  const record = idx => required(records[idx], 'record ' + idx);
  const order = [...m.accounts];
  order.forEach(idx => record(idx));
  if (new Set(order).size !== order.length) throw Error('Duplicate account in widget order');
  const resolve = preferred => order.includes(preferred) ? preferred :
    (order.find(idx => record(idx).p === record(preferred).p) ?? order[0] ?? null);
  const selected = [resolve(2), resolve(3)];
  const kind = (k, size) => e.roots.find(n =>
    (n.name === e.t + '/' + k || n.name.split('|')[1] === k) && (!size || n.name.endsWith('|' + size)));
  const sourceHome = required(kind('SystemHome', 'small'), 'R3 small SystemHome');
  const review = required(kind('WidgetReview', 'small'), 'R3 small WidgetReview');
  const sample = required(one(review, 'Widget canvas'), 'R3 widget canvas').children.find(n => n.name.startsWith('Widget/'));
  required(sample, 'R3 small widget');
  const viewData = selected.map(idx => {
    if (idx === null) return { idx: null };
    const a = record(idx), base = record(a.baseIx ?? idx);
    const sourceCard = required(one(e.dashboard, 'Quota/' + base.k), a.email + ' R3 source card');
    const modelCard = one(m.d, 'Quota/' + a.k);
    const provider = required(one(sourceCard, 'Provider/' + a.p), a.p + ' provider');
    const icon = required(provider.children.find(n => n.type === 'INSTANCE' || n.type === 'FRAME'), a.p + ' icon');
    const names = sourceCard.children.filter(n => n.name.startsWith('Window/')).map(n => n.name.slice(7));
    if (!Array.isArray(a.v) || names.length !== a.v.length || !Array.isArray(a.reset) || a.reset.length !== a.v.length) throw Error('Quota window mismatch for ' + a.email);
    if (a.v.some(v => !Number.isFinite(v) || v < 0 || v > 100)) throw Error('Invalid remaining quota for ' + a.email);
    const pending = m.pendingIdx === idx;
    const updated = pending ? '未获取' : (modelCard && one(modelCard, 'Detail updated')?.characters.match(/\d{2}:\d{2}/)?.[0]) || '未更新';
    const destination = m.widgetDetails?.[idx] || m.details?.[idx];
    required(destination, a.email + ' widget detail destination (widgetDetails or details)');
    const navigation = m.widgetNavigation?.[idx] || 'NAVIGATE';
    if (!['NAVIGATE','OVERLAY'].includes(navigation)) throw Error('Unsupported widget navigation for ' + a.email + ': ' + navigation);
    return { idx, a, icon, names, pending, updated, destination, navigation };
  });
  const pendingIdx = Number.isInteger(m.pendingIdx) ? m.pendingIdx : null;
  if (pendingIdx !== null && !order.includes(pendingIdx)) throw Error('Pending widget account is not bound: ' + pendingIdx);
  const key = 'AccountWidgets/Set-' + m.mask + (pendingIdx === null ? '' : '/Pending-' + pendingIdx), name = 'R4/' + e.t + '/' + key;
  const signature = JSON.stringify({ version: 2, mask: m.mask, order, pendingIdx, dashboard: m.d.id,
    widgets: viewData.map(d => d.idx === null ? { idx: null } :
      { idx: d.idx, email: d.a.email, values: d.a.v, reset: d.a.reset, money: d.a.money || null,
        pending: d.pending, updated: d.updated, destination: d.destination.id, navigation: d.navigation }) });
  const existing = e.registry.get(name);
  if (existing && existing.getPluginData('r4_account_widget_signature') === signature) return existing;
  const home = root(e, sourceHome, key);
  clear(home);
  const container = required(one(home, 'Home widgets'), 'home widget container');
  for (const child of [...container.children]) child.remove();
  container.layoutMode = 'HORIZONTAL';container.primaryAxisSizingMode = 'FIXED';container.counterAxisSizingMode = 'AUTO';
  container.itemSpacing = 16;container.resize(361, 164);
  const editable = n => {
    if (n.type !== 'INSTANCE') return n;
    const detached = n.detachInstance();for (const child of all(detached)) made.add(child.id);return detached;
  };
  const widgetIds = [];
  for (let position = 0; position < viewData.length; position++) {
    const data = viewData[position];
    const widget = editable(clone(sample, container, 'AccountWidget/' + position + '/' + (data.idx ?? 'Empty')));
    widget.name = 'AccountWidget/' + position + '/' + (data.idx ?? 'Empty');
    widget.resize(164, 164);widget.primaryAxisSizingMode = 'FIXED';widget.counterAxisSizingMode = 'FIXED';
    widget.itemSpacing = 6;widget.clipsContent = true;widgetIds.push(widget.id);
    if (data.idx === null) {
      for (const child of [...widget.children]) child.remove();widget.primaryAxisAlignItems = 'CENTER';
      const message = label(e, widget, '未连接账号，无数据', 13);message.textAlignHorizontal = 'CENTER';
      put(widget, m.d);continue;
    }
    const a = data.a, width = widget.width - widget.paddingLeft - widget.paddingRight;
    const header = required(one(widget, 'Widget header'), 'widget header');
    const headerTexts = header.children.filter(n => n.type === 'TEXT');
    const platform = required(headerTexts[0], 'platform text'), time = required(headerTexts[1], 'updated text');
    header.resize(width, 16);header.primaryAxisSizingMode = 'FIXED';header.counterAxisSizingMode = 'FIXED';header.itemSpacing = 4;
    for (const child of [...header.children]) if (child.type !== 'TEXT') child.remove();
    const icon = clone(data.icon, header, a.p + ' logo');icon.rescale(16 / icon.width);header.insertChild(0, icon);
    change(platform, a.p);platform.textAutoResize = 'WIDTH_AND_HEIGHT';platform.layoutGrow = 1;
    change(time, data.updated);time.textAutoResize = 'WIDTH_AND_HEIGHT';time.layoutGrow = 0;
    const identity = clone(platform, widget, 'Widget account');identity.layoutGrow = 0;
    identity.fontSize = 10;identity.lineHeight = { unit: 'PIXELS', value: 14 };
    change(identity, a.email.split('@')[0]);identity.textAutoResize = 'HEIGHT';identity.resize(width, 14);widget.insertChild(1, identity);
    // Remove every template-specific extra label, amount and duplicate identity.
    for (const child of [...widget.children]) if (child.type === 'TEXT' && child !== identity) child.remove();
    const windows = widget.children.filter(n => n.name.startsWith('Widget window/'));
    if (data.pending) {
      // A bound account awaiting its first query has no trustworthy quota or reset.
      windows.forEach(n => n.remove());
      const message = label(e, widget, '未获取额度', 13, 'Widget pending quota');
      message.resize(width, message.height);
    } else {
      if (windows.length < a.v.length) throw Error('R3 widget has too few windows');
      windows.forEach((window, i) => {
        if (i >= a.v.length) { window.remove();return; }
        window.name = 'Widget window/' + data.names[i];window.resize(width, window.height);
        const metric = required(one(window, 'Metric'), 'widget metric'), fields = metric.children.filter(n => n.type === 'TEXT');
        metric.resize(width, metric.height);change(required(fields[0], 'window name'), data.names[i]);
        change(required(fields[1], 'remaining value'), '剩余 ' + a.v[i] + '%');
        fields[0].layoutGrow = 1;fields[1].layoutGrow = 0;fields[1].textAutoResize = 'WIDTH_AND_HEIGHT';
        const track = required(one(window, 'Widget progress'), 'used track');track.resize(width, track.height);
        const bar = required(track.children.find(n => n.type === 'RECTANGLE'), 'used bar');
        bar.visible = a.v[i] < 100;if (bar.visible) bar.resize(width * (100 - a.v[i]) / 100, bar.height);
        const reset = required(window.children.find(n => n.type === 'TEXT'), 'reset text');
        change(reset, a.reset[i] + '重置');reset.textAutoResize = 'HEIGHT';reset.resize(width, 14);
      });
      if (a.money) { const money = clone(identity, widget, 'Widget amount');change(money, a.money);money.resize(width, 14); }
    }
    put(widget, data.destination, data.navigation);
  }
  const back = one(home, 'Action/back');if (back) put(back, m.d);
  const indicator = one(home, 'Home indicator') || home.children.find(n => n.type === 'RECTANGLE' && Math.abs(n.width - 134) < 1 && n.height < 8);
  if (indicator) put(indicator, m.d);
  const apps = one(home, 'Apps'), app = apps && apps.children[0];
  if (app) {
    app.name = 'App/订阅额度';const caption = app.children.find(n => n.type === 'TEXT');if (caption) change(caption, '订阅额度');put(app, m.d);
  }
  const hint = txt(home).find(n => n.characters === '轻点小组件，打开对应账户');
  if (hint) change(hint, '轻点小组件，打开对应账号');
  home.setPluginData('r4_account_widget_state', JSON.stringify({ mask: m.mask, order, preferred: [2, 3], selected,
    pendingIdx, widgets: widgetIds,
    targets: viewData.map(d => d.idx === null ? m.d.id : d.destination.id),
    navigation: viewData.map(d => d.idx === null ? 'NAVIGATE' : d.navigation) }));
  home.setPluginData('r4_account_widget_signature', signature);
  return home;
}
