#!/usr/bin/env python3
"""
convert_md_to_html.py  —  deterministic markdown → HTML converter for the prep site.

Processes ALL categories (01, 02, 03, 04) from the answers/ directory.

Usage:
    python3 convert_md_to_html.py            # convert everything + regenerate index.html
    python3 convert_md_to_html.py 02-001     # convert single slug only
"""

import re, sys, html as H
from pathlib import Path

BASE      = Path(__file__).parent
ANSWERS   = BASE / "answers"
HTML_DIR  = BASE / "html"
OUT_DIR   = HTML_DIR / "answers"
OUT_DIR.mkdir(parents=True, exist_ok=True)

CAT_LABELS = {
    "01": "LLM Fundamentals",
    "02": "RAG Systems",
    "03": "Agents &amp; Tool Use",
    "04": "Fine-Tuning &amp; Training",
    "05": "Evaluation &amp; Metrics",
    "06": "ML Fundamentals",
}

# ── Inline markdown ──────────────────────────────────────────────────────────
def inline(s):
    s = re.sub(r'\*\*(.+?)\*\*', r'<strong>\1</strong>', s)
    s = re.sub(r'`([^`]+)`',      r'<code>\1</code>',    s)
    s = re.sub(r'(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)', r'<em>\1</em>', s)
    return s

# ── Block markdown → HTML ────────────────────────────────────────────────────
def block(text):
    text = text.strip()
    if not text:
        return ''
    text = re.sub(r'\n---\s*$', '', text).strip()

    # 1. Stash fenced code blocks
    stash = {}
    counter = [0]
    def stash_code(m):
        code = H.escape(m.group(1).rstrip())  # group(1) = content after the opening fence line
        key = f'\x00CODE{counter[0]}\x00'
        stash[key] = (f'<div class="code-block-wrap">'
                      f'<pre class="code-block"><code>{code}</code></pre>'
                      f'<button class="copy-btn">copy</button></div>')
        counter[0] += 1
        return key
    text = re.sub(r'```[^\n]*\n(.*?)```', stash_code, text, flags=re.DOTALL)

    # 2. Convert markdown tables
    def conv_table(m):
        rows = [l.strip() for l in m.group(0).strip().splitlines() if l.strip()]
        rows = [r for r in rows if not re.match(r'^[\|\-\s:]+$', r)]
        if not rows:
            return ''
        out = []
        for i, row in enumerate(rows):
            cells = [c.strip() for c in row.strip('|').split('|')]
            tag = 'th' if i == 0 else 'td'
            out.append('<tr>' + ''.join(f'<{tag}>{inline(c)}</{tag}>' for c in cells) + '</tr>')
        return f'<div class="table-wrap"><table class="data-table">{"".join(out)}</table></div>'
    text = re.sub(r'(^\|.+\|[ \t]*\n)+', conv_table, text, flags=re.MULTILINE)

    # 3. Process line by line
    segments, cur_para, cur_list, cur_list_type = [], [], [], None

    def flush_para():
        if cur_para:
            joined = ' '.join(cur_para).strip()
            if joined:
                if joined.startswith('#'):
                    joined = re.sub(r'^#+\s*', '', joined)
                    segments.append(f'<p><strong>{inline(joined)}</strong></p>')
                else:
                    segments.append(f'<p>{inline(joined)}</p>')
            cur_para.clear()

    def flush_list():
        nonlocal cur_list_type
        if cur_list:
            cls  = 'mechanism-steps' if cur_list_type == 'ol' else 'styled-list'
            tag  = cur_list_type
            body = ''.join(f'<li>{inline(i)}</li>' for i in cur_list)
            segments.append(f'<{tag} class="{cls}">{body}</{tag}>')
            cur_list.clear()
            cur_list_type = None

    for line in text.splitlines():
        # Stash placeholders passthrough
        if '\x00CODE' in line or (line.startswith('<') and line[:4] in ('<div', '<pre', '<tab')):
            flush_list(); flush_para(); segments.append(line); continue

        if not line.strip():
            flush_list(); flush_para(); continue

        if line.startswith('#'):
            flush_list(); flush_para()
            heading = re.sub(r'^#+\s*', '', line)
            segments.append(f'<p><strong>{inline(heading)}</strong></p>')
            continue

        m = re.match(r'^\s*(\d+)[.)]\s+(.+)$', line)
        if m:
            flush_para()
            if cur_list_type != 'ol': flush_list(); cur_list_type = 'ol'
            cur_list.append(m.group(2))
            continue

        m = re.match(r'^\s*[-*]\s+(.+)$', line)
        if m:
            flush_para()
            if cur_list_type != 'ul': flush_list(); cur_list_type = 'ul'
            cur_list.append(m.group(1))
            continue

        flush_list()
        cur_para.append(line)

    flush_list(); flush_para()

    result = '\n'.join(segments)
    for key, val in stash.items():
        result = result.replace(key, val)
    return result

