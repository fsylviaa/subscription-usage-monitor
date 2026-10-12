// Exact-source local correction after saved/live comparison on 2026-10-09.
// No node creation/deletion, layout/text/style changes or legacy R2 edits.
async function r4ResumeLocalPlan() {
 const homePlans=await widgetSharedHomeBackPlans();
 const plans=[];
 for(const spec of R4_RESUME_INSPECT_SOURCES){
  const root=await figma.getNodeByIdAsync(spec.rootId),node=await figma.getNodeByIdAsync(spec.nodeId);
  if(!root||!node||root.name!==spec.root||root.type!=='FRAME'||root.parent?.id!==(spec.root.includes('/Light/')?'1:43252':'1:43254')||r4ResumePath(node,root.id)!==spec.path)throw Error('Source scope changed '+spec.nodeId);
  const before=JSON.parse(JSON.stringify(node.reactions||[]));
  if(before.length){const actions=before.flatMap(r=>r.actions||(r.action?[r.action]:[]));if(before.length!==1||before[0].trigger?.type!=='ON_CLICK'||actions.length!==1||actions[0].type!=='NODE'||actions[0].destinationId!==spec.destinationId||actions[0].navigation!==spec.navigation)throw Error('Source reaction changed '+spec.nodeId);}
  if(r4ResumeVisible(node)!==spec.sourceVisible)throw Error('Visibility changed '+spec.nodeId);
  let reason;
  if(spec.sourceVisible){
   let card=node;while(card&&card.id!==root.id&&!card.name.startsWith('Quota/'))card=card.parent;
   const details=card?.children?.filter(n=>n.name==='Account details')||[];
   const icons=node.findAll(n=>n.name==='Icon/down');
   if(details.length!==1||!r4ResumeVisible(details[0])||icons.length!==1||icons[0].visible!==false)throw Error('Expanded static header precondition failed '+spec.nodeId);
   reason='Already expanded account details; disclosure icon hidden. Remove stale navigation hotspot, preserve all visible identity/quota/detail content.';
  }else reason='Hidden obsolete control; clear legacy reaction only.';
  plans.push({node,root,spec,before,reason});
 }
 const roots=await Promise.all(R4_RESUME_INSPECT_ROOTS.map(s=>figma.getNodeByIdAsync(s.id)));
 const allowed=new Set([...plans.map(p=>p.node.id),...homePlans.map(p=>p.arrow.id)]);
 const snapshots=roots.flatMap(r=>[r,...r.findAll()].map(n=>({n,value:JSON.stringify({id:n.id,name:n.name,visible:n.visible,x:n.x,y:n.y,w:n.width,h:n.height,text:n.type==='TEXT'?n.characters:null,reactions:allowed.has(n.id)?null:('reactions'in n?n.reactions:[])})})));
 return {plans,homePlans,snapshots};
}
function r4ResumePlanSummary(p){return {status:'精确局部修复预检通过；未修改',mutationCount:0,createdNodeIds:[],removedNodeIds:[],clearReactions:p.plans.map(x=>({rootId:x.root.id,root:x.root.name,nodeId:x.node.id,path:x.spec.path,before:x.before,reason:x.reason})),homePlans:widgetSharedHomeBackSummary(p.homePlans)};}
async function planR4ResumeLocalRepair(){return r4ResumePlanSummary(await r4ResumeLocalPlan());}
async function applyR4ResumeLocalRepair(){
 const p=await r4ResumeLocalPlan(),mutated=[];
 for(const x of p.plans)if(x.before.length){await x.node.setReactionsAsync([]);mutated.push(x.node.id);}
 for(const x of p.homePlans)if(!widgetReturnOnlyBack(x.before)){await x.arrow.setReactionsAsync(widgetReturnBackReaction());mutated.push(x.arrow.id);}
 for(const x of p.plans)if(x.node.reactions.length)throw Error('Clear verification failed '+x.node.id);
 for(const x of p.homePlans)if(!widgetReturnOnlyBack(x.arrow.reactions))throw Error('BACK verification failed '+x.arrow.id);
 for(const s of p.snapshots){const n=s.n;const current=JSON.stringify({id:n.id,name:n.name,visible:n.visible,x:n.x,y:n.y,w:n.width,h:n.height,text:n.type==='TEXT'?n.characters:null,reactions:([...p.plans.map(x=>x.node.id),...p.homePlans.map(x=>x.arrow.id)].includes(n.id))?null:('reactions'in n?n.reactions:[])});if(current!==s.value)throw Error('Unrelated property changed '+n.id);}
 if(mutated.length)figma.commitUndo();
 return {...r4ResumePlanSummary(p),status:'39处以内精确局部修复完成，待新审计与实际点击',mutationCount:mutated.length,mutatedNodeIds:mutated,unrelatedNodeSnapshotsVerified:p.snapshots.length,actualClickValidation:'pending'};
}
