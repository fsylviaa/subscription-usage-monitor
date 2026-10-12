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
