/* Six independent remaining values. Each value renders into both theme variants. */
(() => {
  const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
  const clamp = value => Math.max(0, Math.min(100, value));
  const format = value => Number(value.toFixed(1)).toString();
  const demos = [[73, 50], [95, 82], [3, 1], [0, 100]];
  document.querySelectorAll('[data-prototype]').forEach(card => {
    const kind = card.dataset.prototype;
    const duration = {skala:300, capsule:450, ticks:220}[kind];
    const states = ['week', 'five'].map(key => {
      const input = card.querySelector(`input[data-control="${key}"]`);
      const state = {value:Number(input.value), frame:0, target:Number(input.value), pointer:null};
      const views = Array.from(card.querySelectorAll(`.quota-window[data-window="${key}"]`)).map(windowNode => {
        const graph = windowNode.querySelector('.quota-graph');
        return {windowNode, graph, clip:graph.querySelector('[data-remaining-clip]'),
          pill:graph.querySelector('[data-pill]'), glow:graph.querySelector('[data-glow]'),
          accent:graph.querySelector('[data-accent]'), accentClip:graph.querySelector('[data-accent-clip]'), radius:18};
      });
      function geometry(view) {
        const bounds = view.graph.getBoundingClientRect();
        if (!bounds.width || !bounds.height) return;
        view.radius = 18 * (bounds.height / 80) / (bounds.width / 1000);
        view.graph.querySelectorAll('[data-track-pill]').forEach(pill => pill.setAttribute('rx', view.radius));
        const angle = Math.atan((bounds.width / 1000) / (bounds.height / 80)) * 180 / Math.PI;
        view.graph.querySelectorAll('[data-grain]').forEach(grain => grain.setAttribute('transform', `rotate(${angle} ${grain.dataset.cx} ${grain.dataset.cy})`));
      }
      function render(value, pulse = 0, changed = null) {
        state.value = Math.round(clamp(value) * 10) / 10;
        const remainingWidth = state.value * 10;
        const displayed = format(state.value);
        views.forEach(view => {
          view.clip.setAttribute('width', remainingWidth.toFixed(4));
          if (view.pill) {
            view.pill.setAttribute('width', remainingWidth.toFixed(4));
            view.pill.setAttribute('rx', Math.min(view.radius, remainingWidth / 2));
            view.glow.setAttribute('opacity', remainingWidth === 0 ? 0 : .25 + pulse * .25);
          }
          if (view.accent) {
            view.accent.setAttribute('opacity', pulse * .45);
            const low = changed ? Math.min(...changed) : remainingWidth;
            const high = changed ? Math.max(...changed) : remainingWidth;
            view.accentClip.setAttribute('x', low);
            view.accentClip.setAttribute('width', high - low);
            if (kind === 'skala') view.accent.setAttribute('transform', `translate(0 ${-pulse * 2})`);
          }
          view.windowNode.querySelector('[data-number]').textContent = `${displayed}%`;
          view.graph.setAttribute('aria-valuenow', state.value.toFixed(1));
          view.graph.setAttribute('aria-valuetext', `剩余 ${displayed}%，已用 ${format(100-state.value)}%`);
        });
        input.value = state.value.toFixed(1);
        card.querySelector(`output[data-output="${key}"]`).textContent = `${displayed}%`;
      }
      function stop() {
        cancelAnimationFrame(state.frame);
        state.frame = 0;
        state.target = state.value;
        render(state.value);
      }
      function set(value) {stop();render(value);}
      function animate(value) {
        stop();
        state.target = clamp(value);
        if (reducedMotion.matches) {render(state.target);return;}
        const from = state.value, target = state.target, start = performance.now();
        const changed = [from*10, target*10];
        const step = now => {
          const t = Math.min(1, (now-start)/duration);
          const eased = 1-Math.pow(1-t,3);
          render(from+(target-from)*eased, t < 1 ? Math.sin(Math.PI*t) : 0, changed);
          state.frame = t < 1 ? requestAnimationFrame(step) : 0;
        };
        state.frame = requestAnimationFrame(step);
      }
      views.forEach(view => {
        const graph = view.graph;
        const fromPointer = event => {
          const bounds = graph.getBoundingClientRect();
          set(clamp((event.clientX-bounds.left)/bounds.width*100));
        };
        graph.addEventListener('pointerdown', event => {
          if (!event.isPrimary || event.button !== 0 || state.pointer) return;
          state.pointer = {view, id:event.pointerId};
          graph.setPointerCapture(event.pointerId);
          graph.focus({preventScroll:true});
          fromPointer(event);
        });
        graph.addEventListener('pointermove', event => {
          if (state.pointer?.view === view && state.pointer.id === event.pointerId) fromPointer(event);
        });
        const endPointer = event => {
          if (state.pointer?.view !== view || state.pointer.id !== event.pointerId) return;
          if (event.type === 'pointerup') fromPointer(event);
          state.pointer = null;
          if (graph.hasPointerCapture(event.pointerId)) graph.releasePointerCapture(event.pointerId);
        };
        graph.addEventListener('pointerup', endPointer);
        graph.addEventListener('pointercancel', endPointer);
        graph.addEventListener('lostpointercapture', () => {if (state.pointer?.view === view) state.pointer=null;});
        graph.addEventListener('keydown', event => {
          let next;
          if (event.key === 'ArrowRight' || event.key === 'ArrowUp') next = state.value + (event.shiftKey ? 10 : .1);
          else if (event.key === 'ArrowLeft' || event.key === 'ArrowDown') next = state.value - (event.shiftKey ? 10 : .1);
          else if (event.key === 'Home') next = 0;
          else if (event.key === 'End') next = 100;
          else return;
          event.preventDefault();set(next);
        });
        geometry(view);
        new ResizeObserver(() => {geometry(view);render(state.value);}).observe(graph);
      });
      input.addEventListener('input', () => set(Number(input.value)));
      input.addEventListener('pointerdown', stop);
      input.addEventListener('keydown', stop);
      reducedMotion.addEventListener('change', () => {if (reducedMotion.matches && state.frame) set(state.target);});
      render(state.value);
      return {animate};
    });
    let demoIndex = 0;
    card.querySelector('[data-demo]').addEventListener('click', () => {
      demoIndex = (demoIndex+1)%demos.length;
      states.forEach((state,index) => state.animate(demos[demoIndex][index]));
    });
  });
})();

