// Incremental native Figma authoring. No account or scoring service access.
const SCOPE=['1:43251','1:43252','1:43253','1:43254'];
let page,secs,busy=false,fontReady=false;
const writes=new Set(),made=new Set(),jobs=new Map(),themes={};
const report={stages:[],screens:[],links:[]};
function all(n){return [n,...('findAll'in n?n.findAll():[])];}
function one(n,name){return n&&n.findOne(x=>x.name===name);}
function txt(n){return n.findAllWithCriteria({types:['TEXT']});}
function mark(n){writes.add(n.id);return n;}
function change(n,s){if(!n)throw Error('Missing text');mark(n).characters=s;}
function clear(n){for(const v of all(n))if('reactions'in v&&v.reactions.length)jobs.set(v,[]);}
function clone(src,par,name){const n=src.clone();par.appendChild(n);n.name=name;all(n).forEach(v=>made.add(v.id));clear(n);return n;}
function put(n,d,nav='NAVIGATE',o={}){if(!n||!d)throw Error('Missing link');if(nav==='NAVIGATE'){for(let a=n;a&&a.type!=='PAGE';a=a.parent)if(a===d){jobs.set(n,[]);writes.add(n.id);return;}}jobs.set(n,[{trigger:o.timeout?{type:'AFTER_TIMEOUT',timeout:o.timeout}:{type:'ON_CLICK'},actions:[{type:'NODE',destinationId:d.id,navigation:nav,transition:{type:o.smart?'SMART_ANIMATE':'DISSOLVE',easing:{type:'EASE_OUT'},duration:o.smart?.24:.18},resetScrollPosition:nav==='NAVIGATE',resetInteractiveComponents:false}]}]);writes.add(n.id);}
function close(n,o={}){if(!n)throw Error('Missing close');jobs.set(n,[{trigger:o.timeout?{type:'AFTER_TIMEOUT',timeout:o.timeout}:{type:'ON_CLICK'},actions:[{type:'CLOSE'}]}]);writes.add(n.id);}
function back(n){jobs.set(n,[{trigger:{type:'ON_CLICK'},actions:[{type:'BACK'}]}]);writes.add(n.id);}
// Only reaction definitions are concurrent. Nodes/targets already exist, and
// every source has one final queued value. Never unlock with writes in flight.
async function flush(){
 const snapshot=[...jobs];
 for(let start=0;start<snapshot.length;start+=8){
  const batch=snapshot.slice(start,start+8);
  const settled=await Promise.allSettled(batch.map(async([n,r])=>{if(!n.removed)await n.setReactionsAsync(r);}));
  const failed=settled.map((result,i)=>({result,node:batch[i][0]})).filter(item=>item.result.status==='rejected');
  if(failed.length)throw Error('Reaction batch failed ('+failed.length+'): '+failed.slice(0,3).map(item=>item.node.id+' '+String(item.result.reason)).join('; '));
 }
 // New/replaced jobs are not covered by the completed snapshot. Keep the
 // entire queue for an idempotent retry; completion tags must not be committed.
 if(jobs.size!==snapshot.length||snapshot.some(([n,r])=>!jobs.has(n)||jobs.get(n)!==r))throw Error('Reaction queue changed during flush; pending jobs retained for retry');
 jobs.clear();figma.commitUndo();
}
async function init(){if(secs)return;page=await figma.getNodeByIdAsync('0:1');await figma.setCurrentPageAsync(page);secs=await Promise.all(SCOPE.map(id=>figma.getNodeByIdAsync(id)));if(secs.some(n=>!n||n.type!=='SECTION'))throw Error('Scope mismatch');}
async function fonts(){if(fontReady)return;await init();for(const f of [{family:'PingFang SC',style:'Regular'},{family:'PingFang SC',style:'Medium'},{family:'PingFang SC',style:'Semibold'},{family:'Inter',style:'Semi Bold'}]){figma.ui.postMessage({status:'载入字体 '+f.family+' '+f.style,progress:true});await Promise.race([figma.loadFontAsync(f),new Promise((_,reject)=>setTimeout(()=>reject(Error('Font timeout '+f.family+' '+f.style)),15000))]);}fontReady=true;}
async function env(t){if(themes[t])return themes[t];await fonts();const i=t==='Light'?0:2,review=secs[i],branch=secs[i+1],roots=review.children.filter(n=>n.type==='FRAME'&&n.visible);function kind(k){return roots.find(n=>n.name===t+'/'+k||n.name.split('|')[1]===k);}
const e={t,review,branch,roots,connect:kind('Connect'),entry:kind('Review'),dashboard:roots.find(n=>n.name===t+'/Dashboard'),settings:roots.find(n=>n.name===t+'/Settings'),logins:{},registry:new Map()};for(const p of['Claude','Codex','Cursor'])e.logins[p]=roots.find(n=>n.name.includes('|Login|')&&n.name.includes('|'+p+'|'));e.primary=one(e.logins.Claude,'Button/继续');e.secondary=one(e.logins.Claude,'Button/取消');for(const n of branch.children)if(n.name.startsWith('R4/'))e.registry.set(n.name,n);themes[t]=e;return e;}
function root(e,src,key){const name='R4/'+e.t+'/'+key;if(e.registry.has(name))return e.registry.get(name);const n=clone(src,e.branch,name);n.visible=true;const i=e.registry.size;n.x=32+(i%12)*433;n.y=80650+Math.floor(i/12)*904;e.registry.set(name,n);const width=Math.max(e.branch.width,5260),height=Math.max(e.branch.height,n.y+930);if(width>e.branch.width||height>e.branch.height)e.branch.resizeWithoutConstraints(width,height);report.screens.push({id:n.id,name:n.name});return n;}
function frame(parent,name,w=353){const n=figma.createFrame();parent.appendChild(n);made.add(n.id);n.name=name;n.resize(w,10);n.layoutMode='VERTICAL';n.primaryAxisSizingMode='AUTO';n.counterAxisSizingMode='FIXED';n.itemSpacing=12;n.fills=[];return n;}
function label(e,parent,s,size=14,name){const n=figma.createText();parent.appendChild(n);made.add(n.id);n.fontName={family:'PingFang SC',style:'Regular'};n.fontSize=size;n.lineHeight={unit:'PIXELS',value:Math.ceil(size*1.45)};const c=e.t==='Dark'?.94:.09;n.fills=[{type:'SOLID',color:{r:c,g:c,b:c}}];n.characters=s;n.name=name||s;n.textAutoResize='HEIGHT';n.resize(parent.width-(parent.paddingLeft||0)-(parent.paddingRight||0),Math.ceil(size*1.45));return n;}
function button(f,s){return one(f,'Button/'+s);}
function addButton(e,par,s,primary=false){const n=clone(primary?e.primary:e.secondary,par,'Button/'+s);change(txt(n)[0],s);n.resize(par.width-(par.paddingLeft||0)-(par.paddingRight||0),44);return n;}
function resizeSheet(f){const sh=one(f,'Sheet'),vp=one(sh,'Sheet viewport'),body=one(vp,'Content');const h=116+body.height;sh.resize(393,h);sh.y=852-h;vp.resize(393,h-96);const home=one(sh,'Home indicator');if(home)home.y=h-14;}
function panel(e,key,title,lines,buttons){const n=root(e,e.connect,key);const sh=one(n,'Sheet');change(one(sh,'Sheet heading').children.find(n=>n.type==='TEXT'),title);const vp=one(sh,'Sheet viewport');const old=one(vp,'Content');if(old)old.remove();const b=frame(vp,'Content',393);b.paddingLeft=b.paddingRight=20;b.paddingTop=8;b.paddingBottom=20;for(const line of lines)label(e,b,line);buttons.forEach((s,i)=>addButton(e,b,s,i===0&&buttons.length>1));resizeSheet(n);close(one(sh,'Action/close'));close(n.children.find(n=>n.type==='RECTANGLE'));return n;}
function progress(e,n,phase){const b=one(one(n,'Sheet'),'Content'),row=frame(b,'Network progress',353);b.insertChild(0,row);row.layoutMode='HORIZONTAL';row.primaryAxisSizingMode='FIXED';row.counterAxisSizingMode='AUTO';row.itemSpacing=6;for(let i=0;i<3;i++){const dot=figma.createEllipse();row.appendChild(dot);made.add(dot.id);dot.name='Progress dot '+i;dot.resize(5,5);const c=e.t==='Dark'?.94:.09;dot.fills=[{type:'SOLID',color:{r:c,g:c,b:c}}];dot.opacity=i===phase?1:.25;}resizeSheet(n);}
function networkEnv(e){return {t:e.t,panel:(key,title,lines,buttons)=>panel(e,key,title,lines,buttons),button,close,go:(n,d,o)=>put(n,d,'SWAP',o),status:(n,s,phase)=>progress(e,n,phase)};}
async function network(e,key,next,operation,outcome='51'){return await buildNetworkFlow(networkEnv(e),{key,source:e.dashboard,next,operation,outcome,mode:'foreground',overlay:true});}
function hub(e,key,title){const n=root(e,e.entry,key);const b=one(n,'Content');for(const c of [...b.children])c.remove();b.itemSpacing=8;label(e,b,title,22);label(e,b,'设计评审 · 所有结果均为模拟',12);one(n,'Scroll viewport').overflowDirection='VERTICAL';const bk=one(n,'Action/back');if(bk)put(bk,e.entry);return n;}
async function networkStage(t){const e=await env(t);if(e.registry.has('R4/'+t+'/Network/Review'))throw Error('Network stage exists. Inspect before retry.');const h=hub(e,'Network/Review','网络检查与失败恢复');const b=one(h,'Content');const login=root(e,e.logins.Codex,'Network/Login');for(const n of txt(login))if(n.characters.includes('@'))change(n,'backup.codex@example.com');close(button(login,'取消'));close(one(login,'Action/close'));close(login.children.find(n=>n.type==='RECTANGLE'));
const auth=panel(e,'Network/Authorization','正在连接 Codex',['平台授权 · 交互示意'],['取消']);close(button(auth,'取消'));progress(e,auth,1);const failed=panel(e,'Network/AuthFailed','授权未完成',['未添加新账号。已有账号保持不变。'],['重新尝试','取消']);close(button(failed,'取消'));put(button(login,'继续'),auth,'SWAP');put(auth,failed,'SWAP',{timeout:1});const retry=await network(e,'Authorization retry',login,'添加 Codex 账号');put(button(failed,'重新尝试'),retry.start,'SWAP');
const entries=[];for(const outcome of['49','50','51','timeout','unavailable','invalid']){const flow=await network(e,'Review '+outcome,login,'添加 Codex 账号',outcome);const s={49:'评分 49 · 阻止新增',50:'评分 50 · 阻止新增',51:'评分 51 · 继续授权',timeout:'检查超时',unavailable:'评分网站不可用',invalid:'没有有效评分'}[outcome];put(addButton(e,b,s),flow.start,'OVERLAY');entries.push({label:s,start:flow.start.id,result:flow.result.id});}
const q=panel(e,'Network/Querying','正在查询额度',['work.codex@example.com'],['取消']);close(button(q,'取消'));progress(e,q,1);const qf=panel(e,'Network/QueryFailed','额度查询失败',['平台暂未返回额度','work.codex@example.com','保留上次成功数据 · 09:41'],['重试','关闭']);close(button(qf,'关闭'));put(q,qf,'SWAP',{timeout:1});const qgate=await network(e,'Query failure',q,'work.codex@example.com 的额度查询');put(button(qf,'重试'),qgate.start,'SWAP');put(addButton(e,b,'检查通过后 · 额度查询失败'),qgate.start,'OVERLAY');put(addButton(e,b,'检查通过后 · 授权失败'),retry.start,'OVERLAY');put(addButton(e,b,'返回评审入口'),e.entry);await flush();report.stages.push(t+'/network');return {status:t+' 网络阶段完成',hub:h.id,entries,createdNodeIds:[...made],mutatedNodeIds:[...writes],screens:report.screens};}
async function inspect(target){await init();const ns=target?await Promise.all(target.split(',').map(id=>figma.getNodeByIdAsync(id.trim()))):secs;return{status:'读取完成',nodes:ns.map(n=>({id:n.id,name:n.name,type:n.type,visible:n.visible,count:n.children?.length,children:n.children?.map(c=>({id:c.id,name:c.name,visible:c.visible})),texts:n.type==='FRAME'?txt(n).map(t=>({id:t.id,text:t.characters})):undefined,reactions:n.type==='FRAME'?all(n).filter(x=>'reactions'in x&&x.reactions.length).map(x=>({id:x.id,name:x.name,reactions:x.reactions})):undefined}))};}
async function gallery(target){const ids=target.split(',');const out=[];for(const id of ids){const n=await figma.getNodeByIdAsync(id.trim());figma.ui.postMessage({status:'导出 '+n.name,progress:true});out.push({id:n.id,name:n.name,bytes:Array.from(await n.exportAsync({format:'PNG',constraint:{type:'SCALE',value:1}}))});}figma.ui.postMessage({status:'截图完成',gallery:out});}


// R4 v2 local Figma author helper. This file never contacts a scoring service.
// It only asks env.panel to create lightweight content; it never clones source.
// The caller supplies a reviewed outcome before building a branch; outcome
// selectors belong to the design-review index, never to a product frame.
//
// env.panel(name, title, lines, buttonLabels, source, mode) -> Frame | Promise<Frame>
// env.go(node, destinationFrame, { timeout?: seconds, smart?: boolean })
// env.button(frame, label) -> SceneNode
// env.status(frame, text, phase) -> void | Promise<void>
// env.close(buttonNode) -> void | Promise<void> (required for cfg.overlay=true)
// env.t -> 'Light' | 'Dark'
// cfg.overlay=true uses native overlay close reactions for dismiss buttons.
// env.go owns OPEN_OVERLAY/SWAP/NAVIGATE behavior and animation destinations.
//
// Result: start, passed, and result are Frames; passed is null for a failed
// first attempt. retry is null or a successful retry-flow result. frames
// contains every generated Frame, including the retry sequence.
async function buildNetworkFlow(env, cfg) {
  const allowedOutcomes = ['51', '49', '50', 'timeout', 'unavailable', 'invalid'];
  const allowedModes = ['foreground', 'background', 'widget'];
  if (!cfg || !cfg.key || !cfg.source || !cfg.next || !cfg.operation) {
    throw new Error('Network flow requires key, source, next, and operation.');
  }
  if (!allowedOutcomes.includes(cfg.outcome) || !allowedModes.includes(cfg.mode)) {
    throw new Error('Unrecognized network outcome or presentation mode.');
  }
  for (const name of ['panel', 'go', 'button', 'status']) {
    if (typeof env[name] !== 'function') throw new Error('Missing network helper: ' + name);
  }
  if (cfg.overlay === true && typeof env.close !== 'function') {
    throw new Error('Overlay network flow requires env.close(buttonNode).');
  }

  const prefix = env.t + ' · R4 NET · ' + cfg.key;
  const mode = cfg.mode;
  const frames = [];
  const dismiss = mode === 'foreground' ? '取消' : mode === 'widget' ? '返回' : '关闭';
  const checkingTitle = mode === 'foreground' ? '正在检查网络' : '更新前检查网络';
  const checkingLines = [cfg.operation, 'Net.Coffee · Claude AI 信任评分'];
  const make = async (suffix, title, lines, labels) => {
    const frame = await env.panel(prefix + ' · ' + suffix, title, lines, labels, cfg.source, mode);
    frames.push(frame);
    return frame;
  };
  const connectButton = async (frame, label, destination) => {
    const target = env.button(frame, label);
    if (!target) throw new Error('Network frame missing button: ' + label);
    await env.go(target, destination, { smart: false });
  };
  const connectDismiss = async frame => {
    const target = env.button(frame, dismiss);
    if (!target) throw new Error('Network frame missing button: ' + dismiss);
    if (cfg.overlay === true) await env.close(target);
    else await env.go(target, cfg.source, { smart: false });
  };

  // Equivalent layers and phase-based opacity allow a restrained Smart Animate
  // transition. The status helper owns the three-dot treatment and colors.
  const start = await make('检查中 A', checkingTitle, checkingLines, [dismiss]);
  const checkingB = await make('检查中 B', checkingTitle, checkingLines, [dismiss]);
  await env.status(start, '正在检查网络', 0);
  await env.status(checkingB, '正在检查网络', 1);
  await connectDismiss(start);
  await connectDismiss(checkingB);
  await env.go(start, checkingB, { timeout: 0.45, smart: true });

  let passed = null;
  let result = null;
  let retry = null;
  if (cfg.outcome === '51') {
    passed = await make('评分 51 · 检查通过', '网络检查通过', [
      '当前评分 51，符合高于 50 的通过条件',
      '继续' + cfg.operation,
    ], []);
    result = passed;
    await env.status(passed, '检查通过', 2);
    await env.go(checkingB, passed, { timeout: 0.55, smart: true });
    // The destination is deliberately an authorization/query-in-progress
    // frame. A passed gate does not itself report a successful quota update.
    await env.go(passed, cfg.next, { timeout: 0.35, smart: false });
  } else {
    const low = cfg.outcome === '49' || cfg.outcome === '50';
    const reason = {
      timeout: '检查超时，无法完成网络检查',
      unavailable: '评分网站暂不可用，无法完成网络检查',
      invalid: '未取得有效评分，无法完成网络检查',
    };
    const title = low ? '网络评分未达标' : '网络检查失败';
    const lines = low ? [
      '当前评分 ' + cfg.outcome + '，需高于 50 才能继续',
      '网络评分未达通过条件，已阻止' + cfg.operation,
    ] : [
      reason[cfg.outcome],
      '尚未执行' + cfg.operation,
    ];
    result = await make(low ? '有效评分 ' + cfg.outcome + ' · 已阻止' : cfg.outcome + ' · 无法完成检查', title, lines, ['重试', dismiss]);
    await env.status(result, mode === 'foreground' ? title : '未更新 · ' + title, 3);
    await env.go(checkingB, result, { timeout: 0.55, smart: false });
    await connectDismiss(result);

    // Every retry repeats the gate. This review branch models a subsequent
    // valid score of 51, then resumes the original operation and account scope.
    retry = await buildNetworkFlow(env, {
      key: cfg.key + ' · 重试',
      source: cfg.source,
      next: cfg.retryNext || cfg.next,
      outcome: '51',
      mode,
      operation: cfg.operation,
      overlay: cfg.overlay === true,
    });
    await connectButton(result, '重试', retry.start);
    frames.push(...retry.frames);
  }
  return { start, passed, result, retry, frames };
}


// View-only foundation. Append after r4-live-core.js; no flows are generated.
// Index: 0=A, 1=B, 2=C, 3=D, 4=F, 5=E, 6=G. At most one extra exists.
const R4A = [
  { idx: 0, bit: 1, id: 'A', p: 'Claude', email: 'alin.claude@example.com', baseIx: 0, k: 'Claude', v: [39, 72], reset: ['4 天后 09:00', '3 小时后'], plan: 'Pro' },
  { idx: 1, bit: 2, id: 'B', p: 'Codex', email: 'alin.codex@example.com', baseIx: 1, k: 'Codex', v: [38, 64], reset: ['3 天后 09:00', '3 小时 34 分后'], plan: 'Plus' },
  { idx: 2, bit: 4, id: 'C', p: 'Codex', email: 'work.codex@example.com', baseIx: 2, k: 'Codex · work', v: [70, 85], reset: ['5 天后 09:00', '4 小时后'], plan: 'Plus' },
  { idx: 3, bit: 8, id: 'D', p: 'Cursor', email: 'alin.cursor@example.com', baseIx: 3, k: 'Cursor', v: [62], reset: ['12 天后'], plan: 'Pro', money: '剩余 $12.40 / $20.00' },
  { idx: 4, bit: 16, id: 'F', p: 'Claude', email: 'new.claude@example.com', baseIx: 0, k: 'Claude · new', v: [61, 47], reset: ['2 天后 09:00', '2 小时后'], plan: 'Pro' },
  { idx: 5, bit: 32, id: 'E', p: 'Codex', email: 'new.codex@example.com', baseIx: 1, k: 'Codex · new', v: [54, 91], reset: ['6 天后 09:00', '4 小时 30 分后'], plan: 'Plus' },
  { idx: 6, bit: 64, id: 'G', p: 'Cursor', email: 'new.cursor@example.com', baseIx: 3, k: 'Cursor · new', v: [28], reset: ['8 天后'], plan: 'Pro', money: '剩余 $5.60 / $20.00' }
];
const R4_ACCOUNT_ORDER = [0, 4, 1, 2, 5, 3, 6];
const R4_ACCOUNT_MASKS = [0, 16, 32, 64].flatMap(extra => Array.from({ length: 16 }, (_, base) => extra + base));
const R4_ACCOUNT_MODELS = new Map();
const R4_ACCOUNT_VIEW_VERSION = '1';
const R4_ACCOUNT_VIEW_TAG = 'r4_account_foundation_view';

function findCard(f, idx) {
  if (!R4A[idx]) throw Error('Unknown account index: ' + idx);
  return one(f, 'Quota/' + R4A[idx].k);
}

function findRow(f, idx) {
  if (!R4A[idx]) throw Error('Unknown account index: ' + idx);
  return one(f, 'Account row/' + R4A[idx].k);
}

function accountModelKey(mask, kind) { return 'Accounts/Set-' + mask + '/' + kind; }
function accountModelName(e, mask, kind) { return 'R4/' + e.t + '/' + accountModelKey(mask, kind); }
// Clones inherit plugin data, so readiness must include the current node ID.
function accountViewReady(n) { return n && n.getPluginData(R4_ACCOUNT_VIEW_TAG) === R4_ACCOUNT_VIEW_VERSION + ':' + n.id; }
function accountViewDone(n) { n.setPluginData(R4_ACCOUNT_VIEW_TAG, R4_ACCOUNT_VIEW_VERSION + ':' + n.id); }
function accountRequired(n, name) { if (!n) throw Error('Account foundation missing ' + name); return n; }
function accountVisible(n, visible) { if (n && n.visible !== visible) { n.visible = visible; writes.add(n.id); } }

function accountSetText(n, value) {
  if (n && n.characters !== value) change(n, value);
}

function accountNormalizeCard(card, idx) {
  const a = R4A[idx];
  for (const text of txt(card)) if (text.characters.includes('@')) accountSetText(text, a.email);
  accountSetText(one(card, 'Last updated'), a.email);
  accountSetText(one(card, 'Detail updated'), '套餐 ' + a.plan + ' · 上次成功更新 09:41');
  const windows = card.children.filter(n => n.name.startsWith('Window/'));
  if (windows.length !== a.v.length) throw Error('Quota window mismatch for ' + a.email);
  windows.forEach((w, i) => {
    const key = w.name.slice('Window/'.length);
    accountSetText(accountRequired(one(w, 'Value/' + key), a.email + ' value'), a.v[i] + '%');
    accountSetText(one(w, 'Reset/' + key), a.reset[i]);
    const track = accountRequired(one(w, 'Track/' + key), a.email + ' track');
    const bar = accountRequired(one(w, 'Bar/' + key), a.email + ' used bar');
    const width = track.width * (100 - a.v[i]) / 100;
    if (Math.abs(bar.width - width) > .02) { bar.resize(width, bar.height); writes.add(bar.id); }
    accountVisible(bar, true);
  });
  if (a.money) for (const text of txt(card)) if (/^剩余\s*\$/.test(text.characters)) accountSetText(text, a.money);
  accountVisible(one(card, 'Account details'), false);
}

function accountCloneExtra(e, f, idx, card) {
  const record = R4A[idx];
  const source = card ? findCard(e.dashboard, record.baseIx) : findRow(e.settings, record.baseIx);
  accountRequired(source, 'R3 template ' + record.p);
  const parent = card ? one(f, 'Content') : one(f, 'Group/账户');
  let n = clone(source, accountRequired(parent, 'account container'), (card ? 'Quota/' : 'Account row/') + record.k);
  // Only added cards are detached. Their distinct metric widths cannot change a
  // shared R3 card component or later snap back to its original account values.
  if (card && n.type === 'INSTANCE') {
    n = n.detachInstance();
    n.name = 'Quota/' + record.k;
    for (const child of all(n)) made.add(child.id);
    clear(n);
  }
  return n;
}

function accountArrangeSettings(e, f, accounts) {
  const group = accountRequired(one(f, 'Group/账户'), 'settings account group');
  const add = accountRequired(one(group, 'Row/连接账户'), 'settings add-account row');
  const dividers = group.children.filter(n => n.name === 'Inset divider');
  dividers.forEach(n => accountVisible(n, false));
  for (let idx = 0; idx < R4A.length; idx++) {
    let row = findRow(f, idx);
    if (accounts.includes(idx) && !row) row = accountCloneExtra(e, f, idx, false);
    if (row) {
      accountVisible(row, accounts.includes(idx));
      for (const text of txt(row)) if (text.characters.includes('@')) accountSetText(text, R4A[idx].email);
    }
  }
  let position = 0;
  accounts.forEach((idx, i) => {
    const row = accountRequired(findRow(f, idx), 'row ' + idx);
    group.insertChild(position++, row);
    let divider = dividers[i];
    if (!divider && dividers[0]) {
      divider = clone(dividers[0], group, 'Inset divider');
      dividers.push(divider);
    }
    if (divider) { accountVisible(divider, true); group.insertChild(position++, divider); }
  });
  accountVisible(add, true);
  group.insertChild(position, add);
  const preference = one(f, 'Row/额度显示');
  accountVisible(preference, false);
  const viewport = one(f, 'Scroll viewport');
  if (viewport) viewport.overflowDirection = 'VERTICAL';
}

function accountArrangeDashboard(e, f, accounts) {
  if (!accounts.length) return; // The dedicated R3 empty-screen template is used.
  const body = accountRequired(one(f, 'Content'), 'dashboard content');
  const oldCards = body.children.filter(n => n.name.startsWith('Quota/'));
  let position = oldCards.length ? body.children.indexOf(oldCards[0]) : 0;
  for (let idx = 0; idx < R4A.length; idx++) {
    let card = findCard(f, idx);
    if (accounts.includes(idx) && !card) card = accountCloneExtra(e, f, idx, true);
    if (card) {
      accountVisible(card, accounts.includes(idx));
      if (accounts.includes(idx)) accountNormalizeCard(card, idx);
    }
  }
  for (const idx of accounts) body.insertChild(position++, accountRequired(findCard(f, idx), 'card ' + idx));
  const viewport = one(f, 'Scroll viewport');
  if (viewport) viewport.overflowDirection = 'VERTICAL';
}

async function accountUpComponent(e) {
  if (e.accountFoundationUp) return e.accountFoundationUp;
  const arrow = one(findCard(e.dashboard, 0), 'Icon/down');
  if (!arrow || arrow.type !== 'INSTANCE') return null;
  const down = await arrow.getMainComponentAsync();
  const parent = down && down.parent;
  if (parent && parent.type === 'PAGE' && typeof parent.loadAsync === 'function') await parent.loadAsync();
  const up = parent && 'children' in parent && parent.children.find(n =>
    n.type === 'COMPONENT' && n.name === 'R2/Icon/' + e.t + '/up');
  if (up) e.accountFoundationUp = up;
  return up || null;
}

async function getAccountModel(e, mask) {
  if (!Number.isInteger(mask) || !R4_ACCOUNT_MASKS.includes(mask)) {
    throw Error('Unsupported account set ' + mask + '; use one of the 64 declared masks');
  }
  const cacheKey = e.t + '/' + mask;
  if (R4_ACCOUNT_MODELS.has(cacheKey)) return R4_ACCOUNT_MODELS.get(cacheKey);
  const accounts = R4_ACCOUNT_ORDER.filter(idx => mask & R4A[idx].bit);
  const empty = accountRequired(e.roots.find(n => n.name.includes('|Dashboard|0|') &&
    !n.name.includes('|initial|')), 'R3 empty dashboard');
  for (let i = 0; i < 4; i++) {
    accountRequired(findCard(e.dashboard, i), 'base card ' + i);
    accountRequired(findRow(e.settings, i), 'base settings row ' + i);
  }
  const d = mask === 15 ? e.dashboard : root(e, mask === 0 ? empty : e.dashboard, accountModelKey(mask, 'Dashboard'));
  const s = mask === 15 ? e.settings : root(e, e.settings, accountModelKey(mask, 'Settings'));
  // Base15 is reused without clearing or changing any existing reactions.
  if (mask !== 15 && !accountViewReady(d)) { accountArrangeDashboard(e, d, accounts); accountViewDone(d); }
  if (mask !== 15 && !accountViewReady(s)) { accountArrangeSettings(e, s, accounts); accountViewDone(s); }
  const details = {};
  const up = accounts.length ? await accountUpComponent(e) : null;
  for (const idx of accounts) {
    const expanded = root(e, d, accountModelKey(mask, 'Expanded-' + idx));
    if (!accountViewReady(expanded)) {
      for (const other of accounts) accountVisible(one(findCard(expanded, other), 'Account details'), other === idx);
      const arrow = one(findCard(expanded, idx), 'Icon/down');
      if (up && arrow && arrow.type === 'INSTANCE') arrow.swapComponent(up);
      const viewport = one(expanded, 'Scroll viewport');
      if (viewport) viewport.overflowDirection = 'VERTICAL';
      accountViewDone(expanded);
    }
    details[idx] = expanded;
  }
  const model = { mask, d, s, details, accounts };
  R4_ACCOUNT_MODELS.set(cacheKey, model);
  return model;
}

async function accountFoundationStage(t, start = 0, count = 8) {
  if (!Number.isInteger(start) || start < 0 || start >= R4_ACCOUNT_MASKS.length) throw Error('start must be a model index from 0 to 63');
  if (!Number.isInteger(count) || count < 1 || count > 8) throw Error('Generate 1–8 account models per batch');
  const e = await env(t);
  const end = Math.min(start + count, R4_ACCOUNT_MASKS.length);
  const before = e.registry.size;
  const models = [];
  for (let i = start; i < end; i++) {
    figma.ui.postMessage({ status: t + ' 账号视图 ' + (i + 1) + '/64', progress: true });
    models.push(await getAccountModel(e, R4_ACCOUNT_MASKS[i]));
    await new Promise(resolve => setTimeout(resolve, 0));
  }
  // Only inherited reactions on newly cloned views are cleared by core helpers.
  // No action destinations are authored, and Base15 actions remain untouched.
  await flush();
  const completedRoots = models.flatMap(m => [m.d, m.s, ...Object.values(m.details)]);
  const result = {
    status: t + ' 账号视图批次完成（尚未连接流程）',
    start, end, totalModels: 64,
    completedModels: models.length,
    completedRootCount: completedRoots.length,
    createdRootCount: e.registry.size - before,
    models: models.map(m => ({
      mask: m.mask, d: m.d.id, s: m.s.id, accounts: m.accounts,
      details: Object.fromEntries(Object.entries(m.details).map(([idx, n]) => [idx, n.id]))
    }))
  };
  e.branch.setPluginData('r4_account_foundation_last_batch', JSON.stringify({ start, end }));
  figma.commitUndo();
  return result;
}


// Native finite-state account paths. All displayed data use the 09:41 review clock.
const FLOW_PENDING=new Map();
// Completion tags are committed only after native reactions have been flushed.
const FLOW_TAGS=new Map();
function flowTag(e,key){const item=FLOW_TAGS.get(e.branch.id+'/'+key);return item?item.value:e.branch.getPluginData(key);}
function flowSaveTag(e,key,value){FLOW_TAGS.set(e.branch.id+'/'+key,{branch:e.branch,key,value});}
async function flowFlush(e){await flush();for(const [key,item] of [...FLOW_TAGS])if(item.branch.id===e.branch.id){item.branch.setPluginData(item.key,item.value);FLOW_TAGS.delete(key);}figma.commitUndo();}
async function flowStoredNode(e,key){const id=flowTag(e,key);if(!id)return null;const n=await figma.getNodeByIdAsync(id);return n&&!n.removed&&n.type==='FRAME'?n:null;}
function pendingModelsToWire(e){const result=[];for(const n of e.registry.values()){const match=n.name.match(new RegExp('^R4/'+e.t+'/AccountFlow/Pending-(\\d+)-(\\d+)/Dashboard$'));if(match&&!flowTag(e,'r4_wired_'+match[1]+'_'+match[2]))result.push({mask:Number(match[1]),idx:Number(match[2])});}return [...new Map(result.map(x=>[x.mask+'/'+x.idx,x])).values()].sort((a,b)=>a.mask-b.mask||a.idx-b.idx);}

