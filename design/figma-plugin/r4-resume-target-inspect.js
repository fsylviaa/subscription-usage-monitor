// Standalone bounded READ-ONLY resume inspection. Not added to r4-live.js.
// Call inspectR4ResumeTargets() after loading this module exactly once.
// Only figma.getNodeByIdAsync and local node reads; no env/init/font/page,
// canvas selection, pluginData, reaction writes, cloning, removal or layout edits.
// Scope: 37 saved R4 bad-source nodes; 22 exact roots including both Settings-denied
// roots and both shared Home/Config pairs. No old full Audit.
const R4_RESUME_INSPECT_ROOTS = [{"id": "46:140983", "name": "R4/Light/Widgets/Detail/B"}, {"id": "46:141286", "name": "R4/Light/Widgets/Detail/C"}, {"id": "46:141589", "name": "R4/Light/Widgets/Detail/D"}, {"id": "46:144327", "name": "R4/Light/Widgets/Accounts/ABCD"}, {"id": "46:144914", "name": "R4/Light/Widgets/Accounts/ABD"}, {"id": "46:145413", "name": "R4/Light/Widgets/Accounts/AD"}, {"id": "46:146479", "name": "R4/Light/Widgets/Accounts/ABCDE"}, {"id": "46:147154", "name": "R4/Light/Widgets/Accounts/ABDE"}, {"id": "53:893425", "name": "R4/Light/AccountSystem/Set-15/Settings-denied"}, {"id": "46:151344", "name": "R4/Dark/Widgets/Detail/B"}, {"id": "46:151647", "name": "R4/Dark/Widgets/Detail/C"}, {"id": "46:151950", "name": "R4/Dark/Widgets/Detail/D"}, {"id": "46:154688", "name": "R4/Dark/Widgets/Accounts/ABCD"}, {"id": "46:155275", "name": "R4/Dark/Widgets/Accounts/ABD"}, {"id": "46:155774", "name": "R4/Dark/Widgets/Accounts/AD"}, {"id": "46:156840", "name": "R4/Dark/Widgets/Accounts/ABCDE"}, {"id": "46:157515", "name": "R4/Dark/Widgets/Accounts/ABDE"}, {"id": "53:895028", "name": "R4/Dark/AccountSystem/Set-15/Settings-denied"}, {"id": "46:142410", "name": "R4/Light/Widgets/Home/Config/small/C"}, {"id": "46:142344", "name": "R4/Light/Widgets/Config/small/C"}, {"id": "46:152771", "name": "R4/Dark/Widgets/Home/Config/small/C"}, {"id": "46:152705", "name": "R4/Dark/Widgets/Config/small/C"}];
const R4_RESUME_INSPECT_SOURCES = [{"rootId": "46:140983", "root": "R4/Light/Widgets/Detail/B", "nodeId": "46:147874", "path": "$/Scroll viewport/Content/Quota/Codex/Card header/Expand account", "sourceVisible": true, "destinationId": "14:42236", "navigation": "NAVIGATE", "group": "visible_widget_detail_expand"}, {"rootId": "46:140983", "root": "R4/Light/Widgets/Detail/B", "nodeId": "46:147882", "path": "$/Scroll viewport/Content/Quota/Codex/Card header/Action/more", "sourceVisible": false, "destinationId": "14:42237", "navigation": "OVERLAY", "group": "hidden_widget_more"}, {"rootId": "46:141286", "root": "R4/Light/Widgets/Detail/C", "nodeId": "46:147966", "path": "$/Scroll viewport/Content/Quota/Codex · work/Card header/Expand account", "sourceVisible": true, "destinationId": "14:42236", "navigation": "NAVIGATE", "group": "visible_widget_detail_expand"}, {"rootId": "46:141286", "root": "R4/Light/Widgets/Detail/C", "nodeId": "46:147974", "path": "$/Scroll viewport/Content/Quota/Codex · work/Card header/Action/more", "sourceVisible": false, "destinationId": "14:42237", "navigation": "OVERLAY", "group": "hidden_widget_more"}, {"rootId": "46:141589", "root": "R4/Light/Widgets/Detail/D", "nodeId": "46:148048", "path": "$/Scroll viewport/Content/Quota/Cursor/Card header/Expand account", "sourceVisible": true, "destinationId": "14:42238", "navigation": "NAVIGATE", "group": "visible_widget_detail_expand"}, {"rootId": "46:141589", "root": "R4/Light/Widgets/Detail/D", "nodeId": "46:148056", "path": "$/Scroll viewport/Content/Quota/Cursor/Card header/Action/more", "sourceVisible": false, "destinationId": "14:42239", "navigation": "OVERLAY", "group": "hidden_widget_more"}, {"rootId": "46:144327", "root": "R4/Light/Widgets/Accounts/ABCD", "nodeId": "46:149137", "path": "$/Scroll viewport/Content/Quota/Codex/Card header/Action/more", "sourceVisible": false, "destinationId": "14:42237", "navigation": "OVERLAY", "group": "hidden_widget_more"}, {"rootId": "46:144327", "root": "R4/Light/Widgets/Accounts/ABCD", "nodeId": "46:149303", "path": "$/Scroll viewport/Content/Quota/Cursor/Card header/Action/more", "sourceVisible": false, "destinationId": "14:42239", "navigation": "OVERLAY", "group": "hidden_widget_more"}, {"rootId": "46:144914", "root": "R4/Light/Widgets/Accounts/ABD", "nodeId": "46:149558", "path": "$/Scroll viewport/Content/Quota/Cursor/Card header/Action/more", "sourceVisible": false, "destinationId": "14:42239", "navigation": "OVERLAY", "group": "hidden_widget_more"}, {"rootId": "46:145413", "root": "R4/Light/Widgets/Accounts/AD", "nodeId": "46:149725", "path": "$/Scroll viewport/Content/Quota/Cursor/Card header/Action/more", "sourceVisible": false, "destinationId": "14:42239", "navigation": "OVERLAY", "group": "hidden_widget_more"}, {"rootId": "46:146479", "root": "R4/Light/Widgets/Accounts/ABCDE", "nodeId": "46:150169", "path": "$/Scroll viewport/Content/Quota/Codex/Card header/Action/more", "sourceVisible": false, "destinationId": "14:42237", "navigation": "OVERLAY", "group": "hidden_widget_more"}, {"rootId": "46:146479", "root": "R4/Light/Widgets/Accounts/ABCDE", "nodeId": "46:150335", "path": "$/Scroll viewport/Content/Quota/Cursor/Card header/Action/more", "sourceVisible": false, "destinationId": "14:42239", "navigation": "OVERLAY", "group": "hidden_widget_more"}, {"rootId": "46:146479", "root": "R4/Light/Widgets/Accounts/ABCDE", "nodeId": "46:150405", "path": "$/Scroll viewport/Content/Quota/Codex · backup/Card header/Expand account", "sourceVisible": true, "destinationId": "14:42236", "navigation": "NAVIGATE", "group": "visible_backup_expand"}, {"rootId": "46:146479", "root": "R4/Light/Widgets/Accounts/ABCDE", "nodeId": "46:150413", "path": "$/Scroll viewport/Content/Quota/Codex · backup/Card header/Action/more", "sourceVisible": false, "destinationId": "14:42237", "navigation": "OVERLAY", "group": "hidden_widget_more"}, {"rootId": "46:147154", "root": "R4/Light/Widgets/Accounts/ABDE", "nodeId": "46:150600", "path": "$/Scroll viewport/Content/Quota/Codex/Card header/Action/more", "sourceVisible": false, "destinationId": "14:42237", "navigation": "OVERLAY", "group": "hidden_widget_more"}, {"rootId": "46:147154", "root": "R4/Light/Widgets/Accounts/ABDE", "nodeId": "46:150678", "path": "$/Scroll viewport/Content/Quota/Cursor/Card header/Action/more", "sourceVisible": false, "destinationId": "14:42239", "navigation": "OVERLAY", "group": "hidden_widget_more"}, {"rootId": "46:147154", "root": "R4/Light/Widgets/Accounts/ABDE", "nodeId": "46:150748", "path": "$/Scroll viewport/Content/Quota/Codex · backup/Card header/Expand account", "sourceVisible": true, "destinationId": "14:42236", "navigation": "NAVIGATE", "group": "visible_backup_expand"}, {"rootId": "46:147154", "root": "R4/Light/Widgets/Accounts/ABDE", "nodeId": "46:150756", "path": "$/Scroll viewport/Content/Quota/Codex · backup/Card header/Action/more", "sourceVisible": false, "destinationId": "14:42237", "navigation": "OVERLAY", "group": "hidden_widget_more"}, {"rootId": "53:893425", "root": "R4/Light/AccountSystem/Set-15/Settings-denied", "nodeId": "53:893478", "path": "$/Scroll viewport/Content/Group/通用/Row/额度显示", "sourceVisible": false, "destinationId": "1:2249", "navigation": "OVERLAY", "group": "hidden_display_preference"}, {"rootId": "46:151344", "root": "R4/Dark/Widgets/Detail/B", "nodeId": "46:151601", "path": "$/Scroll viewport/Content/Quota/Codex/Card header/Expand account", "sourceVisible": true, "destinationId": "14:42698", "navigation": "NAVIGATE", "group": "visible_widget_detail_expand"}, {"rootId": "46:151344", "root": "R4/Dark/Widgets/Detail/B", "nodeId": "46:151609", "path": "$/Scroll viewport/Content/Quota/Codex/Card header/Action/more", "sourceVisible": false, "destinationId": "14:42699", "navigation": "OVERLAY", "group": "hidden_widget_more"}, {"rootId": "46:151647", "root": "R4/Dark/Widgets/Detail/C", "nodeId": "46:151904", "path": "$/Scroll viewport/Content/Quota/Codex · work/Card header/Expand account", "sourceVisible": true, "destinationId": "14:42698", "navigation": "NAVIGATE", "group": "visible_widget_detail_expand"}, {"rootId": "46:151647", "root": "R4/Dark/Widgets/Detail/C", "nodeId": "46:151912", "path": "$/Scroll viewport/Content/Quota/Codex · work/Card header/Action/more", "sourceVisible": false, "destinationId": "14:42699", "navigation": "OVERLAY", "group": "hidden_widget_more"}, {"rootId": "46:151950", "root": "R4/Dark/Widgets/Detail/D", "nodeId": "46:152197", "path": "$/Scroll viewport/Content/Quota/Cursor/Card header/Expand account", "sourceVisible": true, "destinationId": "14:42700", "navigation": "NAVIGATE", "group": "visible_widget_detail_expand"}, {"rootId": "46:151950", "root": "R4/Dark/Widgets/Detail/D", "nodeId": "46:152205", "path": "$/Scroll viewport/Content/Quota/Cursor/Card header/Action/more", "sourceVisible": false, "destinationId": "14:42701", "navigation": "OVERLAY", "group": "hidden_widget_more"}, {"rootId": "46:154688", "root": "R4/Dark/Widgets/Accounts/ABCD", "nodeId": "46:155045", "path": "$/Scroll viewport/Content/Quota/Codex/Card header/Action/more", "sourceVisible": false, "destinationId": "14:42699", "navigation": "OVERLAY", "group": "hidden_widget_more"}, {"rootId": "46:154688", "root": "R4/Dark/Widgets/Accounts/ABCD", "nodeId": "46:155211", "path": "$/Scroll viewport/Content/Quota/Cursor/Card header/Action/more", "sourceVisible": false, "destinationId": "14:42701", "navigation": "OVERLAY", "group": "hidden_widget_more"}, {"rootId": "46:155275", "root": "R4/Dark/Widgets/Accounts/ABD", "nodeId": "46:155710", "path": "$/Scroll viewport/Content/Quota/Cursor/Card header/Action/more", "sourceVisible": false, "destinationId": "14:42701", "navigation": "OVERLAY", "group": "hidden_widget_more"}, {"rootId": "46:155774", "root": "R4/Dark/Widgets/Accounts/AD", "nodeId": "46:156121", "path": "$/Scroll viewport/Content/Quota/Cursor/Card header/Action/more", "sourceVisible": false, "destinationId": "14:42701", "navigation": "OVERLAY", "group": "hidden_widget_more"}, {"rootId": "46:156840", "root": "R4/Dark/Widgets/Accounts/ABCDE", "nodeId": "46:157197", "path": "$/Scroll viewport/Content/Quota/Codex/Card header/Action/more", "sourceVisible": false, "destinationId": "14:42699", "navigation": "OVERLAY", "group": "hidden_widget_more"}, {"rootId": "46:156840", "root": "R4/Dark/Widgets/Accounts/ABCDE", "nodeId": "46:157363", "path": "$/Scroll viewport/Content/Quota/Cursor/Card header/Action/more", "sourceVisible": false, "destinationId": "14:42701", "navigation": "OVERLAY", "group": "hidden_widget_more"}, {"rootId": "46:156840", "root": "R4/Dark/Widgets/Accounts/ABCDE", "nodeId": "46:157433", "path": "$/Scroll viewport/Content/Quota/Codex · backup/Card header/Expand account", "sourceVisible": true, "destinationId": "14:42698", "navigation": "NAVIGATE", "group": "visible_backup_expand"}, {"rootId": "46:156840", "root": "R4/Dark/Widgets/Accounts/ABCDE", "nodeId": "46:157441", "path": "$/Scroll viewport/Content/Quota/Codex · backup/Card header/Action/more", "sourceVisible": false, "destinationId": "14:42699", "navigation": "OVERLAY", "group": "hidden_widget_more"}, {"rootId": "46:157515", "root": "R4/Dark/Widgets/Accounts/ABDE", "nodeId": "46:157872", "path": "$/Scroll viewport/Content/Quota/Codex/Card header/Action/more", "sourceVisible": false, "destinationId": "14:42699", "navigation": "OVERLAY", "group": "hidden_widget_more"}, {"rootId": "46:157515", "root": "R4/Dark/Widgets/Accounts/ABDE", "nodeId": "46:157950", "path": "$/Scroll viewport/Content/Quota/Cursor/Card header/Action/more", "sourceVisible": false, "destinationId": "14:42701", "navigation": "OVERLAY", "group": "hidden_widget_more"}, {"rootId": "46:157515", "root": "R4/Dark/Widgets/Accounts/ABDE", "nodeId": "46:158020", "path": "$/Scroll viewport/Content/Quota/Codex · backup/Card header/Expand account", "sourceVisible": true, "destinationId": "14:42698", "navigation": "NAVIGATE", "group": "visible_backup_expand"}, {"rootId": "46:157515", "root": "R4/Dark/Widgets/Accounts/ABDE", "nodeId": "46:158028", "path": "$/Scroll viewport/Content/Quota/Codex · backup/Card header/Action/more", "sourceVisible": false, "destinationId": "14:42699", "navigation": "OVERLAY", "group": "hidden_widget_more"}];
function r4ResumeVisible(node) {
  for (let n = node; n && n.type !== 'DOCUMENT'; n = n.parent) if (n.visible === false) return false;
  return true;
}
function r4ResumePath(node, rootId) {
  const parts = [];
  for (let n = node; n && n.id !== rootId && n.type !== 'DOCUMENT'; n = n.parent) {
    const peers = n.parent && 'children' in n.parent ? n.parent.children.filter(c => c.name === n.name) : [];
    const i = peers.findIndex(c => c.id === n.id);
    parts.push(n.name + (i > 0 ? '[' + i + ']' : ''));
  }
  return '$' + (parts.length ? '/' + parts.reverse().join('/') : '');
}
function r4ResumeNorm(value) { return String(value).replace(/Light|Dark/g, '{theme}').replace(/浅色|深色/g, '{主题}'); }
function r4ResumeStable(value) {
  if (Array.isArray(value)) return value.map(r4ResumeStable);
  if (value && typeof value === 'object') {
    const out = {}; for (const k of Object.keys(value).sort()) out[k] = r4ResumeStable(value[k]); return out;
  }
  return typeof value === 'string' ? r4ResumeNorm(value) : value;
}
async function inspectR4ResumeTargets() {
  const started = new Date().toISOString(), sections = {Light:'1:43252',Dark:'1:43254'};
  const targets = new Map(), results = [], sourceResults = [], allSources = new Map(R4_RESUME_INSPECT_SOURCES.map(s => [s.nodeId,s]));
  async function destination(id) {
    if (targets.has(id)) return targets.get(id);
    let n = null; try { n = await figma.getNodeByIdAsync(id); } catch (_) {}
    if (!n || n.removed) { const v = {id,missing:true}; targets.set(id,v); return v; }
    let owner = n;
    while (owner.parent && !['PAGE','SECTION','DOCUMENT'].includes(owner.parent.type)) owner = owner.parent;
    const v = {id,name:n.name,type:n.type,visible:r4ResumeVisible(n),localVisible:n.visible !== false,
      parentId:n.parent?.id,ownerId:owner.id,owner:owner.name,path:r4ResumePath(n,owner.id),
      canonical:r4ResumeNorm(owner.name)+'/'+r4ResumeNorm(r4ResumePath(n,owner.id))};
    targets.set(id,v); return v;
  }
  async function actionInfo(value, canonicalOnly = false) {
    if (Array.isArray(value)) { const out = []; for (const v of value) out.push(await actionInfo(v,canonicalOnly)); return out; }
    if (!value || typeof value !== 'object') return canonicalOnly ? r4ResumeStable(value) : value;
    const out = {};
    for (const k of Object.keys(value).sort()) {
      if (k === 'destinationId') {
        const t = await destination(value[k]);
        if (canonicalOnly) out.destination = t.missing ? 'MISSING/'+value[k] : t.canonical;
        else { out.destinationId = value[k]; out.destination = t; }
      } else out[k] = await actionInfo(value[k],canonicalOnly);
    }
    return out;
  }
  for (const spec of R4_RESUME_INSPECT_ROOTS) {
    const root = await figma.getNodeByIdAsync(spec.id), theme = spec.name.includes('/Light/') ? 'Light' : 'Dark';
    if (!root || root.removed) { results.push({id:spec.id,expectedName:spec.name,missing:true}); continue; }
    const result = {id:root.id,name:root.name,type:root.type,localVisible:root.visible !== false,visible:r4ResumeVisible(root),parentId:root.parent?.id,
      scopeMatches:root.name === spec.name && root.type === 'FRAME' && root.parent?.id === sections[theme],
      size:[root.width,root.height],nodes:0,visibleTexts:[],reactions:[],context:[]};
    const stack = [{n:root,path:'$',ancestorVisible:r4ResumeVisible(root.parent)}];
    while (stack.length) {
      if (result.nodes >= 12000) throw Error('Unexpected >12000 nodes in bounded root '+root.id+'; no partial result accepted');
      const item = stack.pop(), n = item.n, visible = item.ancestorVisible && n.visible !== false;
      result.nodes++;
      const reactions = 'reactions' in n ? n.reactions || [] : [];
      const loc = {id:n.id,name:n.name,path:item.path,type:n.type,localVisible:n.visible !== false,visible};
      if (n.type === 'TEXT' && visible) result.visibleTexts.push({id:n.id,path:item.path,text:n.characters});
      if (/^(Navigation|Action\/back|Action\/close|Row\/额度显示|Group\/通用|Expand account|Action\/more|Icon\/down|Account details|Home indicator|Home widgets|App\/订阅额度|Button\/完成|Quota\/|Account\/)/.test(n.name)) {
        result.context.push({...loc,reactionCount:reactions.length,children:'children' in n?n.children.map(c=>({id:c.id,name:c.name,type:c.type,localVisible:c.visible!==false})):undefined});
      }
      if (reactions.length) {
        result.reactions.push({...loc,reactions:await actionInfo(reactions),canonicalReactions:await actionInfo(reactions,true)});
      }
      if (allSources.has(n.id)) {
        const saved = allSources.get(n.id), actions = [];
        for (const r of reactions) for (const a of r.actions || (r.action ? [r.action] : [])) actions.push(a);
        sourceResults.push({saved,current:{...loc,rootId:root.id,reactions:await actionInfo(reactions)},
          savedDestinationStillPresent:actions.some(a=>a.type==='NODE'&&a.destinationId===saved.destinationId&&a.navigation===saved.navigation),
          savedVisibilityMatches:visible===saved.sourceVisible});
      }
      if ('children' in n) {
        const names = new Map(), children = [];
        for (const child of n.children) { const count = names.get(child.name)||0; names.set(child.name,count+1);children.push({n:child,path:item.path+'/'+child.name+(count?'['+count+']':''),ancestorVisible:visible}); }
        for (let i=children.length-1;i>=0;i--) stack.push(children[i]);
      }
    }
    results.push(result);
  }
  const [light,dark] = ['53:893425','53:895028'].map(id=>results.find(r=>r.id===id));
  const themeReactionDiff = [];
  if (light?.reactions && dark?.reactions) {
    const map = root=>new Map(root.reactions.map(r=>[r4ResumeNorm(r.path),r]));
    const lm=map(light),dm=map(dark);
    for (const path of new Set([...lm.keys(),...dm.keys()])) {
      const a=lm.get(path),b=dm.get(path);
      const av=a?{visible:a.visible,reactions:a.canonicalReactions}:null,bv=b?{visible:b.visible,reactions:b.canonicalReactions}:null;
      if(JSON.stringify(r4ResumeStable(av))!==JSON.stringify(r4ResumeStable(bv))) themeReactionDiff.push({path,light:a?{id:a.id,...av}:null,dark:b?{id:b.id,...bv}:null});
    }
  }
  return {status:'Bounded read-only resume inspection; no repair or click validation',started,finished:new Date().toISOString(),
    requestedRootCount:R4_RESUME_INSPECT_ROOTS.length,readRootCount:results.filter(r=>!r.missing).length,
    requestedSourceCount:R4_RESUME_INSPECT_SOURCES.length,foundSourceCount:sourceResults.length,
    missingSourceIds:R4_RESUME_INSPECT_SOURCES.filter(s=>!sourceResults.some(r=>r.saved.nodeId===s.nodeId)).map(s=>s.nodeId),
    mutationCount:0,sampleTruncation:0,results,sourceResults,themeReactionDiff};
}
