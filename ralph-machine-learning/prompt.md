# Ralph Machine Learning — Agent Prompt

## Context files (read every iteration)

| Doc | Path |
|-----|------|
| Spec | `ralph-machine-learning/spec.md` |
| Plan | `ralph-machine-learning/plan.md` |
| Concept list | `ralph-machine-learning/concepts.json` |
| Progress | `ralph-machine-learning/progress.txt` |

## Rules

1. Read `ralph-machine-learning/plan.md` — pick **exactly ONE** unchecked item from **Next** (the first unchecked item).
2. Read `ralph-machine-learning/concepts.json` to get the full concept definition (title, description, viz guidance, group).
3. Generate the HTML file at `machine_learning/concepts/<id>.html`.
4. Self-validate (see Validation Checklist below).
5. Use Playwright MCP to open the file, take a screenshot, and check for JS console errors.
6. If validation or Playwright check fails — fix the file, then re-check.
7. After passing all checks:
   - Mark item as done in `ralph-machine-learning/plan.md` (`- [ ]` → `- [x]`)
   - Append one line to `ralph-machine-learning/progress.txt`
8. If ALL items in plan are done, emit `<promise>COMPLETE</promise>`.

## One task per run — do not start the next plan item.

## HTML generation guidelines

### Structure
```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8"/>
  <meta name="viewport" content="width=device-width,initial-scale=1.0"/>
  <title>{concept title} — Machine Learning Concepts</title>
  <style>/* ALL styles inline here */</style>
</head>
<body>
  <header>...</header>
  <main>
    <section id="theory">...</section>
    <section id="visualization">...</section>
    <section id="takeaways">...</section>
  </main>
  <nav class="concept-nav">...</nav>
  <script>/* ALL JS inline here */</script>
</body>
</html>
```

### Theory section
- Write deep, senior-level content. Minimum 400 words.
- Use `<h2>`, `<h3>`, `<p>`, `<ul>`, `<code>`, `<pre>` as needed.
- Include math inline with unicode or simple notation (no LaTeX renderer needed).
- Add a "Production Reality" or "Why it matters" subsection with real numbers/library names.

### Visualization section
- Lead with a title and brief description of what the viz shows and how to interact with it.
- Build the viz using vanilla JS + Canvas or inline SVG.
- Must have real interactivity: sliders, buttons, click handlers, or animation loops.
- Prefer computing the actual algorithm client-side (real k-means/gradient-descent/PCA steps on sample data) over a pre-baked animation.
- Follow the `viz` field from concepts.json for what to build.
- Controls should be labeled clearly. Show current values next to sliders.

### Key Takeaways section
- 4–6 `<li>` items.
- Senior-level insights: tradeoffs, production gotchas, real numbers, library names.
- Not definitions — insights a junior would miss.

### Concept nav
- Previous and next concept links using relative paths within `machine_learning/concepts/`.
- If first concept, prev link is disabled. If last, next link is disabled.

## Depth and code requirements (from `concepts.json`)

Each concept entry carries fields that shape the page; the first two are
enforced by the validator:

- **`depth`** — sets the minimum word count for `#theory`:
  `intro` → 300 words, `core` → 500, `advanced` → 700.
  An entry with no `depth` falls back to the spec floor of 400.
  Write to the concept's depth; do not pad a `core` topic to `advanced` length.
- **`has_code`** — when `true`, the page **must** contain at least one `<pre>`
  block holding real, multi-line, code-shaped content: the algorithm's inner
  loop, the update rule, a config snippet, the key API call with its decisive
  hyperparameter. A `<pre>` holding a single line, or prose, does not count.
  When `false`, do not add a code block just to satisfy a checker.