async function flowCommon(e){
 if(e.flowCommon)return e.flowCommon;
 const cached=e.branch.getPluginData('r4_flow_common');
 if(cached){try{const x=JSON.parse(cached),res={q:{},fail:{},reconnect:{},addFail:{},detail:{}};let valid=true;for(const group of Object.keys(res))for(const[k,id]of Object.entries(x[group]||{})){res[group][k]=await figma.getNodeByIdAsync(id);if(!res[group][k]||res[group][k].removed)valid=false;}for(const scope of ['all',0,1,2,3,4,5,6])if(!res.q[scope]||!res.fail[scope])valid=false;for(let i=0;i<7;i++)if(!res.reconnect[i]||!res.detail[i])valid=false;for(const p of ['Claude','Codex','Cursor'])if(!res.addFail[p])valid=false;if(valid){e.flowCommon=res;return res;}}catch(err){figma.ui.postMessage({status:'重建不完整的共享账号路径索引',progress:true});}}
 const c={q:{},fail:{},reconnect:{},addFail:{},detail:{}};
 for(const scope of ['all',0,1,2,3,4,5,6]){
  const who=scope==='all'?'全部已绑定账号':R4A[scope].email;
  const load=panel(e,'AccountFlow/Query/'+scope,'正在查询额度',[who],['取消']);progress(e,load,1);close(button(load,'取消'));
  const done=panel(e,'AccountFlow/Done/'+scope,'额度已更新',[who,'上次成功更新 09:41'],['关闭']);close(button(done,'关闭'));put(load,done,'SWAP',{timeout:1});close(done,{timeout:.8});
  const gate=await network(e,'Account query '+scope,load,who+'的额度查询');c.q[scope]=gate.start;
  const fl=panel(e,'AccountFlow/FailLoading/'+scope,'正在查询额度',[who],['取消']);close(button(fl,'取消'));progress(e,fl,1);
  const fail=panel(e,'AccountFlow/Failed/'+scope,'额度查询失败',[who,'平台暂未返回额度','保留上次成功数据 · 09:41'],['重试','关闭']);close(button(fail,'关闭'));put(button(fail,'重试'),gate.start,'SWAP');put(fl,fail,'SWAP',{timeout:1});c.fail[scope]=(await network(e,'Account query failure '+scope,fl,who+'的额度查询')).start;
  if(scope!=='all'){
   const a=R4A[scope],login=root(e,e.logins[a.p],'AccountFlow/Reconnect/'+scope);fixLogin(e,login,a.email);put(button(login,'继续'),gate.start,'SWAP');c.reconnect[scope]=login;
   const lines=[a.email,...a.v.map((v,i)=>(i===0&&a.p==='Cursor'?'套餐内额度':i===0?'每周':'5 小时')+' · 剩余 '+v+'% · '+a.reset[i]+'重置'),'上次成功更新 09:41'];const d=panel(e,'AccountFlow/Details/'+scope,a.p+' 账户',lines,['关闭']);close(button(d,'关闭'));c.detail[scope]=d;
  }
 }
 for(const p of ['Claude','Codex','Cursor']){
  const login=root(e,e.logins[p],'AccountFlow/RetryAdd/'+p);fixLogin(e,login,'another.'+p.toLowerCase()+'@example.com');const auth=panel(e,'AccountFlow/RetryAdd/'+p+'/Loading','正在连接 '+p,['平台授权 · 交互示意'],['取消']);close(button(auth,'取消'));progress(e,auth,1);const fail=panel(e,'AccountFlow/RetryAdd/'+p+'/Failed','授权未完成',['未添加新账号。已有账号保持不变。'],['重新尝试','取消']);close(button(fail,'取消'));put(button(login,'继续'),auth,'SWAP');put(auth,fail,'SWAP',{timeout:1});const gate=await network(e,'Add retry '+p,login,'添加 '+p+' 账号');put(button(fail,'重新尝试'),gate.start,'SWAP');c.addFail[p]=gate.start;
 }
 const ids=Object.fromEntries(Object.entries(c).map(([g,values])=>[g,Object.fromEntries(Object.entries(values).map(([k,n])=>[k,n.id]))]));await flush();e.branch.setPluginData('r4_flow_common',JSON.stringify(ids));e.flowCommon=c;return c;
}
function fixLogin(e,f,email){for(const tx of txt(f))if(tx.characters.includes('@'))change(tx,email);for(const s of['继续','取消']){const b=button(f,s);if(b){const tx=txt(b)[0];change(tx,s);tx.visible=true;tx.opacity=1;const v=s==='继续'?(e.t==='Dark'?.08:.98):(e.t==='Dark'?.94:.09);tx.fills=[{type:'SOLID',color:{r:v,g:v,b:v}}];}}close(button(f,'取消'));close(one(f,'Action/close'));const bg=f.children.find(n=>n.type==='RECTANGLE');if(bg)close(bg);}
function pendingKey(mask,idx){return 'AccountFlow/Pending-'+mask+'-'+idx;}
function unknownCard(f,idx){const c=findCard(f,idx);if(!c)return;for(const tx of txt(c)){if(tx.name.startsWith('Value/'))change(tx,'—');if(tx.name.startsWith('Reset/'))change(tx,'未获取');if(tx.name==='Detail updated')change(tx,'尚未获取额度');if(/^剩余\s*\$/.test(tx.characters))change(tx,'暂无额度数据');}for(const bar of c.findAll(n=>n.name.startsWith('Bar/')))bar.visible=false;}
async function pendingModel(e,mask,idx){const key=e.t+'/'+mask+'/'+idx;if(FLOW_PENDING.has(key))return FLOW_PENDING.get(key);const ready=await getAccountModel(e,mask);const m={mask,accounts:ready.accounts,pendingIdx:idx,key:pendingKey(mask,idx),ready,details:{}};m.d=root(e,ready.d,m.key+'/Dashboard');m.s=root(e,ready.s,m.key+'/Settings');unknownCard(m.d,idx);FLOW_PENDING.set(key,m);return m;}
function flowKey(m){return m.pendingIdx===undefined?'AccountFlow/Set-'+m.mask:m.key;}
async function pendingQuery(e,m,origin,scope='pending'){
 const dest=origin==='s'?m.ready.s:m.ready.d,key=flowKey(m)+'/FirstQuery-'+origin+'-'+scope,tag='pending_q_'+m.mask+'_'+m.pendingIdx+'_'+origin+'_'+scope;
 const stored=await flowStoredNode(e,tag);if(stored)return stored;
 const who=scope==='all'?'全部已绑定账号':R4A[m.pendingIdx].email;
 const loading=panel(e,key+'/Loading','正在查询额度',[who],['取消']);close(button(loading,'取消'));progress(e,loading,1);put(loading,dest,'NAVIGATE',{timeout:1});
 const g=await network(e,key,loading,who+(scope==='all'?' 的额度查询':' 的首次额度查询'));
 // Never rename a registered frame: registry keys and restart discovery agree.
 flowSaveTag(e,tag,g.start.id);return g.start;
}
async function addition(e,m,p,c){const ix=R4_ACCOUNT_ORDER.find(i=>R4A[i].p===p&&!(m.mask&R4A[i].bit));const next=ix===undefined?null:m.mask|R4A[ix].bit;if(m.pendingIdx!==undefined||next===null||!R4_ACCOUNT_MASKS.includes(next))return c.addFail[p];const key='AccountFlow/Add-'+m.mask+'-'+ix;const stored=await flowStoredNode(e,'add_'+m.mask+'_'+ix);if(stored)return stored;
 const pending=await pendingModel(e,next,ix);const first=await pendingQuery(e,pending,'d');
 const bound=root(e,pending.d,key+'/Bound');await copyFlowTree(pending.d,bound);put(bound,first,'OVERLAY',{timeout:.15});
 const auth=panel(e,key+'/Authorization','正在连接 '+p,['平台授权 · 交互示意'],['取消']);close(button(auth,'取消'));progress(e,auth,1);put(auth,bound,'NAVIGATE',{timeout:1});const login=root(e,e.logins[p],key+'/Login');fixLogin(e,login,R4A[ix].email);put(button(login,'继续'),auth,'SWAP');const pre=await network(e,key+'/BeforeAdd',login,'添加 '+p+' 账号');flowSaveTag(e,'add_'+m.mask+'_'+ix,pre.start.id);return pre.start;
}
async function copyFlowTree(src,dest){function go(a,b,visible=true){visible=visible&&a.visible!==false;if('reactions'in a){const r=visible?(jobs.has(a)?jobs.get(a):a.reactions):[],effective=jobs.has(b)?jobs.get(b):(b.reactions||[]);if(r.length||effective.length)jobs.set(b,r.map(x=>({trigger:JSON.parse(JSON.stringify(x.trigger)),actions:JSON.parse(JSON.stringify(x.actions||(x.action?[x.action]:[])))})));}if('children'in a&&'children'in b&&a.children.length===b.children.length)a.children.forEach((n,i)=>go(n,b.children[i],visible));}go(src,dest);}
async function wireAccountModel(e,m,c,withAddition=true){const key=flowKey(m),tag='r4_wired_'+m.mask+'_'+(m.pendingIdx===undefined?'ready':m.pendingIdx);if(flowTag(e,tag))return; if(m.wiring)return;m.wiring=true;try{
 const chooser=root(e,e.connect,key+'/Connect');for(const p of['Claude','Codex','Cursor'])put(one(chooser,'Connect/'+p),withAddition?await addition(e,m,p,c):c.addFail[p],'SWAP');close(one(chooser,'Action/close'));close(chooser.children.find(n=>n.type==='RECTANGLE'));
 const menus={d:{},s:{}};
 for(const origin of['d','s'])for(const i of m.accounts){const a=R4A[i],menu=panel(e,key+'/'+origin+'/Menu-'+i,a.p+' 账户',[a.email],['刷新额度','重新连接','断开连接','取消']);close(button(menu,'取消'));const q=m.pendingIdx===i?await pendingQuery(e,m,origin):c.q[i];put(button(menu,'刷新额度'),q,'SWAP');if(m.pendingIdx===i){const lg=root(e,e.logins[a.p],key+'/'+origin+'/Reconnect-'+i);fixLogin(e,lg,a.email);put(button(lg,'继续'),q,'SWAP');put(button(menu,'重新连接'),lg,'SWAP');}else put(button(menu,'重新连接'),c.reconnect[i],'SWAP');
  const nextMask=m.mask&~a.bit;let next;if(m.pendingIdx!==undefined&&m.pendingIdx!==i){next=await pendingModel(e,nextMask,m.pendingIdx);}else next=await getAccountModel(e,nextMask);
  const conf=panel(e,key+'/'+origin+'/Disconnect-'+i,'断开连接？',[a.email,'移除此账号的额度数据和待发提醒。平台订阅不会取消。'],['断开连接','取消']);close(button(conf,'取消'));put(button(conf,'断开连接'),origin==='s'?next.s:next.d);put(button(menu,'断开连接'),conf,'SWAP');menus[origin][i]=menu;
 }
 const views=[{n:m.d,kind:'d'}, {n:m.s,kind:'s'},...Object.entries(m.details).map(([i,n])=>({n,kind:'d',expanded:Number(i)}))];
 for(const v of views){const f=v.n;const dtab=one(f,'Tab/额度'),stab=one(f,'Tab/设置');if(dtab)put(dtab,m.d);if(stab)put(stab,m.s);const refresh=one(f,'Action/refresh');if(refresh)put(refresh,m.pendingIdx===undefined?c.q.all:await pendingQuery(e,m,v.kind,'all'),'OVERLAY');const add=one(f,'Action/link')||one(f,'Row/连接账户')||f.findOne(n=>n.type==='INSTANCE'&&n.name.startsWith('Button/')&&txt(n).some(x=>/^连接平台$|^连接账户$/.test(x.characters)));if(add)put(add,chooser,'OVERLAY');
  for(const i of m.accounts){const card=findCard(f,i),row=findRow(f,i);const more=one(card||row,'Action/more');if(more)put(more,menus[v.kind][i],'OVERLAY');const expand=card&&one(card,'Expand account'),identity=row&&one(row,'Account identity');const detail=m.details[i];if(expand){if(detail)put(expand,v.expanded===i?m.d:detail,'NAVIGATE',{smart:true});else if(m.pendingIdx===i){const info=panel(e,key+'/PendingDetails',R4A[i].p+' 账户',[R4A[i].email,'尚未获取额度'],['关闭']);close(button(info,'关闭'));put(expand,info,'OVERLAY');}else put(expand,c.detail[i],'OVERLAY');}if(identity){if(m.pendingIdx===i){const inf=e.registry.get('R4/'+e.t+'/'+key+'/PendingDetails')||panel(e,key+'/PendingDetails',R4A[i].p+' 账户',[R4A[i].email,'尚未获取额度'],['关闭']);close(button(inf,'关闭'));put(identity,inf,'OVERLAY');}else put(identity,detail||c.detail[i],detail?'NAVIGATE':'OVERLAY');}}
  const tutorial=e.roots.find(n=>n.name===e.t+'/Tutorial1');for(const name of['Action/如何添加小组件','Row/如何添加小组件']){const b=one(f,name);if(b&&tutorial)put(b,tutorial,'OVERLAY');}
  if(v.kind==='s'){for(const[lab,k]of[['帮助与说明','Help'],['隐私说明','Privacy'],['开源许可','Licenses']]){const b=one(f,'Row/'+lab),target=e.roots.find(n=>n.name===e.t+'/'+k);if(b&&target)put(b,target,'OVERLAY');}}
 }
 m.menus=menus;m.chooser=chooser;
 // Initial binding uses a launch copy. Give it the completed pending-page
 // controls, then restore its one-time check trigger; closing a sheet never
 // leaves a background whose only control is an already-fired timer.
 if(m.pendingIdx!==undefined){const previous=m.mask&~R4A[m.pendingIdx].bit;const bound=e.registry.get('R4/'+e.t+'/AccountFlow/Add-'+previous+'-'+m.pendingIdx+'/Bound');if(bound){await copyFlowTree(m.d,bound);put(bound,await pendingQuery(e,m,'d'),'OVERLAY',{timeout:.15});}}
 flowSaveTag(e,tag,'1');
 }finally{m.wiring=false;}
}
async function accountFlowStage(t,start=0,count=1){
 if(!Number.isInteger(start)||start<0||start>=64||!Number.isInteger(count)||count<1||count>4)throw Error('Account flow batches require start 0–63 and count 1–4');
 const e=await env(t),c=await flowCommon(e),out=[];
 for(let z=start;z<Math.min(start+count,64);z++){const m=await getAccountModel(e,R4_ACCOUNT_MASKS[z]);figma.ui.postMessage({status:t+' 连接账号路径 '+(z+1)+'/64',progress:true});await wireAccountModel(e,m,c);await flowFlush(e);out.push({mask:m.mask,d:m.d.id,s:m.s.id});await new Promise(r=>setTimeout(r,0));}
 return{status:t+' 主账号路径批次完成；待获取额度集合须继续连接',start,end:Math.min(start+count,64),models:out,remainingPending:pendingModelsToWire(e).length};
}
// Pending-set deletion targets are materialized without recursively wiring
// them. Drain this bounded queue after the ordinary model batches, before any
// prototype acceptance run. Later batches discover newly created child sets.
async function accountPendingFlowStage(t,count=1){
 if(!Number.isInteger(count)||count<1||count>4)throw Error('Pending flow batches require count 1–4');
 const e=await env(t),c=await flowCommon(e),out=[];
 for(let z=0;z<count;z++){const next=pendingModelsToWire(e)[0];if(!next)break;const m=await pendingModel(e,next.mask,next.idx);figma.ui.postMessage({status:t+' 连接待获取额度集合 '+next.mask+' / '+next.idx,progress:true});await wireAccountModel(e,m,c,false);await flowFlush(e);out.push({mask:m.mask,pendingIdx:m.pendingIdx,d:m.d.id,s:m.s.id});await new Promise(r=>setTimeout(r,0));}
 return{status:t+' 待获取额度路径批次完成',models:out,remainingPending:pendingModelsToWire(e).length};
}


// Incremental system/notification authoring for the existing base R3 snapshots.
// No real permissions, account access, or changes to account-menu/refresh nodes.
// Append after r4-live-core.js. systemStage(theme) is the only stage entry point.

function systemRequired(node, description) {
  if (!node) throw Error('System stage missing ' + description);
  return node;
}

function systemKind(e, kind) {
  return systemRequired(e.roots.find(n =>
    n.name === e.t + '/' + kind || n.name.split('|')[1] === kind
  ), e.t + '/' + kind);
}

function systemSettingsState(e, state) {
  return systemRequired(e.roots.find(n => {
    const parts = n.name.split('|');
    return parts[1] === 'Settings' && parts[2] === '7' &&
      parts[3] === 'R' && parts[4] === String(state);
  }), e.t + '/Settings notification=' + state);
}

// root() deliberately clears inherited reactions. These base-dashboard/settings
// copies need their existing account actions preserved, then only system actions
// are overridden below. Copy by child position: source and fresh clone have the
// exact same tree before any component swaps or new content are introduced.
function systemCopyWithActions(e, source, key) {
  const name = 'R4/' + e.t + '/' + key;
  const existed = e.registry.has(name);
  const target = root(e, source, key);
  if (!existed) {
    const copy = (a, b) => {
      if ('reactions' in a && a.reactions.length) {
        // Keep only current API fields; older files can expose both the legacy
        // `action` and the modern `actions` fields when reactions are read.
        jobs.set(b, a.reactions.map(r => ({
          trigger: JSON.parse(JSON.stringify(r.trigger)),
          actions: JSON.parse(JSON.stringify(r.actions || (r.action ? [r.action] : [])))
        })));
      }
      if ('children' in a) {
        if (!('children' in b) || a.children.length !== b.children.length) {
          throw Error('Unexpected cloned system tree: ' + a.name);
        }
        a.children.forEach((child, i) => copy(child, b.children[i]));
      }
    };
    copy(source, target);
  }
  return target;
}

function systemSheetClose(frame) {
  close(systemRequired(one(frame, 'Action/close'), frame.name + ' close'));
  const shade = frame.children.find(n => n.type === 'RECTANGLE');
  close(systemRequired(shade, frame.name + ' scrim'));
}

function systemNotificationAction(settings, target, navigation) {
  put(systemRequired(one(settings, 'Toggle/通知'), settings.name + ' toggle'), target, navigation);
  const row = one(settings, 'Row/额度重置通知');
  if (row) put(row, target, navigation);
}

async function systemToggleComponents(instance, theme) {
  if (!instance || instance.type !== 'INSTANCE') throw Error('Notification toggle must be an instance');
  const main = await instance.getMainComponentAsync();
  if (!main) throw Error('Notification toggle has no main component');
  const siblings = main.parent && 'children' in main.parent ? main.parent.children : [main];
  const find = state => siblings.find(n => n.type === 'COMPONENT' &&
    n.name.split(',').some(p => p.trim() === 'Theme=' + theme) &&
    n.name.split(',').some(p => p.trim() === 'State=' + state));
  const on = find('On'), off = find('Off');
  if (!on || !off) throw Error('Missing native ' + theme + ' On/Off toggle components');
  return { on, off };
}

function systemSetToggle(instance, component, name) {
  systemRequired(instance, 'toggle instance').swapComponent(component);
  if (name) instance.name = name;
}

function systemSupportRoute(settings, pages) {
  for (const [label, kind] of [
    ['帮助与说明', 'Help'], ['隐私说明', 'Privacy'], ['开源许可', 'Licenses']
  ]) {
    const row = systemRequired(one(settings, 'Row/' + label), settings.name + ' ' + label);
    // Full-screen overlays keep the exact underlying settings snapshot, including
    // notification state and scrolling, without one help copy per source.
    put(row, pages[kind], 'OVERLAY');
  }
}

function systemIndexHeading(e, parent, text, size) {
  const node = figma.createText();
  parent.appendChild(node);
  made.add(node.id);
  node.name = text;
  node.fontName = { family: 'PingFang SC', style: 'Regular' };
  node.fontSize = size;
  node.lineHeight = { unit: 'PIXELS', value: Math.ceil(size * 1.45) };
  const c = e.t === 'Dark' ? .94 : .09;
  node.fills = [{ type: 'SOLID', color: { r: c, g: c, b: c } }];
  node.characters = text;
  node.textAutoResize = 'HEIGHT';
  node.resize(parent.width - (parent.paddingLeft || 0) - (parent.paddingRight || 0), node.height);
  return node;
}

async function systemStage(t) {
  const e = await env(t);
  const completionKey = 'r4_system_complete_' + t;
  if (e.branch.getPluginData(completionKey)) {
    return JSON.parse(e.branch.getPluginData(completionKey));
  }

  // Validate all existing templates and toggle variants before creating nodes.
  const initial = e.settings;
  const on = systemSettingsState(e, 1);
  const denied = systemSettingsState(e, 2);
  const permission = systemKind(e, 'Permission');
  const systemOff = systemKind(e, 'System');
  const tutorial = ['Tutorial1', 'Tutorial1b', 'Tutorial2', 'Tutorial2b'].map(k => systemKind(e, k));
  const pages = Object.fromEntries(['Help', 'Privacy', 'Licenses', 'License'].map(k => [k, systemKind(e, k)]));
  const variants = await systemToggleComponents(systemRequired(one(initial, 'Toggle/通知'), 'base toggle'), t);
  const isSystemToggle = n => n.type === 'INSTANCE' && (n.name === 'System/Notification toggle' ||
    /(?:^|,)\s*State=(?:Off|On)(?:,|$)/.test(n.name));
  const sourceSystemToggle = systemRequired(systemOff.findOne(isSystemToggle), 'iOS permission toggle');
  for (const s of [initial, on, denied]) {
    systemRequired(one(s, 'Tab/额度'), s.name + ' quota tab');
    systemRequired(one(s, 'Toggle/通知'), s.name + ' notification toggle');
  }

  // Off after permission was granted is distinct from the initial, unasked state.
  const off = systemCopyWithActions(e, initial, 'System/NotificationsOff');
  const systemOn = root(e, systemOff, 'System/iOSNotificationsOn');
  const systemOnToggle = systemRequired(systemOn.findOne(isSystemToggle), 'iOS On toggle');
  systemSetToggle(one(initial, 'Toggle/通知'), variants.off, 'Toggle/通知');
  systemSetToggle(one(off, 'Toggle/通知'), variants.off, 'Toggle/通知');
  systemSetToggle(one(on, 'Toggle/通知'), variants.on, 'Toggle/通知');
  systemSetToggle(one(denied, 'Toggle/通知'), variants.off, 'Toggle/通知');
  systemSetToggle(sourceSystemToggle, variants.off, 'System/Notification toggle');
  systemSetToggle(systemOnToggle, variants.on, 'System/Notification toggle');

  clear(permission);
  systemSheetClose(permission);
  put(systemRequired(button(permission, '允许'), 'permission allow'), on);
  put(systemRequired(button(permission, '不允许'), 'permission deny'), denied);
  systemNotificationAction(initial, permission, 'OVERLAY');
  systemNotificationAction(on, off, 'NAVIGATE');
  systemNotificationAction(off, on, 'NAVIGATE');
  systemNotificationAction(denied, systemOff, 'NAVIGATE');

  // iOS setting changes remain on the iOS screen until its back action is used.
  put(sourceSystemToggle, systemOn, 'NAVIGATE', { smart: true });
  put(systemOnToggle, systemOff, 'NAVIGATE', { smart: true });
  put(systemRequired(one(systemOff, 'Action/back'), 'iOS Off back'), denied);
  put(systemRequired(one(systemOn, 'Action/back'), 'iOS On back'), on);

  // A single set of tutorial overlays serves every dashboard/settings source.
  tutorial.forEach(f => { clear(f); systemSheetClose(f); });
  for (const f of tutorial.slice(0, 2)) put(systemRequired(button(f, '下一步'), 'tutorial next'), tutorial[2], 'SWAP', { smart: true });
  for (const f of tutorial.slice(2)) close(systemRequired(button(f, '完成'), 'tutorial finish'));
  put(tutorial[0], tutorial[1], 'SWAP', { timeout: .9, smart: true });
  put(tutorial[2], tutorial[3], 'SWAP', { timeout: .9, smart: true });

  // Support pages use overlay-close for their caller and a swap within the
  // license drill-down, so License → Licenses → caller is deterministic.
  for (const k of ['Help', 'Privacy', 'Licenses']) {
    clear(pages[k]);
    close(systemRequired(one(pages[k], 'Action/back'), k + ' back'));
  }
  clear(pages.License);
  put(systemRequired(one(pages.Licenses, 'Row/CodexBar'), 'license row'), pages.License, 'SWAP');
  put(systemRequired(one(pages.License, 'Action/back'), 'license detail back'), pages.Licenses, 'SWAP');

  // These three base-snapshot dashboard copies preserve all existing account
  // actions. Only tab destinations and tutorial entry points change here.
  const dashboardByState = {
    initial: e.dashboard,
    on: systemCopyWithActions(e, e.dashboard, 'System/DashboardNotificationsOn'),
    off: systemCopyWithActions(e, e.dashboard, 'System/DashboardNotificationsOff'),
    denied: systemCopyWithActions(e, e.dashboard, 'System/DashboardNotificationsDenied')
  };
  const settingsByState = { initial, on, off, denied };
  for (const [state, settings] of Object.entries(settingsByState)) {
    const dashboard = dashboardByState[state];
    put(systemRequired(one(settings, 'Tab/额度'), state + ' quota tab'), dashboard);
    put(systemRequired(one(dashboard, 'Tab/设置'), state + ' settings tab'), settings);
    const dashboardTab = one(dashboard, 'Tab/额度');
    if (dashboardTab) put(dashboardTab, dashboard);
    const settingsTab = one(settings, 'Tab/设置');
    if (settingsTab) put(settingsTab, settings);
    const dashboardTutorial = one(dashboard, 'Action/如何添加小组件');
    if (dashboardTutorial) put(dashboardTutorial, tutorial[0], 'OVERLAY');
    put(systemRequired(one(settings, 'Row/如何添加小组件'), state + ' tutorial row'), tutorial[0], 'OVERLAY');
    systemSupportRoute(settings, pages);
  }

  const index = root(e, e.entry, 'System/Review');
  const body = systemRequired(one(index, 'Content'), 'system review content');
  for (const child of [...body.children]) child.remove();
  body.itemSpacing = 8;
  systemIndexHeading(e, body, '通知、教程与返回路径', 22);
  systemIndexHeading(e, body, '设计评审 · 系统权限与系统设置均为交互示意', 12);
  const entries = [];
  for (const [label, destination] of [
    ['首次请求通知权限', initial], ['通知已开启', on],
    ['已允许权限 · App 通知关闭', off], ['系统通知权限拒绝', denied],
    ['从看板查看小组件教程', e.dashboard], ['从设置查看小组件教程', initial]
  ]) {
    put(addButton(e, body, label), destination);
    entries.push({ label, id: destination.id });
  }
  put(addButton(e, body, '返回评审入口'), e.entry);
  const backButton = one(index, 'Action/back');
  if (backButton) put(backButton, e.entry);
  const viewport = one(index, 'Scroll viewport');
  if (viewport) viewport.overflowDirection = 'VERTICAL';

  await flush();
  const result = {
    status: t + ' 系统、通知与教程阶段完成',
    stage: t + '/system',
    index: index.id,
    entries,
    settings: Object.fromEntries(Object.entries(settingsByState).map(([k, n]) => [k, n.id])),
    dashboards: Object.fromEntries(Object.entries(dashboardByState).map(([k, n]) => [k, n.id])),
    permission: permission.id,
    system: { off: systemOff.id, on: systemOn.id },
    tutorial: tutorial.map(n => n.id),
    support: Object.fromEntries(Object.entries(pages).map(([k, n]) => [k, n.id])),
    createdFrameCount: 6,
    scope: 'Base R3 account snapshot only. Account menu and refresh nodes are unchanged.'
  };
  e.branch.setPluginData(completionKey, JSON.stringify(result));
  figma.commitUndo();
  return result;
}


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


