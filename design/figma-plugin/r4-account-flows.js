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
