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
