# Ralph Concepts — Agent Prompt

## Context files (read every iteration)

| Doc | Path |
|-----|------|
| Spec | `ralph-concepts/spec.md` |
| Plan | `ralph-concepts/plan.md` |
| Concept list | `ralph-concepts/concepts.json` |
| Progress | `ralph-concepts/progress.txt` |

## Rules

1. Read `ralph-concepts/plan.md` — pick **exactly ONE** unchecked item from **Next** (the first unchecked item).
2. Read `ralph-concepts/concepts.json` to get the full concept definition (title, description, viz guidance, group).
3. Generate the HTML file at `ai-engineering/concepts/<id>.html`.
4. Self-validate (see Validation Checklist below).
5. Use Playwright MCP to open the file, take a screenshot, and check for JS console errors.
6. If validation or Playwright check fails — fix the file, then re-check.
7. After passing all checks:
   - Mark item as done in `ralph-concepts/plan.md` (`- [ ]` → `- [x]`)
   - Append one line to `ralph-concepts/progress.txt`
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
  <title>{concept title} — AI Engineering Concepts</title>
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
- Add a "Production Reality" or "Why it matters" subsection with real numbers/tools.

### Visualization section
- Lead with a title and brief description of what the viz shows and how to interact with it.
- Build the viz using vanilla JS + Canvas or inline SVG.
- Must have real interactivity: sliders, buttons, click handlers, or animation loops.
- Follow the `viz` field from concepts.json for what to build.
- Controls should be labeled clearly. Show current values next to sliders.

### Key Takeaways section
- 4–6 `<li>` items.
- Senior-level insights: tradeoffs, production gotchas, real numbers, tool names.
- Not definitions — insights a junior would miss.

### Concept nav
- Previous and next concept links using relative paths.
- If first concept, prev link is disabled. If last, next link is disabled.

## Depth and code requirements (from `concepts.json`)

Each concept entry carries two fields that the validator enforces:

- **`depth`** — sets the minimum word count for `#theory`:
  `intro` → 300 words, `core` → 500, `advanced` → 700.
  An entry with no `depth` falls back to the spec floor of 400.
  Write to the concept's depth; do not pad a `core` topic to `advanced` length.
- **`has_code`** — when `true`, the page **must** contain at least one `<pre>`
  block holding real, multi-line, code-shaped content: the algorithm's inner
  loop, the update rule, a config snippet, the key API call with its decisive
  hyperparameter. A `<pre>` holding a single line, or prose, does not count.
  When `false`, do not add a code block just to satisfy a checker.

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
- [ ] Every topic named in a compound title is actually implemented in the JS
      (a page titled "X & Y" whose script never mentions Y will be rejected)
- [ ] Playwright: file opens and renders content (not blank white page)
- [ ] Playwright: no uncaught JS errors in console
- [ ] Playwright: screenshot shows the visualization is visible

## Playwright testing steps

```
1. Use playwright mcp to navigate to: file:///absolute/path/to/ai-engineering/concepts/<id>.html
2. Take a screenshot
3. Check console for errors
4. If errors found → fix HTML → re-test
```

## Design tokens (must match)

```css
--bg: #0d0f17; --surface: #141720; --card: #1a1e2e; --border: #252a3d;
--accent: #00d4ff; --purple: #7c3aed; --green: #00ff88; --yellow: #ffd700;
--red: #ff4757; --orange: #ff9500; --text: #e2e8f0; --text-dim: #8892a4;
```

Fonts: Inter + JetBrains Mono from Google Fonts CDN only.
No other external CDN links. All visualization code is vanilla JS.