# ── Section extraction ───────────────────────────────────────────────────────
def section(text, *headings):
    for h in headings:
        # Detect heading level from the first match to pick the right lookahead.
        # ## parent sections should only stop at the next ## (not ###),
        # so that child ### sections are included in the captured block.
        hdr_m = re.search(r'^(#{1,3})\s+' + re.escape(h) + r'\s*\n', text, re.M)
        if not hdr_m:
            continue
        level = len(hdr_m.group(1))  # 1, 2, or 3
        if level == 2:
            # Parent section: stop only at next ## or #, not at ###
            stop = r'(?=^#{1,2}\s|\Z)'
        else:
            # Child section: stop at any heading of same or higher level
            stop = r'(?=^#{1,' + str(level) + r'}\s|\Z)'
        pat = re.compile(r'^#{' + str(level) + r'}\s+' + re.escape(h) + r'\s*\n(.*?)' + stop,
                         re.M | re.S)
        m = pat.search(text)
        if m:
            return m.group(1).strip()
    return ''

def parse_triggers(framing):
    return [re.sub(r'^-\s*"?|"?\s*$', '', l).strip()
            for l in framing.splitlines()
            if re.match(r'^\s*-\s', l)]

def parse_pitfalls(text):
    block_text = section(text, 'Pitfalls')
    pitfalls = []
    for item in re.split(r'\n(?=- \*\*Mistake)', block_text):
        item = item.strip().lstrip('- ')
        if not item: continue
        parts = re.split(r'\s*—\s*\*\*Better:\*\*\s*', item, 1)
        if len(parts) == 2:
            mistake = re.sub(r'^\*\*Mistake:\*\*\s*', '', parts[0]).strip()
            better  = parts[1].strip()
            pitfalls.append((mistake, better))
    return pitfalls

def parse_related(text):
    block_text = section(text, 'Related questions')
    related = []
    for line in block_text.splitlines():
        m = re.match(r'\|\s*\[([^\]]+)\]\(([^\)]+)\)\s*\|\s*([^|]*)\|?', line.strip())
        if m:
            title, path, rel = m.group(1).strip(), m.group(2).strip(), m.group(3).strip()
            sm = re.match(r'(\d{2}-\d{3})', Path(path).stem)
            if sm:
                related.append((sm.group(1), title, rel))
    return related

def parse_oneliner(text):
    block_text = section(text, 'One-liner recall')
    m = re.search(r'>\s*(.+)', block_text, re.DOTALL)
    return re.sub(r'\s+', ' ', m.group(1)).strip() if m else ''

def parse_script(text):
    script_block = section(text, 'Verbal script')
    parts = {}
    for key, pat in [
        ('opening',  r'\*\*Opening \(30s\):\*\*\s*\n(.*?)(?=\*\*Core|\Z)'),
        ('core',     r'\*\*Core explanation \(2.{0,5}min\):\*\*\s*\n(.*?)(?=\*\*Tradeoff|\Z)'),
        ('tradeoff', r'\*\*Tradeoff \/ production angle \(1 min\):\*\*\s*\n(.*?)(?=\*\*Wrap|\Z)'),
        ('wrapup',   r'\*\*Wrap-up \(30s\):\*\*\s*\n(.*?)(?=\Z)'),
    ]:
        m = re.search(pat, script_block, re.DOTALL)
        if m:
            raw = m.group(1).strip()
            raw = re.sub(r'\n---\s*$', '', raw).strip()
            parts[key] = '\n\n'.join(
                ' '.join(l.strip() for l in p.strip().splitlines() if l.strip())
                for p in raw.split('\n\n') if p.strip()
            )
    return parts

