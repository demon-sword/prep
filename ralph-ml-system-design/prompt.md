# Ralph ML System Design — Agent Prompt

## Context files (read every iteration)

| Doc | Path |
|-----|------|
| Spec | `ralph-ml-system-design/spec.md` |
| Plan | `ralph-ml-system-design/plan.md` |
| Case study list | `ralph-ml-system-design/topics.json` |
| Progress | `ralph-ml-system-design/progress.txt` |

## Rules

1. Read `ralph-ml-system-design/plan.md` — pick **exactly ONE** unchecked item from **Next** (the first unchecked item).
2. Read `ralph-ml-system-design/topics.json` for the full definition — especially the **`scale`** object (your starting numbers) and **`capacity_anchors`** (the derivations you must show).
3. Generate the HTML file at `ml-system-design/<id>.html`.
4. Self-validate (see Validation Checklist below).
5. Use Playwright MCP to open the file, screenshot, check for JS console errors.
6. If validation or the Playwright check fails — fix, then re-check.
7. After passing all checks:
   - Mark the item done in `ralph-ml-system-design/plan.md`
   - Append one line to `ralph-ml-system-design/progress.txt`
8. If ALL items are done, emit `<promise>COMPLETE</promise>`.

## One task per run — do not start the next plan item.

## The capacity section is the whole point of this track

Read this before writing anything else.

These interviews test whether you can turn a product number into an infrastructure number, out loud, without a calculator. The rest of the repo never trains that. Your `#capacity` section must **show the arithmetic**, not state the conclusion.

Start from the entry's `scale` object and derive. Cover **every** anchor in `capacity_anchors`.

```
300M DAU × 20 requests/day   = 6×10⁹ req/day
6×10⁹ / 86,400 s             ≈ 69,000 QPS average   (86,400 ≈ 10⁵, so ≈ 7×10⁴)
peak = 3 × average           ≈ 208,000 QPS
feed row 512 B × 500M items  = 256 GB → 3 shards at 128 GB usable
p99 150 ms = 20 retrieval + 60 ranking + 30 feature fetch + 40 slack
ranker 2,000 QPS/GPU → 208,000 / 2,000 = 104 GPUs, +30% headroom ≈ 135
```

Rules for this section:

- **Round aggressively and say so.** Showing that 86,400 ≈ 10⁵ is the skill. False precision is not.
- **Never assert a number you did not derive.** "We need ~100 GPUs" with no working is exactly the failure this track exists to prevent, and the validator rejects it: the section must contain at least 12 numbers *and* real arithmetic (`× / = →`).
- State your per-unit assumptions explicitly — bytes per row, QPS per GPU, cache hit rate. An interviewer will challenge one; make it visible so it can be challenged.
- Sanity-check the result out loud. If the maths says 40,000 GPUs, say that it is implausible and find the wrong assumption.
- A derivation that shows its working and reaches the **wrong answer** is worse than none. The fact-check agent checks the arithmetic.

## HTML generation guidelines

### Structure
```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8"/>
  <meta name="viewport" content="width=device-width,initial-scale=1.0"/>
  <title>{case study title} — ML System Design</title>
  <style>/* ALL styles inline here */</style>
</head>
<body>
  <header>...</header>
  <main>
    <section id="problem">...</section>
    <section id="capacity">...</section>
    <section id="architecture">...</section>
    <section id="visualization">...</section>
    <section id="tradeoffs">...</section>
    <section id="takeaways">...</section>
  </main>
  <nav class="concept-nav">...</nav>
  <script>/* ALL JS inline here */</script>
</body>
</html>
```

### Problem section
Open the way you would open the interview: functional vs non-functional requirements, what you explicitly descope, the SLO you design to, and the ML framing — what is the label, what is the prediction, where does the feedback loop close, and how delayed is the ground truth.

### Capacity section
See above. Use a `<pre>` or a table so the arithmetic reads as arithmetic.

