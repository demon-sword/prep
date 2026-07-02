# Ralph Concepts — Spec

Generates **self-contained interactive HTML concept files** under `ai-engineering/concepts/` — one concept per file — targeting senior AI engineer depth.

## Goal

Each HTML teaches one concept visually and interactively. A senior engineer studying these should be able to:
1. Understand the theory deeply (not surface-level)
2. See the mechanism animate (not just read about it)
3. Interact with parameters to build intuition
4. Walk away with a crisp mental model

## Output artifact per concept

| Attribute | Requirement |
|-----------|-------------|
| Path | `ai-engineering/concepts/<id>.html` |
| Format | Fully self-contained HTML — no external dependencies except Google Fonts CDN |
| Theme | Dark terminal theme (see Design System below) |
| Sections | Header, Theory, Visualization, Key Takeaways |
| Visualization | Interactive (JS-driven) — not a static diagram |
| Code | All CSS and JS inline in `<style>` and `<script>` tags |
| Mobile | Responsive — works on tablet and desktop |

## Required HTML sections (in order)

1. **`<header>`** — concept title, group badge, one-sentence description
2. **`<section id="theory">`** — deep theory: what it is, how it works, when/why it matters, tradeoffs. Use subsections, formulas where helpful. Minimum 400 words of real content. No placeholders.
3. **`<section id="visualization">`** — the interactive viz. Must be functional JS, not a placeholder. Controls (sliders, buttons, toggles) must do something real.
4. **`<section id="takeaways">`** — 4–6 bullet points. Senior-level insights, not beginner summaries. Include real numbers, tools, gotchas.
5. **`<nav class="concept-nav">`** — prev/next links to adjacent concept files (use relative paths `../concepts/<id>-<slug>.html`)

## Design system (match exactly)

```css
--bg:           #0d0f17;
--surface:      #141720;
--card:         #1a1e2e;
--border:       #252a3d;
--accent:       #00d4ff;    /* cyan — primary highlight */
--purple:       #7c3aed;
--green:        #00ff88;
--yellow:       #ffd700;
--red:          #ff4757;
--orange:       #ff9500;
--text:         #e2e8f0;
--text-dim:     #8892a4;
--mono:         'JetBrains Mono', monospace;
--sans:         'Inter', system-ui, sans-serif;
```

Fonts: load from Google Fonts CDN (Inter + JetBrains Mono).
No other external dependencies — no D3 CDN, no Chart.js CDN. All visualization logic must be vanilla JS + Canvas or SVG.

## Visualization quality bar

The viz must be **genuinely interactive**:
- At minimum: user can click, drag, or adjust a slider and see the diagram change
- Prefer: animated flows that show the mechanism in motion (use `requestAnimationFrame`)
- Avoid: static SVG with no interaction, or a viz that's just a colored rectangle

Each concept's `concepts.json` entry has a `viz` field describing what to build — follow it.

## Theory quality bar

- Explain the mechanism, not just the definition
- Include real numbers where they exist (e.g. "GPT-3 was trained with ~300B tokens, Chinchilla says optimal for 175B params is ~3.5T tokens")
- Include production-relevant tradeoffs (memory, latency, cost, quality)
- Reference real tools/systems (FAISS, vLLM, LoRA, HNSW, RAGAS, etc.)
- Write for a senior engineer who knows ML basics — skip trivial definitions, go deep on mechanisms and tradeoffs

## Validation checks (agent self-checks after writing)

1. HTML parses without error (no unclosed tags)
2. All 5 sections present (`header`, `#theory`, `#visualization`, `#takeaways`, `.concept-nav`)
3. Visualization has at least one event listener (click, input, or animation loop)
4. No placeholder text (no "TODO", "PLACEHOLDER", "Lorem ipsum", "coming soon")
5. File is self-contained (no `src=` pointing to local files, no `href=` to local CSS)
6. Playwright screenshot shows rendered content (not blank)
7. Browser console has no uncaught JS errors

## File naming

`<id>.html` — use the `id` field from `concepts.json`

Examples:
- `01-self-supervision.html`
- `06-qkv-attention.html`
- `34-inference-optimization.html`

## Plan format

`ralph-concepts/plan.md` — tracks which concepts are done:

```
## Done
- [x] scaffold

## Next
- [ ] 01-self-supervision — Self-Supervision in LLMs
- [ ] 02-seq2seq — Seq2Seq Architecture
...
```

## Progress log

Append one line per completed concept to `ralph-concepts/progress.txt`:
```
2026-06-28 | 01-self-supervision | Self-Supervision in LLMs | OK
```
