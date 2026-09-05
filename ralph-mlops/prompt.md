# Ralph MLOps — Agent Prompt

## Context files (read every iteration)

| Doc | Path |
|-----|------|
| Spec | `ralph-mlops/spec.md` |
| Plan | `ralph-mlops/plan.md` |
| Concept list | `ralph-mlops/concepts.json` |
| Progress | `ralph-mlops/progress.txt` |

## Rules

1. Read `ralph-mlops/plan.md` — pick **exactly ONE** unchecked item from **Next** (the first unchecked item).
2. Read `ralph-mlops/concepts.json` for the full definition (title, description, viz guidance, group, `depth`, `has_code`).
3. Generate the HTML file at `mlops/concepts/<id>.html`.
4. Self-validate (see Validation Checklist below).
5. Use Playwright MCP to open the file, take a screenshot, and check for JS console errors.
6. If validation or the Playwright check fails — fix the file, then re-check.
7. After passing all checks:
   - Mark the item done in `ralph-mlops/plan.md` (`- [ ]` → `- [x]`)
   - Append one line to `ralph-mlops/progress.txt`
8. If ALL items in the plan are done, emit `<promise>COMPLETE</promise>`.

## One task per run — do not start the next plan item.

## HTML generation guidelines

### Structure
```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8"/>
  <meta name="viewport" content="width=device-width,initial-scale=1.0"/>
  <title>{concept title} — MLOps Concepts</title>
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
- Deep, senior-level. Word floor is set by this concept's `depth` — see below.
- `<h3>` per sub-topic, plus `<p>`, `<ul>`, `<code>`, `<pre>`.
- Formulas inline with unicode (`PSI = Σ (aᵢ − eᵢ) · ln(aᵢ/eᵢ)`) — no LaTeX renderer.
- **Name the failure mode explicitly** — training-serving skew, label lag, feedback loop, silent degradation, feature staleness, schema drift. These are what interviewers listen for.
- Say plainly what is *not* detectable without labels. A drift alarm is not a performance alarm, and claiming otherwise is the most common wrong answer in this round.

### Visualization section
- Lead with a title and a line on what it shows and how to interact.
- Vanilla JS + Canvas or inline SVG. Follow the `viz` field.
- **Compute the real mechanism client-side.** If the concept is PSI, actually bin two distributions and actually sum the PSI terms as the user drags the shifted distribution. Do not animate a pre-computed result.
- Label controls; show current values next to sliders.

### Interview line section
- Quote-styled callout with the sentence to say when this comes up. Specific, names a real trade-off, sounds spoken rather than recited.

### Key Takeaways
- 4–6 `<li>`. Real numbers, real tool names, production gotchas. Insights a junior would miss.

### Concept nav
- Prev/next relative links within `mlops/concepts/`. First has prev disabled, last has next disabled.

## Depth and code requirements (from `concepts.json`)

- **`depth`** sets the `#theory` minimum: `intro` → 300 words, `core` → 500, `advanced` → 700 (400 if absent). Write to the concept's depth; do not pad a `core` topic to `advanced` length.
- **`has_code`** — when `true`, the page **must** contain at least one `<pre>` with real multi-line code (a PSI computation, a point-in-time-correct join, an Airflow DAG fragment, a canary split config, an MLflow call). A single-line or prose `<pre>` does not count. When `false`, do not add one.
- A compound title (`X vs Y`, `X & Y`) must have **both** terms implemented in the JS. `Data Drift vs Concept Drift` needs both drift types simulated, not one.

## Fact-check gate (runs after you finish — you cannot bypass it)

Once you finish, a **separate agent** is given your finished file and nothing else. It is told it did not write the file, and asked to find any incorrect formula, wrong mechanism description, or false factual claim. Its verdict is required before this item is accepted, and it does not see your reasoning — so a claim that only looks right in context will be caught.

Write for that reviewer:

- Every formula must be correct as written. The PSI sum, the KL direction, the KS statistic as a supremum of the CDF difference — get the definition right or omit it.
- **Every threshold and number must be real.** PSI > 0.2 is a genuine convention; do not invent a threshold for a metric that has none, and do not attach fabricated latency or cost figures to a tool. If you are unsure, describe the magnitude qualitatively.
- Attribute tools correctly. Do not credit a capability to Feast that belongs to Tecton, or to MLflow that belongs to W&B.
- Do not pad to hit the word floor with claims you cannot stand behind. A shorter section that is true beats a longer one that is not.
- Keep the viz consistent with the prose: if the text says PSI 0.25 triggers a retrain, the JS threshold must be 0.25.

If this item comes back rejected, you will be shown the exact `FAIL:` lines. Fix the underlying fact — do not reword around it.

## Validation Checklist (run before marking done)

- [ ] File exists at `mlops/concepts/<id>.html`
- [ ] All required sections present (header, theory, visualization, interview-line, takeaways, concept-nav)
- [ ] Visualization has at least one event listener or animation loop
- [ ] No placeholder text (`TODO`, `PLACEHOLDER`, `Lorem ipsum`, `coming soon`)
- [ ] Self-contained — no local asset files. Sibling concept `.html` links in the nav are required and allowed.
- [ ] `#theory` meets the word floor for this concept's `depth`
- [ ] If `has_code` is true: at least one `<pre>` with real multi-line code
- [ ] Every topic named in a compound title is actually implemented in the JS
- [ ] Playwright: renders, no uncaught console errors, viz visible

## Playwright testing steps

```
1. navigate to: file:///absolute/path/to/mlops/concepts/<id>.html
2. screenshot
3. check console for errors
4. if errors → fix HTML → re-test
```

## Design tokens (must match the rest of the repo)

```css
--bg: #0d0f17; --surface: #141720; --card: #1a1e2e; --border: #252a3d;
--accent: #00d4ff; --purple: #7c3aed; --green: #00ff88; --yellow: #ffd700;
--red: #ff4757; --orange: #ff9500; --text: #e2e8f0; --text-dim: #8892a4;
```

Fonts: Inter + JetBrains Mono from Google Fonts CDN only. No other external CDN. All viz code is vanilla JS.