/* Selected 4–11: separate scope preserves the confirmed 1–3 interactions. */
(() => {
  const reduced = matchMedia('(prefers-reduced-motion: reduce)');
  const clamp = v => Math.max(0, Math.min(100, v));
  const format = v => Number(v.toFixed(1)).toString();
  const demos = [[73,50],[95,82],[3,1],[0,100]];
  const durations = {dials:700,island:540,blocks:420,liquid:1050,ticket:280,journal:650,glass:750,panels:480};
  document.querySelectorAll('[data-extra-prototype]').forEach(card => {
    const kind = card.dataset.extraPrototype;
    if (kind === 'liquid') return; // Candidate 7 now has its own horizontal liquid controller.
    const states = ['week','five'].map(key => {
      const input = card.querySelector(`input[data-control="${key}"]`);
      const state = {value:Number(input.value),target:Number(input.value),frame:0,pointer:null};
      const views = [...card.querySelectorAll(`.quota-window[data-window="${key}"]`)];
      function render(value, pulse=0, changed=null) {
        state.value = Math.round(clamp(value)*10)/10;
        const v=state.value, width=v*10;
        for (const view of views) {
          const g=view.querySelector('.quota-graph');
          g.dataset.remaining=v.toFixed(1);
          g.setAttribute('aria-valuenow',v.toFixed(1));
          g.setAttribute('aria-valuetext',`剩余 ${format(v)}%，已用 ${format(100-v)}%`);
          view.querySelector('[data-number]').textContent=`${format(v)}%`;
          g.querySelector('[data-extra-clip]')?.setAttribute('width',width.toFixed(4));
          const change=g.querySelector('[data-extra-change]');
          if(change){change.setAttribute('x',changed?Math.min(...changed):width);change.setAttribute('width',changed?Math.abs(changed[1]-changed[0]):0);}
          g.querySelector('[data-extra-accent]')?.setAttribute('opacity',pulse*.6);
          if(kind==='dials'){
            g.querySelectorAll('[data-dial-fill]').forEach(a=>a.setAttribute('stroke-dasharray',`${v} 100`));
            g.querySelector('[data-needle]').setAttribute('transform',`rotate(${135+v*2.7} 120 116)`);
            g.querySelector('[data-needle]').setAttribute('opacity',v===0?.4:1);
          } else if(kind==='liquid') {
            const y=220-v*2;
            // Two mirrored cubic waves have zero net area. Peaks stay inside both endpoints.
            const a=reduced.matches?0:Math.min(1.2+pulse*1.6,v*2,(100-v)*2);
            const path=`M28 ${y} C45.3333 ${y-a} 62.6667 ${y-a} 80 ${y} C97.3333 ${y+a} 114.6667 ${y+a} 132 ${y}`;
            const d=`${path} V220 H28 Z`;
            g.querySelector('[data-liquid]').setAttribute('d',d);
            g.querySelector('[data-liquid-clip]').setAttribute('d',d);
            g.querySelector('[data-meniscus]').setAttribute('d',path);
            g.querySelector('[data-meniscus]').setAttribute('opacity',v===0||v===100?0:.65);
          } else if(kind==='island') {
            const tip=g.querySelector('[data-boundary]');
            tip.setAttribute('x1',width);tip.setAttribute('x2',width);tip.setAttribute('opacity',v===0?0:1);
            g.querySelector('[data-island-light]').setAttribute('opacity',pulse*.6);
          } else if(kind==='journal') {
            g.querySelector('[data-journal-ink]').setAttribute('opacity',pulse*.32);
          } else if(kind==='glass') {
            const cap=g.querySelector('[data-glass-cap]');
            cap.setAttribute('x',width-16);cap.setAttribute('opacity',v===0?0:.65+pulse*.2);
            g.querySelector('[data-glass-spark]').setAttribute('opacity',.25+pulse*.4);
          }
        }
        input.value=v.toFixed(1);
        card.querySelector(`[data-output="${key}"]`).textContent=`${format(v)}%`;
      }
      function stop(){cancelAnimationFrame(state.frame);state.frame=0;state.target=state.value;render(state.value);}
      function set(v){stop();render(v);}
      function animate(target){
        stop();state.target=clamp(target);
        if(reduced.matches){render(state.target);return;}
        const from=state.value,start=performance.now(),changed=[from*10,target*10];
        const step=now=>{
          const t=Math.min(1,(now-start)/durations[kind]);
          const ease=1-Math.pow(1-t,3);
          render(from+(target-from)*ease,t<1?Math.sin(Math.PI*t):0,changed);
          state.frame=t<1?requestAnimationFrame(step):0;
        };
        state.frame=requestAnimationFrame(step);
      }
      views.forEach(view=>{
        const g=view.querySelector('.quota-graph');
        const fromPointer=e=>{
          // Inverse SVG transform accounts for letterboxing, responsive sizing and viewBox margins.
          const matrix=g.getScreenCTM();if(!matrix)return;
          const point=new DOMPoint(e.clientX,e.clientY).matrixTransform(matrix.inverse());
          let v;
          if(kind==='dials'){
            const delta=(Math.atan2(point.y-116,point.x-120)*180/Math.PI-135+720)%360;
            v=delta<=270?delta/270*100:(delta<315?100:0);
          }else if(kind==='liquid')v=(220-point.y)/200*100;
          else v=point.x/1000*100;
          set(clamp(v));
        };
        if(kind==='glass'){
          const geometry=()=>{
            const m=g.getScreenCTM();if(!m||!m.a||!m.d)return;
            const radius=Math.min(500,40*Math.abs(m.d/m.a));
            g.querySelectorAll('[data-tube-pill]').forEach(p=>p.setAttribute('rx',radius));
          };
          geometry();new ResizeObserver(geometry).observe(g);
        }
        g.addEventListener('pointerdown',e=>{
          if(!e.isPrimary||e.button!==0||state.pointer)return;
          state.pointer={id:e.pointerId,g};g.setPointerCapture(e.pointerId);g.focus({preventScroll:true});fromPointer(e);
        });
        g.addEventListener('pointermove',e=>{if(state.pointer?.g===g&&state.pointer.id===e.pointerId)fromPointer(e);});
        const end=e=>{
          if(state.pointer?.g!==g||state.pointer.id!==e.pointerId)return;
          if(e.type==='pointerup')fromPointer(e);
          state.pointer=null;if(g.hasPointerCapture(e.pointerId))g.releasePointerCapture(e.pointerId);
        };
        g.addEventListener('pointerup',end);g.addEventListener('pointercancel',end);
        g.addEventListener('lostpointercapture',()=>{if(state.pointer?.g===g)state.pointer=null;});
        g.addEventListener('keydown',e=>{
          let v;
          if(e.key==='Home')v=0;else if(e.key==='End')v=100;
          else if(e.key==='ArrowRight'||e.key==='ArrowUp')v=state.value+(e.shiftKey?10:.1);
          else if(e.key==='ArrowLeft'||e.key==='ArrowDown')v=state.value-(e.shiftKey?10:.1);
          else return;
          e.preventDefault();set(v);
        });
      });
      input.addEventListener('input',()=>set(Number(input.value)));
      input.addEventListener('pointerdown',stop);input.addEventListener('keydown',stop);
      reduced.addEventListener('change',()=>{if(reduced.matches&&state.frame)set(state.target);else render(state.value);});
      render(state.value);
      return {animate};
    });
    let demoIndex=0;
    card.querySelector('[data-demo]').addEventListener('click',()=>{
      demoIndex=(demoIndex+1)%demos.length;
      states.forEach((state,i)=>state.animate(demos[demoIndex][i]));
    });
  });
})();
