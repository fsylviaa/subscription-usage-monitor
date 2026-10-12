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