def parse_frontmatter(text):
    fm = {}
    m = re.search(r'\*\*Category:\*\*\s*(.+)', text)
    fm['category'] = m.group(1).strip() if m else '01-llm-fundamentals'
    m = re.search(r'\*\*Question #:\*\*\s*(\d+)', text)
    fm['num'] = m.group(1).strip().zfill(3) if m else '000'
    m = re.search(r'\*\*Status:\*\*\s*`?(\w+)`?', text)
    fm['status'] = m.group(1).strip() if m else 'review'
    m = re.match(r'^#\s+(.+)', text, re.M)
    fm['title'] = m.group(1).strip().rstrip(' ⭐').strip() if m else 'Untitled'
    return fm

# ── HTML template ────────────────────────────────────────────────────────────
def render(slug, fm, text):
    framing_block = section(text, 'Framing')

    why      = section(framing_block, 'Why this question is asked', 'Why this is asked')
    triggers = parse_triggers(section(framing_block, 'Trigger phrases'))
    tests    = section(framing_block, 'What it tests')

    answer_block = section(text, 'Answer')
    concept   = section(answer_block, 'Concept')
    mechanism = section(answer_block, 'Mechanism')
    example   = section(answer_block, 'Example / Tradeoff', 'Example/Tradeoff', 'Example')

    script   = parse_script(text)
    pitfalls = parse_pitfalls(text)
    related  = parse_related(text)
    oneliner = parse_oneliner(text)

    cat_prefix  = fm['category'].split('-')[0]
    cat_label   = CAT_LABELS.get(cat_prefix, fm['category'])
    status      = fm['status']
    title_esc   = H.escape(fm['title'])
    oneliner_attr = H.escape(oneliner, quote=True)

    triggers_html = '\n              '.join(
        f'<div class="trigger-phrase">{H.escape(t)}</div>' for t in triggers
    ) or '<div class="trigger-phrase">—</div>'

    pitfalls_html = ''.join(f'''  <div class="pitfall-card">
    <div class="pitfall-mistake"><strong>✗ Mistake</strong> {inline(H.escape(m))}</div>
    <div class="pitfall-better"><strong>✓ Better</strong> {inline(H.escape(b))}</div>
  </div>\n''' for m, b in pitfalls) or \
        '<p class="text-muted" style="font-size:13px">See source for pitfalls.</p>'

    related_html = ''.join(f'''    <div class="related-pill" data-slug="{s}">
      <span class="related-pill-icon">→</span>
      <div class="related-pill-text">
        <div class="related-pill-q">{H.escape(t)}</div>
        <div class="related-pill-rel">{H.escape(r)}</div>
      </div>
    </div>\n''' for s, t, r in related) or \
        '<p class="text-muted" style="font-size:13px">—</p>'

    def sp(key):
        raw = script.get(key, '')
        if not raw: return '<p>—</p>'
        return '\n'.join(f'<p>{inline(p)}</p>' for p in raw.split('\n\n') if p.strip())

    return f"""<div class="answer-header reveal">
  <div class="answer-meta">
    <span class="meta-badge meta-category">{H.escape(fm['category'])}</span>
    <span class="meta-badge meta-num">Q{fm['num']}</span>
    <span class="meta-badge meta-status-{status}">{status}</span>
  </div>
  <h1 class="answer-title">{title_esc}</h1>
</div>

<div class="answer-section reveal">
  <div class="accordion">
    <div class="accordion-header">
      <span class="accordion-title">⟁ Framing — Why this is asked</span>
      <span class="accordion-chevron">▾</span>
    </div>
    <div class="accordion-body">
      <div class="framing-grid">
        <div><div class="framing-card">
          <div class="framing-card-title">Why asked</div>
          <p style="font-size:13.5px;line-height:1.7;color:var(--text-dim)">{inline(H.escape(why))}</p>
        </div></div>
        <div><div class="framing-card">
          <div class="framing-card-title">Trigger phrases</div>
          <div class="trigger-list">
              {triggers_html}
          </div>
        </div></div>
      </div>
      <div class="tests-block">
        <span style="font-family:var(--mono);font-size:10px;letter-spacing:0.1em;text-transform:uppercase;color:var(--purple);margin-right:8px">Tests:</span>{inline(H.escape(tests))}
      </div>
    </div>
  </div>
</div>

<div class="answer-section reveal">
  <div class="section-label">Concept</div>
  <div class="concept-block">{block(concept)}</div>
</div>

<div class="answer-section reveal">
  <div class="section-label">Mechanism</div>
  <div class="card">{block(mechanism)}</div>
</div>

<div class="answer-section reveal">
  <div class="section-label">Example / Tradeoff</div>
  <div class="card card-accent"><div class="rich-text">{block(example)}</div></div>
</div>

<div class="answer-section reveal">
  <div class="accordion">
    <div class="accordion-header">
      <span class="accordion-title">🎙 Verbal Script (3–5 min)</span>
      <span class="accordion-chevron">▾</span>
    </div>
    <div class="accordion-body">
      <div class="script-block"><div class="script-label">Opening (30s)</div>{sp('opening')}</div>
      <div class="script-block"><div class="script-label">Core explanation (2–3 min)</div>{sp('core')}</div>
      <div class="script-block"><div class="script-label">Tradeoff / production angle (1 min)</div>{sp('tradeoff')}</div>
      <div class="script-block"><div class="script-label">Wrap-up (30s)</div>{sp('wrapup')}</div>
    </div>
  </div>
</div>

<div class="answer-section reveal">
  <div class="section-label">Pitfalls</div>
{pitfalls_html}</div>

<div class="answer-section reveal">
  <div class="section-label">Related Questions</div>
  <div class="related-pills">
{related_html}  </div>
</div>

<div class="answer-section reveal">
  <div class="section-label">One-liner recall</div>
  <div class="oneliner-box">
    <div class="oneliner-label">▸ Reconstruct from memory</div>
    <div class="oneliner-text" data-text="{oneliner_attr}">{H.escape(oneliner)}</div>
  </div>
</div>
"""

