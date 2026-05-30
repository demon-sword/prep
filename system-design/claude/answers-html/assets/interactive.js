/**
 * Shared interactive study UI for system-design answer pages.
 * Auto-structures Q&A articles into tabs, study mode, and progress tracking.
 */
(function () {
  const STORAGE_PREFIX = 'sd-answers-studied-';

  function getPageKey() {
    return location.pathname.split('/').pop() || 'index';
  }

  function loadStudied() {
    try {
      return JSON.parse(localStorage.getItem(STORAGE_PREFIX + getPageKey()) || '{}');
    } catch {
      return {};
    }
  }

  function saveStudied(map) {
    localStorage.setItem(STORAGE_PREFIX + getPageKey(), JSON.stringify(map));
  }

  function extractSoundBite(article) {
    const firstP = article.querySelector('p');
    if (!firstP) return 'Focus on problem framing, concrete approach, and known pitfalls.';
    const text = firstP.textContent.replace(/^Problem framing:\s*/i, '').trim();
    const sentence = text.split(/(?<=[.!?])\s+/)[0];
    return sentence.length > 180 ? sentence.slice(0, 177) + '…' : sentence;
  }

  function getMermaidSource(el) {
    if (el?.dataset?.mermaidSource) return el.dataset.mermaidSource;
    const pre = el.matches?.('pre.mermaid')
      ? el
      : el.querySelector?.('pre.mermaid');
    const div = el.matches?.('div.mermaid')
      ? el
      : el.querySelector?.('div.mermaid');
    const text = (pre || div)?.textContent?.trim();
    if (text) return text;
    return el.dataset?.mermaidSource || '';
  }

  function cloneMermaidWrap(el) {
    const source = getMermaidSource(el);
    const wrap = document.createElement('div');
    wrap.className = 'mermaid-wrap';
    if (source) wrap.dataset.mermaidSource = source;
    const node = document.createElement('pre');
    node.className = 'mermaid';
    node.textContent = source;
    wrap.appendChild(node);
    return wrap;
  }

  function cloneMermaidElement(el) {
    if (el.classList.contains('mermaid-wrap')) return cloneMermaidWrap(el);
    if (el.classList.contains('mermaid')) {
      const source = getMermaidSource(el);
      const wrap = document.createElement('div');
      wrap.className = 'mermaid-wrap';
      if (source) wrap.dataset.mermaidSource = source;
      const node = document.createElement(el.tagName === 'PRE' ? 'pre' : 'div');
      node.className = 'mermaid';
      node.textContent = source;
      wrap.appendChild(node);
      return wrap;
    }
    return el.cloneNode(true);
  }

  function groupContent(article) {
    const panels = {
      problem: [],
      approach: [],
      tradeoffs: [],
      extra: []
    };
    let current = 'problem';
    const children = [...article.children].filter(
      (el) => !el.classList.contains('question') && !el.classList.contains('qa-toolbar')
    );

    for (const el of children) {
      if (el.classList.contains('demo-panel') || el.classList.contains('sound-bite') ||
          el.classList.contains('qa-tabs') || el.classList.contains('qa-body') ||
          el.classList.contains('flashcard-cover')) {
        continue;
      }
      if (el.classList.contains('mermaid-wrap') ||
          (el.classList.contains('mermaid') && (el.tagName === 'PRE' || el.tagName === 'DIV'))) {
        panels[current].push(cloneMermaidElement(el));
        continue;
      }
      const strong = el.querySelector(':scope > strong') || (el.tagName === 'P' && el.querySelector('strong'));
      const label = strong ? strong.textContent.replace(/:$/, '').trim().toLowerCase() : '';

      if (/problem framing/.test(label)) current = 'problem';
      else if (/approach/.test(label)) current = 'approach';
      else if (/tradeoff|pitfall|concrete|when to pick|libraries/.test(label)) current = 'tradeoffs';
      else if (/^h2|^h3/.test(el.tagName)) current = 'extra';

      panels[current].push(el.cloneNode(true));
    }
    return panels;
  }

  function buildTabs(article, panels) {
    const tabDefs = [
      { id: 'problem', label: 'Problem', items: panels.problem },
      { id: 'approach', label: 'Approach', items: panels.approach },
      { id: 'tradeoffs', label: 'Tradeoffs', items: panels.tradeoffs }
    ].filter((t) => t.items.length > 0);

    if (tabDefs.length <= 1) return null;

    const tabsEl = document.createElement('div');
    tabsEl.className = 'qa-tabs';
    tabsEl.setAttribute('role', 'tablist');

    const bodyEl = document.createElement('div');
    bodyEl.className = 'qa-body';

    tabDefs.forEach((tab, i) => {
      const btn = document.createElement('button');
      btn.type = 'button';
      btn.className = 'qa-tab';
      btn.textContent = tab.label;
      btn.setAttribute('role', 'tab');
      btn.setAttribute('aria-selected', i === 0 ? 'true' : 'false');
      btn.dataset.panel = tab.id;

      const panel = document.createElement('div');
      panel.className = 'qa-tab-panel' + (i === 0 ? ' is-visible' : '');
      panel.id = `${article.id}-${tab.id}`;
      panel.setAttribute('role', 'tabpanel');
      tab.items.forEach((node) => panel.appendChild(node));

      btn.addEventListener('click', () => {
        tabsEl.querySelectorAll('.qa-tab').forEach((b) => b.setAttribute('aria-selected', 'false'));
        bodyEl.querySelectorAll('.qa-tab-panel').forEach((p) => p.classList.remove('is-visible'));
        btn.setAttribute('aria-selected', 'true');
        panel.classList.add('is-visible');
        renderMermaidIn(panel);
      });

      tabsEl.appendChild(btn);
      bodyEl.appendChild(panel);
    });

    return { tabsEl, bodyEl };
  }

  function enhanceArticle(article, studiedMap) {
    if (article.dataset.enhanced) return;
    article.dataset.enhanced = '1';

    const id = article.id || `qa-${Math.random().toString(36).slice(2, 8)}`;
    article.id = id;

    const toolbar = document.createElement('div');
    toolbar.className = 'qa-toolbar';

    const checkLabel = document.createElement('label');
    checkLabel.className = 'study-check';
    const checkbox = document.createElement('input');
    checkbox.type = 'checkbox';
    checkbox.checked = !!studiedMap[id];
    if (studiedMap[id]) article.classList.add('studied');
    checkLabel.appendChild(checkbox);
    checkLabel.appendChild(document.createTextNode(' Mark as studied'));

    checkbox.addEventListener('change', () => {
      studiedMap[id] = checkbox.checked;
      article.classList.toggle('studied', checkbox.checked);
      saveStudied(studiedMap);
      updateProgress();
    });

    const modeBtns = document.createElement('div');
    modeBtns.className = 'qa-mode-btns';
    ['Full', 'Flashcard'].forEach((mode) => {
      const btn = document.createElement('button');
      btn.type = 'button';
      btn.className = 'qa-mode-btn' + (mode === 'Full' ? ' is-active' : '');
      btn.textContent = mode;
      btn.dataset.mode = mode.toLowerCase();
      btn.addEventListener('click', () => {
        modeBtns.querySelectorAll('.qa-mode-btn').forEach((b) => b.classList.remove('is-active'));
        btn.classList.add('is-active');
        if (mode === 'Flashcard') {
          article.classList.add('flashcard-mode');
          article.classList.remove('revealed');
        } else {
          article.classList.remove('flashcard-mode', 'revealed');
        }
      });
      modeBtns.appendChild(btn);
    });

    toolbar.appendChild(checkLabel);
    toolbar.appendChild(modeBtns);

    const soundBite = document.createElement('div');
    soundBite.className = 'sound-bite';
    soundBite.innerHTML = `<span class="sound-bite-label">Interview sound bite</span>${extractSoundBite(article)}`;

    const flashcardCover = document.createElement('div');
    flashcardCover.className = 'flashcard-cover';
    flashcardCover.innerHTML = `
      <p>Try answering aloud before revealing.</p>
      <button type="button" class="demo-btn">Reveal answer</button>
    `;
    flashcardCover.querySelector('button').addEventListener('click', () => {
      article.classList.add('revealed');
    });

    const panels = groupContent(article);
    const tabResult = buildTabs(article, panels);

    const question = article.querySelector('h3.question');
    question.after(toolbar);
    toolbar.after(soundBite);

    if (tabResult) {
      const toRemove = [...article.children].filter(
        (el) =>
          el !== question &&
          el !== toolbar &&
          el !== soundBite &&
          !el.classList.contains('demo-panel') &&
          !el.classList.contains('flashcard-cover') &&
          !el.classList.contains('qa-body')
      );
      toRemove.forEach((el) => el.remove());
      soundBite.after(tabResult.tabsEl);
      tabResult.tabsEl.after(tabResult.bodyEl);
    }

    article.appendChild(flashcardCover);
  }

  function updateProgress() {
    const articles = document.querySelectorAll('article.qa');
    const studied = document.querySelectorAll('article.qa.studied').length;
    const el = document.querySelector('.study-progress');
    if (el && articles.length) {
      el.innerHTML = `Study progress: <strong>${studied}/${articles.length}</strong> questions reviewed`;
    }
  }

  function initProgress() {
    const nav = document.querySelector('.site-nav-inner');
    if (!nav || document.querySelector('.study-progress')) return;
    const progress = document.createElement('p');
    progress.className = 'study-progress';
    nav.insertBefore(progress, nav.querySelector('.toc'));
    updateProgress();
  }

  let mermaidInitPromise = null;

  function ensureMermaid() {
    if (mermaidInitPromise) return mermaidInitPromise;
    mermaidInitPromise = (async () => {
      if (window.mermaid?.run) {
        if (!window.mermaid.__sdConfigured) {
          const prefersDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
          window.mermaid.initialize({
            startOnLoad: false,
            theme: prefersDark ? 'dark' : 'neutral',
            securityLevel: 'loose',
            flowchart: { useMaxWidth: true },
            sequence: { useMaxWidth: true }
          });
          window.mermaid.__sdConfigured = true;
        }
        return window.mermaid;
      }
      const mod = await import('https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs');
      const prefersDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
      mod.default.initialize({
        startOnLoad: false,
        theme: prefersDark ? 'dark' : 'neutral',
        securityLevel: 'loose',
        flowchart: { useMaxWidth: true },
        sequence: { useMaxWidth: true }
      });
      window.mermaid = mod.default;
      return mod.default;
    })();
    return mermaidInitPromise;
  }

  async function renderMermaidIn(container) {
    if (!container) return;
    const nodes = [...container.querySelectorAll('.mermaid:not([data-mermaid-rendered])')];
    if (!nodes.length) return;
    const mermaid = await ensureMermaid();
    await mermaid.run({ nodes });
    nodes.forEach((node) => node.setAttribute('data-mermaid-rendered', 'true'));
  }

  async function initPageMermaid() {
    document.querySelectorAll('.qa-tab-panel.is-visible').forEach((panel) => {
      renderMermaidIn(panel);
    });
    document.querySelectorAll('article.qa').forEach((article) => {
      if (!article.querySelector('.qa-tabs')) renderMermaidIn(article);
    });
  }

  function initDemos() {
    document.querySelectorAll('[data-demo]').forEach((panel) => {
      const type = panel.dataset.demo;
      if (type === 'token-throttle') initTokenThrottle(panel);
      else if (type === 'stop-chain') initStopChain(panel);
      else if (type === 'protocol-picker') initProtocolPicker(panel);
      else if (type === 'decision-tree') initDecisionTree(panel);
      else if (type === 'fence-sim') initFenceSim(panel);
      else if (type === 'typing-bubble') initTypingBubble(panel);
      else if (type === 'backpressure') initBackpressure(panel);
      else if (type === 'layout-thrash') initLayoutThrash(panel);
      else if (type === 'textarea-grow') initTextareaGrow(panel);
      else if (type === 'upload-progress') initUploadProgress(panel);
      else if (type === 'content-blocks') initContentBlocks(panel);
      else if (type === 'slash-menu') initSlashMenu(panel);
      else if (type === 'voice-transcript') initVoiceTranscript(panel);
      else if (type === 'token-counter') initTokenCounter(panel);
      else if (type === 'table-stream') initTableStream(panel);
    });
  }

  function initTokenThrottle(panel) {
    const slider = panel.querySelector('input[type="range"]');
    const out = panel.querySelector('.demo-output');
    const fpsEl = panel.querySelector('[data-metric="fps"]');
    const paintsEl = panel.querySelector('[data-metric="paints"]');
    let interval = null;
    let tokens = 0;
    let paints = 0;
    let running = false;

    const btn = panel.querySelector('.demo-btn');
    btn.addEventListener('click', () => {
      if (running) {
        running = false;
        clearInterval(interval);
        btn.textContent = 'Start stream';
        return;
      }
      running = true;
      tokens = 0;
      paints = 0;
      out.innerHTML = '';
      btn.textContent = 'Stop';
      const ms = Number(slider.value);
      let tokenInterval = setInterval(() => {
        tokens++;
        out.innerHTML += `<span class="token-chip">tok</span>`;
      }, 8);

      interval = setInterval(() => {
        paints++;
        if (fpsEl) fpsEl.textContent = String(Math.round(1000 / ms));
        if (paintsEl) paintsEl.textContent = String(paints);
      }, ms);

      panel._cleanup = () => {
        clearInterval(tokenInterval);
        clearInterval(interval);
      };
    });

    slider.addEventListener('input', () => {
      panel.querySelector('[data-metric="interval"]').textContent = slider.value + 'ms';
    });
    panel.querySelector('[data-metric="interval"]').textContent = slider.value + 'ms';
  }

  function initStopChain(panel) {
    const btn = panel.querySelector('.demo-btn');
    const steps = panel.querySelectorAll('.cancel-step');
    btn.addEventListener('click', () => {
      steps.forEach((s) => s.classList.remove('active'));
      let i = 0;
      const tick = () => {
        if (i < steps.length) {
          steps[i].classList.add('active');
          i++;
          setTimeout(tick, 400);
        }
      };
      tick();
    });
  }

  function initProtocolPicker(panel) {
    const scenarios = JSON.parse(panel.dataset.scenarios || '[]');
    let idx = 0;
    const scenarioEl = panel.querySelector('[data-scenario]');
    const cards = panel.querySelectorAll('.protocol-card');
    const feedback = panel.querySelector('.decision-result');

    function showScenario() {
      if (!scenarios.length) return;
      const s = scenarios[idx % scenarios.length];
      scenarioEl.textContent = s.prompt;
      cards.forEach((c) => {
        c.classList.remove('selected', 'correct', 'wrong');
        c.dataset.answer = c.textContent.trim().toLowerCase();
      });
      feedback.textContent = '';
      idx++;
    }

    cards.forEach((card) => {
      card.addEventListener('click', () => {
        const s = scenarios[(idx - 1 + scenarios.length) % scenarios.length];
        if (!s) return;
        cards.forEach((c) => c.classList.remove('selected', 'correct', 'wrong'));
        card.classList.add('selected');
        const pick = card.textContent.trim().toLowerCase();
        const correct = s.answer.toLowerCase();
        card.classList.add(pick === correct ? 'correct' : 'wrong');
        cards.forEach((c) => {
          if (c.textContent.trim().toLowerCase() === correct) c.classList.add('correct');
        });
        feedback.textContent = s.explain;
      });
    });

    panel.querySelector('[data-next]')?.addEventListener('click', showScenario);
    showScenario();
  }

  function initDecisionTree(panel) {
    const tree = JSON.parse(panel.dataset.tree || '{}');
    const root = panel.querySelector('[data-tree-root]');
    const result = panel.querySelector('.decision-result');

    function render(node) {
      root.innerHTML = '';
      result.textContent = '';
      if (node.question) {
        const p = document.createElement('p');
        p.textContent = node.question;
        p.style.fontSize = '0.875rem';
        root.appendChild(p);
        (node.options || []).forEach((opt) => {
          const btn = document.createElement('button');
          btn.type = 'button';
          btn.textContent = opt.label;
          btn.addEventListener('click', () => {
            if (opt.next) render(opt.next);
            else {
              result.textContent = opt.result || '';
              root.innerHTML = '';
            }
          });
          root.appendChild(btn);
        });
      }
    }
    render(tree);
  }

  function initFenceSim(panel) {
    const input = panel.querySelector('textarea');
    const display = panel.querySelector('.fence-display');
    const badge = panel.querySelector('.fence-badge');
    const sample = panel.querySelector('[data-sample]');

    function update() {
      const text = input.value;
      const open = /```[\w]*\n?/.test(text) && !/(^|\n)```\s*$/.test(text);
      badge.textContent = open ? 'IN_CODE (provisional)' : 'OUTSIDE_CODE';
      badge.className = 'fence-badge ' + (open ? 'inside' : 'outside');
      display.textContent = text || '(type or use sample)';
      display.classList.toggle('streaming', open);
    }

    input?.addEventListener('input', update);
    sample?.addEventListener('click', () => {
      input.value = 'Here is code:\n```javascript\nconst x = 1;\n';
      update();
    });
    update();
  }

  function initTypingBubble(panel) {
    const bubble = panel.querySelector('.bubble-demo');
    const btn = panel.querySelector('.demo-btn');
    btn.addEventListener('click', () => {
      bubble.classList.remove('show-text');
      void bubble.offsetWidth;
      setTimeout(() => bubble.classList.add('show-text'), 600);
      setTimeout(() => bubble.classList.remove('show-text'), 2500);
    });
  }

  function initBackpressure(panel) {
    const slider = panel.querySelector('input[type="range"]');
    const gauge = panel.querySelector('.gauge-fill');
    const lagEl = panel.querySelector('[data-metric="lag"]');
    slider.addEventListener('input', () => {
      const v = Number(slider.value);
      gauge.style.width = v + '%';
      gauge.classList.toggle('warn', v > 60);
      gauge.classList.toggle('danger', v > 85);
      const lag = Math.round(v * 5);
      if (lagEl) lagEl.textContent = lag + 'ms';
    });
    slider.dispatchEvent(new Event('input'));
  }

  function initLayoutThrash(panel) {
    const naiveBtn = panel.querySelector('[data-mode="naive"]');
    const incrBtn = panel.querySelector('[data-mode="incremental"]');
    const visual = panel.querySelector('.demo-visual');
    const metric = panel.querySelector('[data-metric="reflows"]');

    function run(mode) {
      visual.innerHTML = '<div class="block-row"></div>';
      const row = visual.querySelector('.block-row');
      let reflows = 0;
      for (let i = 0; i < 8; i++) {
        if (mode === 'naive') {
          row.innerHTML = '';
          reflows += 8;
        }
        const block = document.createElement('span');
        block.className = 'render-block flash';
        block.textContent = 'Block ' + (i + 1);
        row.appendChild(block);
        reflows += mode === 'naive' ? 1 : 0;
        if (mode === 'incremental') reflows += 1;
      }
      if (metric) metric.textContent = String(mode === 'naive' ? reflows : 8);
    }

    naiveBtn?.addEventListener('click', () => run('naive'));
    incrBtn?.addEventListener('click', () => run('incremental'));
    run('incremental');
  }

  function initTextareaGrow(panel) {
    const textarea = panel.querySelector('textarea');
    const maxSlider = panel.querySelector('input[type="range"]');
    const heightEl = panel.querySelector('[data-metric="height"]');
    const cappedEl = panel.querySelector('[data-metric="capped"]');

    function resize() {
      const maxPx = Number(maxSlider?.value || 200);
      textarea.style.height = 'auto';
      const scrollH = textarea.scrollHeight;
      const capped = scrollH > maxPx;
      textarea.style.height = Math.min(scrollH, maxPx) + 'px';
      textarea.style.overflowY = capped ? 'auto' : 'hidden';
      if (heightEl) heightEl.textContent = String(Math.min(scrollH, maxPx));
      if (cappedEl) cappedEl.textContent = capped ? 'yes' : 'no';
    }

    textarea?.addEventListener('input', resize);
    maxSlider?.addEventListener('input', () => {
      const maxLabel = panel.querySelector('[data-metric="max"]');
      if (maxLabel) maxLabel.textContent = maxSlider.value + 'px';
      resize();
    });
    const maxLabel = panel.querySelector('[data-metric="max"]');
    if (maxLabel && maxSlider) maxLabel.textContent = maxSlider.value + 'px';
    resize();
  }

  function initUploadProgress(panel) {
    const btn = panel.querySelector('.demo-btn');
    const cancelBtn = panel.querySelector('[data-cancel]');
    const fill = panel.querySelector('.gauge-fill');
    const statusEl = panel.querySelector('[data-metric="status"]');
    let interval = null;
    let progress = 0;

    function reset() {
      clearInterval(interval);
      interval = null;
      progress = 0;
      if (fill) fill.style.width = '0%';
      if (statusEl) statusEl.textContent = 'queued';
      btn.disabled = false;
      cancelBtn.disabled = true;
      btn.textContent = 'Start upload';
    }

    btn?.addEventListener('click', () => {
      if (interval) return;
      progress = 0;
      btn.textContent = 'Uploading…';
      btn.disabled = true;
      cancelBtn.disabled = false;
      if (statusEl) statusEl.textContent = 'uploading';
      interval = setInterval(() => {
        progress += 4 + Math.random() * 6;
        if (progress >= 100) {
          progress = 100;
          clearInterval(interval);
          interval = null;
          if (statusEl) statusEl.textContent = 'ready';
          btn.textContent = 'Done';
          cancelBtn.disabled = true;
        }
        if (fill) fill.style.width = progress + '%';
      }, 120);
    });

    cancelBtn?.addEventListener('click', () => {
      if (statusEl) statusEl.textContent = 'cancelled';
      reset();
    });
    reset();
  }

  function initContentBlocks(panel) {
    const toggle = panel.querySelector('[data-toggle]');
    const preview = panel.querySelector('.content-block-preview');
    let useBlob = true;

    function render() {
      preview.innerHTML = useBlob
        ? '<div class="block-thumb blob">blob:preview</div><p class="block-text">What is in this screenshot?</p>'
        : '<div class="block-thumb cdn">cdn.example/img.jpg</div><p class="block-text">What is in this screenshot?</p>';
      panel.querySelector('[data-metric="source"]').textContent = useBlob ? 'createObjectURL' : 'CDN URL';
    }

    toggle?.addEventListener('click', () => {
      useBlob = !useBlob;
      render();
    });
    render();
  }

  function initSlashMenu(panel) {
    const input = panel.querySelector('input[type="text"]');
    const menu = panel.querySelector('.slash-menu');
    const commands = JSON.parse(panel.dataset.commands || '[]');
    if (!commands.length) {
      commands.push(
        { name: 'search', desc: 'Search knowledge base' },
        { name: 'summarize', desc: 'Summarize thread' },
        { name: 'code', desc: 'Generate code snippet' }
      );
    }

    function update() {
      const val = input.value;
      const match = val.match(/^\/(\w*)$/);
      if (!match) {
        menu.hidden = true;
        return;
      }
      const q = match[1].toLowerCase();
      const filtered = commands.filter((c) => c.name.startsWith(q));
      menu.innerHTML = filtered
        .map((c) => `<button type="button" class="slash-item" data-cmd="${c.name}">/${c.name} — ${c.desc}</button>`)
        .join('');
      menu.hidden = filtered.length === 0;
      menu.querySelectorAll('.slash-item').forEach((btn) => {
        btn.addEventListener('click', () => {
          input.value = '/' + btn.dataset.cmd + ' ';
          menu.hidden = true;
          input.focus();
        });
      });
    }

    input?.addEventListener('input', update);
    input?.addEventListener('keydown', (e) => {
      if (e.key === 'Escape') menu.hidden = true;
    });
  }

  function initVoiceTranscript(panel) {
    const display = panel.querySelector('.voice-display');
    const interimEl = panel.querySelector('.voice-interim');
    const btn = panel.querySelector('.demo-btn');
    const steps = ['Hello', 'Hello world', 'Hello world, please'];
    let step = 0;
    let committed = 'Summarize this thread: ';

    btn?.addEventListener('click', () => {
      if (step >= steps.length) {
        step = 0;
        committed = 'Summarize this thread: ';
      }
      if (step < steps.length - 1) {
        interimEl.textContent = steps[step];
        display.textContent = committed;
        step++;
      } else {
        committed += steps[step];
        display.textContent = committed;
        interimEl.textContent = '';
        step = steps.length;
        btn.textContent = 'Reset';
      }
      if (step > 0 && step < steps.length) btn.textContent = 'Next partial';
      else if (step >= steps.length) btn.textContent = 'Reset';
      else btn.textContent = 'Simulate dictation';
    });
  }

  function initTokenCounter(panel) {
    const input = panel.querySelector('textarea');
    const countEl = panel.querySelector('[data-metric="tokens"]');
    const remainEl = panel.querySelector('[data-metric="remaining"]');
    const gauge = panel.querySelector('.gauge-fill');
    const budget = Number(panel.dataset.budget || 8000);
    let timer = null;

    function estimate(text) {
      return Math.ceil(text.length / 4);
    }

    function update() {
      const tokens = estimate(input.value);
      const remaining = Math.max(0, budget - tokens);
      if (countEl) countEl.textContent = '~' + tokens;
      if (remainEl) remainEl.textContent = String(remaining);
      const pct = Math.min(100, (tokens / budget) * 100);
      if (gauge) {
        gauge.style.width = pct + '%';
        gauge.classList.toggle('warn', pct > 80);
        gauge.classList.toggle('danger', pct >= 100);
      }
    }

    input?.addEventListener('input', () => {
      clearTimeout(timer);
      timer = setTimeout(update, 200);
    });
    update();
  }

  function initTableStream(panel) {
    const btn = panel.querySelector('.demo-btn');
    const display = panel.querySelector('.table-stream-display');
    const stateEl = panel.querySelector('[data-metric="state"]');
    const lines = ['| Name | Score |', '| --- | --- |', '| Alice | 95 |', '| Bob | 87 |'];
    let idx = 0;

    function render(partial) {
      const committed = lines.slice(0, idx).join('\n');
      const staging = partial || '';
      const hasSep = idx >= 2;
      if (!hasSep) {
        display.innerHTML = `<pre>${committed}${staging ? '\n' + staging : ''}</pre>`;
        if (stateEl) stateEl.textContent = 'TABLE_PENDING (preformatted)';
      } else {
        const rows = committed.split('\n').filter(Boolean);
        const header = rows[0].split('|').filter(Boolean).map((c) => c.trim());
        const body = rows.slice(2);
        display.innerHTML = `<table><thead><tr>${header.map((h) => `<th>${h}</th>`).join('')}</tr></thead><tbody>${body.map((r) => {
          const cells = r.split('|').filter(Boolean).map((c) => c.trim());
          return `<tr>${cells.map((c) => `<td>${c}</td>`).join('')}</tr>`;
        }).join('')}</tbody></table>${staging ? `<pre style="opacity:0.6;margin-top:0.5rem">${staging}</pre>` : ''}`;
        if (stateEl) stateEl.textContent = staging ? 'staging row' : 'row committed';
      }
    }

    btn?.addEventListener('click', () => {
      if (idx >= lines.length) {
        idx = 0;
        btn.textContent = 'Next token line';
      }
      if (idx < lines.length) {
        render('');
        idx++;
        render(idx === lines.length ? '| Cha' : '');
        if (idx >= lines.length) btn.textContent = 'Reset';
      }
    });
    render('');
  }

  document.addEventListener('DOMContentLoaded', () => {
    const studiedMap = loadStudied();
    document.querySelectorAll('article.qa').forEach((a) => enhanceArticle(a, studiedMap));
    initProgress();
    initDemos();
    initPageMermaid();
  });
})();
