// Local Figma author tool only. Never connects accounts or scoring services.
const SCOPE=['1:43251','1:43252','1:43253','1:43254'];
let page,secs,busy=false;
async function init(){if(secs)return;page=await figma.getNodeByIdAsync('0:1');await figma.setCurrentPageAsync(page);secs=await Promise.all(SCOPE.map(id=>figma.getNodeByIdAsync(id)));if(secs.some(n=>!n||n.type!=='SECTION'))throw Error('Scope mismatch');}
function info(n,d=0){if(!n)return null;const r={id:n.id,type:n.type,name:n.name,visible:n.visible};for(const k of ['x','y','width','height','layoutMode','itemSpacing','paddingTop','paddingBottom','reactions'])if(k in n)r[k]=n[k];if(n.type==='TEXT')Object.assign(r,{text:n.characters,font:n.fontName,size:n.fontSize});if(d&&'children'in n)r.children=n.children.map(x=>info(x,d-1));return r;}
async function inspect(target){await init();if(target)return{status:'节点读取完成',nodes:await Promise.all(target.split(',').map(async id=>info(await figma.getNodeByIdAsync(id.trim()),10)))};return{status:'四区读取完成',sections:secs.map(s=>({id:s.id,name:s.name,x:s.x,y:s.y,w:s.width,h:s.height,count:s.children.length,children:s.children.map(n=>info(n))})),review:secs.filter((s,i)=>i%2===0).flatMap(s=>s.children.filter(n=>n.visible&&n.type==='FRAME').map(n=>({id:n.id,name:n.name,texts:n.findAllWithCriteria({types:['TEXT']}).map(t=>({id:t.id,text:t.characters})),actions:n.findAll(x=>'reactions'in x&&x.reactions.length).map(x=>({id:x.id,name:x.name,reactions:x.reactions}))}))) };}