# ── index.html regenerator ────────────────────────────────────────────────────
def build_index(questions):
    total  = len(questions)
    review = sum(1 for q in questions if q['status'] == 'review')
    master = sum(1 for q in questions if q['status'] == 'mastered')
    todo   = sum(1 for q in questions if q['status'] == 'todo')

    js_rows = ''
    for q in questions:
        cat_prefix = q['category'].split('-')[0]
        cat_label  = CAT_LABELS.get(cat_prefix, q['category']).replace('&amp;', '&')
        title_js   = q['title'].replace('\\', '\\\\').replace('"', '\\"').replace("'", "\\'")
        js_rows += (f"  {{ slug:'{q['slug']}', num:'{q['num']}', "
                    f"title:\"{title_js}\", status:'{q['status']}', "
                    f"category:'{q['category']}', catLabel:'{cat_label}' }},\n")

    html = f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8"/>
  <meta name="viewport" content="width=device-width,initial-scale=1.0"/>
  <title>AI Engineering Prep</title>
  <link rel="stylesheet" href="style.css"/>
</head>
<body>
<div id="progress-bar"></div>
<header id="app-header">
  <div class="header-logo"><span class="cursor"></span><span>AI ENGINEERING PREP</span></div>
  <div class="header-spacer"></div>
  <div class="header-count" id="header-count">{total} questions</div>
</header>
<div id="app-layout">
  <nav id="sidebar">
    <div class="sidebar-search">
      <div class="search-wrap">
        <span class="search-icon">⌕</span>
        <input type="text" id="search-input" placeholder="search questions..." autocomplete="off" spellcheck="false"/>
      </div>
    </div>
    <div class="sidebar-status">
      <div class="status-chip active-filter" data-filter="all">
        <span class="status-dot" style="background:var(--accent)"></span><span>all</span>
      </div>
      <div class="status-chip" data-filter="review">
        <span class="status-dot review"></span><span>{review} review</span>
      </div>
      <div class="status-chip" data-filter="mastered">
        <span class="status-dot mastered"></span><span>{master} mastered</span>
      </div>
      <div class="status-chip" data-filter="todo">
        <span class="status-dot todo"></span><span>{todo} todo</span>
      </div>
    </div>
    <div id="sidebar-list"></div>
  </nav>
  <main id="main-panel">
    <div id="answer-container">
      <div id="welcome-screen">
        <div class="welcome-ascii">
 ██████╗██╗     ██████╗     ██████╗  ██████╗
