# Ralph Backend — Agent Prompt

## Context files (read every iteration)

| Doc | Path |
|-----|------|
| Spec | `ralph-backend/spec.md` |
| Plan | `ralph-backend/plan.md` |
| Concept list | `ralph-backend/concepts.json` |
| Progress | `ralph-backend/progress.txt` |
| Cross-links | `ralph-backend/sources/_cross-links.md` |
| Source notes (if `source` field present on the concept) | `ralph-backend/sources/<id>.md` |

## Rules

1. Read `ralph-backend/plan.md` — pick **exactly ONE** unchecked item from **Next** (the first unchecked item).
2. Read `ralph-backend/concepts.json` to get the full concept definition (title, description, viz guidance, group, and `source` field if present).
3. **If a `source` field is present**, read that file in full first — it's hand-written senior-level notes at the target depth. Your `#theory` section is an adaptation of it (see spec.md § Source material), and your `#interview-line` section uses its "In the room" quote. **If no `source` field**, write theory and an interview-line quote from scratch in the same voice, using `sources/_cross-links.md` for how it relates to other concepts.
4. Generate the HTML file at `backend/concepts/<id>.html`.
5. Self-validate (see Validation Checklist below).
6. Use Playwright MCP to open the file, take a screenshot, and check for JS console errors.
7. If validation or Playwright check fails — fix the file, then re-check.
8. After passing all checks:
   - Mark item as done in `ralph-backend/plan.md` (`- [ ]` → `- [x]`)
   - Append one line to `ralph-backend/progress.txt`
9. If ALL items in plan are done, emit `<promise>COMPLETE</promise>`.

## One task per run — do not start the next plan item.

## HTML generation guidelines

### Structure
```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8"/>
  <meta name="viewport" content="width=device-width,initial-scale=1.0"/>
  <title>{concept title} — Backend Concepts</title>
  <style>/* ALL styles inline here */</style>
</head>
<body>
  <header>...</header>
  <main>
    <section id="theory">...</section>
    <section id="visualization">...</section>
    <section id="interview-line">...</section>
    <section id="takeaways">...</section>
  </main>
  <nav class="concept-nav">...</nav>
  <script>/* ALL JS inline here */</script>
</body>
</html>
```

### Theory section
- Write deep, senior-level content. Minimum 400 words.
- Use `<h3>` per sub-topic (mirror the source file's sub-headings when one exists), `<p>`, `<ul>`, `<code>`, `<pre>` as needed.
- Include math/formulas inline with unicode or simple notation (e.g. `W + R > N`) — no LaTeX renderer needed.
- Name failure modes explicitly (thundering herd, split-brain, write skew, etc.) — these are what interviewers listen for.

### Visualization section
- Lead with a title and brief description of what the viz shows and how to interact with it.
- Build the viz using vanilla JS + Canvas or inline SVG.
- Must have real interactivity: sliders, buttons, click handlers, or animation loops.
- Prefer simulating the actual mechanism client-side (real token-bucket refill math, real consistent-hash ring remap, real Raft-style majority check) over a pre-baked animation.
- Follow the `viz` field from concepts.json for what to build.
- Controls should be labeled clearly. Show current values next to sliders.

### Interview line section
- A visually distinct callout (blockquote styling, accent border) with the exact sentence(s) to say when this topic comes up in an interview.
- For sourced concepts, use the source file's "In the room" quote — verbatim or lightly adapted for the HTML context.
- For unsourced concepts, write an equivalent: specific to a real trade-off, not a generic definition. It should sound like something actually said out loud, not read from a slide.

### Key Takeaways section
- 4–6 `<li>` items.
- Senior-level insights: tradeoffs, production gotchas, real numbers, real tool/system names.
- Where genuinely true, draw one explicit connection to another concept in this set (see `sources/_cross-links.md`) — that's what signals systems thinking rather than a definitions recital.

### Concept nav
- Previous and next concept links using relative paths within `backend/concepts/`.
- If first concept, prev link is disabled. If last, next link is disabled.

## Validation Checklist (run before marking done)

- [ ] File exists at correct path
- [ ] All required structural elements present (header, theory, visualization, interview-line, takeaways, concept-nav)
- [ ] Visualization has at least one event listener or animation loop
- [ ] No placeholder text (grep for "TODO", "PLACEHOLDER", "Lorem ipsum", "coming soon", "<!-- ")
- [ ] File is self-contained (no local `src=` or `href=` references except Google Fonts)
- [ ] For sourced concepts: theory doesn't drop or contradict a named pattern/failure mode from the source file
- [ ] Playwright: file opens and renders content (not blank white page)
- [ ] Playwright: no uncaught JS errors in console
- [ ] Playwright: screenshot shows the visualization is visible

## Playwright testing steps

```
1. Use playwright mcp to navigate to: file:///absolute/path/to/backend/concepts/<id>.html
2. Take a screenshot
3. Check console for errors
4. If errors found → fix HTML → re-test
```

## Design tokens (must match — same as `ai-engineering/concepts/` and `machine_learning/concepts/`)

```css
--bg: #0d0f17; --surface: #141720; --card: #1a1e2e; --border: #252a3d;
--accent: #00d4ff; --purple: #7c3aed; --green: #00ff88; --yellow: #ffd700;
--red: #ff4757; --orange: #ff9500; --text: #e2e8f0; --text-dim: #8892a4;
```

Fonts: Inter + JetBrains Mono from Google Fonts CDN only.
No other external CDN links. All visualization code is vanilla JS.
