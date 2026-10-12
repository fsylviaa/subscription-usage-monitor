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