██╔════╝██║     ██╔══██╗    ██╔══██╗██╔════╝
██║     ██║     ██║  ██║    ██║  ██║██║
██║     ██║     ██║  ██║    ██║  ██║██║
╚██████╗███████╗██████╔╝    ██████╔╝╚██████╗
 ╚═════╝╚══════╝╚═════╝     ╚═════╝  ╚═════╝
        </div>
        <h1 class="welcome-title">AI Engineering Prep</h1>
        <p class="welcome-sub">{total} deep-dive answers across 6 categories — LLM fundamentals, RAG systems, agents, fine-tuning, evaluation, and ML fundamentals. Click any question to begin.</p>
        <div class="welcome-stats">
          <div class="welcome-stat"><span class="welcome-stat-num">{total}</span><span class="welcome-stat-label">Questions</span></div>
          <div class="welcome-stat"><span class="welcome-stat-num" style="color:var(--yellow)">{review}</span><span class="welcome-stat-label">In Review</span></div>
          <div class="welcome-stat"><span class="welcome-stat-num" style="color:var(--purple)">6</span><span class="welcome-stat-label">Categories</span></div>
        </div>
      </div>
      <div id="answer-root" style="display:none"></div>
    </div>
  </main>
</div>
<script>
const QUESTIONS=[
{js_rows}];
let activeSlug=null,activeFilter='all';
const mainPanel=document.getElementById('main-panel');

function buildSidebar(){{
  const list=document.getElementById('sidebar-list');
  list.innerHTML='';
  let lastCat=null;
  QUESTIONS.forEach((q,i)=>{{
    if(q.catLabel!==lastCat){{
      const sep=document.createElement('div');
      sep.style.cssText='font-family:var(--mono);font-size:9px;letter-spacing:0.15em;text-transform:uppercase;color:var(--text-muted);padding:14px 10px 6px;border-top:1px solid var(--border);margin-top:4px';
      sep.textContent=q.catLabel;
      list.appendChild(sep);
      lastCat=q.catLabel;
    }}
    const el=document.createElement('div');
    el.className='sidebar-item';
    el.dataset.slug=q.slug;
    el.dataset.status=q.status;
    el.dataset.title=q.title.toLowerCase();
    el.dataset.cat=q.catLabel.toLowerCase();
    el.style.animationDelay=Math.min(i*0.012,0.6)+'s';
    el.innerHTML=`<span class="item-num">${{q.num}}</span><span class="item-title">${{q.title}}</span><span class="item-badge badge-${{q.status}}">${{q.status}}</span>`;
    el.addEventListener('click',()=>loadAnswer(q.slug));
    list.appendChild(el);
  }});
}}

function applyFilters(){{
  const q=document.getElementById('search-input').value.toLowerCase();
  let vis=0;
  document.querySelectorAll('.sidebar-item').forEach(el=>{{
    const show=(!q||el.dataset.title.includes(q)||el.dataset.slug.includes(q)||el.dataset.cat.includes(q))
              &&(activeFilter==='all'||el.dataset.status===activeFilter);
    el.classList.toggle('hidden',!show);
    if(show)vis++;
  }});
  document.getElementById('header-count').textContent=vis+' / {total} questions';
  const old=document.querySelector('.no-results');if(old)old.remove();
  if(vis===0){{const nr=document.createElement('div');nr.className='no-results';nr.textContent='no matches found';document.getElementById('sidebar-list').appendChild(nr);}}
}}

document.getElementById('search-input').addEventListener('input',applyFilters);
document.querySelectorAll('.status-chip').forEach(c=>c.addEventListener('click',()=>{{
  document.querySelectorAll('.status-chip').forEach(x=>x.classList.remove('active-filter'));
  c.classList.add('active-filter');activeFilter=c.dataset.filter;applyFilters();
}}));

mainPanel.addEventListener('scroll',()=>{{
  const pct=mainPanel.scrollTop/(mainPanel.scrollHeight-mainPanel.clientHeight);
  document.getElementById('progress-bar').style.width=(pct*100)+'%';
}});

