# Ralph Machine Learning — Spec

Generates **self-contained interactive HTML concept files** under `machine_learning/concepts/` — one concept per file — targeting senior ML engineer / data scientist interview depth.

## Goal

Each HTML teaches one classical ML / DL concept visually and interactively. A candidate studying these should be able to:
1. Understand the theory deeply (not surface-level)
2. See the mechanism animate (not just read about it)
3. Interact with parameters to build intuition
4. Walk away with a crisp mental model, ready to explain it on a whiteboard

## Scope note (vs `ai-engineering/`)

`ai-engineering/categories/06-ml-fundamentals.md` already covers classical ML at intro depth, scoped to what shows up in LLM/AI-engineer interviews. This track is a **separate, deeper pass** for dedicated ML Engineer / Data Scientist interviews — algorithms, statistics, ensembles, unsupervised learning, DL fundamentals, ML system design, and MLOps. Don't duplicate `06-ml-fundamentals` content; go deeper into mechanism and production tradeoffs.

## Output artifact per concept

| Attribute | Requirement |
|-----------|-------------|
| Path | `machine_learning/concepts/<id>.html` |
| Format | Fully self-contained HTML — no external dependencies except Google Fonts CDN |
| Theme | Dark terminal theme (see Design System below) — matches the rest of the repo |
| Sections | Header, Theory, Visualization, Key Takeaways |
| Visualization | Interactive (JS-driven) — not a static diagram |
| Code | All CSS and JS inline in `<style>` and `<script>` tags |
| Mobile | Responsive — works on tablet and desktop |

## Required HTML sections (in order)

1. **`<header>`** — concept title, group badge, one-sentence description
2. **`<section id="theory">`** — deep theory: what it is, how it works, when/why it matters, tradeoffs, math where helpful. Word floor set by the entry's `depth` field — `intro` 300, `core` 500, `advanced` 700 (400 if `depth` is absent) — of real content. No placeholders.
3. **`<section id="visualization">`** — the interactive viz. Must be functional JS, not a placeholder. Controls (sliders, buttons, toggles) must do something real — ideally computing the actual algorithm live (e.g. real k-means iterations, real gradient descent steps), not a canned animation.
4. **`<section id="takeaways">`** — 4–6 bullet points. Senior-level insights, not beginner summaries. Include real numbers, library names (scikit-learn, XGBoost, statsmodels, etc.), and production gotchas.
5. **`<nav class="concept-nav">`** — prev/next links to adjacent concept files (use relative paths `../concepts/<id>.html`)

## Design system (match exactly — same tokens as `ai-engineering/concepts/`)

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
No other external dependencies — no D3 CDN, no Chart.js CDN, no scikit-learn-in-the-browser. All visualization logic and any "live" algorithm computation (k-means, gradient descent, PCA, etc.) must be vanilla JS + Canvas or SVG, computed client-side from scratch.

## Visualization quality bar

The viz must be **genuinely interactive** and, wherever the concept allows, **mechanistically real** (actually run the algorithm in JS on the sample data, not a pre-baked animation):
- At minimum: user can click, drag, or adjust a slider and see the diagram change
- Prefer: animated flows / iterative algorithm steps that show the mechanism in motion (use `requestAnimationFrame`)
- Avoid: static SVG with no interaction, or a viz that's just a colored rectangle

Each concept's `concepts.json` entry has a `viz` field describing what to build — follow it.

## Theory quality bar

- Explain the mechanism, not just the definition
- Include real numbers where they exist (e.g. "XGBoost's default learning rate is 0.3; production tuning usually lands 0.01–0.1 with more trees")
- Include production-relevant tradeoffs (compute, interpretability, data requirements, failure modes)
- Reference real tools/libraries (scikit-learn, XGBoost, LightGBM, statsmodels, imbalanced-learn, etc.)
- Write for a candidate who knows programming but wants senior-level ML depth — skip trivial definitions, go deep on mechanisms and tradeoffs

## Validation checks (agent self-checks after writing)

1. HTML parses without error (no unclosed tags)
2. All 5 sections present (`header`, `#theory`, `#visualization`, `#takeaways`, `.concept-nav`)
3. Visualization has at least one event listener (click, input, or animation loop)
4. No placeholder text (no "TODO", "PLACEHOLDER", "Lorem ipsum", "coming soon")
5. File is self-contained (no `src=` pointing to local files, no `href=` to local CSS)
6. Playwright screenshot shows rendered content (not blank)
7. Browser console has no uncaught JS errors