### Architecture section
Components and data flow. The offline/online split. Where the model lives, how features reach it, what is precomputed vs computed per request. Name real systems (Kafka, Flink, Redis, Cassandra, Faiss, ScaNN, HNSW, Triton, vLLM, Feast).

### Visualization section
The capacity section made tangible: the user drags DAU / corpus size / latency budget / QPS-per-GPU and the derived numbers — QPS, shards, replicas, storage, cost — recompute live. **The arithmetic must genuinely run in JS**, consistent with the numbers in `#capacity`. Vanilla JS + Canvas or SVG.

### Trade-offs section
The decisions that could have gone the other way, and what would flip each. Precision/recall vs latency, freshness vs cost, batch vs online, exact vs approximate retrieval, one big model vs cascade.

### Key Takeaways
4–6 bullets recallable under pressure.

## Depth and code requirements (from `topics.json`)

- **`depth`** sets the whole-body word floor: `intro` → 500, `core` → 800, `advanced` → 1100 (700 if absent).
- **`has_code`** — when `true`, at least one `<pre>` with real multi-line code (ANN index build, two-tower training step, batched feature fetch, CTR calibration). When `false`, do not add one. Note the capacity arithmetic block is *not* what this refers to.
- A compound title must have both terms implemented in the JS.

## Fact-check gate (runs after you finish — you cannot bypass it)

A **separate agent** is given your finished file and nothing else. It is told it did not write the file, and asked to find any incorrect formula, wrong mechanism description, or false factual claim. Its verdict is required before this item is accepted.

This track is the most exposed in the repo to fabricated numbers, so:

- **Check your arithmetic.** Every division and multiplication in `#capacity` will be recomputed by the reviewer. `6×10⁹ / 86,400` is ~69,000, not ~600,000.
- Keep units consistent and correct — bytes vs bits, QPS vs QPM, GB vs GiB. A bandwidth figure that silently switches between bytes and bits is a hard fail.
- Per-unit assumptions must be *plausible*, and stated as assumptions. Do not invent a benchmark ("Triton serves 50,000 QPS per A100") as though it were a published fact; frame it as the assumption it is.
- Do not attach fabricated latency, throughput or price figures to named products.
- The JS must compute the same arithmetic as the prose. If `#capacity` says 104 GPUs at the stated inputs, the viz at those inputs must show 104.
- Do not pad to the word floor with claims you cannot stand behind.

If rejected, you will be shown the exact `FAIL:` lines. Fix the underlying fact or the underlying arithmetic — do not reword around it.

## Validation Checklist (run before marking done)

- [ ] File exists at `ml-system-design/<id>.html`
- [ ] All required sections present (problem, capacity, architecture, visualization, tradeoffs, takeaways, concept-nav)
- [ ] `#capacity` has ≥12 numbers **and** visible arithmetic (`× / = →`)
- [ ] `#capacity` covers **every** anchor in this entry's `capacity_anchors`
- [ ] Body meets the word floor for this entry's `depth`
- [ ] If `has_code` is true: at least one `<pre>` with real multi-line code
- [ ] Visualization recomputes derived numbers live and agrees with `#capacity`
- [ ] No placeholder text; self-contained (sibling `.html` nav links allowed)
- [ ] Playwright: renders, no uncaught console errors

## Playwright testing steps

```
1. navigate to: file:///absolute/path/to/ml-system-design/<id>.html
2. screenshot
3. check console for errors
4. drag a scale control and confirm the derived numbers change
5. if errors → fix HTML → re-test
```

## Design tokens (must match the rest of the repo)

```css
--bg: #0d0f17; --surface: #141720; --card: #1a1e2e; --border: #252a3d;
--accent: #00d4ff; --purple: #7c3aed; --green: #00ff88; --yellow: #ffd700;
--red: #ff4757; --orange: #ff9500; --text: #e2e8f0; --text-dim: #8892a4;
```

Fonts: Inter + JetBrains Mono from Google Fonts CDN only. All viz code is vanilla JS.