function initReveal(){{
  const obs=new IntersectionObserver(entries=>entries.forEach(e=>{{if(e.isIntersecting){{e.target.classList.add('visible');obs.unobserve(e.target);}}}}),{{threshold:0.08,rootMargin:'0px 0px -40px 0px',root:mainPanel}});
  document.querySelectorAll('.reveal').forEach(el=>obs.observe(el));
}}
function initAccordions(){{document.querySelectorAll('.accordion-header').forEach(h=>h.addEventListener('click',()=>h.closest('.accordion').classList.toggle('open')));}}
function initCopyButtons(){{document.querySelectorAll('.copy-btn').forEach(btn=>btn.addEventListener('click',()=>{{const code=btn.closest('.code-block-wrap').querySelector('code,pre').innerText;navigator.clipboard.writeText(code).then(()=>{{btn.textContent='\u2713 copied';btn.classList.add('copied');setTimeout(()=>{{btn.textContent='copy';btn.classList.remove('copied');}},2000);}});}}));}}
function initRelatedNav(){{document.querySelectorAll('.related-pill[data-slug]').forEach(p=>p.addEventListener('click',e=>{{e.preventDefault();loadAnswer(p.dataset.slug);}}))}}
function typewriter(el,text,speed=16){{el.textContent='';let i=0;function tick(){{if(i<text.length){{el.textContent+=text[i++];setTimeout(tick,speed);}}}}setTimeout(tick,500);}}

function renderAnswer(slug,data){{
  const root=document.getElementById('answer-root');
  root.innerHTML=data;
  root.classList.remove('answer-enter');void root.offsetWidth;root.classList.add('answer-enter');
  document.querySelectorAll('.sidebar-item').forEach(el=>el.classList.toggle('active',el.dataset.slug===slug));
  mainPanel.scrollTop=0;
  initReveal();initAccordions();initCopyButtons();initRelatedNav();
  const ol=root.querySelector('.oneliner-text[data-text]');if(ol)typewriter(ol,ol.dataset.text);
  history.replaceState(null,'','?q='+slug);
}}

function loadAnswer(slug){{
  if(activeSlug===slug)return;activeSlug=slug;
  document.getElementById('welcome-screen').style.display='none';
  const root=document.getElementById('answer-root');root.style.display='block';
  root.innerHTML='<div style="padding:40px;text-align:center;font-family:var(--mono);font-size:12px;color:var(--text-muted)">loading...</div>';
  fetch('answers/'+slug+'.html')
    .then(r=>{{if(!r.ok)throw new Error();return r.text();}})
    .then(html=>renderAnswer(slug,html))
    .catch(()=>{{root.innerHTML=`<div style="padding:40px;text-align:center"><p style="font-family:var(--mono);color:var(--red)">// not found: ${{slug}}.html</p></div>`;}});
}}

buildSidebar();
const qp=new URLSearchParams(location.search).get('q');
if(qp&&QUESTIONS.find(q=>q.slug===qp))loadAnswer(qp);
</script>
</body>
</html>
"""
    (HTML_DIR / 'index.html').write_text(html, encoding='utf-8')
    num_cats = len(set(q['category'].split('-')[0] for q in questions))
    print(f"✅ index.html rebuilt  ({total} questions, {num_cats} categories)")

# ── Main ──────────────────────────────────────────────────────────────────────
def slug_from_path(p):
    m = re.match(r'(\d{2}-\d{3})', p.stem)
    return m.group(1) if m else p.stem[:6]

def convert_one(md_path):
    slug = slug_from_path(md_path)
    text = md_path.read_text(encoding='utf-8')
    fm   = parse_frontmatter(text)
    (OUT_DIR / f'{slug}.html').write_text(render(slug, fm, text), encoding='utf-8')
    return slug

def main():
    filter_slug = sys.argv[1] if len(sys.argv) > 1 else None

    if filter_slug:
        matches = list(ANSWERS.glob(f'{filter_slug}-*.md'))
        if not matches:
            print(f'❌ No file found for slug: {filter_slug}'); sys.exit(1)
        print(f'✅ {convert_one(matches[0])}.html')
        return

    md_files = sorted(ANSWERS.glob('[0-9][0-9]-[0-9][0-9][0-9]-*.md'))
    print(f'Converting {len(md_files)} files...')
    ok, fail = [], []
    for p in md_files:
        try:
            ok.append(convert_one(p)); print(f'  ✅ {ok[-1]}')
        except Exception as e:
            fail.append(p.name); print(f'  ❌ {p.name}: {e}')

    print(f'\nDone: {len(ok)} ok, {len(fail)} failed')
    if fail:
        for f in fail: print(f'  ✗ {f}')

    questions = []
    for md_path in sorted(ANSWERS.glob('[0-9][0-9]-[0-9][0-9][0-9]-*.md')):
        text = md_path.read_text(encoding='utf-8')
        fm   = parse_frontmatter(text)
        fm['slug'] = slug_from_path(md_path)
        questions.append(fm)
    build_index(questions)

if __name__ == '__main__':
    main()
