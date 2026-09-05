# Ralph MLOps — Spec

Generates **self-contained interactive HTML concept files** under `mlops/concepts/` — one concept per file — targeting the production-ML round of a senior (7–8 yr) ML engineer interview.

## Goal

This is the round that asks "your model is live and something is wrong — what do you look at, in what order, and what do you change?" It is not a modelling round. A candidate studying these should be able to:

1. Explain the mechanism of a production ML failure, not just name it
2. See it animate — the real detector or rollout computed live in JS
3. Interact with parameters to build intuition for the trade-off
4. Walk away with the exact sentence to say when the topic comes up

The repo had no coverage of this at all before this track: a repo-wide search found two passing mentions of "drift" and nothing else.

## Output artifact per concept

| Attribute | Requirement |
|-----------|-------------|
| Path | `mlops/concepts/<id>.html` |
| Format | Fully self-contained HTML — no external dependencies except Google Fonts CDN |
| Theme | Dark terminal theme (see Design System below) — matches the rest of the repo |
| Sections | Header, Theory, Visualization, Interview Line, Key Takeaways |
| Visualization | Interactive (JS-driven) — not a static diagram |
| Code | All CSS and JS inline in `<style>` and `<script>` tags |
| Mobile | Responsive — works on tablet and desktop |

## Required HTML sections (in order)

1. **`<header>`** — concept title, group badge, one-sentence description
2. **`<section id="theory">`** — deep theory, sub-sectioned with `<h3>`: mechanism, the options and what separates them, the trade-off that actually matters, named failure modes. Word floor set by the entry's `depth` field — `intro` 300, `core` 500, `advanced` 700 (400 if absent). No placeholders.
3. **`<section id="visualization">`** — the interactive viz. Follow the `viz` field from `concepts.json`. Compute the real mechanism client-side wherever the concept allows: an actual PSI calculation over two histograms, an actual KS statistic, an actual canary traffic split with a real error-rate rollup.
4. **`<section id="interview-line">`** — a visually distinct callout with the exact sentence(s) to say when this comes up. Specific, references a real trade-off, sounds like something said out loud rather than read from a slide.
5. **`<section id="takeaways">`** — 4–6 bullets. Senior-level: real numbers, real tool names (MLflow, Feast, Tecton, Evidently, Great Expectations, Airflow, Seldon, KServe, Triton), production gotchas.
6. **`<nav class="concept-nav">`** — prev/next links to adjacent concept files.

## Per-concept depth and code

Each `concepts.json` entry carries:

- **`depth`** — `intro` | `core` | `advanced`. Sets the `#theory` word floor: 300 / 500 / 700. Missing `depth` falls back to 400.
- **`has_code`** — when `true`, the page must contain at least one `<pre>` block of real multi-line code: the PSI formula as code, a point-in-time-correct feature join, an Airflow DAG fragment, a canary traffic-split config, an MLflow logging call. When `false`, do not add a code block for its own sake.

Compound titles are checked: a page titled `X vs Y` whose `<script>` never mentions `Y` is rejected — half the title unimplemented is a real defect. `Data Drift vs Concept Drift` must implement *both*.

## Theory quality bar

- Explain the mechanism, not the definition — the reader already knows the vocabulary and wants the trade-off
- Real numbers where they exist (PSI > 0.2 as the conventional "investigate" threshold, > 0.25 as "act"; a 1–5% canary as the usual first step)
- Distinguish what is genuinely detectable from what only *looks* detectable — a drift alarm with no labels is not a performance alarm
- Name the failure mode: training-serving skew, label lag, feedback loop, silent degradation, feature staleness, schema drift
- Write for someone who has been paged for a model at 3am

## Visualization quality bar

Genuinely interactive and, wherever possible, mechanistically real — simulate the detector or the rollout step by step in JS, not a pre-baked animation. Minimum: the user changes something and the diagram responds. Prefer: drag a distribution and watch PSI/KL/KS recompute live.

No D3, no Chart.js. Vanilla JS + Canvas or inline SVG.

## Design system (match exactly — same tokens as the other tracks)

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

Fonts: Inter + JetBrains Mono from Google Fonts CDN only.

## Enforcement — these gates are binding

`validate.sh` exit codes are honoured by `once.sh` and `loop.sh`. A failing validation is never accepted, a `COMPLETE` promise is not believed unless validation passes, and a rejected item is regenerated with the exact `FAIL:` lines fed back into the next attempt. After 3 failed attempts the run stops with an error rather than accepting unverified content.

A `COMPLETE` promise is checked against the corpus itself, not just against the
files in it. A per-file validator iterates over what exists, so on an empty or
half-finished corpus it checks nothing and reports a clean pass — right for a
mid-run sweep, and a lie for the final gate. `ralph_require_complete` closes it:
every item in `plan.md`, and every item in the queue JSON in case the plan was
never re-scaffolded, must have produced a file. The same reasoning applies
per-item: an item the agent never wrote is SKIPped and passes, so `once.sh`
confirms the file exists before believing the validator.

A second, independent fact-check agent then reads the finished file — and only that file — looking for incorrect formulas, wrong mechanisms and false claims. Its PASS is required too. This track is especially exposed to invented numbers (thresholds, latencies, costs), so that gate matters here.

`../validate-corpus.sh mlops` flags near-duplicate explanations across the corpus.

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

`<id>.html` — use the `id` field from `concepts.json`.

## Plan format

`ralph-mlops/plan.md`, built by `scaffold.sh`:

```
## Done
- [x] scaffold

## Next
- [ ] 01-data-validation — Data Validation for ML Pipelines
...
```

## Progress log

Append one line per completed concept to `ralph-mlops/progress.txt`:

```
2026-08-30 | 01-data-validation | Data Validation for ML Pipelines | OK
```