// Scoped widget authoring for r4-live-core.js. Only creates Widgets/* roots.
// All account identities and quota values below are Figma review data.
async function widgetStage(t) {
  const e = await env(t), prefix = 'R4/' + t + '/Widgets/';
  // Reuses exact Widgets roots after an inspected partial reaction failure.
  const kind = (k, size) => e.roots.find(n => (n.name === t + '/' + k || n.name.split('|')[1] === k) && (!size || n.name.endsWith('|' + size)));
  const templates = {small:kind('WidgetReview','small'),medium:kind('WidgetReview','medium'),config:kind('WidgetConfig'),home:kind('SystemHome','small'),empty:e.roots.find(n=>n.name.includes('|Dashboard|0|')&&!n.name.includes('initial'))};
  for (const [key, n] of Object.entries(templates)) if (!n) throw Error('Missing R3 widget template: ' + key);
  const created = [], entries = [], targets = [], details = {}, configs = {}, homes = {}, reviews = {};
  const make = (src, key) => { const n=root(e,src,'Widgets/'+key);clear(n);created.push(n);return n; };
  const register = n => { for(const v of [n,...('findAll' in n?n.findAll():[])])made.add(v.id);return n; };
  const copy = (src, parent, name) => {if(name==='Action/back')for(const old of [...parent.children])if(old.name===name)old.remove();const n=src.clone();parent.appendChild(n);if(name)n.name=name;register(n);clear(n);return n;};
  const editable = n => n.type==='INSTANCE'?register(n.detachInstance()):n;
  const hide = (f, name) => {const n=one(f,name);if(n)n.visible=false;};
  const homeIndicator = f => one(f,'Home indicator') || f.children.find(n=>n.type==='RECTANGLE'&&Math.abs(n.width-134)<1&&n.height<8);
  const goBack = (f,d) => {const n=one(f,'Action/back');if(n)put(n,d);const h=homeIndicator(f);if(h)put(h,d);};
  const title = (f,s) => {const n=one(f,'Navigation');const tx=n&&n.children.find(c=>c.type==='TEXT');if(tx)change(tx,s);};
  const body = f => {const b=one(f,'Content');if(!b)throw Error('Missing Content: '+f.name);return b;};
  const sizeOf = size => size==='medium'?353:164;
  const appTarget=(f,d,overlay=false)=>{
    const apps=one(f,'Apps'),app=apps&&apps.children[0];if(!app)return;
    const caption=app.children.find(n=>n.type==='TEXT');if(caption)change(caption,'订阅额度');
    app.name='App/订阅额度';if(d)put(app,d,overlay?'OVERLAY':'NAVIGATE');
  };
  const sources = [
    {key:'A',platform:'Claude',name:'Quota/Claude'},
    {key:'B',platform:'Codex',name:'Quota/Codex'},
    {key:'C',platform:'Codex',name:'Quota/Codex · work'},
    {key:'D',platform:'Cursor',name:'Quota/Cursor'}
  ];
  const accounts = {};
  for(const a of sources){
    const card=one(e.dashboard,a.name);if(!card)throw Error('Missing R3 account card '+a.name);
    const identity=one(card,'Last updated'),updated=one(card,'Detail updated'),provider=one(card,'Provider/'+a.platform);
    const icon=provider&&provider.children.find(n=>n.type==='INSTANCE'||n.type==='FRAME');
    if(!identity||!updated||!icon)throw Error('Incomplete R3 account '+a.key);
    const windows=card.children.filter(n=>n.name.startsWith('Window/')).map(w=>{
      const name=w.name.slice(7),value=one(w,'Value/'+name),reset=one(w,'Reset/'+name);
      if(!value||!reset)throw Error('Incomplete R3 quota window '+a.key+'/'+name);
      const remaining=parseFloat(value.characters);if(!Number.isFinite(remaining)||remaining<0||remaining>100)throw Error('Unexpected R3 quota value');
      return {name,value:value.characters,remaining,reset:reset.characters};
    });
    accounts[a.key]={...a,card,icon,email:identity.characters,updated:updated.characters.match(/\d{2}:\d{2}/)?.[0]||'09:41',windows,money:txt(card).find(n=>n.characters.startsWith('剩余 $'))?.characters};
  }
  // A genuine fifth list card, cloned from Codex styling; quota data is explicit
  // review data inherited from that card, never a textual candidate annotation.
  accounts.E={...accounts.B,key:'E',name:'Quota/Codex · backup',email:'backup.codex@example.com'};
  const accountCard = (key,parent) => {
    const a=accounts[key],n=editable(copy(a.card,parent,a.name));
    for(const tx of txt(n))if(tx.characters.includes('@'))change(tx,a.email);
    const d=one(n,'Account details');if(d)d.visible=false;
    n.visible=true;return n;
  };
  const hub=make(e.entry,'Review');title(hub,'小组件配置与回退');const hb=body(hub);
  for(const c of [...hb.children])c.remove();hb.itemSpacing=10;
  label(e,hb,'小组件配置与回退',22);label(e,hb,'设计评审 · 系统界面与数据均为模拟',12);
  goBack(hub,e.entry);one(hub,'Scroll viewport').overflowDirection='VERTICAL';
  const entry=(s,n)=>{put(addButton(e,hb,s),n);entries.push({label:s,start:n.id});};

  // Full-screen detail overlays retain their own account data. Closing the
  // overlay returns to the exact originating Home, including fallback state.
  for(const key of ['A','B','C','D']){
    const a=accounts[key],f=make(e.dashboard,'Detail/'+key);title(f,'账号额度');
    const b=body(f);for(const c of [...b.children])c.remove();b.itemSpacing=8;
    const card=accountCard(key,b),d=one(card,'Account details');if(d)d.visible=true;
    hide(f,'R3/Header actions');hide(f,'Action/refresh');hide(f,'Action/link');hide(f,'Tab bar');hide(card,'Action/more');
    hide(card,'Icon/down');
    const nav=one(f,'Navigation'),backButton=copy(one(templates.small,'Action/back'),nav,'Action/back');
    close(backButton);close(homeIndicator(f));
    details[key]=f;
  }

  function widget(parent,key,size,index=0){
    const gallery=templates[size],sample=one(gallery,'Widget canvas').children.find(n=>n.name.startsWith('Widget/'));
    if(!sample)throw Error('Missing '+size+' widget');
    let w=editable(copy(sample,parent,'Widget/'+(key||'Empty')+'/'+index));
    w.resize(sizeOf(size),164);w.primaryAxisSizingMode='FIXED';w.counterAxisSizingMode='FIXED';w.itemSpacing=6;w.clipsContent=true;
    if(!key){
      for(const n of [...w.children])n.remove();w.primaryAxisAlignItems='CENTER';
      const tx=label(e,w,'未连接账号，无数据',13);tx.textAlignHorizontal='CENTER';
      return w;
    }
    const a=accounts[key],width=w.width-w.paddingLeft-w.paddingRight,header=one(w,'Widget header');
    header.resize(width,16);header.primaryAxisSizingMode='FIXED';header.counterAxisSizingMode='FIXED';header.itemSpacing=4;
    const headerTexts=header.children.filter(n=>n.type==='TEXT'),name=headerTexts[0],time=headerTexts[1];
    for(const n of [...header.children])if(n.type!=='TEXT')n.remove();
    const icon=copy(a.icon,header,a.platform+' logo');icon.rescale(16/icon.width);header.insertChild(0,icon);
    change(name,a.platform);name.textAutoResize='WIDTH_AND_HEIGHT';name.layoutGrow=1;
    if(time){change(time,a.updated);time.textAutoResize='WIDTH_AND_HEIGHT';time.layoutGrow=0;}
    const oldIdentity=one(w,'Widget account');if(oldIdentity)oldIdentity.remove();
    const id=copy(name,w,'Widget account');id.layoutGrow=0;id.fontSize=10;id.lineHeight={unit:'PIXELS',value:14};
    change(id,a.email.split('@')[0]);id.textAutoResize='HEIGHT';id.resize(width,14);w.insertChild(1,id);
    const wins=w.children.filter(n=>n.name.startsWith('Widget window/'));
    if(wins.length<a.windows.length)throw Error('Widget template has too few windows');
    for(let i=0;i<wins.length;i++){
      const win=wins[i],data=a.windows[i];if(!data){win.remove();continue;}
      win.name='Widget window/'+data.name;win.resize(width,win.height);
      const metric=one(win,'Metric'),fields=metric.children.filter(n=>n.type==='TEXT');
      metric.resize(width,metric.height);change(fields[0],data.name);change(fields[1],'剩余 '+data.value);
      fields[0].layoutGrow=1;fields[1].layoutGrow=0;fields[1].textAutoResize='WIDTH_AND_HEIGHT';
      const track=one(win,'Widget progress');track.resize(width,track.height);
      const bar=track.children.find(n=>n.type==='RECTANGLE');bar.visible=data.remaining<100;if(bar.visible)bar.resize(width*(100-data.remaining)/100,bar.height);
      const reset=win.children.find(n=>n.type==='TEXT');change(reset,data.reset+'重置');reset.textAutoResize='HEIGHT';reset.resize(width,14);
    }
    // No template-specific extra amount or stale reset text survives a platform change.
    for(const n of [...w.children])if(n.type==='TEXT'&&n!==id)n.remove();
    if(a.money){const money=copy(id,w,'Widget amount');change(money,a.money);money.resize(width,14);}
    put(w,details[key],'OVERLAY');targets.push({widget:w.id,account:key,email:a.email,detail:details[key].id,size,windows:a.windows});return w;
  }

  function home(key,size,selected,paired=false){
    const f=make(templates.home,'Home/'+key),b=body(f),container=one(f,'Home widgets');
    for(const c of [...container.children])c.remove();container.layoutMode='HORIZONTAL';container.primaryAxisSizingMode='FIXED';container.counterAxisSizingMode='AUTO';container.itemSpacing=16;container.resize(361,164);
    const widgets=selected.map((id,i)=>widget(container,id,size,i));
    goBack(f,hub);appTarget(f,!paired&&selected[0]?details[selected[0]]:null,!paired);
    const homeNote=txt(f).find(n=>n.characters==='轻点小组件，打开对应账户');if(homeNote)change(homeNote,'轻点小组件，打开对应账号');
    const hint=txt(f).find(n=>n.characters.includes('iOS 主屏幕'));if(hint)change(hint,'iOS 主屏幕 · 交互示意');
    return {f,widgets,selected,b};
  }

  for(const size of ['small','medium']){
    const review=make(templates[size],'Gallery/'+size);reviews[size]=review;goBack(review,hub);
    const canvas=one(review,'Widget canvas');for(const c of [...canvas.children])c.remove();widget(canvas,'A',size);
    // Clear historical display-preference controls even when already hidden.
    for(const n of review.findAll(n=>n.name==='Button/查看已用状态'||n.name==='Button/查看剩余状态'||n.name.startsWith('显示切换仅为评审入口'))){n.visible=false;clear(n);}
    for(const tx of txt(review))if(tx.characters.includes('小组件跟随 App 的'))change(tx,'固定显示所选账户的剩余额度，仅展示平台实际提供的额度周期。');
    for(const key of ['A','B','C','D']){
      const f=make(templates.config,'Config/'+size+'/'+key),g=one(f,'Group/账户');configs[size+'/'+key]=f;
      const checkSource=one(templates.config,'Icon/check');if(!checkSource)throw Error('Missing R3 selection check');
      for(const a of sources){
        const row=one(g,'Account/'+a.name.slice(6));if(!row)throw Error('Missing R3 config row '+a.key);
        for(const c of [...row.children])if(c.name==='Icon/check')c.remove();
        if(a.key===key)copy(checkSource,row,'Icon/check');
      }
      goBack(f,review);
      const h=home('Config/'+size+'/'+key,size,size==='small'&&key==='C'?['C','D']:[key],size==='small'&&key==='C');homes[size+'/'+key]=h;
      put(button(f,'完成'),h.f);put(one(h.f,'Action/back'),f);
    }
  }
  for(const size of ['small','medium']){
    const review=reviews[size];put(button(review,'小号'),reviews.small);put(button(review,'中号'),reviews.medium);
    put(button(review,'添加小组件'),configs[size+'/A']);put(button(review,'编辑小组件'),configs[size+'/A']);
    for(const key of ['A','B','C','D'])for(const a of sources)put(one(configs[size+'/'+key],'Account/'+a.name.slice(6)),configs[size+'/'+a.key]);
  }
  entry('小号小组件 · 选择账号',reviews.small);entry('中号小组件 · 选择账号',reviews.medium);

  // Fallback uses the displayed account order, not platform-mask arithmetic.
  const choose=(current,order)=>order.includes(current)?current:order.find(k=>accounts[k].platform===accounts[current].platform)||order[0]||null;
  const base={order:['A','B','C','D'],selected:['C','D'],home:homes['small/C']};
  const states=[base];let previous=base;
  for(const removed of ['C','B','A','D']){
    const order=previous.order.filter(k=>k!==removed),selected=previous.selected.map(k=>choose(k,order));
    const h=home('Fallback/'+(order.join('')||'Empty'),'small',selected,true),state={order,selected,home:h};states.push(state);previous=state;
  }
  // Empty widgets go to a real empty-account guide. Its connect trigger is
  // returned for the account stage to attach to its network-gated add flow.
  const emptyGuide=make(templates.empty,'EmptyGuide');goBack(emptyGuide,hub);
  hide(emptyGuide,'R3/Header actions');hide(emptyGuide,'Action/refresh');hide(emptyGuide,'Tab bar');
  const emptyBack=copy(one(templates.small,'Action/back'),one(emptyGuide,'Navigation'),'Action/back');put(emptyBack,states[4].home.f);
  put(homeIndicator(emptyGuide),states[4].home.f);
  const connectTrigger=button(emptyGuide,'连接平台')||button(emptyGuide,'连接账户')||emptyGuide.findOne(n=>n.name.startsWith('Button/')&&txt(n).some(x=>/连接|添加/.test(x.characters)))||one(emptyGuide,'Action/link');
  if(!connectTrigger)throw Error('Missing empty-account connect trigger');
  for(const w of states[4].home.widgets)put(w,emptyGuide);
  appTarget(states[4].home.f,emptyGuide);

  function list(key,order,origin){
    const f=make(e.dashboard,'Accounts/'+key);title(f,'账号管理');const b=body(f);for(const c of [...b.children])c.remove();b.itemSpacing=8;
    hide(f,'R3/Header actions');hide(f,'Action/refresh');hide(f,'Action/link');hide(f,'Tab bar');one(f,'Scroll viewport').overflowDirection='VERTICAL';
    const backButton=copy(one(templates.small,'Action/back'),one(f,'Navigation'),'Action/back');put(backButton,origin);put(homeIndicator(f),origin);
    const cards={};for(const k of order){
      cards[k]=accountCard(k,b);const expand=one(cards[k],'Expand account');
      if(expand&&details[k])put(expand,details[k],'OVERLAY');
      else {const d=one(cards[k],'Account details');if(d)d.visible=true;hide(cards[k],'Icon/down');}
    }
    return {f,cards};
  }
  function confirmation(key,account,origin,result){
    const n=make(e.connect,'Disconnect/'+key),sh=one(n,'Sheet'),heading=one(sh,'Sheet heading');change(heading.children.find(v=>v.type==='TEXT'),'断开连接？');
    const vp=one(sh,'Sheet viewport');one(vp,'Content').remove();const b=frame(vp,'Content',393);b.paddingLeft=b.paddingRight=20;b.paddingTop=8;b.paddingBottom=20;
    label(e,b,accounts[account].email,14);label(e,b,'移除此账号的额度数据和待发提醒。平台订阅不会取消。',13);
    put(addButton(e,b,'断开连接',true),result);put(addButton(e,b,'取消'),origin);
    const h=116+b.height;sh.resize(393,h);sh.y=852-h;vp.resize(393,h-96);const indicator=one(sh,'Home indicator');if(indicator){indicator.y=h-14;put(indicator,origin);}
    put(one(sh,'Action/close'),origin);const bg=n.children.find(v=>v.type==='RECTANGLE');if(bg)put(bg,origin);return n;
  }
  const steps=[];
  for(let i=0;i<4;i++){
    const state=states[i],next=states[i+1],removed=['C','B','A','D'][i],l=list(state.order.join(''),state.order,state.home.f);
    const confirm=confirmation(state.order.join('')+'/'+removed,removed,l.f,next.home.f);
    for(const [k,card] of Object.entries(l.cards)){const more=one(card,'Action/more');if(k===removed)put(more,confirm);else if(more)more.visible=false;}
    appTarget(state.home.f,l.f);put(one(state.home.f,'Action/back'),l.f);
    steps.push({order:state.order,selected:state.selected,home:state.home.f.id,list:l.f.id,remove:removed,confirm:confirm.id,result:next.home.f.id,resultSelected:next.selected});
  }
  entry('断开后的回退 · 逐账号操作',base.home.f);

  // Real five-account source list: A is before B, but B is the first remaining
  // Codex candidate and E remains present after work is removed.
  const multiOrder=['A','B','C','D','E'],multiBefore=home('MultipleCandidatesBefore','small',['C','D'],true),multiHome=home('MultipleCandidates','small',['B','D'],true);
  const multi=list('ABCDE',multiOrder,multiBefore.f),multiConfirm=confirmation('ABCDE/C','C',multi.f,multiHome.f);
  appTarget(multiBefore.f,multi.f);
  for(const [k,card] of Object.entries(multi.cards)){const more=one(card,'Action/more');if(k==='C')put(more,multiConfirm);else if(more)more.visible=false;}
  const multiAfter=list('ABDE',['A','B','D','E'],multiHome.f);
  for(const card of Object.values(multiAfter.cards))hide(card,'Action/more');
  appTarget(multiHome.f,multiAfter.f);put(one(multiHome.f,'Action/back'),multiAfter.f);
  entry('同平台多个候选 · 列表顺序',multiBefore.f);entry('全部断开 · 无账号状态',states[4].home.f);
  put(addButton(e,hb,'返回评审入口'),e.entry);
  await flush();report.stages.push(t+'/widgets');
  return {status:t+' 小组件阶段完成',hub:hub.id,entries,screenCount:created.length,screens:created.map(n=>({id:n.id,name:n.name})),accounts:Object.values(accounts).map(({key,platform,email,windows,updated})=>({key,platform,email,windows,updated})),widgetTargets:targets,fallbackSteps:steps,multipleCandidates:{order:multiOrder,start:multiBefore.f.id,initialSelected:['C','D'],list:multi.f.id,confirm:multiConfirm.id,result:multiHome.f.id,afterList:multiAfter.f.id,selected:['B','D'],remaining:['A','B','D','E']},emptyGuide:emptyGuide.id,connectTrigger:connectTrigger.id,tutorialTrigger:one(emptyGuide,'Action/如何添加小组件')?.id,integrationRequired:'Attach emptyGuide connectTrigger to the account stage network-gated add flow and tutorialTrigger to the tutorial flow; no original R3 product button was changed.'};
}


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


// Finite notification/system states for already-wired account models.
// Append after core, foundation, flows, and r4-system.js. No old notification
// settings root is used as a source. Each model adds exactly nine roots.
const R4_ACCOUNT_SYSTEM_VERSION = '1';

function accountSystemRequired(node, description) {
  if (!node) throw Error('Account system missing ' + description);
  return node;
}
function accountSystemReactions(node) {
  return jobs.has(node) ? jobs.get(node) : node.reactions || [];
}
function accountSystemDestination(node) {
  if (!node) return null;
  for (const reaction of accountSystemReactions(node)) {
    for (const action of reaction.actions || (reaction.action ? [reaction.action] : [])) {
      if (action.type === 'NODE' && action.destinationId) return action.destinationId;
    }
  }
  return null;
}
function accountSystemToggleNode(frame) {
  return frame.findOne(node => node.type === 'INSTANCE' &&
    (node.name === 'System/Notification toggle' || /(?:^|,)\s*State=(?:Off|On)(?:,|$)/.test(node.name)));
}
function accountSystemScope(model) {
  return model.pendingIdx === undefined ? 'Set-' + model.mask : 'Pending-' + model.mask + '-' + model.pendingIdx;
}
function accountSystemTag(model) {
  return 'r4_account_system_' + model.mask + '_' + (model.pendingIdx === undefined ? 'ready' : model.pendingIdx);
}
function accountSystemDeniedHint(e, settings) {
  const group = accountSystemRequired(one(settings, 'Group/通用'), settings.name + ' general group');
  let box = one(group, 'Notification permission message');
  if (!box) {
    box = frame(group, 'Notification permission message', group.width);
    box.paddingLeft = box.paddingRight = 16;
    box.paddingBottom = 12;
    const hint = label(e, box, '系统通知权限未开启。点按开关可前往设置。', 12, 'Notification permission hint');
    hint.opacity = .68;
  }
  // The source general group contains a single 52 px row. Let the error text
  // participate in layout instead of obscuring the following support group.
  mark(group).primaryAxisSizingMode = 'AUTO';
}
function accountSystemHasAction(node, type, destinationId, navigation) {
  if (!node) return false;
  return accountSystemReactions(node).some(reaction => (reaction.actions || (reaction.action ? [reaction.action] : [])).some(action =>
    action.type === type && (destinationId === undefined || action.destinationId === destinationId) &&
    (navigation === undefined || action.navigation === navigation)));
}
function accountSystemValidateSupport(e) {
  // supportOnlyStage deliberately has no legacy system-stage completion tag.
  // Read the real return edges so both support entry points are supported.
  const tutorial = ['Tutorial1', 'Tutorial1b', 'Tutorial2', 'Tutorial2b'].map(key => systemKind(e, key));
  const pages = Object.fromEntries(['Help', 'Privacy', 'Licenses', 'License'].map(key => [key, systemKind(e, key)]));
  const valid = tutorial.every(item => accountSystemHasAction(one(item, 'Action/close'), 'CLOSE')) &&
    tutorial.slice(0, 2).every(item => accountSystemHasAction(button(item, '下一步'), 'NODE', tutorial[2].id, 'SWAP')) &&
    tutorial.slice(2).every(item => accountSystemHasAction(button(item, '完成'), 'CLOSE')) &&
    ['Help', 'Privacy', 'Licenses'].every(key => accountSystemHasAction(one(pages[key], 'Action/back'), 'CLOSE')) &&
    accountSystemHasAction(one(pages.Licenses, 'Row/CodexBar'), 'NODE', pages.License.id, 'SWAP') &&
    accountSystemHasAction(one(pages.License, 'Action/back'), 'NODE', pages.Licenses.id, 'SWAP');
  if (!valid) throw Error('Run supportOnlyStage or the shared tutorial/support system stage before account system models');
}

// A completion tag alone is insufficient: base R3 settings could have been
// modified by an older system stage. Validate the concrete account menu edges.
function accountSystemValidateModel(e, model) {
  const state = model.pendingIdx === undefined ? 'ready' : model.pendingIdx;
  if (!e.branch.getPluginData('r4_wired_' + model.mask + '_' + state)) {
    throw Error('Wire and flush account model ' + model.mask + ' / ' + state + ' before its system stage');
  }
  if (model.pendingIdx !== undefined && !model.accounts.includes(model.pendingIdx)) throw Error('Pending account is absent from the source model');
  for (const [kind, frame] of [['d', model.d], ['s', model.s]]) {
    accountSystemRequired(one(frame, 'Tab/额度'), frame.name + ' quota tab');
    accountSystemRequired(one(frame, 'Tab/设置'), frame.name + ' settings tab');
    for (const idx of model.accounts) {
      const item = kind === 'd' ? findCard(frame, idx) : findRow(frame, idx);
      const more = accountSystemRequired(one(item, 'Action/more'), frame.name + ' account menu ' + idx);
      const expected = e.registry.get('R4/' + e.t + '/AccountFlow/' + accountSystemScope(model) + '/' + kind + '/Menu-' + idx);
      if (!expected || accountSystemDestination(more) !== expected.id) {
        throw Error('Account system source still has a stale menu: mask ' + model.mask + ', ' + kind + ', account ' + idx);
      }
    }
  }
  accountSystemRequired(one(model.s, 'Toggle/通知'), model.s.name + ' notification toggle');
  accountSystemRequired(one(model.s, 'Group/通用'), model.s.name + ' general group');
}

async function accountSystemExisting(e, model) {
  const stored = e.branch.getPluginData(accountSystemTag(model));
  if (!stored) return null;
  try {
    const value = JSON.parse(stored);
    if (value.version !== R4_ACCOUNT_SYSTEM_VERSION || value.mask !== model.mask || value.pendingIdx !== model.pendingIdx || value.theme !== e.t) return null;
    const ids = [...Object.values(value.settings || {}), ...Object.values(value.dashboards || {}), value.permission, ...Object.values(value.system || {})];
    if (ids.length !== 9 || new Set(ids).size !== 9 || ids.some(id => typeof id !== 'string')) return null;
    const prefix = 'R4/' + e.t + '/AccountSystem/' + accountSystemScope(model) + '/';
    for (const id of ids) {
      const node = await figma.getNodeByIdAsync(id);
      if (!node || node.removed || node.type !== 'FRAME' || !node.name.startsWith(prefix)) return null;
    }
    return value;
  } catch (_) { return null; }
}

function accountSystemSupport(e, frame, kind, state, dashboards, settings, tutorial, pages) {
  put(accountSystemRequired(one(frame, 'Tab/额度'), frame.name + ' quota tab'), dashboards[state]);
  put(accountSystemRequired(one(frame, 'Tab/设置'), frame.name + ' settings tab'), settings[state]);
  for (const name of ['Action/如何添加小组件', 'Row/如何添加小组件']) {
    const entry = one(frame, name);
    if (entry) put(entry, tutorial, 'OVERLAY');
  }
  if (kind === 's') {
    for (const [label, key] of [['帮助与说明', 'Help'], ['隐私说明', 'Privacy'], ['开源许可', 'Licenses']]) {
      put(accountSystemRequired(one(frame, 'Row/' + label), frame.name + ' ' + label), pages[key], 'OVERLAY');
    }
  }
}

async function wireAccountSystem(e, model) {
  accountSystemValidateSupport(e);
  accountSystemValidateModel(e, model);
  const existing = await accountSystemExisting(e, model);
  if (existing) return { ...existing, skipped: true, createdFrameCount: 0 };

  // Validate all shared visual sources and destinations before creating roots.
  const permissionSource = systemKind(e, 'Permission');
  const systemSource = systemKind(e, 'System');
  const tutorial = systemKind(e, 'Tutorial1');
  const pages = Object.fromEntries(['Help', 'Privacy', 'Licenses'].map(key => [key, systemKind(e, key)]));
  accountSystemRequired(button(permissionSource, '允许'), 'permission Allow button');
  accountSystemRequired(button(permissionSource, '不允许'), 'permission Deny button');
  accountSystemRequired(one(permissionSource, 'Action/close'), 'permission close');
  accountSystemRequired(permissionSource.children.find(node => node.type === 'RECTANGLE'), 'permission scrim');
  accountSystemRequired(accountSystemToggleNode(systemSource), 'system notification toggle');
  accountSystemRequired(one(systemSource, 'Action/back'), 'system back');
  const variants = await systemToggleComponents(one(model.s, 'Toggle/通知'), e.t);
  const key = 'AccountSystem/' + accountSystemScope(model);
  const before = e.registry.size, settings = {}, dashboards = {};

  for (const state of ['on', 'off', 'denied']) {
    settings[state] = root(e, model.s, key + '/Settings-' + state);
    dashboards[state] = root(e, model.d, key + '/Dashboard-' + state);
    // This runs for new and incomplete roots. root() clears cloned reactions;
    // copying the completed ready model restores only current account actions.
    await copyFlowTree(model.s, settings[state]);
    await copyFlowTree(model.d, dashboards[state]);
    systemSetToggle(one(settings[state], 'Toggle/通知'), state === 'on' ? variants.on : variants.off, 'Toggle/通知');
    if (state === 'denied') accountSystemDeniedHint(e, settings[state]);
  }
  const permission = root(e, permissionSource, key + '/Permission');
  const system = {
    off: root(e, systemSource, key + '/iOS-off'),
    on: root(e, systemSource, key + '/iOS-on')
  };
  clear(permission);
  systemSheetClose(permission);
  put(button(permission, '允许'), settings.on);
  put(button(permission, '不允许'), settings.denied);

  // Initial means the permission has not been requested. Off means permission
  // was granted and the App switch was subsequently turned off.
  systemSetToggle(one(model.s, 'Toggle/通知'), variants.off, 'Toggle/通知');
  systemNotificationAction(model.s, permission, 'OVERLAY');
  systemNotificationAction(settings.on, settings.off, 'NAVIGATE');
  systemNotificationAction(settings.off, settings.on, 'NAVIGATE');
  systemNotificationAction(settings.denied, system.off, 'NAVIGATE');

  for (const state of ['off', 'on']) {
    const frame = system[state];
    clear(frame);
    const toggle = accountSystemRequired(accountSystemToggleNode(frame), frame.name + ' toggle');
    systemSetToggle(toggle, state === 'on' ? variants.on : variants.off, 'System/Notification toggle');
    put(toggle, state === 'on' ? system.off : system.on, 'NAVIGATE', { smart: true });
    put(one(frame, 'Action/back'), state === 'on' ? settings.on : settings.denied);
  }
  for (const state of ['on', 'off', 'denied']) {
    accountSystemSupport(e, settings[state], 's', state, dashboards, settings, tutorial, pages);
    accountSystemSupport(e, dashboards[state], 'd', state, dashboards, settings, tutorial, pages);
  }
  // The original ready pair remains the unasked-permission state. Use the same
  // per-model tab and overlay routes, including base mask 15.
  accountSystemSupport(e, model.s, 's', 'initial', { initial: model.d }, { initial: model.s }, tutorial, pages);
  accountSystemSupport(e, model.d, 'd', 'initial', { initial: model.d }, { initial: model.s }, tutorial, pages);

  const result = {
    version: R4_ACCOUNT_SYSTEM_VERSION, theme: e.t, mask: model.mask, pendingIdx: model.pendingIdx,
    settings: Object.fromEntries(Object.entries(settings).map(([state, node]) => [state, node.id])),
    dashboards: Object.fromEntries(Object.entries(dashboards).map(([state, node]) => [state, node.id])),
    permission: permission.id,
    system: Object.fromEntries(Object.entries(system).map(([state, node]) => [state, node.id]))
  };
  await flush();
  // Persist only after all native reactions have successfully committed.
  e.branch.setPluginData(accountSystemTag(model), JSON.stringify(result));
  figma.commitUndo();
  return { ...result, skipped: false, createdFrameCount: e.registry.size - before };
}

async function accountSystemStage(t, start = 0, count = 4) {
  if (!Number.isInteger(start) || start < 0 || start >= 64 || !Number.isInteger(count) || count < 1 || count > 4) {
    throw Error('Account system batches require model index 0–63 and count 1–4');
  }
  const e = await env(t), results = [];
  // supportOnlyStage/systemStage supplies caller-preserving support overlays.
  // Old notification settings roots are never read or copied by this module.
  accountSystemValidateSupport(e);
  for (let index = start; index < Math.min(start + count, 64); index++) {
    const mask = R4_ACCOUNT_MASKS[index];
    if (!e.branch.getPluginData('r4_wired_' + mask + '_ready')) {
      throw Error('Ready account model ' + mask + ' is not yet wired and flushed');
    }
    const model = await getAccountModel(e, mask);
    figma.ui.postMessage({ status: t + ' 通知与系统返回 ' + (index + 1) + '/64', progress: true });
    results.push(await wireAccountSystem(e, model));
    await new Promise(resolve => setTimeout(resolve, 0));
  }
  return {
    status: t + ' 当前账号集合的通知与系统路径批次完成', start, end: Math.min(start + count, 64),
    createdFrameCount: results.reduce((sum, result) => sum + result.createdFrameCount, 0), models: results,
    scope: 'Ready account sets only. Tabs and shared support/tutorial overlays preserve notification state. Account mutations continue through ready account paths.'
  };
}


// Bounded integrations. All source masks and component identities were inspected.
async function supportOnlyStage(t){
 const e=await env(t),tutorial=['Tutorial1','Tutorial1b','Tutorial2','Tutorial2b'].map(k=>systemKind(e,k));
 for(const f of tutorial){clear(f);systemSheetClose(f);}
 for(const f of tutorial.slice(0,2))put(button(f,'下一步'),tutorial[2],'SWAP',{smart:true});
 for(const f of tutorial.slice(2))close(button(f,'完成'));
 put(tutorial[0],tutorial[1],'SWAP',{timeout:.9,smart:true});put(tutorial[2],tutorial[3],'SWAP',{timeout:.9,smart:true});
 const pages=Object.fromEntries(['Help','Privacy','Licenses','License'].map(k=>[k,systemKind(e,k)]));
 for(const k of ['Help','Privacy','Licenses']){clear(pages[k]);close(one(pages[k],'Action/back'));}
 clear(pages.License);put(one(pages.Licenses,'Row/CodexBar'),pages.License,'SWAP');put(one(pages.License,'Action/back'),pages.Licenses,'SWAP');
 await flush();return{status:t+' 教程与说明返回路径已连接',tutorial:tutorial.map(n=>n.id)};
}
function nativeHomeBar(f){return one(f,'Home indicator')||f.children.find(n=>n.type==='RECTANGLE'&&Math.abs(n.width-134)<1&&n.height<8);}
async function accountExtraModel(e,m){
 const key='r4_extra_'+m.mask+'_'+(m.pendingIdx===undefined?'ready':m.pendingIdx);
 if(e.branch.getPluginData(key))return;
 if(m.pendingIdx!==undefined){
  const c=await flowCommon(e);m.widgetDetails={};m.widgetNavigation={};
  for(const idx of m.accounts){
   if(idx===m.pendingIdx){const f=panel(e,flowKey(m)+'/WidgetUnknown',R4A[idx].p+' 账户',[R4A[idx].email,'尚未获取额度'],['关闭']);close(button(f,'关闭'));m.widgetDetails[idx]=f;}
   else m.widgetDetails[idx]=c.detail[idx];m.widgetNavigation[idx]='OVERLAY';
  }
 }
 const home=await accountWidgetHome(e,m);
 for(const f of [m.d,m.s,...Object.values(m.details||{})]){const b=nativeHomeBar(f);if(b)put(b,home);}
 if(m.pendingIdx!==undefined){const previous=m.mask&~R4A[m.pendingIdx].bit,bound=e.registry.get('R4/'+e.t+'/AccountFlow/Add-'+previous+'-'+m.pendingIdx+'/Bound');if(bound){const b=nativeHomeBar(bound);if(b)put(b,home);}}
 const sys=await wireAccountSystem(e,m);
 await flush();e.branch.setPluginData(key,'1');figma.commitUndo();return{mask:m.mask,pendingIdx:m.pendingIdx,home:home.id,system:sys};
}
async function accountExtrasStage(t,start=0,count=4,pending=false){
 const e=await env(t),list=pending?[...new Map([...e.registry.values()].map(n=>n.name.match(new RegExp('^R4/'+t+'/AccountFlow/Pending-(\\d+)-(\\d+)/Dashboard$'))).filter(Boolean).map(m=>[m[1]+'/'+m[2],{mask:+m[1],idx:+m[2]}])).values()].sort((a,b)=>a.mask-b.mask||a.idx-b.idx):R4_ACCOUNT_MASKS.map(mask=>({mask}));
 const out=[];for(let i=start;i<Math.min(start+count,list.length);i++){const x=list[i],m=pending?await pendingModel(e,x.mask,x.idx):await getAccountModel(e,x.mask);figma.ui.postMessage({status:t+' 通知与小组件路径 '+(i+1)+'/'+list.length+(pending?' · 待获取额度':''),progress:true});const z=await accountExtraModel(e,m);if(z)out.push(z);await new Promise(r=>setTimeout(r,0));}
 return{status:t+' 通知与小组件批次完成',start,end:Math.min(start+count,list.length),total:list.length,pending,models:out};
}

async function repairHiddenControlsStage(t){const e=await env(t);for(const f of [e.dashboard,e.settings]){function walk(n,visible=true){visible=visible&&n.visible!==false;if(!visible&&'reactions'in n)jobs.set(n,[]);if('children'in n)for(const child of n.children)walk(child,visible);}walk(f);}const home=e.registry.get('R4/'+t+'/AccountWidgets/Set-15');if(home)home.setPluginData('r4_account_widget_signature','');await flush();return{status:t+' 隐藏旧控件反应已清除'};}
// One observed renderer defect only: native geometry/paint is healthy but the
// prototype repeatedly fails to paint this cloned instance's label.
async function repairCancelRenderStage(t,id){const e=await env(t),f=await figma.getNodeByIdAsync(id);if(!f||!f.name.startsWith('R4/'+t+'/'))throw Error('Expected scoped R4 root');let b=button(f,'取消');if(!b)throw Error('Missing cancel');const before=b.id;if(b.type==='INSTANCE'){b=b.detachInstance();b.name='Button/取消';}for(const tx of txt(b)){mark(tx).visible=true;tx.opacity=1;}close(b);await flush();return{status:t+' 单一取消按钮已重新实例化为局部图层',root:id,before,after:b.id,characters:txt(b).map(n=>n.characters)};}