// R4 scoped reconciliation of existing R3 frames; native Figma authoring only.
const created=new Set(),changed=new Set(),rxJobs=new Map(),registry=new Map(),models=new Map(),themes={};
const A=[{key:'claude',p:'Claude',email:'alin.claude@example.com',card:'Quota/Claude',v:[39,72]}, {key:'codex',p:'Codex',email:'alin.codex@example.com',card:'Quota/Codex',v:[38,64]}, {key:'work',p:'Codex',email:'work.codex@example.com',card:'Quota/Codex · work',v:[70,85]}, {key:'cursor',p:'Cursor',email:'alin.cursor@example.com',card:'Quota/Cursor',v:[62]}];
function all(n){return[n,...('findAll'in n?n.findAll():[])];}
function one(n,name){return n.findOne(x=>x.name===name);}
function texts(n){return n.findAllWithCriteria({types:['TEXT']});}
function live(n){for(let p=n;p&&p.type!=='PAGE';p=p.parent)if('visible'in p&&!p.visible)return false;return true;}
function touch(n){if(n)changed.add(n.id);return n;}
function setText(n,s){if(!n)return;touch(n).characters=s;}
function clearRx(n){for(const x of all(n))if('reactions'in x&&x.reactions.length){rxJobs.set(x,[]);changed.add(x.id);}}
function remember(n){all(n).forEach(x=>created.add(x.id));return n;}
function dup(n,parent,name){const c=n.clone();parent.appendChild(c);c.name=name||n.name;remember(c);clearRx(c);return c;}
function go(n,d,o={}){if(!n||!d)throw Error('Missing action '+(n&&n.name)+' -> '+(d&&d.name));changed.add(n.id);rxJobs.set(n,[{trigger:o.timeout?{type:'AFTER_TIMEOUT',timeout:o.timeout}:{type:'ON_CLICK'},actions:[{type:'NODE',destinationId:d.id,navigation:'NAVIGATE',transition:{type:o.smart?'SMART_ANIMATE':'DISSOLVE',easing:{type:'EASE_OUT'},duration:o.smart?.26:.18},resetScrollPosition:!o.smart,resetInteractiveComponents:false}]}]);}
function frame(parent,name,w=361){const n=figma.createFrame();parent.appendChild(n);created.add(n.id);n.name=name;n.resize(w,10);n.layoutMode='VERTICAL';n.primaryAxisSizingMode='AUTO';n.counterAxisSizingMode='FIXED';n.itemSpacing=10;n.fills=[];n.clipsContent=false;return n;}
function label(parent,s,t,size=14,name){const n=figma.createText();parent.appendChild(n);created.add(n.id);n.fontName={family:'PingFang SC',style:'Regular'};n.fontSize=size;n.lineHeight={unit:'PIXELS',value:Math.ceil(size*1.45)};n.fills=[{type:'SOLID',color:{r:t==='Dark'?.92:.08,g:t==='Dark'?.92:.08,b:t==='Dark'?.92:.08}}];n.characters=s;n.name=name||s;n.textAutoResize='HEIGHT';n.resize(parent.width-(parent.paddingLeft||0)-(parent.paddingRight||0),Math.ceil(size*1.45));return n;}
function button(root,s){return one(root,'Button/'+s);}
function addButton(parent,s,e,primary=false){const n=dup(primary?e.primary:e.secondary,parent,'Button/'+s);setText(texts(n)[0],s);n.resize(parent.width-(parent.paddingLeft||0)-(parent.paddingRight||0),44);return n;}
function getKey(n){return n.name;}
function cloneRoot(e,src,key){const name='R4/'+e.t+'/'+key;if(registry.has(name))return registry.get(name);const n=dup(src,e.branch,name);n.visible=true;registry.set(name,n);return n;}
function attachStrip(e,f,title,lines,buttons,phase){const body=one(f,'Content');const s=frame(body,'R4/Update status',361);body.insertChild(0,s);s.paddingTop=s.paddingBottom=10;s.paddingLeft=s.paddingRight=12;s.cornerRadius=14;const shade=e.t==='Dark'?.16:.91;s.fills=[{type:'SOLID',color:{r:shade,g:shade,b:shade}}];label(s,title,e.t,15,'R4/Status title');for(const line of lines)label(s,line,e.t,12);for(const b of buttons)addButton(s,b,e);const tut=one(f,'Action/如何添加小组件');if(tut)tut.visible=false;return s;}
function panel(e,name,title,lines,buttons,src,mode='foreground'){
 const f=cloneRoot(e,src,name);
 if(mode!=='foreground'){attachStrip(e,f,title,lines,buttons);return f;}
 const bg=dup(e.connect.children.find(n=>n.type==='RECTANGLE'),f,'R4/Scrim');bg.x=0;bg.y=0;const sh=dup(one(e.connect,'Sheet'),f,'R4/Sheet');const head=one(sh,'Sheet heading'),ttl=head.children.find(n=>n.type==='TEXT');setText(ttl,title);const vp=one(sh,'Sheet viewport'),old=one(vp,'Content');old.remove();const b=frame(vp,'Content',393);b.paddingLeft=b.paddingRight=20;b.paddingTop=8;b.paddingBottom=20;b.itemSpacing=12;for(const l of lines)label(b,l,e.t,14);for(let i=0;i<buttons.length;i++)addButton(b,buttons[i],e,i===0&&buttons.length>1);const h=Math.min(680,116+b.height);sh.resize(393,h);sh.x=0;sh.y=852-h;vp.resize(393,h-96);const home=one(sh,'Home indicator');if(home)home.y=h-14;go(one(sh,'Action/close'),src);go(bg,src);return f;
}
function status(e,f,s,phase){let holder=one(f,'R4/Update status')||one(one(f,'R4/Sheet'),'Content');const row=frame(holder,'R4/Network progress',holder.width-(holder.paddingLeft||0)-(holder.paddingRight||0));row.layoutMode='HORIZONTAL';row.primaryAxisSizingMode='FIXED';row.counterAxisSizingMode='AUTO';row.itemSpacing=6;holder.insertChild(0,row);for(let i=0;i<3;i++){const dot=figma.createEllipse();row.appendChild(dot);created.add(dot.id);dot.name='Progress dot '+i;dot.resize(5,5);const c=e.t==='Dark'?.9:.12;dot.fills=[{type:'SOLID',color:{r:c,g:c,b:c}}];dot.opacity=phase===3?.3:i===(phase%3)?1:.25;}if(one(f,'R4/Sheet')){const sh=one(f,'R4/Sheet'),vp=one(sh,'Sheet viewport'),b=one(vp,'Content'),h=116+b.height;sh.resize(393,h);sh.y=852-h;vp.resize(393,h-96);one(sh,'Home indicator').y=h-14;}}
function env(e){return{t:e.t,panel:(...a)=>panel(e,...a),go,button,status:(...a)=>status(e,...a)}}
function accountOfCard(n){return A.findIndex(a=>a.card===n.name);}
function model(e,mask){return models.get(e.t+'/'+mask);}
function fallback(idx,mask){if(mask&(1<<idx))return idx;const p=A[idx].p;for(let i=0;i<4;i++)if(mask&(1<<i)&&A[i].p===p)return i;for(let i=0;i<4;i++)if(mask&(1<<i))return i;return -1;}
function basic(e,mask){const base=mask?e.dashboard:e.empty;const d=mask===15?e.dashboard:cloneRoot(e,base,'Accounts/'+mask+'/Dashboard');const s=mask===15?e.settings:cloneRoot(e,e.settings,'Accounts/'+mask+'/Settings');clearRx(d);clearRx(s);for(const f of[d,s]){for(const n of f.findAll(n=>n.name.startsWith('Quota/')||n.name.startsWith('Account row/'))){const i=n.name.startsWith('Quota/')?accountOfCard(n):A.findIndex(a=>n.name==='Account row/'+a.card.slice(6));if(i>=0){touch(n).visible=!!(mask&(1<<i));}}for(const n of f.findAll(n=>n.name==='Row/额度显示')){touch(n).visible=false;clearRx(n);}const body=one(f,'Content');if(body){body.itemSpacing=8;one(f,'Scroll viewport').overflowDirection='VERTICAL';}}
if(mask===0){const g=one(s,'Group/账户');for(const n of g.children)if(n.name==='Inset divider')n.visible=false;}
const m={e,mask,d,s,details:[],menus:{},homes:{},query:{}};models.set(e.t+'/'+mask,m);for(let i=0;i<4;i++)if(mask&(1<<i)){const f=cloneRoot(e,d,'Accounts/'+mask+'/Expanded/'+A[i].key);const card=one(f,A[i].card),dt=one(card,'Account details');if(dt)dt.visible=true;const tu=one(f,'Action/如何添加小组件');if(tu)tu.visible=false;m.details[i]=f;}return m;}
function updateData(e,root,scope){for(let i=0;i<4;i++){const c=one(root,A[i].card);if(!c||!c.visible||scope!=='all'&&scope!==i)continue;const dt=one(c,'Detail updated');if(dt)setText(dt,dt.characters.replace('09:41','09:45'));}return root;}
async function queryFlow(m,source,scope,key,outcome='51',qfail=false,mode='foreground'){
 const e=m.e,operation=scope==='all'?'全部账号额度查询':A[scope].email+' 的额度查询';
 const result=cloneRoot(e,m.d,key+'/查询'+(qfail?'失败':'成功'));
 if(qfail){attachStrip(e,result,'额度查询失败',['平台暂时未返回额度','保留上次成功数据 · 09:41'],['重试','关闭']);}else{updateData(e,result,scope);attachStrip(e,result,'额度已更新',[scope==='all'?'全部已连接账号 · 09:45':A[scope].email+' · 09:45'],['关闭']);}
 // Result uses the current account set. Dismiss leaves that exact snapshot visible.
 const settled=cloneRoot(e,result,key+'/结果看板');const strip=one(settled,'R4/Update status');if(strip)strip.remove();wireSimple(m,settled);
 go(button(result,'关闭'),settled);wireSimple(m,result);
 const loading=panel(e,key+'/查询中','正在查询额度',[operation],['取消'],source,mode==='foreground'?'foreground':mode);go(button(loading,'取消'),source);go(loading,result,{timeout:1});
 const flow=await buildNetworkFlow(env(e),{key,source,next:loading,outcome,mode,operation});
 if(qfail)go(button(result,'重试'),(await queryFlow(m,source,scope,key+'/重试','51',false,mode)).start);
 return Object.assign(flow,{loading,result,settled});
}
function wireSimple(m,f){const e=m.e;const b=one(f,'Action/back');if(b)go(b,m.d);const set=one(f,'Tab/设置'),dash=one(f,'Tab/额度');if(set)go(set,m.s);if(dash)go(dash,m.d);const link=one(f,'Action/link');if(link&&m.connectD)go(link,m.connectD);const refresh=one(f,'Action/refresh');if(refresh&&m.refresh)go(refresh,m.refresh.start);const tut=one(f,'Action/如何添加小组件');if(tut&&m.tutorialD)go(tut,m.tutorialD);for(let i=0;i<4;i++)if(m.mask&(1<<i)){const c=one(f,A[i].card);if(c){go(one(c,'Expand account'),m.details[i]||m.d,{smart:true});if(m.menus['d'+i])go(one(c,'Action/more'),m.menus['d'+i]);}}}
function menu(m,src,origin,i){const e=m.e,a=A[i],key='Accounts/'+m.mask+'/'+origin+'/Menu/'+a.key;const f=panel(e,key,a.p+' 账户',[a.email],['刷新额度','重新连接','断开连接','取消'],src);go(button(f,'取消'),src);m.menus[origin+i]=f;const confirm=panel(e,key+'/断开确认','断开连接？',[a.email,'移除此账号的额度数据和待发提醒。平台订阅不会取消。'],['断开连接','取消'],src);go(button(confirm,'取消'),src);go(button(confirm,'断开连接'),origin==='s'?model(e,m.mask&~(1<<i)).s:model(e,m.mask&~(1<<i)).d);go(button(f,'断开连接'),confirm);return f;}
function widget(m,selected,size='small',customKey){const e=m.e,key=customKey||'Accounts/'+m.mask+'/Home/'+selected+'/'+size;if(registry.has('R4/'+e.t+'/'+key))return registry.get('R4/'+e.t+'/'+key);const f=cloneRoot(e,e.home,key),container=one(f,'Home widgets');for(const x of [...container.children])x.remove();container.layoutMode='HORIZONTAL';container.itemSpacing=16;container.primaryAxisSizingMode='FIXED';container.counterAxisSizingMode='AUTO';container.resize(361,164);const targets=[fallback(selected,m.mask),fallback(3,m.mask)];if(size==='medium')targets.splice(1,1);
for(let k=0;k<targets.length;k++){const i=targets[k];let w=dup(e.widget,container,'R4/Widget '+k);if(w.type==='INSTANCE')w=w.detachInstance();remember(w);if(i<0){for(const ch of [...w.children])ch.remove();label(w,'未连接账号，无数据',e.t,13);go(w,m.d);}else{const a=A[i],title=one(w,'Widget header').children.find(n=>n.type==='TEXT');setText(title,a.p+' · '+a.email.split('@')[0]);const wins=w.children.filter(n=>n.name.startsWith('Widget window/'));for(let z=0;z<wins.length;z++){const win=wins[z];if(z>=a.v.length){win.visible=false;continue;}const metric=one(win,'Metric'),v=metric.children.find(n=>n.type==='TEXT'&&n.characters.includes('%'));setText(v,'剩余 '+a.v[z]+'%');const tr=one(win,'Widget progress');tr.children[0].resize(tr.width*(100-a.v[z])/100,tr.children[0].height);if(i===3){const tx=metric.children.find(n=>n.type==='TEXT'&&n!==v);if(tx)setText(tx,'套餐额度');}}go(w,m.details[i]||m.d);}if(size==='medium'){w.resize(345,164);}}
const tx=texts(f).find(n=>n.characters==='轻点小组件，打开对应账户');if(tx)setText(tx,'轻点小组件，打开对应账号');go(one(f,'Action/back'),e.widgetReview);const apps=one(f,'Apps');if(apps)go(apps,m.d);return f;}
function tutorial(e,src,key){const a=cloneRoot(e,e.tutorial1,key+'/步骤1'),b=cloneRoot(e,e.tutorial1b,key+'/步骤1动画'),c=cloneRoot(e,e.tutorial2,key+'/步骤2'),d=cloneRoot(e,e.tutorial2b,key+'/步骤2动画');for(const f of[a,b,c,d]){const close=one(f,'Action/close');if(close)go(close,src);const bg=f.children.find(n=>n.type==='RECTANGLE');if(bg)go(bg,src);}for(const f of[a,b])go(button(f,'下一步'),c,{smart:true});for(const f of[c,d])go(button(f,'完成'),src);go(a,b,{timeout:.9,smart:true});go(c,d,{timeout:.9,smart:true});return a;}
async function addFlow(m,src,p,key,outcome='51',authFail=false){const e=m.e;let idx=A.findIndex((a,i)=>a.p===p&&!(m.mask&(1<<i)));const existing=idx<0;const loginTemplate=e.logins[p];const login=cloneRoot(e,loginTemplate,key+'/登录');const cancel=button(login,'取消');if(cancel)go(cancel,src);if(one(login,'Action/close'))go(one(login,'Action/close'),src);const loginBg=login.children.find(n=>n.type==='RECTANGLE');if(loginBg)go(loginBg,src);
let targetMask=existing?m.mask:m.mask|(1<<idx),dest=model(e,targetMask).d;
// A full-list add uses one extra illustrative account, distinct from both existing Codex accounts.
if(existing){dest=cloneRoot(e,m.d,key+'/添加成功');const body=one(dest,'Content'),template=one(m.d,A.find(a=>a.p===p).card);let card=dup(template,body,'Quota/'+p+' · new');if(card.type==='INSTANCE')card=card.detachInstance();remember(card);for(const tx of texts(card))if(tx.characters.includes('@'))setText(tx,'new.'+p.toLowerCase()+'@example.com');const detail=one(card,'Detail updated');if(detail)setText(detail,detail.characters.replace('09:41','09:45'));body.insertChild(body.children.indexOf(template)+1,card);const more=one(card,'Action/more'),expand=one(card,'Expand account');const nf=panel(e,key+'/新增账号菜单',p+' 账户',['new.'+p.toLowerCase()+'@example.com'],['断开连接','取消'],dest);go(button(nf,'取消'),dest);const conf=panel(e,key+'/新增账号断开','断开连接？',['new.'+p.toLowerCase()+'@example.com'],['断开连接','取消'],dest);go(button(nf,'断开连接'),conf);go(button(conf,'取消'),dest);go(button(conf,'断开连接'),m.d);go(more,nf);const expanded=cloneRoot(e,dest,key+'/新增账号详情');const extra=one(expanded,'Quota/'+p+' · new');if(one(extra,'Account details'))one(extra,'Account details').visible=true;go(expand,expanded,{smart:true});go(one(extra,'Expand account'),dest,{smart:true});wireSimple(m,dest);wireSimple(m,expanded);}
const authorized=panel(e,key+'/授权中','正在连接 '+p,['平台授权 · 交互示意'],['取消'],src);go(button(authorized,'取消'),src);const qloading=panel(e,key+'/首次查询中','正在查询额度',[existing?'new.'+p.toLowerCase()+'@example.com':A[idx].email],['取消'],dest);go(button(qloading,'取消'),dest);go(qloading,dest,{timeout:1});const first=await buildNetworkFlow(env(e),{key:key+'/首次查询',source:dest,next:qloading,outcome:'51',mode:'foreground',operation:'新增账号的首次额度查询'});const af=panel(e,key+'/授权失败','授权未完成',['未添加新账号。已有账号保持不变。'],['重新尝试','取消'],src);go(button(af,'取消'),src);go(authorized,authFail?af:first.start,{timeout:1});go(button(login,'继续'),authorized);const pre=await buildNetworkFlow(env(e),{key,source:src,next:login,outcome,mode:'foreground',operation:'添加 '+p+' 账号'});go(button(af,'重新尝试'),pre.start);return Object.assign(pre,{login,authorized,dest,first,authFailed:af});}
async function reconnectFlow(m,src,i,key){const e=m.e,a=A[i],login=cloneRoot(e,e.logins[a.p],key+'/登录');for(const tx of texts(login))if(tx.characters.includes('@'))setText(tx,a.email);go(button(login,'取消'),src);go(one(login,'Action/close'),src);const bg=login.children.find(n=>n.type==='RECTANGLE');if(bg)go(bg,src);const q=await queryFlow(m,src,i,key+'/额度查询');go(button(login,'继续'),q.start);return login;}
async function makeConnect(m,src,origin){const e=m.e,key='Accounts/'+m.mask+'/'+origin+'/添加';const f=panel(e,key,'添加账户',[],[],src);const body=one(one(f,'R4/Sheet'),'Content'),row=dup(one(e.connect,'Connect/Claude').parent,body,'R4/Platform choices');const sh=one(f,'R4/Sheet'),vp=one(sh,'Sheet viewport');sh.resize(393,275);sh.y=577;vp.resize(393,179);one(sh,'Home indicator').y=261;for(const p of['Claude','Codex','Cursor']){const flow=await addFlow(m,src,p,key+'/'+p);go(one(row,'Connect/'+p),flow.start);}return f;}
async function setup(){await init();const fs=new Map();for(const sec of[secs[0],secs[2]])for(const n of texts(sec))for(const s of n.getStyledTextSegments(['fontName']))fs.set(JSON.stringify(s.fontName),s.fontName);for(const f of fs.values()){figma.ui.postMessage({status:'载入字体 '+f.family+' '+f.style,progress:true});await Promise.race([figma.loadFontAsync({family:f.family,style:f.style}),new Promise((_,reject)=>setTimeout(()=>reject(Error('Font timeout: '+f.family+' '+f.style)),25000))]);}
for(const [j,t]of['Light','Dark'].entries()){const review=secs[j*2],branch=secs[j*2+1],roots=review.children.filter(n=>n.type==='FRAME'&&n.visible);const kind=k=>roots.find(n=>n.name===t+'/'+k||n.name.split('|')[1]===k);const findName=part=>roots.find(n=>n.name.includes(part));const e={t,review,branch,roots,sampleFrames:[],dashboard:kind('Dashboard'),settings:kind('Settings'),connect:kind('Connect'),empty:roots.find(n=>n.name.includes('|Dashboard|0|')&&!n.name.includes('initial')),home:kind('SystemHome'),widgetReview:kind('WidgetReview'),widgetConfig:kind('WidgetConfig'),tutorial1:kind('Tutorial1'),tutorial1b:kind('Tutorial1b'),tutorial2:kind('Tutorial2'),tutorial2b:kind('Tutorial2b'),entry:kind('Review'),stateReview:kind('StateReview'),permission:kind('Permission'),system:kind('System'),lock:kind('LockNotification'),logins:{}};e.dashboard=roots.find(n=>n.name===t+'/Dashboard');e.settings=roots.find(n=>n.name===t+'/Settings');for(const p of['Claude','Codex','Cursor'])e.logins[p]=roots.find(n=>n.name.includes('|Login|')&&n.name.includes('|'+p+'|'));e.primary=button(e.logins.Claude,'继续');e.secondary=button(e.logins.Claude,'取消');e.widget=one(e.home,'Widget/Claude');themes[t]=e;}
}
let ledger;
async function apply(){throw Error("R4 draft disabled: inspect actual canvas and repair documented issues before execution");await setup();if(secs.some(s=>s.children.some(n=>n.name.startsWith('R4/'))))throw Error('R4 already exists; inspect before retry');
for(const e of Object.values(themes)){for(const n of e.branch.children){touch(n).visible=false;if('reactions'in n&&n.reactions.length)rxJobs.set(n,[]);}for(const r of e.roots)clearRx(r);for(let mask=0;mask<16;mask++)basic(e,mask);}
for(const e of Object.values(themes)){
 const main=model(e,15);
 for(let mask=0;mask<16;mask++){const m=model(e,mask);figma.ui.postMessage({status:e.t+' · 账号与返回路径 '+(mask+1)+'/16',progress:true});
 m.tutorialD=tutorial(e,m.d,'Accounts/'+mask+'/TutorialDashboard');m.tutorialS=tutorial(e,m.s,'Accounts/'+mask+'/TutorialSettings');
 for(let i=0;i<4;i++)if(mask&(1<<i)){menu(m,m.d,'d',i);menu(m,m.s,'s',i);}
 m.connectD=await makeConnect(m,m.d,'d');m.connectS=await makeConnect(m,m.s,'s');
 if(mask)m.refresh=await queryFlow(m,m.d,'all','Accounts/'+mask+'/RefreshAll');
 for(let i=0;i<4;i++)if(mask&(1<<i)){const q=await queryFlow(m,m.d,i,'Accounts/'+mask+'/Refresh/'+A[i].key);for(const origin of['d','s']){const src=origin==='d'?m.d:m.s,f=m.menus[origin+i];go(button(f,'刷新额度'),q.start);go(button(f,'重新连接'),await reconnectFlow(m,src,i,'Accounts/'+mask+'/'+origin+'/Reconnect/'+A[i].key));}}
 for(const f of[m.d,...m.details.filter(Boolean)])wireSimple(m,f);wireSimple(m,m.s);go(one(m.s,'Tab/额度'),m.d);const add=one(m.s,'Row/连接账户');if(add)go(add,m.connectS);const nt=one(m.s,'Toggle/通知');const on=cloneRoot(e,m.s,'Accounts/'+mask+'/通知开启'),denied=cloneRoot(e,m.s,'Accounts/'+mask+'/通知拒绝');const p=cloneRoot(e,e.permission,'Accounts/'+mask+'/权限');go(button(p,'允许'),on);go(button(p,'不允许'),denied);if(one(p,'Action/close'))go(one(p,'Action/close'),m.s);if(nt)go(nt,p);const ton=one(on,'Toggle/通知');if(ton)go(ton,m.s);const td=one(denied,'Toggle/通知');const sys=cloneRoot(e,e.system,'Accounts/'+mask+'/系统设置'),sysOn=cloneRoot(e,sys,'Accounts/'+mask+'/系统设置已允许');const toggles=sys.findAll(n=>n.name.includes('State=Off'));for(const n of toggles)go(n,sysOn);const ons=sysOn.findAll(n=>n.name.includes('State=Off'));for(const n of ons){const mainC=await n.getMainComponentAsync();const alt=mainC.parent.type==='COMPONENT_SET'&&mainC.parent.children.find(x=>x.name.includes('State=On')&&x.name.includes(e.t));if(alt)n.swapComponent(alt);go(n,sys);}go(one(sys,'Action/back'),denied);go(one(sysOn,'Action/back'),on);if(td)go(td,sys);for(const f of[on,denied]){wireSimple(m,f);go(one(f,'Tab/额度'),m.d);}attachStrip(e,denied,'通知未开启',['可在系统设置中允许通知'],['进入系统设置']);go(button(denied,'进入系统设置'),sys);const onTxt=texts(on).find(x=>x.characters==='额度重置通知');if(onTxt)setText(onTxt,'额度重置通知 · 已开启');
 for(const a of A){const row=one(m.s,'Account row/'+a.card.slice(6));if(row&&row.visible){const i=A.indexOf(a);go(one(row,'Account identity'),m.details[i]);go(one(row,'Action/more'),m.menus['s'+i]);}}
 const tutorialRow=one(m.s,'Row/如何添加小组件');if(tutorialRow)go(tutorialRow,m.tutorialS);
 const hm=widget(m,2);for(const f of[m.d,m.s,...m.details.filter(Boolean)]){const h=f.children.find(n=>n.type==='RECTANGLE'&&n.width===134);if(h)go(h,hm);}
 }
 await reviewFlows(e,main);
}
// Apply queued reactions in bounded batches; original shared components are untouched.
const jobs=[...rxJobs].filter(([n])=>!n.removed);for(let off=0;off<jobs.length;off+=100){await Promise.all(jobs.slice(off,off+100).map(([n,r])=>n.setReactionsAsync(r)));if(off%1000===0)figma.ui.postMessage({status:'同步连线 '+off+'/'+jobs.length,progress:true});}
for(const e of Object.values(themes)){const fresh=e.branch.children.filter(n=>n.visible);fresh.forEach((n,i)=>{touch(n);n.x=32+(i%12)*433;n.y=70+Math.floor(i/12)*904;});touch(e.branch).resizeWithoutConstraints(5260,Math.max(1024,70+Math.ceil(fresh.length/12)*904));e.branch.y=10800;e.branch.x=e.t==='Light'?100:5600;}
page.flowStartingPoints=[{nodeId:themes.Light.entry.id,name:'R4 · 浅色设计评审'},{nodeId:themes.Dark.entry.id,name:'R4 · 深色设计评审'}];ledger={status:'R4 局部交互更新完成',createdNodeIds:[...created],mutatedNodeIds:[...changed],screens:[...registry].map(([name,n])=>({name,id:n.id})),reactionNodes:rxJobs.size};return await audit();}
async function reviewFlows(e,m){
 const review=e.stateReview,body=one(review,'Content');for(const n of [...body.children])n.remove();body.itemSpacing=8;label(body,'设计评审 · 模拟结果',e.t,20);label(body,'仅用于检查原型状态与路径',e.t,12);const entries=[];function entry(s,f){const b=addButton(body,s,e);go(b,f);entries.push({label:s,id:f.id});}
 for(const outcome of['49','50','51','timeout','unavailable','invalid']){const title={49:'评分 49 · 阻止新增',50:'评分 50 · 阻止新增',51:'评分 51 · 继续新增',timeout:'检查超时',unavailable:'评分网站不可用',invalid:'没有有效评分'}[outcome];const a=await addFlow(m,m.d,'Codex','Review/'+outcome,outcome);entry(title,a.start);if(['49','50','timeout','unavailable','invalid'].includes(outcome))e.sampleFrames.push(a.result);else e.sampleFrames.push(a.start,a.passed,a.login);}
 const auth=await addFlow(m,m.d,'Codex','Review/授权失败','51',true);entry('后续授权失败',auth.start);e.sampleFrames.push(auth.authFailed);
 const qf=await queryFlow(m,m.d,2,'Review/查询失败','51',true);entry('检查通过后 · 额度查询失败',qf.start);e.sampleFrames.push(qf.result);
 const all=await queryFlow(m,m.d,'all','Review/全部查询失败','timeout',true);entry('全部刷新 · 检查失败与重试',all.start);
 entry('顶部全部刷新',m.refresh.start);const single=await queryFlow(m,m.d,2,'Review/单账号查询');entry('仅刷新 work.codex',single.start);e.sampleFrames.push(single.settled);
 const bg=await queryFlow(m,m.d,'all','Review/后台自动','timeout',false,'background');entry('进入 App · 自动检查失败',bg.start);e.sampleFrames.push(bg.start,bg.result);
 const note=cloneRoot(e,e.lock,'Review/通知打开');const nq=await queryFlow(m,m.d,0,'Review/通知查询','51',false);const card=one(note,'Card');if(card)go(card,nq.start);if(one(note,'Action/back'))go(one(note,'Action/back'),review);entry('打开预计重置通知',note);
 const home=widget(m,2),wf=await buildNetworkFlow(env(e),{key:'Review/小组件联网',source:home,next:home,outcome:'unavailable',mode:'widget',operation:'小组件额度查询'});const wql=panel(e,'Review/WidgetQuery','正在查询额度',['work.codex@example.com'],['返回'],home,'widget');go(button(wql,'返回'),home);go(wql,home,{timeout:1});go(wf.retry.passed,wql,{timeout:.35});entry('小组件联网 · 检查失败',wf.start);e.sampleFrames.push(wf.result);
 // The paired widgets retain their own identities. The second starts on Cursor.
 entry('断开 work · 同平台回退',m.menus.d2);entry('断开最后一个 Codex · 跨平台回退',model(e,11).menus.d1);entry('断开最后账号 · 无数据',model(e,8).menus.d3);
 entry('小组件同平台回退结果',widget(model(e,11),2));entry('小组件跨平台回退结果',widget(model(e,9),2));entry('全部断开 · 小组件空态',widget(model(e,0),2));e.sampleFrames.push(widget(model(e,11),2),widget(model(e,9),2),widget(model(e,0),2));
 // Multiple same-platform candidates: work is removed, two remaining Codex examples.
 const order=cloneRoot(e,widget(model(e,11),2),'Review/同平台多候选顺序');attachStrip(e,order,'同平台回退 · 列表首位',['设计评审：work.codex 已断开','候选顺序：alin.codex → backup.codex','组件选择 alin.codex；Cursor 组件保持不变'],[]);entry('同平台多候选 · 按列表顺序',order);e.sampleFrames.push(order);
 const conf=e.widgetConfig;clearRx(conf);const rows=one(conf,'Group/账户');const configs={};for(let i=0;i<4;i++){const f=cloneRoot(e,conf,'WidgetConfig/'+A[i].key);configs[i]=f;for(const r of one(f,'Group/账户').children){const a=A.findIndex(x=>'Account/'+x.card.slice(6)===r.name);if(a>=0){for(const check of r.findAll(n=>n.name.includes('check')))check.visible=a===i;}}const subtitle=texts(f).find(n=>n.characters==='显示所选账户的剩余额度。');if(subtitle)setText(subtitle,'已选择 '+A[i].email);go(button(f,'完成'),widget(m,i));go(one(f,'Action/back'),e.widgetReview);}for(let i=0;i<4;i++)for(const f of[conf,...Object.values(configs)])for(const a of A){const row=one(f,'Account/'+a.card.slice(6));if(row)go(row,configs[A.indexOf(a)]);}go(button(conf,'完成'),widget(m,0));go(one(conf,'Action/back'),e.widgetReview);
 const medium=cloneRoot(e,e.widgetReview,'WidgetReview/Medium');const canvas=one(medium,'Widget canvas');const oldW=one(canvas,'Widget/Claude');if(oldW)oldW.resize(345,164);
 for(const f of[e.widgetReview,medium]){go(button(f,'小号'),e.widgetReview);go(button(f,'中号'),medium);go(button(f,'编辑小组件'),conf);go(button(f,'添加小组件'),widget(m,0,f===medium?'medium':'small'));go(one(f,'Action/back'),e.entry);}
 // Entry and all old review snapshots are rewired to the new local graph.
 for(const t of texts(e.entry)){if(t.characters.startsWith('本轮先审核'))setText(t,'网络检查、授权、额度与系统界面均为设计模拟。');if(t.characters.startsWith('直接在画布审核'))setText(t,'仅供设计评审 · 产品外观自动跟随系统');if(t.characters==='页面评审 · 多账户与固定剩余显示')setText(t,'R4 · 网络检查与交互路径');}
 go(button(e.entry,'从首次使用开始'),model(e,0).d);go(button(e.entry,'查看已连接看板'),m.d);go(button(e.entry,'小组件与系统交互'),e.widgetReview);go(button(e.entry,'检查通知与异常状态'),review);go(button(e.entry,e.t==='Light'?'查看深色版本':'查看浅色版本'),themes[e.t==='Light'?'Dark':'Light'].entry);go(one(review,'Action/back'),e.entry);
 for(const f of e.roots){const k=f.name.includes('|')?f.name.split('|')[1]:f.name.split('/')[1];if(k==='Dashboard'&&f!==m.d&&f!==model(e,0).d){wireSimple(m,f);if(button(f,'重试'))go(button(f,'重试'),m.refresh.start);if(button(f,'重新连接'))go(button(f,'重新连接'),await reconnectFlow(m,f,0,'Review/ExpiredReconnect'));if(button(f,'查询最新额度'))go(button(f,'查询最新额度'),nq.start);}else if(k==='Connect'){go(one(f,'Action/close'),m.d);const bg=f.children.find(n=>n.type==='RECTANGLE');if(bg)go(bg,m.d);for(const p of['Claude','Codex','Cursor']){const flow=await addFlow(m,m.d,p,'Review/Connect/'+p);go(one(f,'Connect/'+p),flow.start);}}else if(k==='Menu'){for(const s of['刷新额度','重新连接','断开连接']){const r=one(f,'Row/'+s);if(r)go(r,s==='刷新额度'?m.refresh.start:s==='断开连接'?m.menus.d0:m.menus.d0);}if(one(f,'Action/close'))go(one(f,'Action/close'),m.d);}else if(k==='Login'){const p=['Claude','Codex','Cursor'].find(p=>f.name.includes('|'+p+'|'));const af=await addFlow(m,m.d,p,'Review/DirectLogin/'+p);go(button(f,'继续'),af.authorized);go(button(f,'取消'),m.d);go(one(f,'Action/close'),m.d);}else if(k==='Settings'&&f!==m.s){wireSimple(m,f);if(one(f,'Toggle/通知'))go(one(f,'Toggle/通知'),e.permission);if(one(f,'Row/连接账户'))go(one(f,'Row/连接账户'),m.connectS);}else if(k==='Permission'){go(button(f,'允许'),registry.get('R4/'+e.t+'/Accounts/15/通知开启'));go(button(f,'不允许'),registry.get('R4/'+e.t+'/Accounts/15/通知拒绝'));if(one(f,'Action/close'))go(one(f,'Action/close'),m.s);}else if(k==='System'){go(one(f,'Action/back'),m.s);for(const n of f.findAll(n=>n.name.includes('State=Off')))go(n,registry.get('R4/'+e.t+'/Accounts/15/系统设置已允许'));}else if(k==='Disconnect'){go(button(f,'断开连接'),model(e,14).d);go(button(f,'取消'),m.d);go(one(f,'Action/close'),m.d);}else if(k==='Connecting'){go(f,m.refresh.start,{timeout:1});if(button(f,'取消'))go(button(f,'取消'),m.d);}else if(k==='Failed'){go(button(f,'重新尝试'),auth.start);go(button(f,'取消'),m.d);if(one(f,'Action/close'))go(one(f,'Action/close'),m.d);}else if(k.startsWith('Tutorial')){const step=k.includes('1')?1:2;if(step===1)go(button(f,'下一步'),e.tutorial2);else go(button(f,'完成'),m.d);if(one(f,'Action/close'))go(one(f,'Action/close'),m.d);if(!k.endsWith('b'))go(f,step===1?e.tutorial1b:e.tutorial2b,{timeout:.9,smart:true});}else if(k==='LockNotification'){if(one(f,'Card'))go(one(f,'Card'),nq.start);if(one(f,'Action/back'))go(one(f,'Action/back'),review);}else if(k==='SystemHome'){const w=f.findOne(n=>n.name.startsWith('Widget/'));if(w)go(w,m.details[0]);go(one(f,'Action/back'),e.widgetReview);}else if(k==='WidgetState'){const b=one(f,'Content');for(const tx of texts(b))if(tx.characters.includes('账户已断开'))setText(tx,'已切换到仍绑定账号');for(const c of f.findAll(n=>n.name==='Card'))go(c,widget(model(e,11),2));if(one(f,'Action/back'))go(one(f,'Action/back'),e.widgetReview);}else if(['Help','Privacy','Licenses','License'].includes(k)){go(one(f,'Action/back'),k==='License'?e.roots.find(r=>r.name.endsWith('/Licenses')):m.s);if(k==='Licenses'&&one(f,'Row/CodexBar'))go(one(f,'Row/CodexBar'),e.roots.find(r=>r.name.endsWith('/License')));}}
 for(const mask of [...Array(16).keys()]){const x=model(e,mask);for(const [name,kind]of[['帮助与说明','Help'],['隐私说明','Privacy'],['开源许可','Licenses']]){const row=one(x.s,'Row/'+name);if(row){const src=e.roots.find(r=>r.name.endsWith('/'+kind)),dest=cloneRoot(e,src,'Accounts/'+mask+'/'+kind);go(one(dest,'Action/back'),x.s);go(row,dest);}}}
 e.entries=entries;
}
async function audit(){await init();const active=secs.flatMap(s=>s.children.filter(n=>n.type==='FRAME'&&n.visible));const ids=new Set(active.map(n=>n.id)),invalid=[],dead=[],forbidden=[],nonGray=[],overflow=[],bars=[];let links=0,animated=0;const forbiddenRe=/开启后，在额度预计重置时收到提醒|外观自动跟随 iPhone 系统|选择平台添加账户。同一平台可继续添加其他账户|集中查看 Claude、Codex 和 Cursor|使用你的平台账户继续|小组件会在下次系统更新后显示已断开|^已添加\s*\d+\s*个$|额度显示|查看已用状态|点按刷新查看最新额度|剩余／已用/;
for(const r of active){let count=0;for(const n of all(r).filter(live)){if(n.type==='TEXT'&&forbiddenRe.test(n.characters))forbidden.push({id:n.id,text:n.characters});if('reactions'in n)for(const rx of n.reactions){for(const a of rx.actions||[]){links++;count++;if(a.transition)animated++;if(a.type==='NODE'&&!ids.has(a.destinationId))invalid.push({source:n.id,target:a.destinationId});}}if('fills'in n&&Array.isArray(n.fills))for(const p of n.fills)if(p.type==='SOLID'&&(Math.abs(p.color.r-p.color.g)>.001||Math.abs(p.color.g-p.color.b)>.001))nonGray.push(n.id);if(n.type==='TEXT'&&n.parent&&n.parent.layoutMode!=='NONE'&&n.width>n.parent.width+1)overflow.push({id:n.id,reason:'text wider than parent'});if(n.name.startsWith('Window/')){const key=n.name.slice(7),v=one(n,'Value/'+key),tr=one(n,'Track/'+key),bar=one(n,'Bar/'+key);if(v&&tr&&bar){const rem=parseFloat(v.characters);if(Number.isFinite(rem)&&Math.abs(rem+bar.width/tr.width*100-100)>.15)bars.push({id:bar.id,remaining:rem,used:bar.width/tr.width*100});}}}if(!count&&!r.name.includes('Private components'))dead.push({id:r.id,name:r.name});}
return Object.assign({},ledger||{},{status:'R4 结构验收完成',activeScreens:active.length,links,animated,invalidTargets:invalid,deadScreens:dead,forbiddenTexts:forbidden,nonGray:nonGray.slice(0,100),textOverflow:overflow.slice(0,100),barErrors:bars.slice(0,100),sections:secs.map(s=>({id:s.id,name:s.name,visibleFrames:s.children.filter(n=>n.type==='FRAME'&&n.visible).length})),reviewEntries:Object.fromEntries(Object.entries(themes).map(([t,e])=>[t,e.entries])),sampleFrames:Object.fromEntries(Object.entries(themes).map(([t,e])=>[t,e.sampleFrames.map(n=>({id:n.id,name:n.name}))]))});}
async function gallery(target){await init();let frames;if(target)frames=await Promise.all(target.split(',').map(id=>figma.getNodeByIdAsync(id.trim())));else frames=Object.values(themes).flatMap(e=>[e.entry,e.dashboard,e.settings,...e.sampleFrames]);const out=[];for(const n of [...new Map(frames.map(x=>[x.id,x])).values()]){figma.ui.postMessage({status:'导出静态图 '+(out.length+1)+'/'+frames.length,progress:true});out.push({id:n.id,name:n.name,bytes:Array.from(await n.exportAsync({format:'PNG',constraint:{type:'SCALE',value:1}}))});}figma.ui.postMessage({status:'静态图已导出',gallery:out});}

