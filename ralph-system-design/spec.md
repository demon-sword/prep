# System Design Topic Generator — Spec

## Topic input
- Single slug only (e.g. `slack`) — agent researches the product from the name.

## Output folder
`system-design/<topic>/`

## Required artifacts

| File | Description |
|------|-------------|
| `<topic>-design-doc.md` | Question bank: themed sections, Core + Deep questions |
| `answers/NN-<slug>.md` | One file per design-doc section |
| `answers-html/NN-<slug>.html` | Generated from markdown (script) — do NOT hand-author unless script missing |
| `<topic>-frontend-architecture.html` | Interactive system diagram |
| `<topic>-system-design-interview.html` | Full 45–60m interview answer |
| `answers-html/index.html` | Section index with links |

## Answer format (every question)
1. **Problem framing:** …
2. **Approach:** …
3. **Tradeoffs:** …

Optional: Mermaid diagrams in Approach section.

## Interview format (interview HTML)
1. Requirements (5–10m) — FR, NFR, scope
2. Architecture (10–15m) — stack, component tree, state ladder
3. Data model (~5m) — core entities
4. API / BFF (~10m) — protocols, endpoints, streaming lifecycle
5. Deep dive (~10m) — pick 1–2 areas

## HTML rules
- HTML is **presentation only** — no interactive demo widgets (`data-demo` panels)
- Copy shared assets from `system-design/claude/answers-html/assets/`
- Section pages use `article.qa` + `h3.question` per question (md_to_html.py handles this)
- Mermaid: `startOnLoad: false`; lazy render via `interactive.js`

## Reference
- Structure/tone: `system-design/claude/` (do not copy Claude-specific content)
- Format: `system-design/README.md`

## Section count
Derived from design doc — not fixed. Parse `## N.` headings.