// Local extension: Set-31 (Claude F already added) -> add Cursor G -> Set-95.
// Append after foundation, flows, account widgets/system, and integrate.
// No stage runs on load. Original 64 mask positions are never reordered.
const R4_CROSS_MASKS = Array.from({ length: 16 }, (_, base) => 80 + base);
const R4_CROSS_VERSION = '1';

function crossAddMasks() {
  const original = [0, 16, 32, 64].flatMap(extra => Array.from({ length: 16 }, (_, base) => extra + base));
  if (original.some((mask, i) => R4_ACCOUNT_MASKS[i] !== mask)) throw Error('Original account mask order changed');
  for (const mask of R4_CROSS_MASKS) if (!R4_ACCOUNT_MASKS.includes(mask)) R4_ACCOUNT_MASKS.push(mask);
  return R4_CROSS_MASKS;
}
function crossAddBatch(start, count, length) {
  if (!Number.isInteger(start) || start < 0 || start >= length || !Number.isInteger(count) || count < 1 || count > 4) throw Error('Cross-add batches require a valid start and count 1–4');
  return Math.min(start + count, length);
}
function crossAddPendingList(e, onlyUnwired = false) {
  const prefix = new RegExp('^R4/' + e.t + '/AccountFlow/Pending-(\\d+)-(\\d+)/Dashboard$');
  const found = new Map();
  for (const node of e.registry.values()) {
    const match = node.name.match(prefix);
    if (!match || !R4_CROSS_MASKS.includes(+match[1])) continue;
    const mask = +match[1], idx = +match[2];
    if (onlyUnwired && flowTag(e, 'r4_wired_' + mask + '_' + idx)) continue;
    found.set(mask + '/' + idx, { mask, idx });
  }
  return [...found.values()].sort((a, b) => a.mask - b.mask || a.idx - b.idx);
}
function crossAddExpectedPending() {
  // G is the newly added extra. Restoring a removed original account must also
  // remain actionable in the paired sets; these add 32 pending base-account
  // models. F never becomes pending in this one-direction example.
  return R4_CROSS_MASKS.flatMap(mask => [0, 1, 2, 3, 6].filter(idx => mask & R4A[idx].bit).map(idx => ({ mask, idx })));
}
function crossAddNode(e, key) { return e.registry.get('R4/' + e.t + '/' + key); }
function crossAddRequired(node, description) { if (!node || node.removed) throw Error('Cross-add missing ' + description); return node; }
function crossAddActions(node) {
  if (!node) return [];
  return (jobs.has(node) ? jobs.get(node) : node.reactions || []).flatMap(r => r.actions || (r.action ? [r.action] : []));
}
function crossAddEdge(node, target, navigation) {
  return !!node && !!target && crossAddActions(node).some(a => a.type === 'NODE' && a.destinationId === target.id && (!navigation || a.navigation === navigation));
}
function crossAddSnapshot(model) {
  return JSON.stringify({ mask: model.mask, accounts: model.accounts,
    dashboard: txt(model.d).map(n => [n.name, n.characters]),
    settings: txt(model.s).map(n => [n.name, n.characters]) });
}

// Prepare the gated addition and its pending launch without exposing an
// unfinished destination from any product control. Run before the ready batches.
async function accountCrossAddPrepareStage(t) {
  crossAddMasks();
  const e = await env(t), source = await getAccountModel(e, 31);
  if (!flowTag(e, 'r4_wired_31_ready')) throw Error('Wire original Set-31 before cross-add preparation');
  const chooser = crossAddRequired(crossAddNode(e, 'AccountFlow/Set-31/Connect'), 'Set-31 chooser');
  crossAddRequired(one(chooser, 'Connect/Cursor'), 'Set-31 Cursor choice');
  const key = 'r4_cross_add_source_snapshot';
  if (!e.branch.getPluginData(key)) e.branch.setPluginData(key, crossAddSnapshot(source));
  const c = await flowCommon(e), gate = await addition(e, source, 'Cursor', c);
  if (gate === c.addFail.Cursor) throw Error('Cross-add still resolves to the simulated authorization failure');
  await flowFlush(e);
  return { status: t + ' 连续添加路径已准备，尚未替换产品入口', source: source.d.id, sourceMask: 31, targetMask: 95,
    account: R4A[6].email, check: gate.id, readyMasks: R4_CROSS_MASKS, expectedNewPendingModels: 48,
    pendingRemaining: crossAddPendingList(e, true).length };
}

async function accountCrossAddReadyStage(t, start = 0, count = 1) {
  crossAddMasks();
  const end = crossAddBatch(start, count, 16), e = await env(t), c = await flowCommon(e), results = [];
  if (!flowTag(e, 'add_31_6')) throw Error('Prepare the cross-add path before wiring its closure');
  for (let i = start; i < end; i++) {
    const mask = R4_CROSS_MASKS[i], model = await getAccountModel(e, mask);
    figma.ui.postMessage({ status: t + ' 连续添加账号集合 ' + (i + 1) + '/16', progress: true });
    // Existing ready source sets are untouched. Missing original accounts in
    // this family may be added back through their own network-gated flows.
    await wireAccountModel(e, model, c, true);
    await flowFlush(e);
    results.push({ mask, dashboard: model.d.id, settings: model.s.id });
    await new Promise(resolve => setTimeout(resolve, 0));
  }
  return { status: t + ' 连续添加 ready 闭包批次完成', start, end, total: 16, models: results, pendingRemaining: crossAddPendingList(e, true).length };
}

// Drain only the new 80..95 family. It never takes work from the original
// 176 pending models, so this can coexist with their separately queued batches.
async function accountCrossAddPendingStage(t, count = 1) {
  crossAddMasks();
  if (!Number.isInteger(count) || count < 1 || count > 4) throw Error('Cross-add pending count must be 1–4');
  const e = await env(t), c = await flowCommon(e), results = [];
  if (R4_CROSS_MASKS.some(mask => !flowTag(e, 'r4_wired_' + mask + '_ready'))) throw Error('Finish all 16 cross-add ready models before draining pending models');
  for (let i = 0; i < count; i++) {
    const next = crossAddPendingList(e, true)[0];
    if (!next) break;
    const model = await pendingModel(e, next.mask, next.idx);
    figma.ui.postMessage({ status: t + ' 连续添加待获取额度 ' + next.mask + ' / ' + next.idx, progress: true });
    await wireAccountModel(e, model, c, false);
    await flowFlush(e);
    results.push({ mask: next.mask, pendingIdx: next.idx, dashboard: model.d.id, settings: model.s.id });
    await new Promise(resolve => setTimeout(resolve, 0));
  }
  return { status: t + ' 连续添加 pending 闭包批次完成', models: results,
    totalDiscovered: crossAddPendingList(e).length, expectedTotal: 48, remaining: crossAddPendingList(e, true).length };
}

async function accountCrossAddExtrasStage(t, start = 0, count = 1, pending = false) {
  crossAddMasks();
  const e = await env(t), list = pending ? crossAddPendingList(e) : R4_CROSS_MASKS.map(mask => ({ mask }));
  if (pending && (list.length !== 48 || crossAddPendingList(e, true).length)) throw Error('Finish the 48 local pending models before their widget/system extras');
  const end = crossAddBatch(start, count, list.length), results = [];
  for (let i = start; i < end; i++) {
    const item = list[i], state = pending ? item.idx : 'ready';
    if (!flowTag(e, 'r4_wired_' + item.mask + '_' + state)) throw Error('Unwired cross-add model ' + item.mask + '/' + state);
    const model = pending ? await pendingModel(e, item.mask, item.idx) : await getAccountModel(e, item.mask);
    figma.ui.postMessage({ status: t + ' 连续添加小组件与返回 ' + (i + 1) + '/' + list.length, progress: true });
    const result = await accountExtraModel(e, model);
    results.push(result || { mask: item.mask, pendingIdx: pending ? item.idx : undefined, skipped: true });
    await new Promise(resolve => setTimeout(resolve, 0));
  }
  return { status: t + ' 连续添加 extras 批次完成', start, end, total: list.length, pending, models: results };
}

// Static audit only; no missing frame is materialized here. Dynamic prototype
// clicks (especially overlay Cancel) remain a separate acceptance requirement.
async function accountCrossAddAuditStage(t) {
  const e = await env(t), errors = [], models = [];
  const expect = (ok, description) => { if (!ok) errors.push(description); };
  const checkModel = (mask, pendingIdx) => {
    const isPending = pendingIdx !== undefined, state = isPending ? pendingIdx : 'ready';
    const key = isPending ? pendingKey(mask, pendingIdx) : accountModelKey(mask, '').replace(/\/$/, '');
    const d = crossAddNode(e, key + '/Dashboard'), s = crossAddNode(e, key + '/Settings');
    expect(!!d && !!s, key + ' dashboard/settings exist');
    expect(!!flowTag(e, 'r4_wired_' + mask + '_' + state), key + ' reactions flushed');
    expect(!!e.branch.getPluginData('r4_extra_' + mask + '_' + state), key + ' widget/system extras complete');
    if (!d || !s) return;
    const accounts = R4_ACCOUNT_ORDER.filter(idx => mask & R4A[idx].bit);
    for (const idx of accounts) {
      const a = R4A[idx], card = findCard(d, idx), row = findRow(s, idx);
      expect(!!card && card.visible !== false && !!row && row.visible !== false, key + ' visible account ' + a.email);
      if (card) {
        expect(txt(card).some(n => n.characters === a.email), key + ' exact identity ' + idx);
        const values = txt(card).filter(n => n.name.startsWith('Value/')).map(n => n.characters);
        expect(JSON.stringify(values) === JSON.stringify(isPending && pendingIdx === idx ? a.v.map(() => '—') : a.v.map(v => v + '%')), key + ' correct quota ' + idx);
        if (isPending && pendingIdx === idx) expect(card.findAll(n => n.name.startsWith('Bar/') && n.visible !== false).length === 0, key + ' pending has no quota bar');
      }
      for (const [origin, view] of [['d', d], ['s', s]]) {
        const scope = isPending ? key : 'AccountFlow/Set-' + mask;
        const menu = crossAddNode(e, scope + '/' + origin + '/Menu-' + idx);
        const confirm = crossAddNode(e, scope + '/' + origin + '/Disconnect-' + idx);
        const more = one(origin === 'd' ? findCard(view, idx) : findRow(view, idx), 'Action/more');
        expect(crossAddEdge(more, menu, 'OVERLAY'), key + ' precise menu ' + origin + '/' + idx);
        expect(crossAddEdge(menu && button(menu, '断开连接'), confirm, 'SWAP'), key + ' disconnect overlay ' + origin + '/' + idx);
        const next = mask & ~a.bit;
        const nextKey = isPending && pendingIdx !== idx ? pendingKey(next, pendingIdx) : accountModelKey(next, '').replace(/\/$/, '');
        const destination = crossAddNode(e, nextKey + (origin === 's' ? '/Settings' : '/Dashboard'));
        expect(crossAddEdge(confirm && button(confirm, '断开连接'), destination, 'NAVIGATE'), key + ' disconnect preserves source/data ' + origin + '/' + idx);
        expect(!!confirm && crossAddActions(button(confirm, '取消')).some(action => action.type === 'CLOSE'), key + ' disconnect cancel closes ' + origin + '/' + idx);
      }
    }
    expect(crossAddEdge(one(d, 'Tab/设置'), s, 'NAVIGATE'), key + ' settings tab');
    expect(crossAddEdge(one(s, 'Tab/额度'), d, 'NAVIGATE'), key + ' quota tab');
    models.push({ mask, pendingIdx, accounts, dashboard: d.id, settings: s.id });
  };
  R4_CROSS_MASKS.forEach(mask => checkModel(mask));
  const pending = crossAddExpectedPending();
  pending.forEach(item => checkModel(item.mask, item.idx));
  const sourceD = crossAddNode(e, 'Accounts/Set-31/Dashboard'), sourceS = crossAddNode(e, 'Accounts/Set-31/Settings');
  if (sourceD && sourceS) expect(e.branch.getPluginData('r4_cross_add_source_snapshot') === crossAddSnapshot({ mask: 31, accounts: R4_ACCOUNT_ORDER.filter(idx => 31 & R4A[idx].bit), d: sourceD, s: sourceS }), 'Original Set-31 identity/quota/settings text unchanged');
  else errors.push('Original Set-31 source missing');
  const gateId = flowTag(e, 'add_31_6'), gate = gateId && await figma.getNodeByIdAsync(gateId);
  const chooser = crossAddNode(e, 'AccountFlow/Set-31/Connect');
  const active = !!gate && crossAddEdge(chooser && one(chooser, 'Connect/Cursor'), gate, 'SWAP');
  const login = crossAddNode(e, 'AccountFlow/Add-31-6/Login');
  const authorization = crossAddNode(e, 'AccountFlow/Add-31-6/Authorization');
  const bound = crossAddNode(e, 'AccountFlow/Add-31-6/Bound');
  const firstId = flowTag(e, 'pending_q_95_6_d_pending');
  const first = firstId && await figma.getNodeByIdAsync(firstId);
  const loading = crossAddNode(e, pendingKey(95, 6) + '/FirstQuery-d-pending/Loading');
  expect(!!gate && !gate.removed, 'Representative add begins at a real network-check frame');
  expect(crossAddEdge(login && button(login, '继续'), authorization, 'SWAP'), 'Representative login continues to authorization');
  for (const [name, frame] of [['login', login], ['authorization', authorization]]) expect(!!frame && crossAddActions(button(frame, '取消')).some(a => a.type === 'CLOSE'), 'Representative ' + name + ' Cancel preserves overlay source');
  expect(crossAddEdge(authorization, bound, 'NAVIGATE'), 'Successful authorization creates the bound pending source');
  expect(crossAddEdge(bound, first, 'OVERLAY'), 'Bound source begins a separate first-query check');
  expect(crossAddEdge(loading, crossAddNode(e, 'Accounts/Set-95/Dashboard'), 'NAVIGATE'), 'First-query completion opens ready Set-95');
  const boundCard = bound && findCard(bound, 6);
  expect(!!boundCard && txt(boundCard).filter(n => n.name.startsWith('Value/')).every(n => n.characters === '—'), 'Launch copy has no fabricated Cursor quota');
  expect(crossAddEdge(bound && nativeHomeBar(bound), crossAddNode(e, 'AccountWidgets/Set-95/Pending-6'), 'NAVIGATE'), 'First-query Cancel retains a working pending widget return');
  return { status: t + ' 连续添加静态审查', passed: errors.length === 0, activated: active, errors,
    sourceMask: 31, targetMask: 95, readyModels: 16, expectedPendingModels: 48, pendingDiscovered: crossAddPendingList(e).length,
    pendingRemaining: crossAddPendingList(e, true).length, models,
    unverified: ['Actual click: both pre-add/authorization Cancel return to unchanged Set-31', 'Actual click: cancel first quota query leaves G bound with no quota', 'Actual click: query retry checks again before Set-95', 'Actual click: disconnect G returns Set-31; disconnect F returns Set-79; deleting originals preserves both extras', 'Actual click: widget Cursor fallback to G uses G identity, quota or pending state, and click target'] };
}

// The only rewired existing product node is Set-31's Cursor provider choice.
// Run last, after the local audit is complete; all its callers share this chooser.
async function accountCrossAddActivateStage(t) {
  crossAddMasks();
  const audit = await accountCrossAddAuditStage(t);
  if (!audit.passed) throw Error('Cross-add not activated: ' + audit.errors.slice(0, 8).join('; '));
  const e = await env(t), chooser = crossAddRequired(crossAddNode(e, 'AccountFlow/Set-31/Connect'), 'source chooser');
  const gate = crossAddRequired(await flowStoredNode(e, 'add_31_6'), 'gated addition');
  const entry = crossAddRequired(one(chooser, 'Connect/Cursor'), 'Cursor choice');
  put(entry, gate, 'SWAP');
  await flowFlush(e);
  const result = { version: R4_CROSS_VERSION, sourceMask: 31, targetMask: 95, provider: 'Cursor', account: R4A[6].email,
    source: entry.id, check: gate.id, readyModels: 16, pendingModels: 48, originalModelBatchesRerun: 0 };
  e.branch.setPluginData('r4_cross_add_active', JSON.stringify(result));
  figma.commitUndo();
  return { status: t + ' Claude 后继续添加 Cursor 的代表性路径已接入', ...result };
}


// Scoped notification-mode preservation for finite review stories.
// Append after core, foundation, flows, account-system, integrate, cross-add.
// No code runs on load; this never changes canonical/initial account controls.
const R4_PERMISSION_READY_MASKS = [...Array.from({ length: 16 }, (_, i) => i), 31, 47, 79, 95];
const R4_PERMISSION_ADD_ROUTES = [
  { source: 15, idx: 4, next: 31 }, { source: 15, idx: 5, next: 47 },
  { source: 15, idx: 6, next: 79 }, { source: 31, idx: 6, next: 95 }
];
const R4_PERMISSION_MODES = ['on', 'off', 'denied'];
const R4_PERMISSION_VERSION = '1';

function permissionPreservePlan() {
  return { readyMasks: R4_PERMISSION_READY_MASKS, modes: R4_PERMISSION_MODES, additionRoutes: R4_PERMISSION_ADD_ROUTES,
    estimatedNewFramesPerTheme: { readyMenusAndConfirmations: 636, pendingQueries: 192, pendingMenusAndReconnect: 48, additionChains: 72, choosers: 6, total: 954 },
    boundaries: [
      'Disconnect destinations outside the 20 ready masks retain the same mode, but their subsequent account controls are not repaired by this module.',
      'Pending repair covers only the four declared new-account models: details, all/pending-account query, query cancellation/retry and the pending-account reconnect.',
      'Disconnects and further additions from these pending views remain outside this scoped repair.',
      'Successful additions other than Set15 → 31/47/79 and Set31 → 95 are outside this mode-preservation story.',
      'System Home/widget navigation and separate notification/background review stories remain outside this module.'
    ] };
}
function permissionRequired(node, description) { if (!node || node.removed) throw Error('Permission preservation missing ' + description); return node; }
function permissionNode(e, key) { return e.registry.get('R4/' + e.t + '/' + key); }
function permissionScope(model) { return model.pendingIdx === undefined ? 'Set-' + model.mask : 'Pending-' + model.mask + '-' + model.pendingIdx; }
function permissionViews(e, model, mode) {
  const key = 'AccountSystem/' + permissionScope(model);
  return { d: permissionRequired(permissionNode(e, key + '/Dashboard-' + mode), key + ' dashboard ' + mode),
    s: permissionRequired(permissionNode(e, key + '/Settings-' + mode), key + ' settings ' + mode) };
}
function permissionModelRefs(e, mask, pendingIdx) {
  const accounts = R4_ACCOUNT_ORDER.filter(i => mask & R4A[i].bit);
  const model = { mask, accounts, pendingIdx };
  if (pendingIdx !== undefined && !accounts.includes(pendingIdx)) throw Error('Pending account is not in model');
  return model;
}
function permissionActions(node) { return node ? (jobs.has(node) ? jobs.get(node) : node.reactions || []).flatMap(r => r.actions || (r.action ? [r.action] : [])) : []; }
function permissionEdge(node, target, navigation) { return !!target && permissionActions(node).some(a => a.type === 'NODE' && a.destinationId === target.id && a.navigation === navigation); }
function permissionClosed(node) { return permissionActions(node).some(a => a.type === 'CLOSE'); }
function permissionFlowScope(model) { return model.pendingIdx === undefined ? 'AccountFlow/Set-' + model.mask : pendingKey(model.mask, model.pendingIdx); }
function permissionAddControl(view) {
  return one(view, 'Action/link') || one(view, 'Row/连接账户') || view.findOne(n => n.name.startsWith('Button/') && txt(n).some(t => /^连接平台$|^连接账户$/.test(t.characters)));
}
function permissionBatch(start, count, length) {
  if (!Number.isInteger(start) || start < 0 || start >= length || !Number.isInteger(count) || count < 1 || count > 2) throw Error('Permission batches require valid start and count 1–2');
  return Math.min(start + count, length);
}
async function permissionCopyRoot(e, source, key) {
  const dest = root(e, permissionRequired(source, key + ' source'), key);
  await copyFlowTree(source, dest);
  return dest;
}
function permissionPreserveDetails(e, model, views, common) {
  for (const origin of ['d', 's']) for (const idx of model.accounts) {
    const item = origin === 'd' ? findCard(views[origin], idx) : findRow(views[origin], idx);
    const trigger = one(item, origin === 'd' ? 'Expand account' : 'Account identity');
    if (!trigger) continue;
    const target = model.pendingIdx === idx ? permissionNode(e, permissionFlowScope(model) + '/WidgetUnknown') || permissionNode(e, permissionFlowScope(model) + '/PendingDetails') : common.detail[idx];
    put(trigger, permissionRequired(target, 'specific cached/pending account detail ' + idx), 'OVERLAY');
  }
}

async function permissionReadyModel(e, mask, common) {
  const tag = 'r4_permission_ready_' + mask;
  if (e.branch.getPluginData(tag) === R4_PERMISSION_VERSION) return { mask, skipped: true };
  const model = permissionModelRefs(e, mask), key = 'PermissionKeep/Set-' + mask, boundaries = [];
  if (!e.branch.getPluginData('r4_wired_' + mask + '_ready')) throw Error('Ready account flow not complete: ' + mask);
  // Preflight every source/destination before creating the first local menu.
  for (const mode of R4_PERMISSION_MODES) {
    permissionViews(e, model, mode);
    for (const idx of model.accounts) permissionViews(e, permissionModelRefs(e, mask & ~R4A[idx].bit), mode);
  }
  for (const mode of R4_PERMISSION_MODES) {
    const views = permissionViews(e, model, mode);
    permissionPreserveDetails(e, model, views, common);
    for (const origin of ['d', 's']) {
      const refresh = one(views[origin], 'Action/refresh');
      if (refresh) put(refresh, common.q.all, 'OVERLAY');
      for (const idx of model.accounts) {
        const sourceKey = permissionFlowScope(model) + '/' + origin;
        const sourceMenu = permissionNode(e, sourceKey + '/Menu-' + idx), sourceConfirm = permissionNode(e, sourceKey + '/Disconnect-' + idx);
        const menu = await permissionCopyRoot(e, sourceMenu, key + '/' + mode + '/' + origin + '/Menu-' + idx);
        const confirm = await permissionCopyRoot(e, sourceConfirm, key + '/' + mode + '/' + origin + '/Disconnect-' + idx);
        const next = mask & ~R4A[idx].bit, target = permissionViews(e, permissionModelRefs(e, next), mode)[origin];
        put(button(menu, '刷新额度'), common.q[idx], 'SWAP');
        put(button(menu, '重新连接'), common.reconnect[idx], 'SWAP');
        put(button(menu, '断开连接'), confirm, 'SWAP');
        put(button(confirm, '断开连接'), target);
        close(button(menu, '取消')); close(button(confirm, '取消'));
        const item = origin === 'd' ? findCard(views[origin], idx) : findRow(views[origin], idx);
        put(permissionRequired(one(item, 'Action/more'), 'specific source menu ' + idx), menu, 'OVERLAY');
        if (!R4_PERMISSION_READY_MASKS.includes(next)) boundaries.push({ mode, origin, removedIdx: idx, nextMask: next, destination: target.id });
      }
    }
  }
  await flush();
  e.branch.setPluginData(tag, R4_PERMISSION_VERSION); figma.commitUndo();
  return { mask, accountCount: model.accounts.length, addedMenuAndConfirmFrames: model.accounts.length * 12, boundaryDestinations: boundaries };
}

// Stage A: 20 ready models only. Existing on/off/denied system views receive
// local menus; their initial/canonical siblings and shared menus stay untouched.
async function permissionPreserveReadyStage(t, start = 0, count = 1) {
  const end = permissionBatch(start, count, R4_PERMISSION_READY_MASKS.length), e = await env(t), common = await flowCommon(e), results = [];
  for (let i = start; i < end; i++) {
    figma.ui.postMessage({ status: t + ' 保留通知状态 · ready ' + (i + 1) + '/20', progress: true });
    results.push(await permissionReadyModel(e, R4_PERMISSION_READY_MASKS[i], common));
    await new Promise(resolve => setTimeout(resolve, 0));
  }
  return { status: t + ' 定域 ready 通知状态保持完成', start, end, total: 20, models: results, boundaries: permissionPreservePlan().boundaries };
}

async function permissionPendingQuery(e, model, mode, origin, scope) {
  const key = 'PermissionKeep/' + permissionScope(model) + '/' + mode + '/Query-' + origin + '-' + scope;
  const tag = 'r4_permission_query_' + model.mask + '_' + model.pendingIdx + '_' + mode + '_' + origin + '_' + scope;
  const stored = await flowStoredNode(e, tag); if (stored) return stored;
  const who = scope === 'all' ? '全部已绑定账号' : R4A[model.pendingIdx].email;
  const target = permissionViews(e, permissionModelRefs(e, model.mask), mode)[origin];
  const loading = panel(e, key + '/Loading', '正在查询额度', [who], ['取消']);
  progress(e, loading, 1); close(button(loading, '取消'));
  put(loading, target, 'NAVIGATE', { timeout: 1 });
  const gate = await network(e, key, loading, who + (scope === 'all' ? ' 的额度查询' : ' 的首次额度查询'));
  flowSaveTag(e, tag, gate.start.id); return gate.start;
}

async function permissionPendingModel(e, route, common) {
  const model = permissionModelRefs(e, route.next, route.idx), tag = 'r4_permission_pending_' + route.next + '_' + route.idx;
  if (e.branch.getPluginData(tag) === R4_PERMISSION_VERSION) return model;
  const scope = permissionFlowScope(model), key = 'PermissionKeep/' + permissionScope(model);
  if (!e.branch.getPluginData('r4_wired_' + route.next + '_' + route.idx)) throw Error('Representative pending flow not complete');
  for (const mode of R4_PERMISSION_MODES) { permissionViews(e, model, mode); permissionViews(e, permissionModelRefs(e, route.next), mode); }
  for (const mode of R4_PERMISSION_MODES) {
    const views = permissionViews(e, model, mode); permissionPreserveDetails(e, model, views, common);
    for (const origin of ['d', 's']) {
      const allQuery = await permissionPendingQuery(e, model, mode, origin, 'all');
      const firstQuery = await permissionPendingQuery(e, model, mode, origin, 'pending');
      const refresh = one(views[origin], 'Action/refresh'); if (refresh) put(refresh, allQuery, 'OVERLAY');
      const sourceMenu = permissionNode(e, scope + '/' + origin + '/Menu-' + route.idx);
      const menu = await permissionCopyRoot(e, sourceMenu, key + '/' + mode + '/' + origin + '/Menu-' + route.idx);
      const sourceLogin = permissionNode(e, scope + '/' + origin + '/Reconnect-' + route.idx);
      const login = await permissionCopyRoot(e, sourceLogin, key + '/' + mode + '/' + origin + '/Reconnect-' + route.idx);
      put(button(menu, '刷新额度'), firstQuery, 'SWAP');
      put(button(menu, '重新连接'), login, 'SWAP'); put(button(login, '继续'), firstQuery, 'SWAP');
      close(button(menu, '取消')); close(button(login, '取消'));
      const item = origin === 'd' ? findCard(views[origin], route.idx) : findRow(views[origin], route.idx);
      put(permissionRequired(one(item, 'Action/more'), 'pending account menu'), menu, 'OVERLAY');
      // The inherited Disconnect action deliberately remains a declared
      // boundary. No further pending deletion permutations are generated.
    }
  }
  await flowFlush(e); e.branch.setPluginData(tag, R4_PERMISSION_VERSION); figma.commitUndo(); return model;
}

async function permissionChooser(e, source, mode) {
  const key = 'PermissionKeep/Set-' + source + '/' + mode + '/Connect';
  const chooser = root(e, permissionRequired(permissionNode(e, 'AccountFlow/Set-' + source + '/Connect'), 'source chooser'), key);
  // Preserve other representative provider routes when another B batch reuses
  // this chooser. Only its first creation copies the original provider edges.
  const tag = 'r4_permission_chooser_' + source + '_' + mode;
  if (flowTag(e, tag) !== chooser.id) {
    await copyFlowTree(permissionNode(e, 'AccountFlow/Set-' + source + '/Connect'), chooser);
    flowSaveTag(e, tag, chooser.id);
  }
  return chooser;
}

async function permissionAddRoute(e, route, common) {
  const tag = 'r4_permission_add_' + route.source + '_' + route.idx;
  if (e.branch.getPluginData(tag) === R4_PERMISSION_VERSION) return { ...route, skipped: true };
  if (e.branch.getPluginData('r4_permission_ready_' + route.source) !== R4_PERMISSION_VERSION || e.branch.getPluginData('r4_permission_ready_' + route.next) !== R4_PERMISSION_VERSION) throw Error('Complete stage A for source and destination before this addition');
  const pending = await permissionPendingModel(e, route, common), source = permissionModelRefs(e, route.source), a = R4A[route.idx], results = [];
  for (const mode of R4_PERMISSION_MODES) {
    const key = 'PermissionKeep/Add-' + route.source + '-' + route.idx + '/' + mode;
    const sourceViews = permissionViews(e, source, mode), pendingViews = permissionViews(e, pending, mode);
    const first = await permissionPendingQuery(e, pending, mode, 'd', 'pending');
    const bound = await permissionCopyRoot(e, pendingViews.d, key + '/Bound');
    put(bound, first, 'OVERLAY', { timeout: .15 });
    const auth = panel(e, key + '/Authorization', '正在连接 ' + a.p, ['平台授权 · 交互示意'], ['取消']);
    progress(e, auth, 1); close(button(auth, '取消')); put(auth, bound, 'NAVIGATE', { timeout: 1 });
    const login = root(e, e.logins[a.p], key + '/Login'); fixLogin(e, login, a.email); put(button(login, '继续'), auth, 'SWAP');
    const gate = await network(e, key + '/BeforeAdd', login, '添加 ' + a.p + ' 账号');
    flowSaveTag(e, 'r4_permission_add_gate_' + route.source + '_' + route.idx + '_' + mode, gate.start.id);
    const chooser = await permissionChooser(e, route.source, mode);
    put(permissionRequired(one(chooser, 'Connect/' + a.p), 'provider choice'), gate.start, 'SWAP');
    for (const origin of ['d', 's']) put(permissionRequired(permissionAddControl(sourceViews[origin]), 'mode-preserving add entry'), chooser, 'OVERLAY');
    results.push({ mode, chooser: chooser.id, check: gate.start.id, login: login.id, authorization: auth.id, bound: bound.id,
      firstQuery: first.id, success: permissionViews(e, permissionModelRefs(e, route.next), mode).d.id });
  }
  await flowFlush(e); e.branch.setPluginData(tag, R4_PERMISSION_VERSION); figma.commitUndo();
  return { ...route, modes: results };
}

// Stage B: 0=15→31, 1=15→47, 2=15→79, 3=31→95. Each batch first
// prepares that route's pending cancellation/retry states, then exposes entry.
async function permissionPreserveAddStage(t, start = 0, count = 1) {
  const end = permissionBatch(start, count, 4), e = await env(t), common = await flowCommon(e), results = [];
  for (let i = start; i < end; i++) {
    figma.ui.postMessage({ status: t + ' 保留通知状态 · 连续添加 ' + (i + 1) + '/4', progress: true });
    results.push(await permissionAddRoute(e, R4_PERMISSION_ADD_ROUTES[i], common));
    await new Promise(resolve => setTimeout(resolve, 0));
  }
  return { status: t + ' 定域新增通知状态保持完成', start, end, total: 4, routes: results, boundaries: permissionPreservePlan().boundaries };
}

