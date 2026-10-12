// R4 local Figma author helper. This file never contacts a scoring service.
// The caller supplies a reviewed outcome before building a branch; outcome
// selectors belong to the design-review index, never to a product frame.
//
// env.panel(name, title, lines, buttonLabels, source, mode) -> Frame | Promise<Frame>
// env.go(node, destinationFrame, { timeout?: seconds, smart?: boolean })
// env.button(frame, label) -> SceneNode
// env.status(frame, text, phase) -> void | Promise<void>
// env.t -> 'Light' | 'Dark'
//
// Result: start, passed, and result are Frames; passed is null for a failed
// first attempt. retry is null or a successful retry-flow result. frames
// contains every generated Frame, including the retry sequence.
async function buildNetworkFlow(env, cfg) {
  const allowedOutcomes = ['51', '49', '50', 'timeout', 'unavailable', 'invalid'];
  const allowedModes = ['foreground', 'background', 'widget'];
  if (!cfg || !cfg.key || !cfg.source || !cfg.next || !cfg.operation) {
    throw new Error('Network flow requires key, source, next, and operation.');
  }
  if (!allowedOutcomes.includes(cfg.outcome) || !allowedModes.includes(cfg.mode)) {
    throw new Error('Unrecognized network outcome or presentation mode.');
  }
  for (const name of ['panel', 'go', 'button', 'status']) {
    if (typeof env[name] !== 'function') throw new Error('Missing network helper: ' + name);
  }

  const prefix = env.t + ' · R4 NET · ' + cfg.key;
  const mode = cfg.mode;
  const frames = [];
  const dismiss = mode === 'foreground' ? '取消' : mode === 'widget' ? '返回' : '关闭';
  const checkingTitle = mode === 'foreground' ? '正在检查网络' : '更新前检查网络';
  const checkingLines = [cfg.operation, 'Net.Coffee · Claude AI 信任评分'];
  const make = async (suffix, title, lines, labels) => {
    const frame = await env.panel(prefix + ' · ' + suffix, title, lines, labels, cfg.source, mode);
    frames.push(frame);
    return frame;
  };
  const connectButton = async (frame, label, destination) => {
    const target = env.button(frame, label);
    if (!target) throw new Error('Network frame missing button: ' + label);
    await env.go(target, destination, { smart: false });
  };

  // Equivalent layers and phase-based opacity allow a restrained Smart Animate
  // transition. The status helper owns the three-dot treatment and colors.
  const start = await make('检查中 A', checkingTitle, checkingLines, [dismiss]);
  const checkingB = await make('检查中 B', checkingTitle, checkingLines, [dismiss]);
  await env.status(start, '正在检查网络', 0);
  await env.status(checkingB, '正在检查网络', 1);
  await connectButton(start, dismiss, cfg.source);
  await connectButton(checkingB, dismiss, cfg.source);
  await env.go(start, checkingB, { timeout: 0.45, smart: true });

  let passed = null;
  let result = null;
  let retry = null;
  if (cfg.outcome === '51') {
    passed = await make('评分 51 · 检查通过', '网络检查通过', [
      '当前评分 51，符合高于 50 的通过条件',
      '继续' + cfg.operation,
    ], []);
    result = passed;
    await env.status(passed, '检查通过', 2);
    await env.go(checkingB, passed, { timeout: 0.55, smart: true });
    // The destination is deliberately an authorization/query-in-progress
    // frame. A passed gate does not itself report a successful quota update.
    await env.go(passed, cfg.next, { timeout: 0.35, smart: false });
  } else {
    const low = cfg.outcome === '49' || cfg.outcome === '50';
    const reason = {
      timeout: '检查超时，无法完成网络检查',
      unavailable: '评分网站暂不可用，无法完成网络检查',
      invalid: '未取得有效评分，无法完成网络检查',
    };
    const title = low ? '网络评分未达标' : '网络检查失败';
    const lines = low ? [
      '当前评分 ' + cfg.outcome + '，需高于 50 才能继续',
      '网络评分未达通过条件，已阻止' + cfg.operation,
    ] : [
      reason[cfg.outcome],
      '尚未执行' + cfg.operation,
    ];
    result = await make(low ? '有效评分 ' + cfg.outcome + ' · 已阻止' : cfg.outcome + ' · 无法完成检查', title, lines, ['重试', dismiss]);
    await env.status(result, mode === 'foreground' ? title : '未更新 · ' + title, 3);
    await env.go(checkingB, result, { timeout: 0.55, smart: false });
    await connectButton(result, dismiss, cfg.source);

    // Every retry repeats the gate. This review branch models a subsequent
    // valid score of 51, then resumes the original operation and account scope.
    retry = await buildNetworkFlow(env, {
      key: cfg.key + ' · 重试',
      source: cfg.source,
      next: cfg.retryNext || cfg.next,
      outcome: '51',
      mode,
      operation: cfg.operation,
    });
    await connectButton(result, '重试', retry.start);
    frames.push(...retry.frames);
  }
  return { start, passed, result, retry, frames };
}
