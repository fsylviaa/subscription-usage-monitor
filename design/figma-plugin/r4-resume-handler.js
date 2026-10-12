
figma.showUI(__html__,{width:600,height:520});
let resumeBusy=false;
async function resumeInspect(ids) {
 const out=[];
 for(const id of ids) {const n=await figma.getNodeByIdAsync(id);if(!n){out.push({id,missing:true});continue;}
 const nodes=[n,...('findAll' in n?n.findAll():[])];
 const reactions=[];for(const c of nodes)if('reactions'in c&&c.reactions.length){const targets=[];for(const r of c.reactions)for(const a of r.actions||[r.action])if(a&&a.destinationId){const t=await figma.getNodeByIdAsync(a.destinationId);targets.push({id:a.destinationId,name:t?.name,visible:t?r4cVisible(t):false,parent:t?.parent?.id});}reactions.push({id:c.id,name:c.name,path:r4cPath(c,n.id),visible:r4cVisible(c),reactions:c.reactions,targets});}
 out.push({id:n.id,name:n.name,parent:n.parent?.id,visible:r4cVisible(n),children:n.children?.map(c=>({id:c.id,name:c.name,visible:c.visible})),texts:n.type==='FRAME'?nodes.filter(c=>c.type==='TEXT').map(c=>({id:c.id,text:c.characters,visible:r4cVisible(c)})):[],reactions});
 }
 return {status:'定向只读读取完成',nodes:out};
}
figma.ui.onmessage=async m=>{if(resumeBusy)return;resumeBusy=true;try{
 let result;const parts=(m.target||'').split('/');
 if(m.type==='inspect')result=await resumeInspect(m.target.split(',').map(s=>s.trim()));
 else if(m.type==='apply'&&parts[0]==='resumeinspect')result=await inspectR4ResumeTargets();
 else if(m.type==='apply'&&parts[0]==='localplan')result=await planR4ResumeLocalRepair();
 else if(m.type==='apply'&&parts[0]==='localfix')result=await applyR4ResumeLocalRepair();
 else if(m.type==='apply'&&parts[0]==='homeplan')result=await planWidgetSharedHomeBackRepairStage();
 else if(m.type==='apply'&&parts[0]==='homefix')result=await repairWidgetSharedHomeBackStage();
 else if(m.type==='apply'&&parts[0]==='compact'){
 if(parts[1]==='start')result=await auditR4CompactStart({reset:true});
 else if(parts[1]==='batch')result=await auditR4CompactBatch(parts[2],Number(parts[3]||200));
 else if(parts[1]==='theme'){let x;do{x=await auditR4CompactBatch(parts[2],200);figma.ui.postMessage({...x,progress:true});}while(x.queues[parts[2]].remaining>0);result=x;}
 else if(parts[1]==='finish')result=await auditR4CompactFinish();
 else result=auditR4CompactProgress();
 }else if(m.type==='gallery'){const gallery=[];for(const id of m.target.split(',')){const n=await figma.getNodeByIdAsync(id.trim());gallery.push({id:n.id,name:n.name,bytes:Array.from(await n.exportAsync({format:'PNG',constraint:{type:'SCALE',value:1}}))});}result={status:'定向截图完成',gallery};}
 else throw Error('本恢复工具只开放定向读取、已预检Home修复及新版分批审计。旧生成、清理、全量Audit已禁用。');
 figma.ui.postMessage(result);
 }catch(e){figma.ui.postMessage({status:'停止：'+String(e),error:String(e),stack:e.stack});}finally{resumeBusy=false}};