// Read-only native-edge audit. It reports boundaries explicitly and does not
// treat structural checks as an actual click test.
async function permissionPreserveAuditStage(t) {
  const e = await env(t), common = { q: {}, reconnect: {}, detail: {} }, stored = e.branch.getPluginData('r4_flow_common');
  if (!stored) throw Error('Audit requires the existing shared flow index; it will not create one');
  const shared = JSON.parse(stored);
  for (const group of Object.keys(common)) for (const [key, id] of Object.entries(shared[group] || {})) common[group][key] = permissionRequired(await figma.getNodeByIdAsync(id), 'existing shared ' + group + '/' + key);
  const errors = [], boundaries = [], expect = (ok, reason) => { if (!ok) errors.push(reason); };
  for (const mask of R4_PERMISSION_READY_MASKS) {
    const model = permissionModelRefs(e, mask);
    expect(e.branch.getPluginData('r4_permission_ready_' + mask) === R4_PERMISSION_VERSION, 'Ready stage complete ' + mask);
    for (const mode of R4_PERMISSION_MODES) {
      let views; try { views = permissionViews(e, model, mode); } catch (error) { errors.push(error.message); continue; }
      for (const origin of ['d', 's']) for (const idx of model.accounts) {
        const item = origin === 'd' ? findCard(views[origin], idx) : findRow(views[origin], idx);
        const detailTrigger = one(item, origin === 'd' ? 'Expand account' : 'Account identity');
        if (detailTrigger) expect(permissionEdge(detailTrigger, common.detail[idx], 'OVERLAY'), 'Cached detail preserves mode ' + [mask, mode, origin, idx].join('/'));
        const key = 'PermissionKeep/Set-' + mask + '/' + mode + '/' + origin;
        const menu = permissionNode(e, key + '/Menu-' + idx), confirm = permissionNode(e, key + '/Disconnect-' + idx);
        const next = mask & ~R4A[idx].bit;
        expect(permissionEdge(one(item, 'Action/more'), menu, 'OVERLAY'), 'Scoped menu ' + key + '/' + idx);
        expect(permissionEdge(menu && button(menu, '刷新额度'), common.q[idx], 'SWAP'), 'Query preserves source ' + key + '/' + idx);
        expect(permissionEdge(menu && button(menu, '重新连接'), common.reconnect[idx], 'SWAP'), 'Reconnect preserves source ' + key + '/' + idx);
        expect(permissionEdge(menu && button(menu, '断开连接'), confirm, 'SWAP'), 'Disconnect opens scoped confirmation ' + key + '/' + idx);
        try { expect(permissionEdge(confirm && button(confirm, '断开连接'), permissionViews(e, permissionModelRefs(e, next), mode)[origin], 'NAVIGATE'), 'Disconnect retains mode ' + key + '/' + idx); } catch (error) { errors.push(error.message); }
        expect(permissionClosed(menu && button(menu, '取消')) && permissionClosed(confirm && button(confirm, '取消')), 'Cancel retains source ' + key + '/' + idx);
        if (!R4_PERMISSION_READY_MASKS.includes(next)) boundaries.push({ mask, mode, origin, removedIdx: idx, nextMask: next });
      }
    }
  }
  for (const route of R4_PERMISSION_ADD_ROUTES) {
    expect(e.branch.getPluginData('r4_permission_add_' + route.source + '_' + route.idx) === R4_PERMISSION_VERSION, 'Addition stage complete ' + route.source + '/' + route.idx);
    const model = permissionModelRefs(e, route.next, route.idx);
    for (const mode of R4_PERMISSION_MODES) {
      const key = 'PermissionKeep/Add-' + route.source + '-' + route.idx + '/' + mode;
      const login = permissionNode(e, key + '/Login'), auth = permissionNode(e, key + '/Authorization'), bound = permissionNode(e, key + '/Bound');
      const gateId = e.branch.getPluginData('r4_permission_add_gate_' + route.source + '_' + route.idx + '_' + mode);
      const gate = gateId && await figma.getNodeByIdAsync(gateId);
      const chooser = permissionNode(e, 'PermissionKeep/Set-' + route.source + '/' + mode + '/Connect');
      expect(permissionEdge(chooser && one(chooser, 'Connect/' + R4A[route.idx].p), gate, 'SWAP'), 'Addition choice begins with network check ' + key);
      try { const sources = permissionViews(e, permissionModelRefs(e, route.source), mode);
        for (const origin of ['d', 's']) expect(permissionEdge(permissionAddControl(sources[origin]), chooser, 'OVERLAY'), 'Mode-specific add chooser ' + key + '/' + origin);
      } catch (error) { errors.push(error.message); }
      expect(permissionClosed(login && button(login, '取消')) && permissionClosed(auth && button(auth, '取消')), 'Add cancellation preserves source ' + key);
      expect(permissionEdge(login && button(login, '继续'), auth, 'SWAP') && permissionEdge(auth, bound, 'NAVIGATE'), 'Authorization order ' + key);
      const card = bound && findCard(bound, route.idx);
      expect(!!card && txt(card).filter(n => n.name.startsWith('Value/')).every(n => n.characters === '—'), 'Bound has no fabricated quota ' + key);
      for (const origin of ['d', 's']) for (const scope of ['all', 'pending']) {
        const qkey = 'PermissionKeep/' + permissionScope(model) + '/' + mode + '/Query-' + origin + '-' + scope;
        const loading = permissionNode(e, qkey + '/Loading');
        const queryId = e.branch.getPluginData('r4_permission_query_' + route.next + '_' + route.idx + '_' + mode + '_' + origin + '_' + scope);
        const query = queryId && await figma.getNodeByIdAsync(queryId);
        expect(permissionClosed(loading && button(loading, '取消')), 'First-query cancellation ' + qkey);
        expect(!!query && !query.removed, 'Retry has its own network-check start ' + qkey);
        if (origin === 'd' && scope === 'pending') expect(permissionEdge(bound, query, 'OVERLAY'), 'Bound checks before first quota query ' + key);
        try { expect(permissionEdge(loading, permissionViews(e, permissionModelRefs(e, route.next), mode)[origin], 'NAVIGATE'), 'Query completion retains mode and ready data ' + qkey); } catch (error) { errors.push(error.message); }
      }
    }
  }
  return { status: t + ' 通知状态定域静态审查', passed: errors.length === 0, errors, readyModelCount: 20, additionRouteCount: 4,
    modeBoundaryDestinations: boundaries, declaredBoundaries: permissionPreservePlan().boundaries,
    actualClickRequired: ['on/off/denied: Set15 work disconnect → Set11 same mode', 'Known account details/query/reconnect → close returns same mode', 'Set15 three additions and Set31 Cursor: before-add/auth cancel preserves source and account count', 'First-query cancel retains bound unknown account and mode; retry checks before correct ready mode', 'Denied target toggle opens system settings; off target toggle enables without re-requesting permission'] };
}


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


// Local R3 review repair. Never regenerate a section or traverse old interaction
// subtrees. All new roots are R4/ReviewRepair/*; the original 44 review roots stay.
// Run after account flows, account extras, supportOnlyStage and finalLinksStage.
// cleanupReviewStage(theme, start=0, count=1) is deliberately resumable by source.
const R4_REVIEW_CLEANUP_VERSION = '1';
const R4_REVIEW_CLEANUP_EXPECTED_CANDIDATES = 32;

function reviewCleanupKind(node) {
  const p = node.name.split('|');
  return p.length > 1 ? p[1] : node.name.split('/').pop();
}
function reviewCleanupState(node) {
  const p = node.name.split('|');
  return { kind: reviewCleanupKind(node), expanded: p[6] || '', status: p[8] || '', updated: p[5] === 'new', size: p[9] || 'small', platform: p[7] || '' };
}
function reviewCleanupRequired(node, what) {
  if (!node || node.removed) throw Error('Review cleanup missing ' + what);
  return node;
}
function reviewCleanupGet(e, key) {
  return reviewCleanupRequired(e.registry.get('R4/' + e.t + '/' + key), key);
}
function reviewCleanupReactions(node) {
  return jobs.has(node) ? jobs.get(node) : node.reactions || [];
}
function reviewCleanupActive(node, root) {
  for (let n = node; n; n = n.parent) {
    if (n.visible === false) return false;
    if (n === root) return true;
  }
  return false;
}
function reviewCleanupClearOne(node) { jobs.set(node, []); writes.add(node.id); }
function reviewCleanupProtected(e, root) {
  return [e.entry.id, e.dashboard.id, e.settings.id].includes(root.id) ||
    ['Tutorial1', 'Tutorial1b', 'Tutorial2', 'Tutorial2b', 'Help', 'Privacy', 'Licenses', 'License', 'LockNotification'].includes(reviewCleanupKind(root));
}
function reviewCleanupRoots(e) {
  return e.review.children.filter(n => n.type === 'FRAME' && n.visible && !n.name.startsWith('R4/'));
}
function reviewCleanupCandidates(e) { return reviewCleanupRoots(e).filter(n => !reviewCleanupProtected(e, n)); }
function reviewCleanupCards(root, includeHidden = false) {
  const body = one(root, 'Content');
  if (!body) return [];
  const result = [];
  for (const child of body.children) {
    if (!includeHidden && child.visible === false) continue;
    const childTexts = child.type === 'TEXT' ? [child] : (typeof child.findAllWithCriteria === 'function' ? txt(child) : []);
    const text = childTexts.map(n => n.characters).join('\n');
    const accounts = R4A.slice(0, 4).filter(a => text.includes(a.email));
    if (accounts.length === 1) result.push({ idx: accounts[0].idx, node: child });
    else if (accounts.length > 1) throw Error('Ambiguous direct account card in ' + root.name + ': ' + child.name);
  }
  if (new Set(result.map(x => x.idx)).size !== result.length) throw Error('Duplicate account identity in ' + root.name);
  return result;
}
function reviewCleanupFamily(root) {
  const s = reviewCleanupState(root);
  return 'Dashboard-' + (s.expanded || 'collapsed') + '-' + (s.status || 'normal') + '-' + (s.updated ? 'new' : 'old');
}
function reviewCleanupSpecial(root) {
  const s = reviewCleanupState(root);
  return s.updated || ['stale', 'nodata', 'expired', 'unavailable', 'unknown', 'unlimited', 'noreset', 'due'].includes(s.status);
}
function reviewCleanupAffected(root) {
  const s = reviewCleanupState(root);
  if (['nodata', 'expired', 'due'].includes(s.status)) return 0;
  if (['unavailable', 'unknown', 'unlimited', 'noreset'].includes(s.status)) return 3;
  return null;
}
function reviewCleanupSheetClose(root) {
  const x = one(root, 'Action/close');
  if (x) close(x);
  const shade = root.children.find(n => n.type === 'RECTANGLE' && Math.abs(n.width - root.width) < 1 && Math.abs(n.height - root.height) < 1);
  if (shade) close(shade);
  for (const caption of ['取消', '关闭']) { const b = button(root, caption); if (b) close(b); }
}
function reviewCleanupHomeBar(root) {
  return one(root, 'Home indicator') || root.children.find(n => n.type === 'RECTANGLE' && Math.abs(n.width - 134) < 1 && n.height < 8);
}
async function reviewCleanupReady(e, mask) {
  if (!e.branch.getPluginData('r4_wired_' + mask + '_ready')) throw Error('Ready account model ' + mask + ' must be wired before R3 cleanup');
  return await getAccountModel(e, mask);
}

// The overlay stack is the source context. Shared failure panels never change
// quota, binding records, or timestamps, and therefore safely retain 09:11,
// 12:41, unlimited, unavailable-reset, and pending snapshots alike.
async function reviewCleanupCommon(e) {
  if (e.reviewCleanupCommon) return e.reviewCleanupCommon;
  const tag = 'r4_review_cleanup_common', raw = e.branch.getPluginData(tag);
  if (raw) {
    try {
      const saved = JSON.parse(raw), out = { q: {}, reconnect: {} };
      if (saved.version === R4_REVIEW_CLEANUP_VERSION) {
        for (const group of ['q', 'reconnect']) for (const [key, id] of Object.entries(saved[group] || {})) out[group][key] = await figma.getNodeByIdAsync(id);
        if (['all', 0, 1, 2, 3].every(k => out.q[k] && !out.q[k].removed) && [0, 1, 2, 3].every(k => out.reconnect[k] && !out.reconnect[k].removed)) {
          e.reviewCleanupCommon = out;
          return out;
        }
      }
    } catch (_) { /* Rehydrate the small local group after an interrupted run. */ }
  }
  const out = { q: {}, reconnect: {} };
  for (const scope of ['all', 0, 1, 2, 3]) {
    const who = scope === 'all' ? '当前全部已绑定账号' : R4A[scope].email;
    const key = 'ReviewRepair/Query/' + scope;
    const loading = panel(e, key + '/Loading', '正在查询额度', [who], ['取消']);
    progress(e, loading, 1); close(button(loading, '取消'));
    const failed = panel(e, key + '/Failed', '额度查询失败', [who, '平台暂未返回额度', '保留现有可信数据及上次成功时间'], ['重试', '关闭']);
    close(button(failed, '关闭'));
    put(loading, failed, 'SWAP', { timeout: 1 });
    const gate = await network(e, key, loading, who + '的额度查询');
    put(button(failed, '重试'), gate.start, 'SWAP');
    out.q[scope] = gate.start;
    if (scope !== 'all') {
      const login = root(e, e.logins[R4A[scope].p], 'ReviewRepair/Reconnect/' + scope);
      clear(login); fixLogin(e, login, R4A[scope].email);
      put(button(login, '继续'), gate.start, 'SWAP');
      out.reconnect[scope] = login;
    }
  }
  await flush();
  e.branch.setPluginData(tag, JSON.stringify({ version: R4_REVIEW_CLEANUP_VERSION,
    q: Object.fromEntries(Object.entries(out.q).map(([k, n]) => [k, n.id])),
    reconnect: Object.fromEntries(Object.entries(out.reconnect).map(([k, n]) => [k, n.id])) }));
  e.reviewCleanupCommon = out;
  return out;
}

// A detail overlay contains only the clicked account copied from its actual
// static source. No standard-model quota, reset, or timestamp is substituted.
// Prune only locally-owned clone content. Removing an instance's internal
// child is not allowed by Figma; retain the previous hidden override there.
function reviewCleanupPruneCloneNode(cloneRoot, node) {
  if (!cloneRoot.name.startsWith('R4/') || !cloneRoot.name.includes('/ReviewRepair/') || node === cloneRoot) throw Error('Pruning requires a local review-repair clone child');
  let parent = node.parent, insideInstance = false;
  for (; parent && parent !== cloneRoot; parent = parent.parent) {
    if (parent.type === 'INSTANCE') insideInstance = true;
  }
  if (parent !== cloneRoot) throw Error('Pruning target is outside its review-repair clone');
  if (insideInstance) { node.visible = false; return; }
  for (const child of all(node)) jobs.delete(child);
  node.remove();
}
async function reviewCleanupDetail(e, source, idx) {
  const key = 'ReviewRepair/' + reviewCleanupFamily(source) + '/Detail-' + idx;
  const detail = root(e, source, key);
  clear(detail);
  const cards = reviewCleanupCards(detail, true), card = reviewCleanupRequired(cards.find(x => x.idx === idx), source.name + ' detail account ' + idx).node;
  card.visible = true;
  const body = one(detail, 'Content');
  // The source stays intact. This overlay never displays another card or
  // source-state banner, so those complete cloned subtrees are unnecessary.
  for (const child of [...body.children]) if (child !== card) reviewCleanupPruneCloneNode(detail, child);
  const expanded = one(card, 'Account details');
  if (expanded) expanded.visible = true;
  for (const name of ['R3/Header actions', 'Action/refresh', 'Action/link', 'Tab bar']) { const n = one(detail, name); if (n) reviewCleanupPruneCloneNode(detail, n); }
  const more = one(card, 'Action/more'); if (more) more.visible = false;
  const expand = one(card, 'Expand account'); if (expand) close(expand);
  const sourceExpanded = e.registry.get('R4/' + e.t + '/Accounts/Set-15/Expanded-0');
  const upInstance = sourceExpanded && one(one(sourceExpanded, 'Quota/Claude'), 'Icon/down');
  const targetChevron = one(card, 'Icon/down');
  if (targetChevron && upInstance && targetChevron.type === 'INSTANCE' && upInstance.type === 'INSTANCE') {
    const component = await upInstance.getMainComponentAsync(); if (component) targetChevron.swapComponent(component);
  }
  const template = e.roots.find(n => reviewCleanupKind(n) === 'WidgetReview' && n.name.endsWith('|small'));
  const navigation = reviewCleanupRequired(one(detail, 'Navigation'), detail.name + ' navigation');
  const sourceBack = reviewCleanupRequired(one(template, 'Action/back'), 'R3 review back');
  let backButton = one(navigation, 'Action/back');
  if (!backButton) backButton = clone(sourceBack, navigation, 'Action/back');
  backButton.x = 12; backButton.y = 2; backButton.visible = true; close(backButton);
  const title = navigation.children.find(n => n.type === 'TEXT'); if (title) { title.x = 74; title.resize(245, title.height); }
  const home = reviewCleanupHomeBar(detail); if (home) close(home);
  return detail;
}

async function reviewCleanupDashboard(e, source, result) {
  const state = reviewCleanupState(source), cards = reviewCleanupCards(source), originalMask = cards.reduce((mask, item) => mask | R4A[item.idx].bit, 0);
  const common = await reviewCleanupCommon(e);
  const family = reviewCleanupFamily(source), special = reviewCleanupSpecial(source), affected = reviewCleanupAffected(source);
  // Resolve the sole R3 stale-time contradiction explicitly authorized for this
  // repair; do not normalize any other review frame's timestamp or quota.
  if (state.status === 'stale') for (const text of txt(source)) if (text.characters.includes('上次成功更新 09:41')) {
    change(text, text.characters.replace('上次成功更新 09:41', '上次成功更新 09:11'));
    result.textCorrections.push(text.id);
  }
  const contexts = new Map(), details = new Map();
  for (const { idx, node } of cards) if (one(node, 'Expand account')) details.set(idx, await reviewCleanupDetail(e, source, idx));
  for (let mask = 0; mask <= 15; mask++) {
    if ((mask & originalMask) !== mask) continue;
    const ready = await reviewCleanupReady(e, mask);
    const preserve = mask === originalMask || (special && mask !== 0 && (affected === null || (mask & R4A[affected].bit)));
    if (!preserve) { contexts.set(mask, { mask, d: ready.d, s: ready.s, readyD: ready.d, canonical: true }); continue; }
    const d = mask === originalMask ? source : root(e, source, 'ReviewRepair/' + family + '/Set-' + mask);
    clear(d);
    for (const item of reviewCleanupCards(d, true)) {
      const retained = !!(mask & R4A[item.idx].bit);
      if (d !== source && !retained) reviewCleanupPruneCloneNode(d, item.node);
      else item.node.visible = retained;
    }
    contexts.set(mask, { mask, d, s: ready.s, readyD: ready.d, canonical: false });
  }
  const tutorial = systemKind(e, 'Tutorial1');
  for (const context of contexts.values()) {
    if (context.canonical) continue;
    const f = context.d, chooser = reviewCleanupGet(e, 'AccountFlow/Set-' + context.mask + '/Connect');
    const link = one(f, 'Action/link'); if (link && reviewCleanupActive(link, f)) put(link, chooser, 'OVERLAY');
    for (const n of all(f)) if (reviewCleanupActive(n, f) && /^Button\/(?:连接账户|连接平台|添加账户)$/.test(n.name)) put(n, chooser, 'OVERLAY');
    const refresh = one(f, 'Action/refresh'); if (refresh && reviewCleanupActive(refresh, f)) put(refresh, common.q.all, 'OVERLAY');
    const latest = button(f, '查询最新额度'); if (latest && reviewCleanupActive(latest, f)) put(latest, common.q.all, 'OVERLAY');
    const st = one(f, 'Tab/设置'); if (st) put(st, context.s);
    const dt = one(f, 'Tab/额度'); if (dt) put(dt, f);
    const help = one(f, 'Action/如何添加小组件'); if (help) put(help, tutorial, 'OVERLAY');
    const home = reviewCleanupHomeBar(f), widget = e.registry.get('R4/' + e.t + '/AccountWidgets/Set-' + context.mask);
    if (home && widget && !special) put(home, widget);
    for (const item of reviewCleanupCards(f)) {
      const a = R4A[item.idx], idx = item.idx;
      const expand = one(item.node, 'Expand account');
      if (expand && details.has(idx)) {
        const open = one(item.node, 'Account details');
        if (open && open.visible && !special) put(expand, context.readyD, 'NAVIGATE', { smart: true });
        else put(expand, details.get(idx), 'OVERLAY');
      }
      const retry = button(item.node, '重试'); if (retry) put(retry, common.q[idx], 'OVERLAY');
      const reconnect = button(item.node, '重新连接'); if (reconnect) put(reconnect, common.reconnect[idx], 'OVERLAY');
      const more = one(item.node, 'Action/more');
      if (!more) continue;
      const key = 'ReviewRepair/' + family + '/Set-' + context.mask + '/Account-' + idx;
      const menu = panel(e, key + '/Menu', a.p + ' 账户', [a.email], ['刷新额度', '重新连接', '断开连接', '取消']);
      close(button(menu, '取消'));
      put(button(menu, '刷新额度'), common.q[idx], 'SWAP');
      put(button(menu, '重新连接'), common.reconnect[idx], 'SWAP');
      const confirmation = panel(e, key + '/Disconnect', '断开连接？', [a.email, '移除此账号的额度数据和待发提醒。平台订阅不会取消。'], ['断开连接', '取消']);
      close(button(confirmation, '取消'));
      const next = reviewCleanupRequired(contexts.get(context.mask & ~a.bit), 'remaining account context');
      put(button(confirmation, '断开连接'), next.d);
      put(button(menu, '断开连接'), confirmation, 'SWAP');
      put(more, menu, 'OVERLAY');
    }
  }
  result.sourceContexts = [...contexts.values()].filter(x => !x.canonical).map(x => ({ mask: x.mask, id: x.d.id }));
  result.navigationBoundary = 'Settings and successful addition use the existing same-binding R4 model. Query failure, cancellation, reconnect failure, expanded details, and disconnect retain the visual source data.';
}

async function reviewCleanupReplaceChildren(e, destination, source) {
  // Keep the original review root, URL, position and visibility. Its replacement
  // content is the already-validated R4 equivalent, never an old settings tree.
  clear(destination);
  for (const child of [...destination.children]) child.remove();
  for (const child of source.children) clone(child, destination, child.name);
  await copyFlowTree(source, destination);
}

async function reviewCleanupStaticRoot(e, root, result) {
  const state = reviewCleanupState(root), kind = state.kind;
  if (!['Dashboard', 'Settings', 'Connect', 'Menu', 'Login', 'Connecting', 'Failed', 'Disconnect', 'Permission', 'System', 'WidgetReview', 'WidgetConfig', 'SystemHome', 'WidgetState', 'StateReview'].includes(kind)) {
    throw Error('R3 review kind requires a specific plan before edits: ' + kind);
  }
  if (kind === 'Dashboard') { await reviewCleanupDashboard(e, root, result); return; }
  if (kind === 'Settings') {
    const n = root.name.split('|')[4], suffix = n === '1' ? 'on' : n === '2' ? 'denied' : null;
    if (!suffix) throw Error('Unrecognized R3 notification settings: ' + root.name);
    await reviewCleanupReplaceChildren(e, root, reviewCleanupGet(e, 'AccountSystem/Set-15/Settings-' + suffix));
    result.replacedChildren = true;
    return;
  }
  const saved = all(root).filter(n => 'reactions' in n && n.reactions.length).map(n => ({ n, reactions: n.reactions }));
  const base = await reviewCleanupReady(e, 15), common = await reviewCleanupCommon(e);
  clear(root);
  const idx = { Claude: 0, Codex: 1, Cursor: 3 }[state.platform || 'Claude'];
  if (['Connect', 'Menu', 'Login', 'Connecting', 'Failed', 'Disconnect', 'Permission'].includes(kind)) reviewCleanupSheetClose(root);
  if (kind === 'Connect' || kind === 'Failed') {
    const chooser = reviewCleanupGet(e, 'AccountFlow/Set-15/Connect');
    for (const platform of kind === 'Connect' ? ['Claude', 'Codex', 'Cursor'] : [state.platform || 'Claude']) {
      const from = reviewCleanupRequired(one(chooser, 'Connect/' + platform), 'current add action');
      const reaction = reviewCleanupReactions(from).find(r => (r.actions || []).some(a => a.type === 'NODE'));
      const action = reaction && reaction.actions.find(a => a.type === 'NODE');
      const destination = action && await figma.getNodeByIdAsync(action.destinationId);
      put(kind === 'Connect' ? one(root, 'Connect/' + platform) : button(root, '重新尝试'), reviewCleanupRequired(destination, 'network-gated add ' + platform), 'SWAP');
    }
  } else if (kind === 'Menu') {
    put(one(root, 'Row/刷新额度'), common.q[idx], 'SWAP');
    put(one(root, 'Row/重新连接'), common.reconnect[idx], 'SWAP');
    put(one(root, 'Row/断开连接'), reviewCleanupGet(e, 'AccountFlow/Set-15/d/Disconnect-' + idx), 'SWAP');
  } else if (kind === 'Login') {
    put(button(root, '继续'), common.q[idx], 'SWAP');
  } else if (kind === 'Connecting') {
    // This retained R3 loading illustration is no longer an authorization or
    // account-creation shortcut. Its existing close/cancel controls stay live.
    result.staticLoadingIllustration = true;
  } else if (kind === 'Disconnect') {
    put(button(root, '断开连接'), (await reviewCleanupReady(e, 15 & ~R4A[idx].bit)).d);
  } else if (kind === 'Permission') {
    put(button(root, '允许'), reviewCleanupGet(e, 'AccountSystem/Set-15/Settings-on'));
    put(button(root, '不允许'), reviewCleanupGet(e, 'AccountSystem/Set-15/Settings-denied'));
  } else if (kind === 'System') {
    const toggle = reviewCleanupRequired(accountSystemToggleNode(root), 'R3 system toggle');
    put(toggle, reviewCleanupGet(e, 'AccountSystem/Set-15/iOS-on'), 'NAVIGATE', { smart: true });
    put(one(root, 'Action/back'), reviewCleanupGet(e, 'AccountSystem/Set-15/Settings-denied'));
  } else if (kind === 'WidgetReview') {
    put(one(root, 'Action/back'), e.entry);
    for (const [label, size] of [['小号', 'small'], ['中号', 'medium']]) { const b = button(root, label); if (b) put(b, reviewCleanupGet(e, 'Widgets/Gallery/' + size)); }
    for (const label of ['添加小组件', '编辑小组件']) put(button(root, label), reviewCleanupGet(e, 'Widgets/Config/' + state.size + '/A'));
    for (const n of all(root)) if (/^Button\/查看(?:已用|剩余)状态$/.test(n.name) || n.name.startsWith('显示切换仅为评审入口')) { n.visible = false; reviewCleanupClearOne(n); }
  } else if (kind === 'WidgetConfig') {
    put(one(root, 'Action/back'), reviewCleanupGet(e, 'Widgets/Gallery/' + state.size));
    for (const [label, key] of [['Claude', 'A'], ['Codex', 'B'], ['Codex · work', 'C'], ['Cursor', 'D']]) put(one(root, 'Account/' + label), reviewCleanupGet(e, 'Widgets/Config/' + state.size + '/' + key));
    put(button(root, '完成'), reviewCleanupGet(e, 'Widgets/Home/Config/' + state.size + '/A'));
  } else if (kind === 'SystemHome') {
    put(one(root, 'Widget/Claude'), reviewCleanupGet(e, 'Widgets/Detail/A'), 'OVERLAY');
    put(one(root, 'Action/back'), reviewCleanupGet(e, 'Widgets/Gallery/' + state.size));
    const home = reviewCleanupHomeBar(root); if (home) put(home, base.d);
  } else if (kind === 'WidgetState') {
    const groups = root.findAll(n => n.name === 'Card');
    const matching = caption => reviewCleanupRequired(groups.find(n => txt(n).some(tx => tx.characters === caption)), 'widget status ' + caption);
    // The root argument is the retained review frame; the helper creates only
    // the separate R4 configuration view whose selection is initially empty.
    const config = await reviewCleanupUnselected(e, root);
    put(matching('尚未选择账户'), config);
    put(matching('账户已断开'), reviewCleanupGet(e, 'AccountWidgets/Set-13'));
    put(matching('需要重新连接'), common.reconnect[1], 'OVERLAY');
    put(matching('暂时无法更新'), common.q[1], 'OVERLAY');
    put(one(root, 'Action/back'), systemKind(e, 'StateReview'));
  } else if (kind === 'StateReview') {
    // Its existing status entries still point to the visible R3 screenshots.
    // Preserve those exact review destinations, including error illustrations.
    const visibleIds = new Set(reviewCleanupRoots(e).map(n => n.id));
    for (const item of saved) if (reviewCleanupActive(item.n, root)) {
      const reactions = item.reactions.map(r => ({ trigger: JSON.parse(JSON.stringify(r.trigger)), actions: JSON.parse(JSON.stringify(r.actions || (r.action ? [r.action] : []))) }));
      if (reactions.some(r => r.actions.some(a => a.type === 'NODE' && !visibleIds.has(a.destinationId)))) throw Error('Unexpected non-review StateReview destination');
      jobs.set(item.n, reactions); writes.add(item.n.id);
    }
    put(one(root, 'Action/back'), e.entry);
  } else throw Error('R3 review kind requires a specific plan: ' + kind);
}

async function reviewCleanupUnselected(e, source) {
  const config = root(e, reviewCleanupGet(e, 'Widgets/Config/small/A'), 'ReviewRepair/WidgetUnselectedConfig');
  clear(config);
  for (const check of config.findAll(n => n.name === 'Icon/check')) check.visible = false;
  const finish = button(config, '完成'); if (finish) finish.visible = false;
  for (const [label, key] of [['Claude', 'A'], ['Codex', 'B'], ['Codex · work', 'C'], ['Cursor', 'D']]) put(one(config, 'Account/' + label), reviewCleanupGet(e, 'Widgets/Config/small/' + key));
  put(one(config, 'Action/back'), source);
  return config;
}

async function reviewCleanupLegacyEdges(e) {
  const legacy = new Set(e.branch.children.filter(n => !n.name.startsWith('R4/')).map(n => n.id)), result = [], cache = new Map();
  for (const source of reviewCleanupRoots(e)) for (const node of all(source)) {
    if (!reviewCleanupActive(node, source) || !('reactions' in node)) continue;
    for (const reaction of reviewCleanupReactions(node)) for (const action of reaction.actions || (reaction.action ? [reaction.action] : [])) {
      if (action.type !== 'NODE' || !action.destinationId) continue;
      if (!cache.has(action.destinationId)) {
        let target = await figma.getNodeByIdAsync(action.destinationId), old = null;
        for (let n = target; n && n.type !== 'PAGE'; n = n.parent) if (legacy.has(n.id)) { old = n; break; }
        cache.set(action.destinationId, { target, old });
      }
      const value = cache.get(action.destinationId);
      if (!value.target || value.old || reviewCleanupKind(value.target) === 'Display' || /\|U\|/.test(value.target.name)) result.push({ source: source.id, node: node.id, nodeName: node.name, destination: action.destinationId, target: value.target?.name || null, protected: reviewCleanupProtected(e, source) });
    }
  }
  return result;
}

async function planReviewCleanupStage(t) {
  const e = await env(t), roots = reviewCleanupRoots(e), candidates = reviewCleanupCandidates(e);
  return { status: t + ' R3 局部修复方案（未写入）', visibleReviewCount: roots.length,
    candidateCount: candidates.length, expectedCandidateCount: R4_REVIEW_CLEANUP_EXPECTED_CANDIDATES,
    eligibleForMutation: roots.length === 44 && candidates.length === R4_REVIEW_CLEANUP_EXPECTED_CANDIDATES,
    protected: roots.filter(n => reviewCleanupProtected(e, n)).map(n => ({ id: n.id, name: n.name })),
    candidates: candidates.map((n, index) => ({ index, id: n.id, name: n.name, kind: reviewCleanupKind(n), specialData: reviewCleanupSpecial(n), key: reviewCleanupFamily(n) })),
    rules: ['保留 44 个原 review root、位置和可见性；仅两个旧通知设置根替换为对应当前 R4 子树。', '查询只模拟检查后失败，CLOSE 保留来源、身份、可信数据与成功时间；每次重试重新检查。', '特殊状态的断开副本只删除指定账号；剩余账号仍用来源数据。', '仅旧 stale 页成功时间统一为其既有说明中的 09:11。', '最终只浅层隐藏非 R4 interaction 根，不删除或遍历其子树。'],
    remainingLegacyEdges: await reviewCleanupLegacyEdges(e) };
}

