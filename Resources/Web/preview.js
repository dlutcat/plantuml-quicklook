/* Inspired by plantuml-for-github's TeaVM renderer and DOM-settle protocol (MIT). */
(function () {
  'use strict';
  const output = document.getElementById('output');
  const sourceView = document.getElementById('source');
  const status = document.getElementById('status');
  const selector = document.getElementById('diagrams');
  const toggle = document.getElementById('source-toggle');
  const download = document.getElementById('download');
  const exportFormat = document.getElementById('export-format');
  let diagrams = [], busy = false, showingSource = false;
  let rendered = null, exporting = false, filename = '', renderStatus = '';

  function send(message) { window.webkit?.messageHandlers?.preview?.postMessage(message); }
  function updateControls() {
    selector.disabled = busy || exporting;
    download.disabled = exportFormat.disabled = busy || exporting || !rendered;
  }
  function error(message) {
    rendered = null; updateControls();
    output.replaceChildren();
    const node = document.createElement('div');
    node.className = 'error'; node.textContent = message;
    output.append(node); status.textContent = '无法渲染 · 可切换查看源码';
    send({ type: 'result', ok: false, error: message });
  }

  function stripActiveContent(svg) {
    svg.querySelectorAll('script, foreignObject, iframe, object, embed').forEach(n => n.remove());
    for (const node of [svg, ...svg.querySelectorAll('*')]) {
      for (const attr of [...node.attributes]) {
        const name = attr.name.toLowerCase();
        if (name.startsWith('on') || ((name === 'href' || name === 'xlink:href') &&
          !attr.value.startsWith('#') && !/^data:image\/(?:png|jpeg|gif|webp);base64,/i.test(attr.value))) {
          node.removeAttribute(attr.name);
        }
      }
    }
  }

  async function renderSelected() {
    if (busy || exporting) return;
    busy = true; rendered = null; updateControls();
    send({ type: 'rendering' });
    output.replaceChildren();
    status.textContent = '正在本地渲染…';
    const started = performance.now();
    try {
      const diagram = diagrams[Number(selector.value) || 0];
      PlantUMLSource.validateIncludes(diagram.source);
      const svg = await new Promise((resolve, reject) => {
        let settle;
        const cleanup = () => { observer.disconnect(); clearTimeout(settle); clearTimeout(deadline); };
        const observer = new MutationObserver(() => {
          const svg = output.querySelector('svg');
          if (!svg) return;
          clearTimeout(settle);
          settle = setTimeout(() => { cleanup(); resolve(svg); }, 150);
        });
        observer.observe(output, { childList: true, subtree: true, attributes: true, characterData: true });
        const deadline = setTimeout(() => { cleanup(); reject(new Error('渲染超过 20 秒，请简化图表后重试。')); }, 20000);
        try { PlantUMLEngine.render(diagram.source.split('\n'), 'output', { dark: matchMedia('(prefers-color-scheme: dark)').matches }); }
        catch (e) { cleanup(); reject(e); }
      });
      stripActiveContent(svg);
      const text = svg.textContent || '';
      const syntaxError = /syntax error|fatal parsing error|error line\s*\d/i.test(text);
      const dimensions = svg.getAttribute('viewBox')?.split(/[ ,]+/).map(Number);
      const width = dimensions?.[2] || parseFloat(svg.getAttribute('width')) || svg.getBoundingClientRect().width;
      const height = dimensions?.[3] || parseFloat(svg.getAttribute('height')) || svg.getBoundingClientRect().height;
      if (!syntaxError) rendered = { svg, width, height, index: Number(selector.value) || 0 };
      renderStatus = status.textContent = syntaxError ? 'PlantUML 语法错误 · 可查看源码' : `${Math.round(width)} × ${Math.round(height)} · ${Math.round(performance.now() - started)} ms`;
      send({ type: 'result', ok: !syntaxError, error: syntaxError ? 'PlantUML syntax error' : '', width, height, text, diagrams: diagrams.length });
    } catch (e) { error(String(e.message || e)); }
    finally { busy = false; updateControls(); }
  }

  async function prepareExport(format) {
    if (busy || !rendered) throw new Error('请等待图表成功渲染后再下载。');
    if (!['png', 'svg'].includes(format)) throw new Error('不支持的图片格式。');
    const { svg, width, height, index } = rendered;
    if (![width, height].every(n => Number.isFinite(n) && n > 0)) throw new Error('图表尺寸无效。');
    // Export intrinsic dimensions, independent of fit-to-window, zoom or source view.
    const copy = svg.cloneNode(true);
    copy.setAttribute('width', width); copy.setAttribute('height', height);
    const content = new XMLSerializer().serializeToString(copy);
    const base = filename.replace(/\.[^.]+$/, '') || 'PlantUML';
    const name = `${base}${diagrams.length > 1 ? '-' + (index + 1) : ''}.${format}`;
    if (format === 'svg') return { format, filename: name, content };

    // Use 2x resolution for ordinary diagrams; bound memory for very large ones.
    const scale = Math.min(2, 16384 / width, 16384 / height, Math.sqrt(16000000 / (width * height)));
    const canvas = document.createElement('canvas');
    canvas.width = Math.max(1, Math.floor(width * scale));
    canvas.height = Math.max(1, Math.floor(height * scale));
    const context = canvas.getContext('2d');
    if (!context) throw new Error('无法创建 PNG 图片，请尝试 SVG 格式。');
    const image = new Image();
    await new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error('生成 PNG 超时，请尝试 SVG 格式。')), 10000);
      image.onload = () => { clearTimeout(timer); resolve(); };
      image.onerror = () => { clearTimeout(timer); reject(new Error('生成 PNG 失败，请尝试 SVG 格式。')); };
      image.src = 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(content);
    });
    // Keep text legible when the PNG is viewed on a different system appearance.
    context.fillStyle = getComputedStyle(document.body).backgroundColor;
    context.fillRect(0, 0, canvas.width, canvas.height);
    context.drawImage(image, 0, 0, canvas.width, canvas.height);
    const dataURL = canvas.toDataURL('image/png');
    if (!dataURL.startsWith('data:image/png;base64,')) throw new Error('生成 PNG 失败，请尝试 SVG 格式。');
    return { format, filename: name, content: dataURL.slice('data:image/png;base64,'.length) };
  }

  function exportFinished(message) {
    exporting = false; updateControls();
    status.textContent = message || renderStatus;
  }

  window.preview = {
    load(source, name) {
      filename = name;
      sourceView.textContent = source; document.title = filename;
      try {
        diagrams = PlantUMLSource.splitDiagrams(source);
        selector.replaceChildren(...diagrams.map((d, i) => { const o = document.createElement('option'); o.value = i; o.textContent = d.title; return o; }));
        selector.hidden = diagrams.length < 2;
        renderSelected();
      } catch (e) { error(e.message); }
    },
    prepareExport,
    exportFinished,
    svg() { const svg = output.querySelector('svg'); return svg ? new XMLSerializer().serializeToString(svg) : ''; },
    select(index) { selector.value = index; return renderSelected(); }
  };
  document.getElementById('fit').onclick = () => output.classList.add('fit');
  document.getElementById('actual').onclick = () => output.classList.remove('fit');
  toggle.onclick = () => {
    showingSource = !showingSource;
    sourceView.hidden = !showingSource; output.hidden = showingSource;
    toggle.textContent = showingSource ? '查看图表' : '查看源码';
    toggle.setAttribute('aria-pressed', String(showingSource));
  };
  selector.onchange = renderSelected;
  download.onclick = async () => {
    if (download.disabled) return;
    exporting = true; updateControls();
    status.textContent = '正在生成图片…';
    try {
      const payload = await prepareExport(exportFormat.value);
      if (!window.webkit?.messageHandlers?.preview) throw new Error('请在 PlantUML Preview 中下载图片。');
      status.textContent = '请选择图片保存位置…';
      send({ type: 'export', ...payload });
    } catch (e) { exportFinished('下载失败：' + (e.message || e)); }
  };
  output.classList.add('fit');
  document.addEventListener('click', e => { if (e.target.closest('a')) e.preventDefault(); });
  send({ type: 'ready' });
})();
