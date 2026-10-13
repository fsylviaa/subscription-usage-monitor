/* Candidate 7: horizontal volume with a gentle, value-preserving idle motion. */
(() => {
  const card = document.querySelector('[data-extra-prototype="liquid"]');
  if (!card) return;
  const reduced = matchMedia('(prefers-reduced-motion: reduce)');
  const clamp = v => Math.max(0, Math.min(100, v));
  const format = v => Number(v.toFixed(1)).toString();
  const demos = [[73,50],[95,82],[3,1],[0,100]];
  let frame=0, inView=true;
  const states = ['week','five'].map(key => ({
    key, value:Number(card.querySelector(`[data-control="${key}"]`).value), tween:null,
    pointer:null, rendered:null,
    input:card.querySelector(`[data-control="${key}"]`),
    output:card.querySelector(`[data-output="${key}"]`),
    views:[...card.querySelectorAll(`.quota-window[data-window="${key}"]`)].map(view => ({
      node:view, graph:view.querySelector('.quota-graph'), number:view.querySelector('[data-number]'),
      liquid:view.querySelector('[data-liquid]'), clip:view.querySelector('[data-liquid-clip]'),
      surface:view.querySelector('[data-meniscus]'), bubbles:[...view.querySelectorAll('[data-bubble]')],
    })),
  }));
  function render(state, now) {
    const v=state.value, x=20+v*2;
    // The mirrored cubic curves cancel their areas; the average boundary is x.
    const a=reduced.matches?0:Math.min(2.3,v*2,(100-v)*2)*Math.sin(now/1000);
    const curves=`C${x+a} 34.3333333333 ${x+a} 44.6666666667 ${x} 55 C${x-a} 65.3333333333 ${x-a} 75.6666666667 ${x} 86`;
    const surface=`M${x} 24 ${curves}`, liquid=`M20 24 H${x} ${curves} H20 Z`;
    for (const view of state.views) {
      view.liquid.setAttribute('d',liquid);view.clip.setAttribute('d',liquid);
      view.surface.setAttribute('d',surface);view.surface.setAttribute('opacity',v===0||v===100?0:.55);
      view.bubbles.forEach((bubble,i) => {
        const cycle=(now/6200+i*.31)%1;
        bubble.setAttribute('cy',reduced.matches?70-i*13:79-cycle*45);
        bubble.setAttribute('opacity',v===0?0:reduced.matches?.24:Math.sin(Math.PI*cycle)*.3);
        bubble.setAttribute('transform',`translate(${reduced.matches?0:Math.sin(now/1400+i)*1.5} 0)`);
      });
      if(state.rendered!==v){
        view.number.textContent=`${format(v)}%`;view.graph.dataset.remaining=v.toFixed(1);
        view.graph.setAttribute('aria-valuenow',v.toFixed(1));
        view.graph.setAttribute('aria-valuetext',`剩余 ${format(v)}%，已用 ${format(100-v)}%`);
      }
    }
    if(state.rendered!==v){state.input.value=v.toFixed(1);state.output.textContent=`${format(v)}%`;state.rendered=v;}
  }
  function renderAll(now=performance.now()){states.forEach(state=>render(state,now));}
  function needsFrame(){return inView&&!document.hidden&&!reduced.matches&&states.some(s=>s.tween||(s.value>0&&s.value<100));}
  function tick(now){
    frame=0;
    for(const state of states)if(state.tween){
      const {from,target,start}=state.tween, t=Math.min(1,(now-start)/760);
      state.value=Math.round((from+(target-from)*(1-Math.pow(1-t,3)))*10)/10;
      if(t===1)state.tween=null;
    }
    renderAll(now);wake();
  }
  function wake(){
    if(needsFrame()){if(!frame)frame=requestAnimationFrame(tick);}
    else {cancelAnimationFrame(frame);frame=0;}
  }
  function stop(state){state.tween=null;}
  function set(state,value){stop(state);state.value=Math.round(clamp(value)*10)/10;render(state,performance.now());wake();}
  for(const state of states){
    for(const view of state.views){
      const g=view.graph;
      const fromPointer=e=>{
        const matrix=g.getScreenCTM();if(!matrix)return;
        const point=new DOMPoint(e.clientX,e.clientY).matrixTransform(matrix.inverse());
        set(state,(point.x-20)/200*100);
      };
      g.addEventListener('pointerdown',e=>{
        if(!e.isPrimary||e.button!==0||state.pointer)return;
        state.pointer={id:e.pointerId,g};g.setPointerCapture(e.pointerId);g.focus({preventScroll:true});fromPointer(e);
      });
      g.addEventListener('pointermove',e=>{if(state.pointer?.g===g&&state.pointer.id===e.pointerId)fromPointer(e);});
      const end=e=>{
        if(state.pointer?.g!==g||state.pointer.id!==e.pointerId)return;
        if(e.type==='pointerup')fromPointer(e);state.pointer=null;
        if(g.hasPointerCapture(e.pointerId))g.releasePointerCapture(e.pointerId);
      };
      g.addEventListener('pointerup',end);g.addEventListener('pointercancel',end);
      g.addEventListener('lostpointercapture',()=>{if(state.pointer?.g===g)state.pointer=null;});
      g.addEventListener('keydown',e=>{
        let v;
        if(e.key==='Home')v=0;else if(e.key==='End')v=100;
        else if(e.key==='ArrowRight'||e.key==='ArrowUp')v=state.value+(e.shiftKey?10:.1);
        else if(e.key==='ArrowLeft'||e.key==='ArrowDown')v=state.value-(e.shiftKey?10:.1);
        else return;e.preventDefault();set(state,v);
      });
    }
    state.input.addEventListener('input',()=>set(state,Number(state.input.value)));
    state.input.addEventListener('pointerdown',()=>stop(state));
    state.input.addEventListener('keydown',()=>stop(state));
  }
  let demoIndex=0;
  card.querySelector('[data-demo]').addEventListener('click',()=>{
    demoIndex=(demoIndex+1)%demos.length;
    states.forEach((state,i)=>{
      const target=demos[demoIndex][i];
      if(reduced.matches){state.tween=null;state.value=target;}
      else state.tween={from:state.value,target,start:performance.now()};
    });renderAll();wake();
  });
  reduced.addEventListener('change',()=>{
    if(reduced.matches)states.forEach(state=>{if(state.tween){state.value=state.tween.target;state.tween=null;}});
    renderAll();wake();
  });
  document.addEventListener('visibilitychange',wake);
  if(typeof IntersectionObserver!=='undefined')new IntersectionObserver(entries=>{
    inView=entries[0].isIntersecting;wake();
  }).observe(card);
  renderAll();wake();
})();