async function cleanupReviewStage(t, start = 0, count = 1) {
  const e = await env(t), roots = reviewCleanupRoots(e), candidates = reviewCleanupCandidates(e);
  if (roots.length !== 44) throw Error('Expected exactly 44 visible R3 review frames, got ' + roots.length);
  if (candidates.length !== R4_REVIEW_CLEANUP_EXPECTED_CANDIDATES) throw Error('Expected exactly 32 reviewed cleanup candidates (indexes 0–31), got ' + candidates.length + '; inspect cleanupplan before mutation');
  if (!Number.isInteger(start) || start < 0 || start >= candidates.length || !Number.isInteger(count) || count < 1 || count > 4) throw Error('Review cleanup requires a valid source index and batch count 1–4');
  for (let mask = 0; mask <= 15; mask++) if (!e.branch.getPluginData('r4_wired_' + mask + '_ready')) throw Error('Complete ready model ' + mask + ' before starting R3 review cleanup');
  const results = [];
  for (let index = start; index < Math.min(start + count, candidates.length); index++) {
    const source = candidates[index], tag = 'r4_review_cleanup_' + source.id.replace(/:/g, '_');
    const done = e.branch.getPluginData(tag);
    if (done === R4_REVIEW_CLEANUP_VERSION) { results.push({ index, id: source.id, skipped: true }); continue; }
    const before = e.registry.size, result = { index, id: source.id, name: source.name, textCorrections: [] };
    figma.ui.postMessage({ status: t + ' 整理 R3 评审路径 ' + (index + 1) + '/' + candidates.length, progress: true });
    await reviewCleanupStaticRoot(e, source, result);
    // Even invisible historical controls cannot carry obsolete reactions into
    // later clones. Protected roots are inspected elsewhere, not modified here.
    for (const node of all(source)) if ('reactions' in node && !reviewCleanupActive(node, source)) reviewCleanupClearOne(node);
    await flush();
    if (!source.visible || roots.some(n => n.removed || !n.visible)) throw Error('R3 review visibility changed unexpectedly');
    e.branch.setPluginData(tag, R4_REVIEW_CLEANUP_VERSION); figma.commitUndo();
    result.createdRootCount = e.registry.size - before;
    results.push(result);
    await new Promise(resolve => setTimeout(resolve, 0));
  }
  const complete = candidates.every(n => e.branch.getPluginData('r4_review_cleanup_' + n.id.replace(/:/g, '_')) === R4_REVIEW_CLEANUP_VERSION);
  let remainingLegacyEdges = null, hiddenLegacyRootIds = [];
  if (complete) {
    remainingLegacyEdges = await reviewCleanupLegacyEdges(e);
    if (!remainingLegacyEdges.length) {
      const restoreKey = 'r4_review_cleanup_old_visible', previous = e.branch.getPluginData(restoreKey);
      hiddenLegacyRootIds = e.branch.children.filter(n => !n.name.startsWith('R4/') && n.visible).map(n => n.id);
      if (!previous) e.branch.setPluginData(restoreKey, JSON.stringify(hiddenLegacyRootIds));
      for (const n of e.branch.children) if (!n.name.startsWith('R4/') && n.visible) { n.visible = false; writes.add(n.id); }
      figma.commitUndo();
    }
  }
  return { status: complete && !remainingLegacyEdges?.length ? t + ' R3 评审路径清理完成' : t + ' R3 评审路径批次完成',
    start, end: Math.min(start + count, candidates.length), nextIndex: Math.min(start + count, candidates.length), total: candidates.length,
    complete: complete && !remainingLegacyEdges?.length, results, remainingLegacyEdges, hiddenLegacyRootIds,
    preservedReviewRootIds: roots.map(n => n.id), protectedRootIds: roots.filter(n => reviewCleanupProtected(e, n)).map(n => n.id) };
}


// Bounded final canvas organization and native PNG delivery.
// No new roots, cloning, reparenting, component edits, or reaction edits.
// Read-only entry points never call env()/init(), load fonts, or select nodes.
const R4_DELIVERY_VERSION = '1';
const R4_DELIVERY_SCOPE = {
  Light: { review: '1:43251', branch: '1:43252', entry: '1:500', label: '浅色' },
  Dark: { review: '1:43253', branch: '1:43254', entry: '1:4088', label: '深色' },
};
const R4_DELIVERY_CACHE = new Map();
const R4_DELIVERY_PAGE_OBSERVERS = new Map(), R4_DELIVERY_OBSERVER_TRIED = new Set();
let R4_DELIVERY_GENERATION = 0;
const R4_DELIVERY_OWN_GEOMETRY = new Map(), R4_DELIVERY_EVENT_CHECKS = new Set();
function deliveryAck(status) { figma.ui.postMessage({ status, progress: true }); }
async function deliveryYield(status) { if (status) deliveryAck(status); await new Promise(resolve => setTimeout(resolve, 0)); }
function deliveryMeta(n, parentId) {
  return { id: n.id, type: n.type, name: n.name, visible: n.visible !== false,
    parentId: parentId === undefined ? n.parent?.id || null : parentId,
    width: n.width || 0, height: n.height || 0, x: n.x || 0, y: n.y || 0 };
}
function deliverySameMeta(a, b) { return ['id', 'type', 'name', 'visible', 'parentId', 'width', 'height', 'x', 'y'].every(k => a[k] === b[k]); }
function deliveryMarkStale(reason) { R4_DELIVERY_GENERATION++; for (const d of R4_DELIVERY_CACHE.values()) d.stale = reason; }
function deliveryHasObserver(d) { return d.review.parentId === d.branch.parentId && R4_DELIVERY_PAGE_OBSERVERS.has(d.review.parentId); }
function deliveryObserve(page) {
  if (!page || page.type !== 'PAGE') throw Error('Delivery sections require a Page parent.');
  const pageId = page.id;
  if (R4_DELIVERY_OBSERVER_TRIED.has(pageId)) return;
  R4_DELIVERY_OBSERVER_TRIED.add(pageId);
  try {
    if (typeof page.on !== 'function') throw Error('Page nodechange is unavailable.');
    const listener = event => {
      for (const change of event.nodeChanges || []) {
        const id = change.node?.id;
        const properties = change.properties || [];
        if (!id) { deliveryMarkStale('Page event has no node ID'); continue; }
        if (change.type === 'PROPERTY_CHANGE' && properties.length && properties.every(p => ['pluginData', 'sharedPluginData', 'flowStartingPoints'].includes(p))) continue;
        const expected = R4_DELIVERY_OWN_GEOMETRY.get(id);
        if (change.type !== 'PROPERTY_CHANGE' || !expected || !properties.length || !properties.every(p => ['x', 'y', 'width', 'height', 'name', 'relativeTransform', 'size', 'pluginData', 'sharedPluginData'].includes(p))) {
          deliveryMarkStale('Page changed: ' + id); continue;
        }
        // Own layout events may arrive after the write returns. Accept them only
        // while live metadata still exactly matches this module's final values.
        const check = (async () => {
          try { const n = await figma.getNodeByIdAsync(id), latest = R4_DELIVERY_OWN_GEOMETRY.get(id); if (!n || n.removed || !latest || !deliverySameMeta(deliveryMeta(n), latest)) deliveryMarkStale('Unexpected geometry change: ' + id); }
          catch (_) { deliveryMarkStale('Cannot verify changed root: ' + id); }
        })();
        R4_DELIVERY_EVENT_CHECKS.add(check); check.finally(() => R4_DELIVERY_EVENT_CHECKS.delete(check));
      }
    };
    // Page-scoped events work with dynamic-page without loading other pages.
    page.on('nodechange', listener); R4_DELIVERY_PAGE_OBSERVERS.set(pageId, listener);
    deliveryAck('当前页面变更监听已启用 · 缓存按根 ID 校验');
  } catch (error) {
    deliveryAck('页面监听不可用，将逐批完整核对根元数据 · ' + String(error));
  }
}
async function deliverySettleEvents() {
  await deliveryYield();
  while (R4_DELIVERY_EVENT_CHECKS.size) await Promise.all([...R4_DELIVERY_EVENT_CHECKS]);
}
function deliveryInvalidateCache(t) {
  if (t !== undefined && !R4_DELIVERY_SCOPE[t]) throw Error('Choose Light or Dark.');
  const themes = t ? [t] : ['Light', 'Dark'];
  for (const theme of themes) R4_DELIVERY_CACHE.delete(theme);
  return { status: '交付缓存已失效，下次将重新读取', themes, mutationCount: 0 };
}
async function deliveryRows(container, label) {
  const children = container.children, result = [];
  for (let i = 0; i < children.length; i++) {
    result.push(deliveryMeta(children[i], container.id));
    if ((i + 1) % 100 === 0) await deliveryYield(label + ' · 元数据 ' + (i + 1) + '/' + children.length);
  }
  return result;
}
async function deliveryValidateCache(d) {
  await deliverySettleEvents();
  if (d.stale) throw Error(d.stale + '; explicitly refresh delivery cache before continuing.');
  for (const [meta, rows] of [[d.review, d.reviewRows], [d.branch, d.branchRows]]) {
    const container = await figma.getNodeByIdAsync(meta.id);
    if (!container || container.removed || container.type !== 'SECTION' || !deliverySameMeta(deliveryMeta(container), meta)) { d.stale = 'Scoped section changed'; break; }
    const children = container.children;
    if (children.length !== rows.length) { d.stale = 'Root count changed'; break; }
    for (let i = 0; i < rows.length; i++) {
      if (children[i].id !== rows[i].id || (!deliveryHasObserver(d) && !deliverySameMeta(deliveryMeta(children[i], meta.id), rows[i]))) { d.stale = 'Root snapshot changed at ' + rows[i].id; break; }
      if ((i + 1) % 200 === 0) await deliveryYield();
    }
    if (d.stale) break;
  }
  await deliverySettleEvents();
  if (d.stale) throw Error(d.stale + '; explicitly refresh delivery cache before continuing.');
}

function deliveryManifestSpec(t) {
  const n = (key, suffix) => t + ' · R4 NET · ' + key + ' · ' + suffix;
  const rows = [];
  const add = (group, slug, key, title, source = 'r4') => rows.push({ group, slug, key, title, source });
  add('overview', 'review', 'Review', 'R4 交互评审目录');
  add('overview', 'dashboard', 'Dashboard', '多账号与固定剩余看板', 'r3');
  add('overview', 'settings', 'Settings', '当前设置入口', 'r3');
  add('network', 'check-a', n('Review 51', '检查中 A'), '检查中 · 动画相位 A');
  add('network', 'check-b', n('Review 51', '检查中 B'), '检查中 · 动画相位 B');
  add('network', 'pass51', n('Review 51', '评分 51 · 检查通过'), '51 分通过后继续授权');
  add('network', 'score49', n('Review 49', '有效评分 49 · 已阻止'), '49 分阻止');
  add('network', 'score50', n('Review 50', '有效评分 50 · 已阻止'), '50 分阻止');
  for (const outcome of ['timeout', 'unavailable', 'invalid']) {
    add('network', outcome, n('Review ' + outcome, outcome + ' · 无法完成检查'),
      { timeout: '检查超时', unavailable: '评分网站不可用', invalid: '无有效评分' }[outcome]);
  }
  add('network', 'query-failed', 'Network/QueryFailed', '通过检查后额度查询失败');
  add('network', 'authorization-failed', 'Network/AuthFailed', '通过检查后授权失败');
  add('first-query', 'before-add-source', 'Review/BeforeAddFailedLaunch', '新增前失败保留已有账号');
  add('first-query', 'before-add49', n('Review before add preserve accounts', '有效评分 49 · 已阻止'), '新增前 49 分阻止');
  add('first-query', 'pending', 'Review/FirstQueryLaunch', '新增后尚未取得额度');
  add('first-query', 'failed', 'Review/FirstQuery/Failed', '首次查询失败 · 无可信旧额度');
  for (const [state, title] of [['CheckA', '进入 App 自动检查'], ['Failed', '超时，保留旧数据'], ['Passed', '51 分检查通过'], ['Querying', '正在查询额度'], ['Success', '成功更新至 09:45']]) {
    add('background', 'app-' + state.toLowerCase(), 'Background/App/' + state, '后台更新 · ' + title);
  }
  for (const [state, title] of [['Failed', '网站不可用，保留 09:41'], ['Querying', '正在查询额度'], ['Success', '成功更新至 09:45']]) {
    add('background', 'widget-' + state.toLowerCase(), 'Background/Widget/' + state, '小组件联网 · ' + title);
  }
  add('widgets', 'gallery-small', 'Widgets/Gallery/small', '小号小组件');
  add('widgets', 'gallery-medium', 'Widgets/Gallery/medium', '中号小组件');
  add('widgets', 'choose-work', 'Widgets/Config/small/C', '选择具体 work 账号');
  add('widgets', 'configured-pair', 'Widgets/Home/Config/small/C', 'work 与 Cursor 两个独立组件');
  add('widgets', 'same-platform', 'Widgets/Home/Fallback/ABD', '同平台回退至个人 Codex');
  add('widgets', 'cross-platform', 'Widgets/Home/Fallback/AD', '跨平台回退至 Claude');
  add('widgets', 'empty', 'Widgets/Home/Fallback/Empty', '全部断开后的无账号状态');
  add('widgets', 'multiple-candidates', 'Widgets/Home/MultipleCandidates', '多个同平台候选按列表次序选择');
  add('widgets', 'same-platform-pending', 'AccountWidgets/Set-10/Pending-1', '同平台回退 · 未获取额度');
  add('widgets', 'cross-platform-pending', 'AccountWidgets/Set-9/Pending-0', '跨平台回退 · 未获取额度');
  add('widgets', 'stale-target', 'Widgets/Stale/Pending-10-1', '旧组件缓存 · 点击进入当前账号状态');
  add('accounts', 'work-expanded', 'Accounts/Set-15/Expanded-2', '具体 work 账号展开');
  add('accounts', 'work-menu', 'AccountFlow/Set-15/d/Menu-2', '具体 work 账号操作菜单');
  add('accounts', 'work-disconnect', 'AccountFlow/Set-15/d/Disconnect-2', '断开具体 work 账号');
  add('system', 'permission', 'AccountSystem/Set-15/Permission', '系统通知权限');
  add('system', 'denied', 'AccountSystem/Set-15/Settings-denied', '通知拒绝后的设置');
  add('system', 'ios-on', 'AccountSystem/Set-15/iOS-on', '系统设置开启通知');
  add('system', 'notification', 'LockNotification', '点击通知进入具体账号', 'kind');
  add('system', 'notification-removed', 'Notifications/TargetRemoved', '通知目标已断开');
  add('system', 'tutorial', 'Tutorial1', '小组件教程与退出', 'kind');
  return rows;
}

async function deliveryDirectory(t, options = {}) {
  deliveryAck(t + ' · 读取交付目录' + (options.refresh ? '（显式刷新）' : ''));
  const scope = R4_DELIVERY_SCOPE[t];
  if (!scope) throw Error('Delivery theme must be Light or Dark.');
  await deliverySettleEvents();
  if (options.refresh) deliveryInvalidateCache(t);
  const existing = R4_DELIVERY_CACHE.get(t);
  if (existing) { await deliveryValidateCache(existing); return existing; }
  const [review, branch, entry] = await Promise.all([scope.review, scope.branch, scope.entry].map(id => figma.getNodeByIdAsync(id)));
  if (!review || review.type !== 'SECTION' || !branch || branch.type !== 'SECTION' || !entry || entry.type !== 'FRAME') throw Error('Delivery scope missing.');
  const page = review.parent;
  if (!page || page.type !== 'PAGE' || branch.parent?.id !== page.id) throw Error('Delivery sections must share a Page.');
  deliveryObserve(page);
  await deliverySettleEvents();
  const generation = R4_DELIVERY_GENERATION;
  await deliveryYield(t + ' · 已取得评审区与交互区');
  const reviewRows = await deliveryRows(review, t + '评审区'), branchRows = await deliveryRows(branch, t + '交互区');
  const r3 = reviewRows.filter(n => n.type === 'FRAME' && n.visible);
  const r4 = branchRows.filter(n => n.type === 'FRAME' && n.name.startsWith('R4/' + t + '/'));
  const byName = new Map(), duplicates = [];
  for (const node of r4) {
    if (byName.has(node.name)) duplicates.push({ name: node.name, ids: [byName.get(node.name).id, node.id] });
    else byName.set(node.name, node);
  }
  const manifest = deliveryManifestSpec(t).map(item => {
    const node = item.source === 'r4' ? byName.get('R4/' + t + '/' + item.key) :
      item.source === 'r3' ? r3.find(n => n.name === t + '/' + item.key) :
      r3.find(n => n.name === t + '/' + item.key || n.name.split('|')[1] === item.key);
    return { ...item, node: node || null };
  });
  await deliverySettleEvents();
  if (generation !== R4_DELIVERY_GENERATION) throw Error('Document changed while reading delivery metadata; explicitly refresh.');
  const d = { t, scope, review: deliveryMeta(review), branch: deliveryMeta(branch), entry: deliveryMeta(entry),
    reviewRows, branchRows, r3, r4, byName, manifest, duplicates, generation, stale: null, layout: null,
    visibleLegacy: branchRows.filter(n => !n.name.startsWith('R4/') && n.visible) };
  R4_DELIVERY_CACHE.set(t, d);
  deliveryAck(t + ' · 目录元数据完成，R4 根 ' + r4.length);
  return d;
}

function deliveryArchiveGroup(t, name) {
  const key = name.slice(('R4/' + t + '/').length);
  const pending = key.match(/(?:Accounts|AccountFlow|AccountWidgets|AccountSystem)\/Pending-(\d+)-(\d+)/);
  if (pending) return '40 · 待获取集合 ' + pending[1].padStart(3, '0') + ' / 账号 ' + pending[2];
  const set = key.match(/(?:Accounts|AccountFlow|AccountWidgets|AccountSystem)\/Set-(\d+)/);
  if (set) return '30 · 账号集合 ' + set[1].padStart(3, '0');
  if (key.includes('· R4 NET ·') || key.startsWith('Network/')) return '10 · 网络检查完整分支';
  if (key.startsWith('Widgets/') || key.startsWith('AccountWidgets/')) return '11 · 小组件完整分支';
  if (key.startsWith('Background/')) return '12 · 后台与小组件更新完整分支';
  if (key.startsWith('Notifications/') || key.startsWith('AccountSystem/') || key.startsWith('System/')) return '13 · 通知与系统完整分支';
  if (key.startsWith('ReviewRepair/')) return '50 · 原评审画面的保留数据分支';
  if (key.startsWith('AccountFlow/')) return '20 · 账号新增与共享查询分支';
  return '60 · 其他已建 R4 状态';
}

async function deliveryLayout(directory) {
  if (directory.stale) throw Error('Delivery layout cache is stale; refresh first.');
  if (directory.layout) return directory.layout;
  await deliveryYield(directory.t + ' · 准备缓存布局');
  const order = ['overview', 'network', 'first-query', 'background', 'widgets', 'accounts', 'system'];
  const labels = { overview: '评审目录', network: '网络检查', 'first-query': '新增前检查与首次查询', background: '后台与小组件联网', widgets: '小组件配置与回退', accounts: '具体账号操作', system: '通知与教程' };
  const selected = new Set(), groups = [];
  for (let i = 0; i < order.length; i++) {
    const key = order[i], nodes = [];
    for (const item of directory.manifest.filter(x => x.group === key && x.source === 'r4' && x.node)) {
      if (!selected.has(item.node.id)) { selected.add(item.node.id); nodes.push(item.node); }
    }
    if (nodes.length) groups.push({ name: '0' + i + ' · 关键评审 · ' + labels[key], key, columns: 8, nodes });
  }
  const archive = new Map();
  let prepared = 0;
  for (const node of directory.r4) {
    if (selected.has(node.id)) continue;
    const group = deliveryArchiveGroup(directory.t, node.name);
    if (!archive.has(group)) archive.set(group, []);
    archive.get(group).push(node);
    if (++prepared % 500 === 0) await deliveryYield();
  }
  for (const key of [...archive.keys()].sort()) {
    groups.push({ name: key, key, columns: 16,
      nodes: archive.get(key).sort((a, b) => a.name < b.name ? -1 : a.name > b.name ? 1 : 0) });
    await deliveryYield();
  }
  const placements = [], summaries = [];
  const cellWidth = Math.ceil(directory.r4.reduce((width, n) => Math.max(width, n.width), 393)) + 32;
  let y = 96, right = 0;
  for (const group of groups) {
    const startY = y;
    for (let offset = 0; offset < group.nodes.length; offset += group.columns) {
      const row = group.nodes.slice(offset, offset + group.columns);
      const rowHeight = Math.ceil(Math.max(...row.map(n => n.height)));
      row.forEach((node, column) => {
        const x = 48 + column * cellWidth;
        placements.push({ node, x, y, group: group.name });
        right = Math.max(right, x + node.width);
      });
      y += rowHeight + 56;
      if (placements.length % 256 < group.columns) await deliveryYield();
    }
    summaries.push({ name: group.name, count: group.nodes.length, top: startY, bottom: y - 56,
      first: group.nodes[0].id, last: group.nodes[group.nodes.length - 1].id });
    y += 128;
  }
  await deliverySettleEvents();
  if (directory.stale) throw Error('Document changed while preparing delivery layout; refresh first.');
  directory.layout = { placements, groups: summaries, width: right + 48, height: y, cellWidth };
  return directory.layout;
}

// Shallow, read-only counts/manifest. This does not replace auditR4 or clicking.
async function deliveryReadOnlyStage(t, options = {}) {
  deliveryAck(t + ' · 开始只读交付检查');
  const d = await deliveryDirectory(t, options), layout = await deliveryLayout(d);
  return { status: t + ' 交付清单与排布计划（只读）', version: R4_DELIVERY_VERSION,
    counts: { originalVisibleReview: d.r3.length, expectedOriginalVisibleReview: 44,
      r4Roots: d.r4.length, r4Visible: d.r4.filter(n => n.visible !== false).length,
      legacyVisible: d.visibleLegacy.length, curated: d.manifest.filter(x => x.node).length },
    duplicates: d.duplicates,
    missingCurated: d.manifest.filter(x => !x.node).map(({ node, ...item }) => item),
    groups: layout.groups, plannedBounds: { width: layout.width, height: layout.height },
    manifest: d.manifest.filter(x => x.node).map(({ node, ...item }) => ({ ...item, id: node.id, name: node.name,
      filename: t.toLowerCase() + '-' + item.group + '-' + item.slug + '.png',
      section: node.parentId, width: node.width, height: node.height })),
    entries: { original: d.entry.id, r4: d.byName.get('R4/' + t + '/Review')?.id || null },
    cache: { generation: d.generation, metadataCached: true, documentObserver: false, pageObserver: deliveryHasObserver(d), observedPageId: deliveryHasObserver(d) ? d.review.parentId : null, validation: deliveryHasObserver(d) ? 'root IDs plus page nodechange observer' : 'root IDs plus full metadata fallback' },
    limitations: ['只浅读根节点与导出清单；不验证文字遮挡、反应目标、动画或实际点击。', '排布不会改变任何根名称、父级、可见性或原型反应。'] };
}

// Resumable, deterministic batches. The caller repeats using nextIndex.
async function arrangeDeliveryStage(t, start = 0, count = 200) {
  deliveryAck(t + ' · 开始排布批次 ' + start);
  if (!Number.isInteger(start) || start < 0 || !Number.isInteger(count) || count < 1 || count > 400) throw Error('Delivery batches require start>=0 and count 1–400.');
  const d = await deliveryDirectory(t);
  if (d.r3.length !== 44) throw Error('Expected 44 visible original review roots.');
  if (d.visibleLegacy.length) throw Error('Finish reviewed legacy cleanup before moving R4 roots to the top.');
  if (d.duplicates.length) throw Error('Duplicate R4 root names require inspection before arrangement.');
  if (d.manifest.some(x => !x.node)) throw Error('Missing curated root; run deliveryReadOnlyStage for exact keys.');
  const layout = await deliveryLayout(d), end = Math.min(start + count, layout.placements.length);
  if (start > layout.placements.length) throw Error('Delivery start exceeds root count.');
  // Width stays within the existing side-by-side section spacing in this file.
  if (layout.width > 9000) throw Error('Unexpected wide root: inspect layout before changing section bounds.');
  const neededHeight = d.branchRows.reduce((height, n) => n.name.startsWith('R4/') ? height : Math.max(height, n.y + n.height + 48), layout.height);
  const [branch, review] = await Promise.all([d.branch.id, d.review.id].map(id => figma.getNodeByIdAsync(id)));
  if (!branch || !review || branch.removed || review.removed) throw Error('Delivery sections disappeared.');
  const own = (node, meta) => { const current = deliveryMeta(node); Object.assign(meta, current); R4_DELIVERY_OWN_GEOMETRY.set(node.id, { ...current }); };
  // Preflight only this batch's live roots. Sorting and target coordinates use
  // the single cached plan; no global native name/size reads recur per batch.
  const batch = [];
  for (let i = start; i < end; i++) {
    const placement = layout.placements[i], node = await figma.getNodeByIdAsync(placement.node.id);
    if (!node || node.removed || !deliverySameMeta(deliveryMeta(node), placement.node)) { d.stale = 'Live root differs from cached layout'; throw Error(d.stale + '; refresh before writing.'); }
    batch.push({ placement, node });
    if ((i - start + 1) % 80 === 0) await deliveryYield(t + ' · 排布预检 ' + (i + 1) + '/' + layout.placements.length);
  }
  await deliverySettleEvents(); if (d.stale) throw Error(d.stale + '; refresh before writing.');
  branch.resizeWithoutConstraints(Math.max(branch.width, layout.width), Math.max(branch.height, neededHeight)); own(branch, d.branch);
  if (typeof writes !== 'undefined') writes.add(branch.id);
  let moved = 0;
  for (let i = 0; i < batch.length; i++) {
    const { placement, node } = batch[i], { x, y } = placement;
    if (node.x !== x || node.y !== y) { node.x = x; node.y = y; own(node, placement.node); moved++; if (typeof writes !== 'undefined') writes.add(node.id); }
    if ((i + 1) % 80 === 0) {
      await deliveryYield(t + ' 排布 ' + (start + i + 1) + '/' + layout.placements.length);
    }
  }
  const remaining = end === layout.placements.length ? layout.placements.findIndex(x => x.node.x !== x.x || x.node.y !== x.y) : -1;
  const complete = end === layout.placements.length && remaining === -1;
  const nextIndex = end === layout.placements.length && !complete ? remaining : end;
  branch.setPluginData('r4_delivery_layout_batch', JSON.stringify({ version: R4_DELIVERY_VERSION, nextIndex, total: layout.placements.length }));
  if (complete) {
    review.name = d.scope.label + ' · R4 画面评审 · 保留 44 页'; own(review, d.review);
    branch.name = d.scope.label + ' · R4 交互状态与返回路径 · 关键评审置顶'; own(branch, d.branch);
    if (typeof writes !== 'undefined') writes.add(d.review.id);
    branch.resizeWithoutConstraints(Math.max(branch.width, layout.width), neededHeight); own(branch, d.branch);
    branch.setPluginData('r4_delivery_layout_complete', JSON.stringify({ version: R4_DELIVERY_VERSION, total: layout.placements.length, groups: layout.groups }));
  }
  figma.commitUndo();
  await deliverySettleEvents(); if (d.stale) throw Error(d.stale + '; inspect the completed batch before refreshing.');
  return { status: complete ? t + ' 画布排布完成' : t + ' 画布排布批次完成',
    start, end, nextIndex, total: layout.placements.length, moved, complete,
    scope: '只移动当前交互区现有 R4 根；不改原 44 页坐标，不改根名称、父级、反应或组件。' };
}

// Preserve both original entry URLs. Unrelated flow-starting points on the
// same page are retained; only starts within these four scoped sections change.
async function finalizeDeliveryEntriesStage() {
  deliveryAck('开始核对两套原型起点');
  const light = await deliveryDirectory('Light'), dark = await deliveryDirectory('Dark');
  for (const d of [light, dark]) {
    const branch = await figma.getNodeByIdAsync(d.branch.id);
    if (!branch?.getPluginData('r4_final_links_complete') || !d.byName.has('R4/' + d.t + '/Review')) throw Error('Complete both final review directories before publishing flow-starting points.');
  }
  const p = await figma.getNodeByIdAsync(light.review.parentId);
  if (light.review.parentId !== dark.review.parentId || !p || p.type !== 'PAGE') throw Error('Delivery sections must share a page.');
  const scopedSections = new Set([light, dark].flatMap(d => [d.review.id, d.branch.id]));
  const scopedRoots = new Set([light, dark].flatMap(d => [...d.reviewRows, ...d.branchRows].map(n => n.id)));
  const previous = p.flowStartingPoints.map(x => ({ nodeId: x.nodeId, name: x.name }));
  const unrelated = [];
  for (const point of previous) {
    if (scopedRoots.has(point.nodeId)) continue;
    let owned = false;
    const node = await figma.getNodeByIdAsync(point.nodeId);
    for (let parent = node; parent && parent.type !== 'PAGE'; parent = parent.parent) if (scopedSections.has(parent.id)) { owned = true; break; }
    if (!owned) unrelated.push(point);
  }
  p.flowStartingPoints = unrelated.concat([
    { nodeId: light.entry.id, name: 'R4 · 浅色 · 交互状态与返回路径' },
    { nodeId: dark.entry.id, name: 'R4 · 深色 · 交互状态与返回路径' },
  ]);
  figma.commitUndo();
  return { status: '原型起点已更新，原链接保留', previous, current: p.flowStartingPoints,
    entries: { Light: light.entry.id, Dark: dark.entry.id } };
}

// Export only a small native gallery batch. No section-wide bitmap, composite,
// temporary frames, or screenshots produced by redrawing the Figma content.
async function deliveryGalleryStage(t, group = 'network', start = 0, count = 4) {
  deliveryAck(t + ' · 开始导出批次 ' + group + '/' + start);
  if (!Number.isInteger(start) || start < 0 || !Number.isInteger(count) || count < 1 || count > 4) throw Error('Export 1–4 selected frames per batch.');
  const d = await deliveryDirectory(t), selected = d.manifest.filter(x => group === 'all' || x.group === group);
  if (!selected.length) throw Error('Unknown or empty delivery group: ' + group);
  const batch = selected.slice(start, start + count);
  if (batch.some(x => !x.node)) throw Error('Selected export target missing; inspect deliveryReadOnlyStage.');
  const gallery = [];
  for (const item of batch) {
    figma.ui.postMessage({ status: '导出 ' + t + ' · ' + item.title, progress: true });
    const node = await figma.getNodeByIdAsync(item.node.id);
    if (!node || node.removed || !deliverySameMeta(deliveryMeta(node), item.node)) { d.stale = 'Export target changed'; throw Error(d.stale + '; refresh before exporting.'); }
    const bytes = await node.exportAsync({ format: 'PNG', constraint: { type: 'SCALE', value: 1 } });
    gallery.push({ id: item.node.id, name: item.node.name, title: item.title,
      filename: t.toLowerCase() + '-' + item.group + '-' + item.slug + '.png', bytes: Array.from(bytes) });
  }
  return { status: t + ' ' + group + ' 原生静态截图完成', group, start, end: start + batch.length,
    total: selected.length, complete: start + batch.length >= selected.length, gallery };
}


// Read-only native Figma audit. This module never changes nodes, selection,
// plugin data, fonts, the current page, or prototype reactions.
// All new R4 roots and visible R3 review roots are inspected. Old interaction
// trees are opened only when a reachable edge leads to them, within a budget.
const R4_AUDIT_SCOPES = [
  { id: '1:43251', theme: 'Light', role: 'review' },
  { id: '1:43252', theme: 'Light', role: 'interaction' },
  { id: '1:43253', theme: 'Dark', role: 'review' },
  { id: '1:43254', theme: 'Dark', role: 'interaction' }
];

