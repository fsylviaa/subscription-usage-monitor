/* Six independent states; rendered value drives numbers, controls and SVG geometry. */
(() => {
  const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
  const clamp = value => Math.max(0, Math.min(100, value));
  const format = value => Number(value.toFixed(1)).toString();
  const demos = [[73, 50], [95, 82], [3, 1], [0, 100]];
  document.querySelectorAll('[data-prototype]').forEach(card => {
    const kind = card.dataset.prototype;
    const duration = {skala:300, capsule:450, ticks:220}[kind];
    const states = Array.from(card.querySelectorAll('.quota-window')).map(windowNode => {
      const key = windowNode.dataset.window;
      const graph = windowNode.querySelector('.quota-graph');
      const input = card.querySelector(`input[data-control="${key}"]`);
      const state = {value:Number(input.value), frame:0, target:Number(input.value), pointer:null};
      const clip = graph.querySelector('[data-used-clip]');
      const activePill = graph.querySelector('[data-pill]');
      const glow = graph.querySelector('[data-glow]');
      const accent = graph.querySelector('[data-accent]');
      const accentClip = graph.querySelector('[data-accent-clip]');
      let pillRadius = 18;
      function geometry() {
        const bounds = graph.getBoundingClientRect();
        if (!bounds.width || !bounds.height) return;
        pillRadius = 18 * (bounds.height / 80) / (bounds.width / 1000);
        graph.querySelectorAll('[data-track-pill]').forEach(pill => pill.setAttribute('rx', pillRadius));
        const angle = Math.atan((bounds.width / 1000) / (bounds.height / 80)) * 180 / Math.PI;
        graph.querySelectorAll('[data-grain]').forEach(grain => grain.setAttribute('transform', `rotate(${angle} ${grain.dataset.cx} ${grain.dataset.cy})`));
      }
      function render(value, pulse = 0, changed = null) {
        state.value = Math.round(clamp(value) * 10) / 10;
        const usedWidth = (100 - state.value) * 10;
        clip.setAttribute('width', usedWidth.toFixed(4));
        if (activePill) {
          activePill.setAttribute('width', usedWidth.toFixed(4));
          activePill.setAttribute('rx', Math.min(pillRadius, usedWidth / 2));
          glow.setAttribute('opacity', usedWidth === 0 ? 0 : .25 + pulse * .25);
        }
        if (accent) {
          accent.setAttribute('opacity', pulse * .45);
          const low = changed ? Math.min(...changed) : usedWidth;
          const high = changed ? Math.max(...changed) : usedWidth;
          accentClip.setAttribute('x', low);
          accentClip.setAttribute('width', high - low);
          if (kind === 'skala') accent.setAttribute('transform', `translate(0 ${-pulse * 2})`);
        }
        const displayed = format(state.value);
        windowNode.querySelector('[data-number]').textContent = `${displayed}%`;
        input.value = state.value.toFixed(1);
        card.querySelector(`output[data-output="${key}"]`).textContent = `${displayed}%`;
        graph.setAttribute('aria-valuenow', state.value.toFixed(1));
        graph.setAttribute('aria-valuetext', `剩余 ${displayed}%，已用 ${format(100-state.value)}%`);
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
        const changed = [(100-from)*10, (100-target)*10];
        const step = now => {
          const t = Math.min(1, (now-start)/duration);
          const eased = 1-Math.pow(1-t,3);
          render(from+(target-from)*eased, Math.sin(Math.PI*t), changed);
          state.frame = t < 1 ? requestAnimationFrame(step) : 0;
        };
        state.frame = requestAnimationFrame(step);
      }
      const fromPointer = event => {
        const bounds = graph.getBoundingClientRect();
        set(100 - clamp((event.clientX-bounds.left)/bounds.width*100));
      };
      graph.addEventListener('pointerdown', event => {
        if (!event.isPrimary || event.button !== 0) return;
        state.pointer = event.pointerId;
        graph.setPointerCapture(event.pointerId);
        graph.focus({preventScroll:true});
        fromPointer(event);
      });
      graph.addEventListener('pointermove', event => {
        if (state.pointer === event.pointerId) fromPointer(event);
      });
      const endPointer = event => {
        if (state.pointer !== event.pointerId) return;
        if (event.type === 'pointerup') fromPointer(event);
        state.pointer = null;
        if (graph.hasPointerCapture(event.pointerId)) graph.releasePointerCapture(event.pointerId);
      };
      graph.addEventListener('pointerup', endPointer);
      graph.addEventListener('pointercancel', endPointer);
      graph.addEventListener('lostpointercapture', () => {state.pointer=null;});
      graph.addEventListener('keydown', event => {
        let next;
        if (event.key === 'ArrowRight' || event.key === 'ArrowUp') next = state.value + (event.shiftKey ? 10 : .1);
        else if (event.key === 'ArrowLeft' || event.key === 'ArrowDown') next = state.value - (event.shiftKey ? 10 : .1);
        else if (event.key === 'Home') next = 0;
        else if (event.key === 'End') next = 100;
        else return;
        event.preventDefault();set(next);
      });
      input.addEventListener('input', () => set(Number(input.value)));
      // Grabbing a native slider interrupts an in-flight demo before its next frame.
      input.addEventListener('pointerdown', stop);
      input.addEventListener('keydown', stop);
      reducedMotion.addEventListener('change', () => {if (reducedMotion.matches && state.frame) set(state.target);});
      geometry();
      new ResizeObserver(() => {geometry();render(state.value);}).observe(graph);
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
