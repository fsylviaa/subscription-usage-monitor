/* Candidate 12 owns two values, shared by its light/dark views only. */
(() => {
  const card = document.querySelector('[data-watermark-prototype]');
  if (!card) return;
  const reduced = matchMedia('(prefers-reduced-motion: reduce)');
  const clamp = value => Math.max(0, Math.min(100, value));
  const format = value => Number(value.toFixed(1)).toString();
  const demos = [[73, 50], [95, 82], [3, 1], [0, 100]];
  const states = ['week', 'five'].map(key => {
    const input = card.querySelector(`[data-control="${key}"]`);
    const output = card.querySelector(`[data-output="${key}"]`);
    const state = {value:Number(input.value), target:Number(input.value), frame:0, pointer:null};
    const views = [...card.querySelectorAll(`.quota-window[data-window="${key}"]`)].map(windowNode => ({
      windowNode, graph:windowNode.querySelector('.quota-graph'),
      fill:windowNode.querySelector('[data-watermark-fill]'), radius:14,
    }));
    function render(value) {
      state.value = Math.round(clamp(value)*10)/10;
      const width = state.value*10;
      for (const view of views) {
        view.fill.setAttribute('width', width.toFixed(4));
        view.fill.setAttribute('rx', Math.min(view.radius, width/2));
        view.windowNode.querySelector('[data-number]').textContent = `${format(state.value)}%`;
        view.graph.setAttribute('aria-valuenow', state.value.toFixed(1));
        view.graph.setAttribute('aria-valuetext', `剩余 ${format(state.value)}%，已用 ${format(100-state.value)}%`);
      }
      input.value = state.value.toFixed(1);
      output.textContent = `${format(state.value)}%`;
    }
    function stop() {cancelAnimationFrame(state.frame);state.frame=0;state.target=state.value;}
    function set(value) {stop();render(value);}
    function animate(value) {
      stop();state.target=clamp(value);
      if (reduced.matches) {render(state.target);return;}
      const from=state.value, target=state.target, start=performance.now();
      const step = now => {
        const t=Math.min(1,(now-start)/380);
        render(from+(target-from)*(1-Math.pow(1-t,3)));
        state.frame=t<1?requestAnimationFrame(step):0;
      };
      state.frame=requestAnimationFrame(step);
    }
    for (const view of views) {
      const graph=view.graph;
      const geometry = () => {
        const matrix=graph.getScreenCTM();
        if (!matrix || !matrix.a || !matrix.d) return;
        view.radius=Math.min(500,14*Math.abs(matrix.d/matrix.a));
        graph.querySelectorAll('[data-watermark-track]').forEach(track => track.setAttribute('rx',view.radius));
        render(state.value);
      };
      const fromPointer = event => {
        const matrix=graph.getScreenCTM();
        if (!matrix) return;
        const point=new DOMPoint(event.clientX,event.clientY).matrixTransform(matrix.inverse());
        set(point.x/1000*100);
      };
      graph.addEventListener('pointerdown', event => {
        if (!event.isPrimary || event.button!==0 || state.pointer) return;
        state.pointer={graph,id:event.pointerId};
        graph.setPointerCapture(event.pointerId);graph.focus({preventScroll:true});fromPointer(event);
      });
      graph.addEventListener('pointermove', event => {
        if(state.pointer?.graph===graph && state.pointer.id===event.pointerId) fromPointer(event);
      });
      const endPointer = event => {
        if(state.pointer?.graph!==graph || state.pointer.id!==event.pointerId) return;
        if(event.type==='pointerup') fromPointer(event);
        state.pointer=null;
        if(graph.hasPointerCapture(event.pointerId)) graph.releasePointerCapture(event.pointerId);
      };
      graph.addEventListener('pointerup',endPointer);graph.addEventListener('pointercancel',endPointer);
      graph.addEventListener('lostpointercapture',() => {if(state.pointer?.graph===graph)state.pointer=null;});
      graph.addEventListener('keydown', event => {
        let value;
        if(event.key==='Home')value=0;else if(event.key==='End')value=100;
        else if(event.key==='ArrowRight'||event.key==='ArrowUp')value=state.value+(event.shiftKey?10:.1);
        else if(event.key==='ArrowLeft'||event.key==='ArrowDown')value=state.value-(event.shiftKey?10:.1);
        else return;
        event.preventDefault();set(value);
      });
      geometry();new ResizeObserver(geometry).observe(graph);
    }
    input.addEventListener('input',() => set(Number(input.value)));
    input.addEventListener('pointerdown',stop);input.addEventListener('keydown',stop);
    reduced.addEventListener('change',() => {if(reduced.matches && state.frame)set(state.target);});
    render(state.value);
    return {animate};
  });
  let demoIndex=0;
  card.querySelector('[data-demo]').addEventListener('click',() => {
    demoIndex=(demoIndex+1)%demos.length;
    states.forEach((state,index) => state.animate(demos[demoIndex][index]));
  });
})();