function r4AuditPlain(value) {
  if (value === undefined) return null;
  return JSON.parse(JSON.stringify(value));
}
function r4AuditRound(value) {
  return typeof value === 'number' ? Math.round(value * 1000) / 1000 : value;
}
function r4AuditBox(node) {
  const box = {};
  for (const key of ['x', 'y', 'width', 'height', 'rotation']) {
    if (typeof node[key] === 'number') box[key] = r4AuditRound(node[key]);
  }
  if (node.absoluteBoundingBox) {
    box.absolute = Object.fromEntries(Object.entries(node.absoluteBoundingBox).map(([key, value]) => [key, r4AuditRound(value)]));
  }
  return box;
}
function r4AuditCanonical(value) {
  return String(value).replace(/Light|Dark/g, '{theme}').replace(/浅色|深色/g, '{主题}');
}
function r4AuditActions(reaction) {
  return reaction.actions || (reaction.action ? [reaction.action] : []);
}
function r4AuditNodeActions(value, result = []) {
  if (!value || typeof value !== 'object') return result;
  if (Array.isArray(value)) {
    value.forEach(item => r4AuditNodeActions(item, result));
  } else {
    if (value.type === 'NODE') result.push(value);
    for (const [key, item] of Object.entries(value)) {
      if (key !== 'destinationId') r4AuditNodeActions(item, result);
    }
  }
  return result;
}
function r4AuditOldKind(name, text = '') {
  const reasons = [];
  if (/\|U\|/.test(name)) reasons.push('legacy-used-root');
  if (/(?:^|[\/|])Display(?:$|[\/|])/.test(name)) reasons.push('legacy-display-preferences-root');
  if (/^Row\/额度显示$|^Choice\/已用$|^Button\/查看(?:已用|剩余)状态$/.test(name)) reasons.push('legacy-display-control');
  if (/^(?:额度显示|显示偏好|显示已用|已用显示|查看已用状态|查看剩余状态)$/.test(text.trim())) reasons.push('legacy-display-text');
  return reasons;
}
function r4AuditRemovedText(text) {
  const deleted = [
    '开启后，在额度预计重置时收到提醒',
    '外观自动跟随 iPhone 系统',
    '选择平台添加账户。同一平台可继续添加其他账户。',
    '集中查看 Claude、Codex 和 Cursor 的订阅额度与重置时间。',
    '使用你的平台账户继续',
    '小组件会在下次系统更新后显示已断开。'
  ];
  return deleted.filter(value => text.includes(value)).concat(/^已添加\s*\d+\s*个$/.test(text.trim()) ? ['已添加 n 个'] : []);
}

async function auditR4(options = {}) {
  const maxLegacyRoots = Number.isInteger(options.maxLegacyRoots) ? Math.max(0, Math.min(128, options.maxLegacyRoots)) : 64;
  const maxLegacyNodes = Number.isInteger(options.maxLegacyNodes) ? Math.max(0, Math.min(30000, options.maxLegacyNodes)) : 12000;
  const started = new Date().toISOString();
  const directory = new Map(), nodes = new Map(), owners = new Map(), paths = new Map();
  const inspected = new Map(), edges = new Map(), targetCache = new Map();
  const invalidTargets = [], selfLinks = [], externalTargets = [], legacyBoundaries = [];
  const sections = [], missingSections = [];
  let legacyNodeCount = 0, legacyRootCount = 0;
  const legacyUnscanned = new Set(), incompleteRoots = new Set();

  for (const scope of R4_AUDIT_SCOPES) {
    const section = await figma.getNodeByIdAsync(scope.id);
    if (!section || section.type !== 'SECTION') {
      missingSections.push(scope.id);
      continue;
    }
    sections.push({ ...scope, node: section });
    // This is a shallow directory; never call findAll on an old section.
    for (const root of section.children) {
      directory.set(root.id, { node: root, ...scope });
      nodes.set(root.id, root);
      owners.set(root.id, root.id);
      paths.set(root.id, '$');
    }
  }

  function owner(node) {
    if (!node) return null;
    if (owners.has(node.id)) return owners.get(node.id);
    for (let current = node; current && current.type !== 'PAGE' && current.type !== 'DOCUMENT'; current = current.parent) {
      if (directory.has(current.id)) {
        owners.set(node.id, current.id);
        return current.id;
      }
    }
    return null;
  }
  function rootName(id) {
    return directory.has(id) ? directory.get(id).node.name : null;
  }
  function collect(rootInfo, legacy = false) {
    const root = rootInfo.node;
    if (inspected.has(root.id)) return inspected.get(root.id);
    const record = {
      id: root.id, name: root.name, theme: rootInfo.theme, sectionId: rootInfo.id,
      role: rootInfo.role, generation: root.name.startsWith('R4/') ? 'R4' : 'R3-or-legacy',
      visible: root.visible !== false, bounds: r4AuditBox(root), legacyTraversal: legacy,
      complete: true, nodeCount: 0, texts: [], reactions: [], legacyMarkers: [], removedText: []
    };
    const rootReasons = r4AuditOldKind(root.name);
    if (rootReasons.length) record.legacyMarkers.push({ id: root.id, path: '$', visible: root.visible !== false, reasons: rootReasons });
    const stack = [{ node: root, path: '$', visible: rootInfo.node.parent.visible !== false }];
    while (stack.length) {
      if (legacy && legacyNodeCount >= maxLegacyNodes) {
        record.complete = false;
        incompleteRoots.add(root.id);
        break;
      }
      const item = stack.pop(), node = item.node;
      // A transparent hotspot can still be clickable in a prototype. Only
      // the visibility flag excludes it from the conservative link graph.
      const visible = item.visible && node.visible !== false;
      record.nodeCount++;
      if (legacy) legacyNodeCount++;
      nodes.set(node.id, node);
      owners.set(node.id, root.id);
      paths.set(node.id, item.path);
      if (node.type === 'TEXT') {
        record.texts.push({ id: node.id, name: node.name, path: item.path, text: node.characters, visible, opacity: node.opacity, bounds: r4AuditBox(node) });
        const removed = r4AuditRemovedText(node.characters);
        if (removed.length && visible) record.removedText.push({ id: node.id, path: item.path, text: node.characters, matches: removed });
      }
      const reasons = r4AuditOldKind(node.name, node.type === 'TEXT' ? node.characters : '');
      if (node.id !== root.id && reasons.length) record.legacyMarkers.push({ id: node.id, path: item.path, visible, reasons });
      if ('reactions' in node && node.reactions.length) {
        record.reactions.push({
          id: node.id, name: node.name, path: item.path, visible, opacity: node.opacity, bounds: r4AuditBox(node),
          reactions: node.reactions.map(reaction => ({ trigger: r4AuditPlain(reaction.trigger), actions: r4AuditPlain(r4AuditActions(reaction)) }))
        });
      }
      if ('children' in node) {
        const seen = new Map(), children = [];
        for (const child of node.children) {
          const occurrence = seen.get(child.name) || 0;
          seen.set(child.name, occurrence + 1);
          // Ordinals only distinguish equal sibling names; light/dark IDs differ.
          children.push({ node: child, path: item.path + '/' + child.name + (occurrence ? '[' + occurrence + ']' : ''), visible });
        }
        for (let i = children.length - 1; i >= 0; i--) stack.push(children[i]);
      }
    }
    inspected.set(root.id, record);
    return record;
  }

  async function target(id) {
    if (!id || typeof id !== 'string') return null;
    if (targetCache.has(id)) return targetCache.get(id);
    let node = nodes.get(id) || null;
    if (!node) {
      try { node = await figma.getNodeByIdAsync(id); } catch (_) { node = null; }
    }
    if (node && node.removed) node = null;
    const result = node ? { id: node.id, name: node.name, type: node.type, rootId: owner(node), visible: node.visible !== false } : null;
    targetCache.set(id, result);
    return result;
  }

  async function connect(record) {
    if (edges.has(record.id)) return;
    const result = [], seen = new Set();
    for (const layer of record.reactions) for (let index = 0; index < layer.reactions.length; index++) {
      const reaction = layer.reactions[index];
      for (const action of r4AuditNodeActions(reaction.actions)) {
        const destination = await target(action.destinationId);
        const edge = {
          sourceRootId: record.id, sourceNodeId: layer.id, sourcePath: layer.path, visible: layer.visible,
          reactionIndex: index, trigger: reaction.trigger, navigation: action.navigation,
          transition: r4AuditPlain(action.transition), destinationId: action.destinationId || null,
          destinationRootId: destination ? destination.rootId : null,
          destinationName: destination ? destination.name : null
        };
        result.push(edge);
        if (!destination) invalidTargets.push(edge);
        else if (destination.rootId === record.id) selfLinks.push(edge);
        else if (!destination.rootId) externalTargets.push({ ...edge, destinationType: destination.type });
        else {
          const info = directory.get(destination.rootId);
          if (info.role === 'interaction' && !info.node.name.startsWith('R4/')) {
            const key = layer.id + '/' + destination.rootId;
            if (!seen.has(key)) legacyBoundaries.push({ ...edge, legacyKind: r4AuditOldKind(info.node.name) });
            seen.add(key);
          }
        }
      }
    }
    edges.set(record.id, result);
  }

  const primaryIds = [];
  for (const info of directory.values()) {
    if (info.node.name.startsWith('R4/') || (info.role === 'review' && info.node.type === 'FRAME' && info.node.visible !== false)) {
      primaryIds.push(info.node.id);
      collect(info);
    }
  }
  for (let i = 0; i < primaryIds.length; i++) {
    await connect(inspected.get(primaryIds[i]));
    if (i % 12 === 11) await new Promise(resolve => setTimeout(resolve, 0));
  }

  const sourcePage = sections.length ? sections[0].node.parent : null;
  const configured = sourcePage && 'flowStartingPoints' in sourcePage ? r4AuditPlain(sourcePage.flowStartingPoints) : [];
  const configuredIds = [];
  for (const point of configured || []) {
    const destination = await target(point.nodeId);
    if (destination && destination.rootId) configuredIds.push(destination.rootId);
  }
  const reviewIds = primaryIds.filter(id => {
    const info = directory.get(id);
    return info.node.visible !== false && (info.role === 'review' || /\/(?:Review|StateReview)$/.test(info.node.name));
  });

  async function trace(entryIds) {
    const queue = [...new Set(entryIds)], previous = new Map(queue.map(id => [id, null]));
    const blocked = new Set();
    for (let cursor = 0; cursor < queue.length; cursor++) {
      const id = queue[cursor], info = directory.get(id);
      if (!info) continue;
      if (!inspected.has(id)) {
        if (legacyRootCount >= maxLegacyRoots || legacyNodeCount >= maxLegacyNodes) {
          legacyUnscanned.add(id);
          blocked.add(id);
          continue;
        }
        legacyRootCount++;
        collect(info, true);
        await connect(inspected.get(id));
      }
      const record = inspected.get(id);
      if (!record.complete) blocked.add(id);
      for (const edge of edges.get(id) || []) {
        if (!edge.visible || !edge.destinationRootId || previous.has(edge.destinationRootId)) continue;
        previous.set(edge.destinationRootId, { rootId: id, sourceNodeId: edge.sourceNodeId, navigation: edge.navigation });
        queue.push(edge.destinationRootId);
      }
    }
    function pathTo(id) {
      const path = [];
      for (let current = id; current; current = previous.get(current)?.rootId) {
        const step = previous.get(current);
        path.push({ id: current, name: rootName(current), via: step ? { sourceNodeId: step.sourceNodeId, navigation: step.navigation } : null });
      }
      return path.reverse();
    }
    const oldUsedOrPreferences = [];
    for (const id of previous.keys()) {
      const record = inspected.get(id), rootReasons = r4AuditOldKind(rootName(id) || '');
      const markers = record ? record.legacyMarkers.filter(marker => marker.visible) : [];
      if (rootReasons.length || markers.length) oldUsedOrPreferences.push({ id, name: rootName(id), rootReasons, markers, path: pathTo(id) });
    }
    return {
      entryIds: [...new Set(entryIds)], reachableRootIds: [...previous.keys()], complete: blocked.size === 0,
      blockedRootIds: [...blocked], oldUsedOrPreferences,
      reachableInvalidTargets: invalidTargets.filter(edge => edge.visible && previous.has(edge.sourceRootId))
    };
  }

  // Configured flows get the legacy budget first. The broader review sweep
  // includes every visible review frame so a static evaluation entry is clear.
  const configuredReachability = await trace(configuredIds);
  const reviewReachability = await trace(reviewIds);

  function canonicalAction(value) {
    if (Array.isArray(value)) return value.map(canonicalAction);
    if (!value || typeof value !== 'object') return typeof value === 'string' ? r4AuditCanonical(value) : r4AuditRound(value);
    const result = {};
    for (const key of Object.keys(value).sort()) {
      if (key === 'destinationId') {
        const destination = targetCache.get(value[key]);
        result.destination = destination ? r4AuditCanonical((destination.rootId ? rootName(destination.rootId) : 'EXTERNAL/' + destination.name) + '/' + (paths.get(value[key]) || '$')) : 'MISSING';
      } else result[key] = canonicalAction(value[key]);
    }
    return result;
  }
  function fingerprint(record) {
    return {
      geometry: { width: record.bounds.width, height: record.bounds.height, visible: record.visible },
      text: record.texts.map(item => ({ path: r4AuditCanonical(item.path), visible: item.visible, text: r4AuditCanonical(item.text) })),
      reactions: record.reactions.map(item => ({ path: r4AuditCanonical(item.path), visible: item.visible, reactions: canonicalAction(item.reactions) }))
    };
  }
  const byTheme = { Light: new Map(), Dark: new Map() };
  for (const id of primaryIds) {
    const record = inspected.get(id), key = r4AuditCanonical(record.name);
    const group = byTheme[record.theme].get(key) || [];
    group.push(record);
    byTheme[record.theme].set(key, group);
  }
  const symmetry = { pairedCount: 0, missingLight: [], missingDark: [], duplicates: [], geometry: [], text: [], reactions: [] };
  for (const key of new Set([...byTheme.Light.keys(), ...byTheme.Dark.keys()])) {
    const light = byTheme.Light.get(key) || [], dark = byTheme.Dark.get(key) || [];
    if (!light.length) symmetry.missingLight.push({ key, ids: dark.map(item => item.id) });
    if (!dark.length) symmetry.missingDark.push({ key, ids: light.map(item => item.id) });
    if (light.length > 1 || dark.length > 1) symmetry.duplicates.push({ key, lightIds: light.map(item => item.id), darkIds: dark.map(item => item.id) });
    if (light.length !== 1 || dark.length !== 1) continue;
    symmetry.pairedCount++;
    const a = fingerprint(light[0]), b = fingerprint(dark[0]);
    for (const field of ['geometry', 'text', 'reactions']) {
      if (JSON.stringify(a[field]) !== JSON.stringify(b[field])) symmetry[field].push({ key, lightId: light[0].id, darkId: dark[0].id });
    }
  }

  const roots = [...inspected.values()];
  return {
    status: '只读审计完成；结果不代表已经实际点击验证', schemaVersion: 1, started, finished: new Date().toISOString(),
    scope: sections.map(({ node, ...scope }) => ({ ...scope, name: node.name, rootCount: node.children.length, bounds: r4AuditBox(node) })),
    missingSections, budgets: { maxLegacyRoots, maxLegacyNodes, legacyRootCount, legacyNodeCount },
    coverage: {
      primaryRootCount: primaryIds.length, inspectedRootCount: roots.length,
      inspectedNodeCount: roots.reduce((sum, root) => sum + root.nodeCount, 0),
      legacyUnscanned: [...legacyUnscanned].map(id => ({ id, name: rootName(id) })), incompleteRoots: [...incompleteRoots],
      allPrimaryRootsComplete: primaryIds.every(id => inspected.get(id).complete)
    },
    configuredFlowStartingPoints: configured, roots,
    edges: [...edges.values()].flat(), invalidTargets, selfLinks, externalTargets, legacyBoundaries,
    removedText: roots.flatMap(root => root.removedText.map(item => ({ rootId: root.id, rootName: root.name, ...item }))),
    reachability: { configured: configuredReachability, visibleReview: reviewReachability }, symmetry,
    limitations: [
      'Reachability is a conservative graph of visible prototype NODE actions; conditions are treated as possible branches.',
      'Zero-opacity hotspots remain in the link graph because opacity does not disable prototype interaction.',
      'CLOSE and BACK return to the runtime overlay/navigation stack and have no fixed destination in this static audit.',
      'Legacy reachability is incomplete whenever blockedRootIds or incompleteRoots are nonempty.',
      'Text, animation, return-path intent, and actual tappable areas still require prototype clicks and screenshots.'
    ]
  };
}


// Read-only, bounded native audit. No env(), fonts(), selection, page change,
// pluginData write, or reaction/node mutation. Progress exists in runtime only.
// Start after authoring/delivery has stopped; then batch each theme (<=200 roots).
let R4_COMPACT_AUDIT = null;
const R4_COMPACT_SCOPES = [
  { id: '1:43251', theme: 'Light', role: 'review' }, { id: '1:43252', theme: 'Light', role: 'interaction' },
  { id: '1:43253', theme: 'Dark', role: 'review' }, { id: '1:43254', theme: 'Dark', role: 'interaction' }
];
function r4cNorm(value) { return String(value).replace(/Light|Dark/g, '{theme}').replace(/浅色|深色/g, '{主题}'); }
function r4cShort(value, length = 180) { const s = String(value); return s.length > length ? s.slice(0, length) + '…' : s; }
function r4cBytes(value) { let n = 0; for (const c of String(value)) { const x = c.codePointAt(0); n += x < 128 ? 1 : x < 2048 ? 2 : x < 65536 ? 3 : 4; } return n; }
function r4cHash() { return { a: 2166136261, b: 5381, length: 0 }; }
function r4cFeed(h, value) { const s = String(value); h.length += s.length + 1; for (let i = 0; i <= s.length; i++) { const c = i === s.length ? 0 : s.charCodeAt(i); h.a = Math.imul(h.a ^ c, 16777619) >>> 0; h.b = (Math.imul(h.b, 33) ^ c) >>> 0; } }
function r4cDigest(h) { return [h.a.toString(16), h.b.toString(16), h.length].join(':'); }
function r4cStable(value) {
  if (Array.isArray(value)) return value.map(r4cStable);
  if (value && typeof value === 'object') { const out = {}; for (const k of Object.keys(value).sort()) out[k] = r4cStable(value[k]); return out; }
  return typeof value === 'string' ? r4cNorm(value) : typeof value === 'number' ? Math.round(value * 1000) / 1000 : value;
}
function r4cActions(r) { return r.actions || (r.action ? [r.action] : []); }
function r4cClickable(node) { return 'reactions' in node && (node.reactions || []).some(r => r.trigger?.type === 'ON_CLICK' && r4cActions(r).length > 0); }
function r4cVisible(node) { for (let n = node; n && n.type !== 'DOCUMENT'; n = n.parent) if (n.visible === false) return false; return true; }
function r4cOld(name, text = '') {
  const found = [];
  if (/\|U\||(?:^|[\/|])Display(?:$|[\/|])/.test(name)) found.push('used/display root');
  if (/^Row\/额度显示$|^Choice\/已用$|^Button\/查看(?:已用|剩余)状态$/.test(name)) found.push('display control');
  if (/^(?:额度显示|显示偏好|显示已用|已用显示|查看已用状态|查看剩余状态)$/.test(text.trim())) found.push('display text');
  return found;
}
function r4cRemoved(text) {
  const clean = text.replace(/\s+/g, ''), list = [
    ['TXT-01', '开启后，在额度预计重置时收到提醒'], ['TXT-02', '外观自动跟随iPhone系统'],
    ['TXT-03', '选择平台添加账户。同一平台可继续添加其他账户。'],
    ['TXT-04', '集中查看Claude、Codex和Cursor的订阅额度与重置时间。'],
    ['TXT-05', '使用你的平台账户继续'], ['TXT-06', '小组件会在下次系统更新后显示已断开。']
  ];
  const found = list.filter(([, phrase]) => clean.includes(phrase)).map(([id]) => id);
  if (/已添加\d+个/.test(clean)) found.push('TXT-03/count'); return found;
}
function r4cIssue(s, kind, data) {
  const bucket = s.issues[kind] || (s.issues[kind] = { count: 0, samples: [], omitted: 0 }); bucket.count++;
  const sample = { ...data };
  for (const k of ['root', 'path', 'target', 'text', 'reason', 'key']) if (sample[k] !== undefined) sample[k] = r4cShort(sample[k]);
  const bytes = r4cBytes(JSON.stringify(sample));
  if (bucket.samples.length < s.options.sampleCap && s.sampleBytes + bytes <= s.options.sampleBudgetBytes) { bucket.samples.push(sample); s.sampleBytes += bytes; }
  else bucket.omitted++;
}
function r4cOwner(s, node) { for (let n = node; n && n.type !== 'PAGE' && n.type !== 'DOCUMENT'; n = n.parent) if (s.byId.has(n.id)) return s.byId.get(n.id); return null; }
function r4cPath(node, ownerId) {
  const parts = []; for (let n = node; n && n.id !== ownerId; n = n.parent) {
    const peers = n.parent && 'children' in n.parent ? n.parent.children.filter(c => c.name === n.name) : [];
    const index = peers.findIndex(c => c.id === n.id); parts.push(n.name + (index > 0 ? '[' + index + ']' : ''));
  } return '$' + (parts.length ? '/' + parts.reverse().join('/') : '');
}
async function r4cTarget(s, id) {
  if (s.targets.has(id)) return s.targets.get(id);
  let node = null; try { if (typeof id === 'string') node = await figma.getNodeByIdAsync(id); } catch (_) {}
  if (!node || node.removed) { s.targets.set(id, null); return null; }
  const owner = r4cOwner(s, node), result = { id, type: node.type, visible: r4cVisible(node), owner: owner === null ? null : owner,
    canonical: owner === null ? 'EXTERNAL/' + r4cNorm(node.name) : s.directory[owner].canonical + '/' + r4cNorm(r4cPath(node, s.directory[owner].id)), name: node.name };
  s.targets.set(id, result); return result;
}
function r4cQueueLegacy(s, index) {
  const info = s.directory[index]; if (s.queued.has(index)) return;
  if (s.legacyQueued >= s.options.maxLegacyRoots) { s.legacyUnscanned.add(index); return; }
  s.legacyQueued++; s.queued.add(index); s.queue[info.theme].push(index);
}
function r4cGeometry(s, info, node, path) {
  if (node.id === info.id) return; // Authoring-canvas placement is not product overflow.
  if (!node.absoluteBoundingBox || (node.type !== 'TEXT' && !('reactions' in node && node.reactions.length))) return;
  const b = node.absoluteBoundingBox; if (!b.width || !b.height) return;
  let scrollX = false, scrollY = false, reported = false;
  for (let p = node.parent; p && !reported; p = p.parent) {
    const dir = p.overflowDirection; scrollX ||= dir === 'HORIZONTAL' || dir === 'BOTH'; scrollY ||= dir === 'VERTICAL' || dir === 'BOTH';
    const pb = p.absoluteBoundingBox;
    if (pb && (p.clipsContent || p.id === info.id || (node.type === 'TEXT' && p.name.startsWith('Button/')))) {
      const x = !scrollX && (b.x < pb.x - 1 || b.x + b.width > pb.x + pb.width + 1);
      const y = !scrollY && (b.y < pb.y - 1 || b.y + b.height > pb.y + pb.height + 1);
      if (x || y) { r4cIssue(s, 'geometryOverflow', { rootId: info.id, root: info.name, nodeId: node.id, path, clipId: p.id, clip: r4cShort(p.name), axes: [x ? 'x' : null, y ? 'y' : null].filter(Boolean), box: [b.x - pb.x, b.y - pb.y, b.width, b.height, pb.width, pb.height].map(v => Math.round(v * 10) / 10) }); reported = true; }
    }
    if (p.id === info.id) break;
  }
  if (node.type === 'TEXT') {
    let button = null, opacity = 1; for (let n = node; n; n = n.parent) { opacity *= typeof n.opacity === 'number' ? n.opacity : 1; if (n.name.startsWith('Button/')) { button = n; break; } if (n.id === info.id) break; }
    if (button && node.characters.trim() && opacity <= .01) r4cIssue(s, 'hiddenButtonText', { rootId: info.id, root: info.name, nodeId: node.id, path, text: node.characters, opacity });
  }
}
function r4cCounters() { return { roots: 0, primaryRoots: 0, legacyRoots: 0, visibleRoots: 0, nodes: 0, visibleNodes: 0, texts: 0, visibleTexts: 0, reactionLayers: 0, visibleReactionLayers: 0, reactions: 0, nodeActions: 0, visibleNodeActions: 0, closeBackActions: 0 }; }
function r4cSummary(s) { return { runId: s.runId, started: s.started, counts: s.counts, queues: Object.fromEntries(['Light', 'Dark'].map(t => [t, { processed: s.cursor[t], queued: s.queue[t].length, remaining: s.queue[t].length - s.cursor[t] }])), issueCounts: Object.fromEntries(Object.entries(s.issues).map(([k, v]) => [k, v.count])), incompleteRoots: s.incomplete.size, legacyUnscanned: s.legacyUnscanned.size }; }

async function auditR4CompactStart(options = {}) {
  if (R4_COMPACT_AUDIT && !options.reset) return { status: '已有只读审计；继续批次，或显式reset重新取快照', ...r4cSummary(R4_COMPACT_AUDIT) };
  const s = { runId: 'r4compact-' + Date.now(), started: new Date().toISOString(), options: {
    sampleCap: Math.max(1, Math.min(150, options.sampleCap || 80)), sampleBudgetBytes: 1200000,
    maxLegacyRoots: Math.max(0, Math.min(256, Number.isInteger(options.maxLegacyRoots) ? options.maxLegacyRoots : 64)),
    maxNodesPerRoot: 50000, timeBudgetMs: Math.max(1000, Math.min(20000, options.timeBudgetMs || 8000))
  }, directory: [], byId: new Map(), sections: [], queue: { Light: [], Dark: [] }, cursor: { Light: 0, Dark: 0 },
    counts: { Light: r4cCounters(), Dark: r4cCounters() }, queued: new Set(), records: new Map(), targets: new Map(), issues: {}, sampleBytes: 0,
    legacyQueued: 0, legacyUnscanned: new Set(), incomplete: new Set(), configured: [], configuredDeclared: 0, finalized: null };
  let sourcePage;
  for (const scope of R4_COMPACT_SCOPES) {
    const section = await figma.getNodeByIdAsync(scope.id);
    if (!section || section.type !== 'SECTION') { r4cIssue(s, 'missingSections', { id: scope.id }); continue; }
    sourcePage ||= section.parent;
    const snapshot = { ...scope, name: section.name, childCount: section.children.length, frameCount: 0, visibleFrameCount: 0, primaryRootCount: 0, directoryHash: r4cHash() };
    for (const n of section.children) {
      r4cFeed(snapshot.directoryHash, JSON.stringify([n.id, n.name, n.visible !== false]));
      if (n.type !== 'FRAME') continue;
      const index = s.directory.length, primary = n.name.startsWith('R4/') || (scope.role === 'review' && n.visible !== false);
      const info = { index, id: n.id, name: n.name, canonical: scope.role + '/' + r4cNorm(n.name), theme: scope.theme, role: scope.role,
        section: scope.id, primary, visible: r4cVisible(n), r4: n.name.startsWith('R4/') };
      s.directory.push(info); s.byId.set(n.id, index); snapshot.frameCount++; if (n.visible !== false) snapshot.visibleFrameCount++;
      if (primary) { snapshot.primaryRootCount++; s.queue[scope.theme].push(index); s.queued.add(index); }
    }
    snapshot.directoryHash = r4cDigest(snapshot.directoryHash); s.sections.push(snapshot);
  }
  for (const point of sourcePage && sourcePage.flowStartingPoints || []) {
    s.configuredDeclared++; const target = await r4cTarget(s, point.nodeId);
    if (target && target.owner !== null) { s.configured.push(target.owner); if (!s.queued.has(target.owner)) r4cQueueLegacy(s, target.owner); }
    else r4cIssue(s, 'invalidOrUnscopedFlowStart', { id: point.nodeId, name: r4cShort(point.name || ''), reason: target ? 'outside audited sections' : 'missing target' });
  }
  R4_COMPACT_AUDIT = s;
  return { status: '只读目录快照完成；每theme批次最多200根', ...r4cSummary(s), sections: s.sections };
}

async function r4cScanRoot(s, index) {
  const info = s.directory[index], node = await figma.getNodeByIdAsync(info.id);
  if (!node || node.removed) { s.incomplete.add(index); r4cIssue(s, 'changedSnapshot', { rootId: info.id, root: info.name, reason: 'root removed during audit' }); return; }
  const c = s.counts[info.theme], record = { index, nodes: 0, textCount: 0, reactionCount: 0, visible: r4cVisible(node), width: Math.round(node.width * 100) / 100, height: Math.round(node.height * 100) / 100, text: r4cHash(), reactions: r4cHash(), outgoing: new Set(), directExit: false, hasVisibleAction: false };
  const stack = [{ node, path: '$', visible: r4cVisible(node.parent), ancestorAction: false }];
  while (stack.length) {
    if (record.nodes >= s.options.maxNodesPerRoot) { s.incomplete.add(index); r4cIssue(s, 'rootNodeBudget', { rootId: info.id, root: info.name, scanned: record.nodes }); break; }
    const item = stack.pop(), n = item.node, visible = item.visible && n.visible !== false;
    record.nodes++; c.nodes++; if (visible) c.visibleNodes++;
    const reactions = 'reactions' in n ? n.reactions || [] : [];
    if (n.type === 'TEXT') {
      c.texts++; record.textCount++; if (visible) c.visibleTexts++;
      r4cFeed(record.text, JSON.stringify([r4cNorm(item.path), visible, r4cNorm(n.characters)]));
      if (visible) { const matches = r4cRemoved(n.characters); if (matches.length) r4cIssue(s, 'removedText', { rootId: info.id, root: info.name, nodeId: n.id, path: item.path, text: n.characters, matches }); }
    }
    if (visible) {
      const old = r4cOld(n.name, n.type === 'TEXT' ? n.characters : ''); if (old.length) r4cIssue(s, 'visibleLegacy', { rootId: info.id, root: info.name, nodeId: n.id, path: item.path, reasons: old });
      r4cGeometry(s, info, n, item.path);
      if (/^(?:Action\/(?:close|back)|Button\/(?:取消|关闭|返回|返回评审入口))$/.test(n.name) && !r4cClickable(n) && !item.ancestorAction && !('findOne' in n && n.findOne(r4cClickable))) r4cIssue(s, 'missingHotspotActions', { rootId: info.id, root: info.name, nodeId: n.id, path: item.path });
    }
    if (reactions.length) { c.reactionLayers++; if (visible) c.visibleReactionLayers++; record.reactionCount += reactions.length; c.reactions += reactions.length; }
    for (const reaction of reactions) {
      async function actionSummary(value) {
        if (Array.isArray(value)) { const out = []; for (const v of value) out.push(await actionSummary(v)); return out; }
        if (!value || typeof value !== 'object') return r4cStable(value);
        const out = {};
        if (value.type === 'NODE') {
          c.nodeActions++; if (visible) { c.visibleNodeActions++; record.hasVisibleAction = true; }
          const target = await r4cTarget(s, value.destinationId), edge = { rootId: info.id, root: info.name, nodeId: n.id, path: item.path, sourceVisible: visible,
            destinationId: value.destinationId || null, navigation: value.navigation, trigger: r4cStable(reaction.trigger), transition: r4cStable(value.transition || null) };
          if (!target) r4cIssue(s, 'invalidTargets', edge);
          else {
            if (!target.visible) r4cIssue(s, 'hiddenTargets', { ...edge, target: target.name });
            if (target.owner === null) { r4cIssue(s, 'externalTargets', { ...edge, target: target.name, targetType: target.type }); if (visible) record.directExit = true; }
            else {
              if (visible) record.outgoing.add(target.owner);
              if (target.owner === index && value.navigation === 'NAVIGATE') r4cIssue(s, 'selfNavigation', edge);
              const targetInfo = s.directory[target.owner];
              if (targetInfo.role === 'interaction' && !targetInfo.r4) { r4cIssue(s, 'legacyTargets', { ...edge, target: targetInfo.name }); if (visible) r4cQueueLegacy(s, target.owner); }
            }
          }
          out.destination = target ? target.canonical : 'MISSING';
        } else if (['CLOSE', 'BACK', 'URL'].includes(value.type) && visible) { record.directExit = true; record.hasVisibleAction = true; if (value.type !== 'URL') c.closeBackActions++; }
        for (const key of Object.keys(value).sort()) if (key !== 'destinationId') out[key] = await actionSummary(value[key]);
        return out;
      }
      r4cFeed(record.reactions, JSON.stringify([r4cNorm(item.path), visible, r4cStable(reaction.trigger), await actionSummary(r4cActions(reaction))]));
    }
    if ('children' in n) {
      const names = new Map(), children = [];
      for (const child of n.children) { const occurrence = names.get(child.name) || 0; names.set(child.name, occurrence + 1); children.push({ node: child, path: item.path + '/' + child.name + (occurrence ? '[' + occurrence + ']' : ''), visible, ancestorAction: item.ancestorAction || r4cClickable(n) }); }
      for (let i = children.length - 1; i >= 0; i--) stack.push(children[i]);
    }
  }
  record.text = r4cDigest(record.text); record.reactions = r4cDigest(record.reactions); s.records.set(index, record);
  c.roots++; c[info.primary ? 'primaryRoots' : 'legacyRoots']++; if (record.visible) c.visibleRoots++;
}