## Per-concept depth and code

Each `concepts.json` entry carries:

- **`depth`** — `intro` | `core` | `advanced`. Sets the `#theory` word floor:
  300 / 500 / 700 words. Missing `depth` falls back to 400.
- **`has_code`** — when `true`, the page must contain at least one `<pre>` block
  of real multi-line code (the algorithm's inner loop, the update rule, a config
  snippet). When `false`, do not add a code block for its own sake.

- **`gaps`** — optional array of specific depth omissions found by an audit of
  the **existing** page. Present only on concepts that already have a file. A run
  that picks up a gaps-bearing entry extends that page rather than regenerating
  it, must cover every item, and removes the array from that entry once all of
  them are covered. An entry with no `gaps` is either new or already at depth.

Compound titles are also checked: a page titled `X & Y` whose `<script>` never
mentions `Y` is rejected — half the title unimplemented is a real defect, not a
naming quibble.

## Enforcement — these gates are binding

`validate.sh` exit codes are honoured by `once.sh` and `loop.sh`. A failing
validation is never accepted, a `COMPLETE` promise is not believed unless
validation passes, and a rejected item is regenerated with the exact `FAIL:`
lines fed back into the next attempt. After 3 failed attempts the run stops
with an error rather than accepting unverified content.

A `COMPLETE` promise is checked against the corpus itself, not just against the
files in it. A per-file validator iterates over what exists, so on an empty or
half-finished corpus it checks nothing and reports a clean pass — right for a
mid-run sweep, and a lie for the final gate. `ralph_require_complete` closes it:
every item in `plan.md`, and every item in the queue JSON in case the plan was
never re-scaffolded, must have produced a file. The same reasoning applies
per-item: an item the agent never wrote is SKIPped and passes, so `once.sh`
confirms the file exists before believing the validator.

A second, independent fact-check agent then reads the finished file — and only
that file — looking for incorrect formulas, wrong mechanisms and false claims.
Its PASS is required too.

`../validate-corpus.sh` runs across a finished corpus and flags near-duplicate
explanations between files (copied 5-grams, and same-topic redundancy).
`--final` (or `RALPH_CORPUS_FINAL=1`) additionally fails a track whose corpus is empty or short of its queue — the end-of-run form of the same question `ralph_require_complete` asks inside the loop.

### Loop safety

`loop.sh` used to dispatch on a handful of exit codes and let everything else
fall through to the next iteration, with nothing sleeping in between. Against an
agent binary that exits immediately that is 80 real invocations in nine seconds.
Three guards now bound the damage:

- **Any exit code that is not "one item done, more remain" stops the loop.**
  Previously `1` matched no branch at all.
- **Three consecutive iterations that write no new file stop the loop** with exit
  `5`. An agent that produces nothing looks exactly like one doing real work if
  you only read exit codes. `RALPH_MAX_STALLS` tunes it; the counter resets the
  moment a file appears.
- **`RALPH_LOOP_SLEEP`** (default 5s) pauses between iterations.

The rejection budget lives in `<generator>/.state/`, not in a shell variable,
because `loop.sh` starts a fresh `once.sh` process for every iteration — an
in-process counter reset each time, and a 3-strike cap silently became a
`MAX`-strike one. It is keyed by run, so a new run starts with a full budget and
a `once.sh` invoked by hand is never charged for a previous run's strikes.

## File naming

`<id>.html` — use the `id` field from `concepts.json`

Examples:
- `01-bias-variance-tradeoff.html`
- `14-gradient-boosting.html`
- `29-cnn-convolution.html`

## Plan format

`ralph-machine-learning/plan.md` — tracks which concepts are done:

```
## Done
- [x] scaffold

## Next
- [ ] 01-bias-variance-tradeoff — Bias-Variance Tradeoff
- [ ] 02-bayes-theorem — Bayes' Theorem
...
```

## Progress log

Append one line per completed concept to `ralph-machine-learning/progress.txt`:
```
2026-08-13 | 01-bias-variance-tradeoff | Bias-Variance Tradeoff | OK
```