// R4 local Figma author helper. This file never contacts a scoring service.
// The caller supplies a reviewed outcome before building a branch; outcome
// selectors belong to the design-review index, never to a product frame.
//
// env.panel(name, title, lines, buttonLabels, source, mode) -> Frame | Promise<Frame>
// env.go(node, destinationFrame, { timeout?: seconds, smart?: boolean })
// env.button(frame, label) -> SceneNode
// env.status(frame, text, phase) -> void | Promise<void>
// env.t -> 'Light' | 'Dark'
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

  // Equivalent layers and phase-based opacity allow a restrained Smart Animate
  // transition. The status helper owns the three-dot treatment and colors.
  const start = await make('检查中 A', checkingTitle, checkingLines, [dismiss]);
  const checkingB = await make('检查中 B', checkingTitle, checkingLines, [dismiss]);
  await env.status(start, '正在检查网络', 0);
  await env.status(checkingB, '正在检查网络', 1);
  await connectButton(start, dismiss, cfg.source);
  await connectButton(checkingB, dismiss, cfg.source);
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
    await connectButton(result, dismiss, cfg.source);

    // Every retry repeats the gate. This review branch models a subsequent
    // valid score of 51, then resumes the original operation and account scope.
    retry = await buildNetworkFlow(env, {
      key: cfg.key + ' · 重试',
      source: cfg.source,
      next: cfg.retryNext || cfg.next,
      outcome: '51',
      mode,
      operation: cfg.operation,
    });
    await connectButton(result, '重试', retry.start);
    frames.push(...retry.frames);
  }
  return { start, passed, result, retry, frames };
}

figma.showUI(__html__,{width:600,height:520});figma.ui.onmessage=async m=>{if(busy)return;busy=true;try{let r;if(m.type==='inspect')r=await inspect(m.target);else if(m.type==='focus'){await init();const n=await figma.getNodeByIdAsync(m.target||SCOPE[0]);figma.currentPage.selection=[n];figma.viewport.scrollAndZoomIntoView([n]);r={status:'已定位',id:n.id}}else if(m.type==='apply')r=await apply();else if(m.type==='audit')r=await audit();else if(m.type==='gallery')await gallery(m.target);else throw Error('Unknown action');if(r)figma.ui.postMessage(r)}catch(e){figma.ui.postMessage({status:'停止',error:String(e),stack:e.stack,createdNodeIds:[...created],mutatedNodeIds:[...changed],screens:[...registry].map(([name,n])=>({name,id:n.id}))})}finally{busy=false}};