- **`gaps`** — present only on concepts whose page **already exists** and was
  audited as correct but one layer short of senior-interview depth. Each string
  is a specific, named omission, written by the auditor who read the page.
  When the entry you are working has a `gaps` array:
  - This run **extends** the existing page. Read the current file first and keep
    what is already right — its structure, its voice, its working visualization.
    Do not rewrite it from scratch and do not drop existing sections.
  - Every item in the array must be genuinely covered in the finished page, in
    the section where it belongs. A gap naming a formula means the formula
    appears and is derived or explained, not name-dropped.
  - Several gaps ask for a worked code block; that is also how a page with
    `has_code: true` and no `<pre>` gets fixed. 41 of the 58 existing ML and
    backend pages currently fail exactly that check.
  - When — and only when — every item is covered, re-read `concepts.json`,
    remove the `gaps` array from **this entry only**, and write the file back.
    Re-read immediately before writing: other agents edit this file too. Leave
    every other entry and field byte-identical. If you covered some but not all
    items, leave the array in place; a partly-drained queue is a lie.

## Fact-check gate (runs after you finish — you cannot bypass it)

Once you finish, a **separate agent** is given your finished file and nothing
else. It is told it did not write the file, and asked to find any incorrect
formula, wrong mechanism description, or false factual claim. Its verdict is
required before this item is accepted, and it does not see your reasoning — so a
claim that only looks right in context will be caught.

Write for that reviewer:

- Every formula must be correct as written, including scaling factors,
  normalisation terms and exponents. If you write softmax(QKᵀ/√d_k)V, the √d_k
  must be there and must be in the denominator.
- Every number must be real. Do not invent benchmark figures, parameter counts,
  latencies or costs to make a sentence land. If you are not sure of a number,
  describe the magnitude qualitatively instead.
- Attribute papers, tools and techniques correctly, or not at all.
- Do not pad to hit a word count with claims you cannot stand behind. A shorter
  section that is true beats a longer one that is not — the word floor is a
  minimum for *real* content, not a licence to speculate.
- Keep the visualization's numbers consistent with the prose. If the text says
  the ring has 128 virtual nodes, the JS must not use 64.

If this item comes back rejected, you will be shown the exact FAIL lines. Fix the
underlying fact — do not reword around it.

## Validation Checklist (run before marking done)

- [ ] File exists at correct path
- [ ] All 5 structural elements present
- [ ] Visualization has at least one event listener or animation loop
- [ ] No placeholder text (grep for "TODO", "PLACEHOLDER", "Lorem ipsum", "coming soon", "<!-- ")
- [ ] File is self-contained — no local asset files. Sibling concept `.html`
      links in the `.concept-nav` are required and allowed.
- [ ] `#theory` meets the word floor for this concept's `depth` (intro 300 / core 500 / advanced 700)
- [ ] If `has_code` is true: at least one `<pre>` with real multi-line code
- [ ] If the entry has `gaps`: every item covered, and the `gaps` array removed
      from that entry in `concepts.json` (only when all of them are done)
- [ ] Every topic named in a compound title is actually implemented in the JS
      (a page titled "X & Y" whose script never mentions Y will be rejected)
- [ ] Playwright: file opens and renders content (not blank white page)
- [ ] Playwright: no uncaught JS errors in console
- [ ] Playwright: screenshot shows the visualization is visible

## Playwright testing steps

```
1. Use playwright mcp to navigate to: file:///absolute/path/to/machine_learning/concepts/<id>.html
2. Take a screenshot
3. Check console for errors
4. If errors found → fix HTML → re-test
```

## Design tokens (must match — same as `ai-engineering/concepts/`)

```css
--bg: #0d0f17; --surface: #141720; --card: #1a1e2e; --border: #252a3d;
--accent: #00d4ff; --purple: #7c3aed; --green: #00ff88; --yellow: #ffd700;
--red: #ff4757; --orange: #ff9500; --text: #e2e8f0; --text-dim: #8892a4;
```

Fonts: Inter + JetBrains Mono from Google Fonts CDN only.
No other external CDN links. All visualization code is vanilla JS.
