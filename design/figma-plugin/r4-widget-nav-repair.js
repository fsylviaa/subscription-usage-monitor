// Local repair of existing Widgets roots only. No root creation or stage rebuild.
// The inspected R3 Navigation template is 393x48 with manual positioning:
// back (12,2,44,44), heading (74,11); Dashboard's heading instead starts at x=16.
async function repairWidgetNavigationStage(t) {
  const e = await env(t), prefix = 'R4/' + t + '/Widgets/';
  const roots = [...e.registry.values()].filter(n => !n.removed && n.name.startsWith(prefix));
  if (!roots.length) throw Error('No existing ' + t + ' Widgets roots to repair');
  const localName = n => n.name.slice(prefix.length);
  const navigationRoots = roots.filter(n => /^(Detail\/|Accounts\/)/.test(localName(n)) || localName(n) === 'EmptyGuide');
  const confirmations = roots.filter(n => localName(n).startsWith('Disconnect/'));
  const confirmationIds = new Map(confirmations.map(n => [n.id, n]));
  const required = (n, name) => { if (!n) throw Error('Widget repair missing ' + name);return n; };
  const actionsOf = reaction => reaction.actions || (reaction.action ? [reaction.action] : []);
  const copyReaction = reaction => { const result = JSON.parse(JSON.stringify(reaction));delete result.action;result.actions = JSON.parse(JSON.stringify(actionsOf(reaction)));return result; };
  const geometry = n => ({ id:n.id, name:n.name, x:n.x, y:n.y, width:n.width, height:n.height, visible:n.visible, layoutMode:n.layoutMode, layoutGrow:n.layoutGrow });
  // Preflight the precise known structures and destinations before any writes.
  const navPlans = navigationRoots.map(root => {
    const nav = required(one(root, 'Navigation'), root.name + ' Navigation');
    const backs = nav.children.filter(n => n.name === 'Action/back');
    if (backs.length !== 1) throw Error('Expected one return button in ' + root.name + ', got ' + backs.length);
    const heading = required(nav.children.find(n => n.type === 'TEXT'), root.name + ' heading');
    return { root, nav, back:backs[0], heading, before:{ nav:geometry(nav), back:geometry(backs[0]), heading:geometry(heading), order:nav.children.map(n=>n.name) } };
  });
  const confirmPlans = confirmations.map(root => {
    const sheet = required(one(root, 'Sheet'), root.name + ' Sheet');
    const confirm = required(button(root, '断开连接'), root.name + ' confirm');
    const cancel = required(button(root, '取消'), root.name + ' cancel');
    const x = required(one(sheet, 'Action/close'), root.name + ' close');
    const scrim = required(root.children.find(n => n.type === 'RECTANGLE' && Math.abs(n.width-root.width)<1 && Math.abs(n.height-root.height)<1), root.name + ' full-screen scrim');
    const confirmActions = confirm.reactions.flatMap(actionsOf).filter(a => a.type === 'NODE');
    if (confirmActions.length !== 1 || confirmActions[0].navigation !== 'NAVIGATE') throw Error('Unexpected confirm action in ' + root.name);
    const result = roots.find(n => n.id === confirmActions[0].destinationId && localName(n).startsWith('Home/'));
    if (!result) throw Error('Confirm does not target an existing local widget Home: ' + root.name);
    return { root, sheet, confirm, cancel, x, scrim, indicator:one(sheet,'Home indicator'), result,
      confirmBefore:JSON.stringify(confirm.reactions) };
  });
  const triggerPlans = [];
  for (const root of roots) for (const n of all(root)) {
    if (!('reactions' in n) || !n.reactions.length) continue;
    const changed = [];
    const reactions = n.reactions.map(r => {
      const match = actionsOf(r).some(a => a.type === 'NODE' && confirmationIds.has(a.destinationId));
      if (!match) return copyReaction(r);
      const out = copyReaction(r);
      for (const a of out.actions) if (a.type === 'NODE' && confirmationIds.has(a.destinationId)) {
        if (!['NAVIGATE','OVERLAY'].includes(a.navigation)) throw Error('Unexpected confirmation open mode: '+a.navigation);
        changed.push({target:a.destinationId,before:a.navigation});a.navigation='OVERLAY';a.resetScrollPosition=false;
      }
      return out;
    });
    if (changed.length) triggerPlans.push({n,root,reactions,changed});
  }
  for (const plan of confirmPlans) if (!triggerPlans.some(p=>p.changed.some(c=>c.target===plan.root.id))) throw Error('No local opener for ' + plan.root.name);
  const navResults = [];
  for (const p of navPlans) {
    // A horizontal 393x48 navigation row reproduces the source back/title x
    // positions while preventing reparented buttons from keeping canvas x/y.
    p.nav.layoutMode='HORIZONTAL';p.nav.primaryAxisSizingMode='FIXED';p.nav.counterAxisSizingMode='FIXED';
    p.nav.resize(393,48);p.nav.paddingLeft=12;p.nav.paddingRight=16;p.nav.paddingTop=p.nav.paddingBottom=0;
    p.nav.itemSpacing=18;p.nav.primaryAxisAlignItems='MIN';p.nav.counterAxisAlignItems='CENTER';
    for (const child of p.nav.children) {
      if (['R3/Header actions','Action/refresh','Action/link'].includes(child.name)) {child.visible=false;writes.add(child.id);}
    }
    p.back.visible=true;p.back.layoutPositioning='AUTO';p.back.layoutGrow=0;p.back.layoutAlign='INHERIT';p.back.resize(44,44);
    p.heading.visible=true;p.heading.layoutPositioning='AUTO';p.heading.layoutGrow=1;p.heading.layoutAlign='INHERIT';
    p.heading.textAutoResize='HEIGHT';p.heading.textAlignHorizontal='LEFT';p.heading.resize(303,Math.max(26,p.heading.height));
    p.nav.insertChild(0,p.back);p.nav.insertChild(1,p.heading);
    writes.add(p.nav.id);writes.add(p.back.id);writes.add(p.heading.id);
    // Existing CLOSE versus NAVIGATE semantics are intentionally preserved.
    navResults.push({root:p.root.id,name:p.root.name,before:p.before,after:{nav:geometry(p.nav),back:geometry(p.back),heading:geometry(p.heading),order:p.nav.children.map(n=>n.name)}});
  }
  for (const p of triggerPlans) {jobs.set(p.n,p.reactions);writes.add(p.n.id);}
  for (const p of confirmPlans) {
    close(p.cancel);close(p.x);close(p.scrim);if(p.indicator)close(p.indicator);
  }
  await flush();
  for (const p of confirmPlans) if (JSON.stringify(p.confirm.reactions)!==p.confirmBefore) throw Error('Confirm destination changed unexpectedly: '+p.root.name);
  const result = {status:t+' 小组件返回导航与断开弹层已局部修复',createdRootCount:0,
    navigationCount:navResults.length,navigation:navResults,
    openers:triggerPlans.map(p=>({node:p.n.id,name:p.n.name,root:p.root.id,changes:p.changed.map(c=>({...c,after:'OVERLAY'}))})),
    confirmations:confirmPlans.map(p=>({id:p.root.id,name:p.root.name,result:p.result.id,confirm:p.confirm.id,confirmAction:'NAVIGATE preserved',closeNodes:[p.cancel,p.x,p.scrim,p.indicator].filter(Boolean).map(n=>n.id)}))};
  e.branch.setPluginData('r4_widget_navigation_repair',JSON.stringify({version:1,navigationCount:navResults.length,confirmationCount:confirmPlans.length}));
  return result;
}