async function auditR4CompactBatch(theme, count = 200) {
  const s = R4_COMPACT_AUDIT; if (!s) throw Error('Run auditR4CompactStart first'); if (s.finalized) return { status: '审计已汇总；新快照需start({reset:true})', ...r4cSummary(s) };
  if (!['Light', 'Dark'].includes(theme) || !Number.isInteger(count) || count < 1 || count > 200) throw Error('Use Light/Dark and count 1–200');
  const start = Date.now(), initial = s.cursor[theme];
  while (s.cursor[theme] < s.queue[theme].length && s.cursor[theme] - initial < count) {
    const index = s.queue[theme][s.cursor[theme]]; await r4cScanRoot(s, index); s.cursor[theme]++;
    if (Date.now() - start >= s.options.timeBudgetMs) break;
    if ((s.cursor[theme] - initial) % 10 === 0) await new Promise(resolve => setTimeout(resolve, 0));
  }
  return { status: theme + ' 只读审计批次完成', processedThisBatch: s.cursor[theme] - initial, elapsedMs: Date.now() - start, ...r4cSummary(s) };
}

async function auditR4CompactFinish() {
  const s = R4_COMPACT_AUDIT; if (!s) throw Error('Run auditR4CompactStart first'); if (s.finalized) return s.finalized;
  if (['Light', 'Dark'].some(t => s.cursor[t] < s.queue[t].length)) return { status: '尚有批次未扫描；继续两theme批次', ...r4cSummary(s) };
  for (const snapshot of s.sections) {
    const section = await figma.getNodeByIdAsync(snapshot.id), h = r4cHash();
    if (section) for (const node of section.children) r4cFeed(h, JSON.stringify([node.id, node.name, node.visible !== false]));
    if (!section || r4cDigest(h) !== snapshot.directoryHash) r4cIssue(s, 'changedSnapshot', { id: snapshot.id, reason: 'section root IDs/names/visibility changed during audit; restart after authoring stops' });
  }
  const pairs = new Map(), reverse = new Map(), incoming = new Set();
  for (const [index, r] of s.records) {
    const info = s.directory[index]; if (info.primary) { const p = pairs.get(info.canonical) || { Light: [], Dark: [] }; p[info.theme].push(index); pairs.set(info.canonical, p); }
    for (const target of r.outgoing) { incoming.add(target); const sources = reverse.get(target) || []; sources.push(index); reverse.set(target, sources); }
  }
  let paired = 0;
  for (const [key, pair] of pairs) {
    if (!pair.Light.length || !pair.Dark.length) r4cIssue(s, 'themeMissing', { key, missing: pair.Light.length ? 'Dark' : 'Light', ids: [...pair.Light, ...pair.Dark].slice(0, 5).map(i => s.directory[i].id) });
    if (pair.Light.length > 1 || pair.Dark.length > 1) r4cIssue(s, 'themeDuplicate', { key, lightCount: pair.Light.length, darkCount: pair.Dark.length, ids: [...pair.Light, ...pair.Dark].slice(0, 5).map(i => s.directory[i].id) });
    if (pair.Light.length !== 1 || pair.Dark.length !== 1) continue;
    paired++; const a = s.records.get(pair.Light[0]), b = s.records.get(pair.Dark[0]), refs = { key, lightId: s.directory[a.index].id, darkId: s.directory[b.index].id };
    if (a.text !== b.text || a.textCount !== b.textCount) r4cIssue(s, 'themeTextMismatch', { ...refs, light: a.text, dark: b.text });
    if (a.reactions !== b.reactions || a.reactionCount !== b.reactionCount) r4cIssue(s, 'themeReactionMismatch', { ...refs, light: a.reactions, dark: b.reactions });
    if (a.width !== b.width || a.height !== b.height || a.visible !== b.visible) r4cIssue(s, 'themeGeometryMismatch', { ...refs, light: [a.width, a.height, a.visible], dark: [b.width, b.height, b.visible] });
  }
  const canExit = new Set(), queue = [];
  for (const [i, r] of s.records) if (r.directExit) { canExit.add(i); queue.push(i); }
  for (let cursor = 0; cursor < queue.length; cursor++) for (const prev of reverse.get(queue[cursor]) || []) if (!canExit.has(prev)) { canExit.add(prev); queue.push(prev); }
  const entries = [...new Set([...s.configured, ...s.directory.filter(i => i.primary && i.visible && (i.role === 'review' || /\/(?:Review|StateReview)$/.test(i.name))).map(i => i.index)])];
  const reachable = new Set(entries), visit = [...entries];
  for (let cursor = 0; cursor < visit.length; cursor++) for (const target of s.records.get(visit[cursor])?.outgoing || []) if (!reachable.has(target)) { reachable.add(target); visit.push(target); }
  for (const [index, r] of s.records) if (r.visible && (incoming.has(index) || entries.includes(index)) && !canExit.has(index) && (incoming.has(index) || r.hasVisibleAction)) r4cIssue(s, 'noExitCandidates', { rootId: s.directory[index].id, root: s.directory[index].name, reachable: reachable.has(index), outgoingRootCount: r.outgoing.size, reason: 'No reachable visible CLOSE/BACK/URL/external escape in the scanned graph; inspect runtime stack and intended static-only screens' });
  const result = { status: '只读分批审计汇总；不代表实际点击验证', schemaVersion: 1, ...r4cSummary(s), finished: new Date().toISOString(),
    sections: s.sections, comparison: { pairedRoots: paired, primaryCanonicalNames: pairs.size, normalization: 'Theme-normalized root/path/text; NODE destination canonical root/path; full sorted trigger/action/transition values; dual incremental 32-bit hashes plus length/counts. No per-text geometry dump.' },
    graph: { configuredDeclaredCount: s.configuredDeclared, configuredEntryCount: s.configured.length, reviewAndConfiguredEntryCount: entries.length, reachableRoots: reachable.size, inspectedReachableRoots: [...reachable].filter(i => s.records.has(i)).length, rootsWithKnownEscape: canExit.size },
    issues: s.issues, truncation: { sampleCapPerCategory: s.options.sampleCap, sampleBudgetBytes: s.options.sampleBudgetBytes, sampleBytesRetained: s.sampleBytes, issueCountTotalsAreUntruncated: true, outputBytes: 0, outputCapBytes: 1800000 },
    limitations: [
      'Freeze authoring during all batches. Directory changes are detected; in-place content changes between batches are not versioned by this read-only audit.',
      'Only R4 roots and visible R3 review frames are primary; visible edges may add up to the declared legacy-root budget. Unscanned legacy targets are counted.',
      'Theme equality uses dual hashes plus lengths/counts rather than retaining every normalized text/reaction object. Hash equality is practical evidence, not a mathematical collision proof.',
      'Visible means inherited visible flags. Zero opacity does not disable a clickable hotspot. Background/overlay runtime stack behavior needs actual click validation.',
      'Geometry flags focus on text/click targets clipped or outside root/button bounds; legitimate scroll axes are excluded. Occlusion, font rendering and semantic TXT synonyms need screenshots.',
      'No-exit candidates are conservative: CLOSE/BACK/URL/external actions and paths to them count as escape. Conditional branches are treated as possible.'
    ] };
  // Hard final-size guard; retain every category's exact total and omission count.
  let encoded = JSON.stringify(result);
  while (r4cBytes(encoded) > result.truncation.outputCapBytes) {
    const bucket = Object.values(result.issues).filter(b => b.samples.length).sort((a, b) => b.samples.length - a.samples.length)[0];
    if (!bucket) break; bucket.samples.pop(); bucket.omitted++; encoded = JSON.stringify(result);
  }
  result.truncation.sampleBytesRetained = Object.values(result.issues).reduce((sum, b) => sum + b.samples.reduce((n, sample) => n + r4cBytes(JSON.stringify(sample)), 0), 0);
  for (let i = 0; i < 4; i++) { const size = r4cBytes(JSON.stringify(result)); if (result.truncation.outputBytes === size) break; result.truncation.outputBytes = size; }
  s.finalized = result; return result;
}

function auditR4CompactProgress() { if (!R4_COMPACT_AUDIT) return { status: '尚未开始' }; return { status: '只读审计进度', ...r4cSummary(R4_COMPACT_AUDIT) }; }

// Optional bounded drill-down for a reported pair/anomaly. This never changes
// aggregate counts, queues or nodes. Use exact root IDs from the summary.
async function auditR4CompactInspect(rootIds) {
  const s = R4_COMPACT_AUDIT;
  if (!s || !Array.isArray(rootIds) || !rootIds.length || rootIds.length > 4) throw Error('Start an audit, then inspect 1–4 exact root IDs');
  const results = []; let bytes = 0;
  async function summarize(value) {
    if (Array.isArray(value)) { const out = []; for (const v of value) out.push(await summarize(v)); return out; }
    if (!value || typeof value !== 'object') return r4cStable(value);
    const out = {}; for (const key of Object.keys(value).sort()) {
      if (key === 'destinationId') { const target = await r4cTarget(s, value[key]); out.destination = target ? target.canonical : 'MISSING'; }
      else out[key] = await summarize(value[key]);
    } return out;
  }
  for (const id of rootIds) {
    const index = s.byId.get(id); if (index === undefined) throw Error('Root was not in the directory snapshot: ' + id);
    const node = await figma.getNodeByIdAsync(id); if (!node || node.removed) { results.push({ id, missing: true }); continue; }
    const result = { id, canonical: s.directory[index].canonical, texts: [], reactions: [], omitted: 0 }, stack = [{ node, path: '$', visible: r4cVisible(node.parent) }];
    while (stack.length) {
      const item = stack.pop(), n = item.node, visible = item.visible && n.visible !== false;
      const add = (key, value) => { const size = r4cBytes(JSON.stringify(value)); if (result.texts.length + result.reactions.length < 400 && bytes + size < 500000) { result[key].push(value); bytes += size; } else result.omitted++; };
      if (n.type === 'TEXT') add('texts', { id: n.id, path: r4cShort(r4cNorm(item.path), 300), visible, text: r4cShort(r4cNorm(n.characters), 500) });
      if ('reactions' in n) for (const reaction of n.reactions || []) add('reactions', { id: n.id, path: r4cShort(r4cNorm(item.path), 300), visible, trigger: r4cStable(reaction.trigger), actions: await summarize(r4cActions(reaction)) });
      if ('children' in n) { const names = new Map(), children = []; for (const child of n.children) { const occurrence = names.get(child.name) || 0; names.set(child.name, occurrence + 1); children.push({ node: child, path: item.path + '/' + child.name + (occurrence ? '[' + occurrence + ']' : ''), visible }); } for (let i = children.length - 1; i >= 0; i--) stack.push(children[i]); }
    }
    results.push(result);
  }
  return { status: '指定根的只读规范摘要', results, payloadBytes: bytes, capBytes: 500000, aggregateAuditCountsChanged: false };
}


// Inspect first. No shared component, label string, background or reaction is
// changed by inspection. Repair requires explicit root IDs and a repair mode.
function buttonTextPaints(node) {
  return Array.isArray(node.fills) ? JSON.parse(JSON.stringify(node.fills)) : null;
}
function buttonTextSolid(node) {
  const paints=buttonTextPaints(node),visible=paints&&paints.filter(p=>p.visible!==false);
  return visible&&visible.length===1&&visible[0].type==='SOLID'?visible[0]:null;
}
function buttonTextLuminance(c) {
  const f=v=>v<=.04045?v/12.92:Math.pow((v+.055)/1.055,2.4);
  return .2126*f(c.r)+.7152*f(c.g)+.0722*f(c.b);
}
function buttonTextContrast(text,button) {
  const foreground=buttonTextSolid(text),background=buttonTextSolid(button);if(!foreground||!background||(background.opacity??1)<.99)return null;
  const alpha=(foreground.opacity??1)*(text.opacity??1),bg=background.color;
  const fg={r:foreground.color.r*alpha+bg.r*(1-alpha),g:foreground.color.g*alpha+bg.g*(1-alpha),b:foreground.color.b*alpha+bg.b*(1-alpha)};
  const a=buttonTextLuminance(fg),b=buttonTextLuminance(bg);return(Math.max(a,b)+.05)/(Math.min(a,b)+.05);
}
function buttonTextBounds(node) {
  const b=node.absoluteBoundingBox;return b?{x:b.x,y:b.y,width:b.width,height:b.height}:null;
}
function buttonTextClipping(text,root) {
  const bounds=buttonTextBounds(text),result=[];if(!bounds)return result;
  for(let parent=text.parent;parent;parent=parent.parent){
    if(parent.clipsContent){const b=buttonTextBounds(parent);if(b){
      const width=Math.max(0,Math.min(bounds.x+bounds.width,b.x+b.width)-Math.max(bounds.x,b.x));
      const height=Math.max(0,Math.min(bounds.y+bounds.height,b.y+b.height)-Math.max(bounds.y,b.y));
      if(width<bounds.width-.5||height<bounds.height-.5)result.push({id:parent.id,name:parent.name,bounds:b,visibleWidth:width,visibleHeight:height});
    }}
    if(parent===root)break;
  }
  return result;
}
function buttonTextVisible(node,root) {
  for(let n=node;n;n=n.parent){if(n.visible===false||(n.opacity??1)<=0)return false;if(n===root)break;}return true;
}
function buttonTextSnapshot(button,root) {
  const texts=txt(button);return{id:button.id,name:button.name,type:button.type,visible:button.visible,opacity:button.opacity,
    x:button.x,y:button.y,width:button.width,height:button.height,bounds:buttonTextBounds(button),fills:buttonTextPaints(button),fillStyleId:button.fillStyleId,
    clipsContent:button.clipsContent,layoutMode:button.layoutMode,primaryAxisSizingMode:button.primaryAxisSizingMode,counterAxisSizingMode:button.counterAxisSizingMode,
    primaryAxisAlignItems:button.primaryAxisAlignItems,counterAxisAlignItems:button.counterAxisAlignItems,
    padding:{top:button.paddingTop,bottom:button.paddingBottom,left:button.paddingLeft,right:button.paddingRight},
    texts:texts.map(text=>({id:text.id,name:text.name,characters:text.characters,visible:text.visible,opacity:text.opacity,
      x:text.x,y:text.y,width:text.width,height:text.height,bounds:buttonTextBounds(text),fills:buttonTextPaints(text),fillStyleId:text.fillStyleId,
      fontName:text.fontName,fontSize:text.fontSize,lineHeight:text.lineHeight,hasMissingFont:text.hasMissingFont,textAutoResize:text.textAutoResize,
      layoutPositioning:text.layoutPositioning,layoutGrow:text.layoutGrow,contrast:buttonTextContrast(text,button),clippedBy:buttonTextClipping(text,root)}))};
}
async function buttonTextRoots(t,rootIds) {
  const e=await env(t);let roots;
  if(rootIds&&rootIds.length){roots=await Promise.all(rootIds.map(id=>figma.getNodeByIdAsync(id)));}
  else roots=[...e.registry.values()].filter(n=>/R4 NET · Review (50|timeout) ·/.test(n.name)&&/已阻止|无法完成检查/.test(n.name));
  for(const n of roots)if(!n||n.removed||n.type!=='FRAME'||n.parent!==e.branch||!n.name.startsWith('R4/'+t+'/'))throw Error('Button text inspection target is outside '+t+' R4 roots');
  if(!roots.length)throw Error('No matching result roots. Supply exact root IDs.');
  return{e,roots:[...new Map(roots.map(n=>[n.id,n])).values()]};
}
function buttonTextIncoming(e,targets) {
  const ids=new Set(targets.map(n=>n.id));
  // Bounded sibling-group search: the score-50/timeout transition sources share
  // their result's network-flow prefix. This does not traverse every account tree.
  const prefixes=targets.map(n=>{
    const flow=n.name.replace(/ · (?:有效评分 (?:49|50) · 已阻止|(?:timeout|unavailable|invalid) · 无法完成检查|评分 51 · 检查通过|检查中 [AB])$/,'');
    if(flow!==n.name)return flow+' · ';
    const split=n.name.lastIndexOf(' · ');return split>=0?n.name.slice(0,split+3):n.name.slice(0,n.name.lastIndexOf('/')+1);
  });
  const roots=[...e.registry.values()].filter(n=>prefixes.some(p=>n.name.startsWith(p)));
  const found=[];for(const root of roots)for(const n of all(root))if('reactions'in n)for(let ri=0;ri<n.reactions.length;ri++){
    const r=n.reactions[ri];for(const a of r.actions||(r.action?[r.action]:[]))if(a.type==='NODE'&&ids.has(a.destinationId))found.push({node:n,root,reactionIndex:ri,trigger:r.trigger,action:a});
  }return found;
}
async function inspectButtonTextStage(t,rootIds=[]) {
  const{e,roots}=await buttonTextRoots(t,rootIds);return{status:t+' 按钮文字只读诊断',mutatedNodeCount:0,
    roots:roots.map(root=>({id:root.id,name:root.name,buttons:root.findAll(n=>n.name.startsWith('Button/')&&buttonTextVisible(n,root)).map(n=>buttonTextSnapshot(n,root))})),
    incoming:buttonTextIncoming(e,roots).map(x=>({node:x.node.id,root:x.root.id,name:x.root.name,trigger:x.trigger,action:x.action})),
    note:'Snapshots include actual fills, opacity, geometry and ancestor clipping. Matching siblings are searched for incoming transitions; no mutation has run.'};
}
async function repairButtonTextStage(t,rootIds=[],mode='diagnose') {
  if(mode==='diagnose')return await inspectButtonTextStage(t,rootIds);
  if(!rootIds.length)throw Error('Supply inspected root IDs before a local button repair');
  if(!['observed-defects','dissolve-result'].includes(mode))throw Error('Use diagnose, observed-defects, or dissolve-result');
  const{e,roots}=await buttonTextRoots(t,rootIds),changes=[],unresolved=[];
  if(mode==='dissolve-result'){
    const targets=new Set(roots.map(n=>n.id)),incoming=buttonTextIncoming(e,roots),nodes=[...new Set(incoming.map(x=>x.node))];
    for(const n of nodes){let changed=false;const reactions=n.reactions.map(r=>{
      const out=JSON.parse(JSON.stringify(r));delete out.action;out.actions=JSON.parse(JSON.stringify(r.actions||(r.action?[r.action]:[])));
      for(const a of out.actions)if(a.type==='NODE'&&targets.has(a.destinationId)&&a.transition?.type==='SMART_ANIMATE'){
        a.transition={type:'DISSOLVE',easing:{type:'EASE_OUT'},duration:.18};changed=true;
      }return out;
    });if(changed){jobs.set(n,reactions);writes.add(n.id);changes.push({node:n.id,name:n.name,repair:'only incoming result transition SMART_ANIMATE → DISSOLVE'});}}
    await flush();return{status:t+' 指定结果页过渡已局部修复',mode,roots:rootIds,changes,labelsChanged:0,sharedComponentWrites:0};
  }
  for(const root of roots)for(const button of root.findAll(n=>n.name.startsWith('Button/')&&buttonTextVisible(n,root))){
    const texts=txt(button);if(texts.length!==1){unresolved.push({button:button.id,reason:'Multiple/no text layers; no generic repair'});continue;}
    const text=texts[0],before=buttonTextSnapshot(button,root),reasons=[];
    if(!text.characters.trim()){unresolved.push({button:button.id,reason:'Blank characters; content is intentionally not invented'});continue;}
    if(text.hasMissingFont){unresolved.push({button:button.id,reason:'Missing font; inspect the loaded font before editing'});continue;}
    const clips=buttonTextClipping(text,root),externalClip=clips.some(x=>x.id!==button.id);
    if(externalClip)unresolved.push({button:button.id,reason:'Text is clipped by an ancestor viewport; no automatic panel resize',clippedBy:clips});
    if(!text.visible||(text.opacity??1)<.01){text.visible=true;text.opacity=1;reasons.push('restore invisible label');}
    const localOverflow=text.parent===button&&(text.x<-.5||text.y<-.5||text.x+text.width>button.width+.5||text.y+text.height>button.height+.5);
    if(localOverflow&&text.parent===button&&['VERTICAL','HORIZONTAL'].includes(button.layoutMode)){
      button.primaryAxisAlignItems='CENTER';button.counterAxisAlignItems='CENTER';
      button.primaryAxisSizingMode='FIXED';button.counterAxisSizingMode='FIXED';
      text.layoutPositioning='AUTO';text.layoutGrow=0;text.layoutAlign='INHERIT';text.textAutoResize='WIDTH_AND_HEIGHT';
      reasons.push('center label inside its existing button dimensions');
    }
    const ratio=buttonTextContrast(text,button),bg=buttonTextSolid(button);
    if(ratio!==null&&ratio<4.5&&bg){
      const candidates=[20/255,250/255];let chosen=candidates[0],best=-1;
      for(const v of candidates){const a=buttonTextLuminance({r:v,g:v,b:v}),b=buttonTextLuminance(bg.color),r=(Math.max(a,b)+.05)/(Math.min(a,b)+.05);if(r>best){best=r;chosen=v;}}
      text.fills=[{type:'SOLID',color:{r:chosen,g:chosen,b:chosen}}];reasons.push('repair measured contrast '+ratio.toFixed(2));
    }
    if(reasons.length){writes.add(button.id);writes.add(text.id);const after=buttonTextSnapshot(button,root);
      if(after.texts[0].characters!==before.texts[0].characters)throw Error('Button repair unexpectedly changed characters');
      changes.push({root:root.id,button:button.id,reasons,before,after});}
  }
  figma.commitUndo();return{status:t+' 已测得的按钮文字缺陷已局部修复',mode,roots:rootIds,changes,unresolved,labelsChanged:0,sharedComponentWrites:0,
    note:'Healthy buttons are untouched. If geometry/fills are valid but prototype text disappears, use a separately reviewed dissolve-result repair on the affected result root only.'};
}


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


figma.showUI(__html__,{width:600,height:520});
figma.ui.onmessage=async m=>{if(busy)return;busy=true;try{if(m.type==='inspect')figma.ui.postMessage(await inspect(m.target));else if(m.type==='focus'){await init();const n=await figma.getNodeByIdAsync(m.target);figma.currentPage.selection=[n];figma.viewport.scrollAndZoomIntoView([n]);figma.ui.postMessage({status:'已定位',id:n.id});}else if(m.type==='apply'){const parts=m.target.split('/');if(parts[0]==='appauto')figma.ui.postMessage(await repairAppAutoEntryStage());else if(parts[0]==='pendingwidgets')figma.ui.postMessage(parts[1]==='lookup'?await lookupPendingWidgetReviewStage():await repairPendingWidgetReviewStage());else if(parts[0]==='network')figma.ui.postMessage(await networkStage(parts[1]));else if(parts[0]==='foundation'){const out=[];if(parts[2]==='all'){for(let start=0;start<64;start+=8)out.push(await accountFoundationStage(parts[1],start,8));figma.ui.postMessage({status:parts[1]+' 账号视图已分8批完成',batches:out});}else figma.ui.postMessage(await accountFoundationStage(parts[1],Number(parts[2]||0),Number(parts[3]||8)));}else if(parts[0]==='flows'){if(parts[3]==='rest'){const out=[];for(let i=Number(parts[2]||0);i<64;i+=4)out.push(await accountFlowStage(parts[1],i,4));figma.ui.postMessage({status:parts[1]+' 主账号流程完成',batches:out});}else figma.ui.postMessage(await accountFlowStage(parts[1],Number(parts[2]||0),Number(parts[3]||1)));}else if(parts[0]==='pending'){if(parts[2]==='all'){let x;let batches=0;do{x=await accountPendingFlowStage(parts[1],4);batches++;}while(x.remainingPending&&batches<64);figma.ui.postMessage({...x,batches});}else figma.ui.postMessage(await accountPendingFlowStage(parts[1],Number(parts[2]||1)));}else if(parts[0]==='compact'){const phase=parts[1];if(phase==='start')figma.ui.postMessage(await auditR4CompactStart({reset:true}));else if(phase==='theme'){let x;do{x=await auditR4CompactBatch(parts[2],200);figma.ui.postMessage({...x,status:parts[2]+' 只读审计 '+x.queues[parts[2]].processed+'/'+x.queues[parts[2]].queued,progress:true});}while(x.queues[parts[2]].remaining>0);figma.ui.postMessage(x);}else if(phase==='batch')figma.ui.postMessage(await auditR4CompactBatch(parts[2],Number(parts[3]||5)));else if(phase==='finish')figma.ui.postMessage(await auditR4CompactFinish());else if(phase==='inspect')figma.ui.postMessage(await auditR4CompactInspect(parts[2].split(',')));else figma.ui.postMessage(auditR4CompactProgress());}else if(parts[0]==='failuresource')figma.ui.postMessage(await repairFailureSourceStage(parts[1]));else if(parts[0]==='emptycopy')figma.ui.postMessage(await repairEmptyWidgetCopyStage(parts[1]));else if(parts[0]==='permissions'){const t=parts[1],phase=parts[2];if(phase==='plan')figma.ui.postMessage(permissionPreservePlan());else if(phase==='ready'){const out=[];for(let i=0;i<20;i+=2)out.push(await permissionPreserveReadyStage(t,i,2));figma.ui.postMessage({status:t+'权限状态ready保留完成',batches:out});}else if(phase==='add'){const out=[];for(let i=0;i<4;i++)out.push(await permissionPreserveAddStage(t,i,1));figma.ui.postMessage({status:t+'权限状态新增保留完成',batches:out});}else if(phase==='audit')figma.ui.postMessage(await permissionPreserveAuditStage(t));else throw Error('Specify permission phase');}else if(parts[0]==='delivery')figma.ui.postMessage(await deliveryReadOnlyStage(parts[1],{refresh:parts[2]==='refresh'}));else if(parts[0]==='arrange'){let x;do{x=await arrangeDeliveryStage(parts[1],Number(parts[2]||0),200);parts[2]=String(x.nextIndex);}while(!x.complete);figma.ui.postMessage(x);}else if(parts[0]==='entries')figma.ui.postMessage(await finalizeDeliveryEntriesStage());else if(parts[0]==='exportall'){const gallery=[];let x;for(let i=0;;i+=4){x=await deliveryGalleryStage(parts[1],'all',i,4);gallery.push(...x.gallery);if(x.complete)break;}figma.ui.postMessage({status:parts[1]+' 原生交付截图全部完成',gallery});}else if(parts[0]==='export')figma.ui.postMessage(await deliveryGalleryStage(parts[1],parts[2]||'all',Number(parts[3]||0),Number(parts[4]||4)));else if(parts[0]==='cleanupplan')figma.ui.postMessage(await planReviewCleanupStage(parts[1]));else if(parts[0]==='cleanup'){if(parts[3]==='rest'){let x;const out=[];for(let i=Number(parts[2]||0);i<32;i++){x=await cleanupReviewStage(parts[1],i,1);out.push(x);}figma.ui.postMessage({status:x?.complete?parts[1]+'评审清理完成':parts[1]+'评审清理未完成，请检查剩余目标',complete:!!x?.complete,nextIndex:x?.nextIndex,total:x?.total,remainingLegacyEdges:x?.remainingLegacyEdges,batches:out});}else figma.ui.postMessage(await cleanupReviewStage(parts[1],Number(parts[2]||0),Number(parts[3]||1)));}else if(parts[0]==='cross'){const t=parts[1],phase=parts[2];if(phase==='all'){await accountCrossAddPrepareStage(t);for(let i=0;i<16;i+=4)await accountCrossAddReadyStage(t,i,4);let x,b=0;do{x=await accountCrossAddPendingStage(t,4);b++;}while(x.remaining&&b<32);if(x.remaining)throw Error('Cross pending remains');for(const pending of[false,true])for(let i=0;i<(pending?48:16);i+=4)await accountCrossAddExtrasStage(t,i,4,pending);const audit=await accountCrossAddAuditStage(t);if(!audit.passed)figma.ui.postMessage(audit);else figma.ui.postMessage(await accountCrossAddActivateStage(t));}else if(phase==='prepare')figma.ui.postMessage(await accountCrossAddPrepareStage(t));else if(phase==='ready'){for(let i=0;i<16;i+=4)await accountCrossAddReadyStage(t,i,4);figma.ui.postMessage({status:t+'连续添加ready完成'});}else if(phase==='pending'){let x,b=0;do{x=await accountCrossAddPendingStage(t,4);b++;}while(x.remaining&&b<32);figma.ui.postMessage({...x,batches:b});}else if(phase==='extras'){for(const pending of[false,true])for(let i=0;i<(pending?48:16);i+=4)await accountCrossAddExtrasStage(t,i,4,pending);figma.ui.postMessage({status:t+'连续添加系统与小组件完成'});}else if(phase==='audit')figma.ui.postMessage(await accountCrossAddAuditStage(t));else if(phase==='activate')figma.ui.postMessage(await accountCrossAddActivateStage(t));else throw Error('Specify cross phase');}else if(parts[0]==='cancelrender')figma.ui.postMessage(await repairCancelRenderStage(parts[1],parts[2]));else if(parts[0]==='buttondiag')figma.ui.postMessage(await inspectButtonTextStage(parts[1],parts[2].split(',')));else if(parts[0]==='buttonrepair')figma.ui.postMessage(await repairButtonTextStage(parts[1],parts[2].split(','),'observed-defects'));else if(parts[0]==='repairhidden')figma.ui.postMessage(await repairHiddenControlsStage(parts[1]));else if(parts[0]==='support')figma.ui.postMessage(await supportOnlyStage(parts[1]));else if(parts[0]==='repairwidgets')figma.ui.postMessage(await repairWidgetNavigationStage(parts[1]));else if(parts[0]==='repairbackground')figma.ui.postMessage(await repairBackgroundAccountControls(parts[1]));else if(parts[0]==='final')figma.ui.postMessage(await finalLinksStage(parts[1]));else if(parts[0]==='extras'){if(parts[3]==='all'){let x;const out=[];for(let i=Number(parts[2]||0);;i+=4){x=await accountExtrasStage(parts[1],i,4,parts[4]==='pending');out.push(x);if(x.end>=x.total)break;}figma.ui.postMessage({status:parts[1]+' 通知和小组件全部完成',batches:out});}else figma.ui.postMessage(await accountExtrasStage(parts[1],Number(parts[2]||0),Number(parts[3]||4),parts[4]==='pending'));}else if(parts[0]==='system')figma.ui.postMessage(await systemStage(parts[1]));else if(parts[0]==='background')figma.ui.postMessage(await backgroundStage(parts[1]));else if(parts[0]==='widgets')figma.ui.postMessage(await widgetStage(parts[1]));else if(parts[0]==='fonts'){await fonts();figma.ui.postMessage({status:'字体已载入'});}else throw Error('Specify a reviewed stage');}else if(m.type==='audit')figma.ui.postMessage(await auditR4());else if(m.type==='gallery')await gallery(m.target);else figma.ui.postMessage({status:'请指定读取节点或阶段'});}catch(e){figma.ui.postMessage({status:'停止：'+String(e),error:String(e),stack:e.stack||null,createdNodeIds:[...made],mutatedNodeIds:[...writes],screens:report.screens});}finally{busy=false}};
