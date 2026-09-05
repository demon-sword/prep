# Ralph ML System Design — Spec

Generates **self-contained interactive HTML case studies** under `ml-system-design/` — one case study per file — for the ML system design round of a senior ML engineer interview.

## What this track is, and what it is not

The existing `system-design/` folder is **frontend** system design: its spec requires a `<topic>-frontend-architecture.html` artifact, and across its 108 files there are 9 total mentions of "QPS" and zero capacity estimation.

This track is the opposite. It is backend/ML system design, and **back-of-envelope numeracy is its load-bearing skill**. The thing these interviews actually test — and the thing the existing material never trains — is whether a candidate can turn "300M DAU" into a replica count, a shard count, a storage bill and a latency budget, out loud, without a calculator.

So: **every case study must derive its numbers, and the validator enforces it.** A page that asserts "we need about 100 GPUs" without showing the arithmetic fails.

## Output artifact per case study

| Attribute | Requirement |
|-----------|-------------|
| Path | `ml-system-design/<id>.html` |
| Format | Fully self-contained HTML — no external dependencies except Google Fonts CDN |
| Theme | Dark terminal theme (same tokens as the rest of the repo) |
| Sections | Header, Problem, **Capacity**, Architecture, Visualization, Trade-offs, Key Takeaways |
| Visualization | Interactive — the user drags the input scale and the derived numbers recompute live |
| Code | All CSS and JS inline |

## Required HTML sections (in order)

1. **`<header>`** — case study title, group badge, one-line framing
2. **`<section id="problem">`** — requirements clarification the way you would actually open the interview: functional vs non-functional, what you explicitly descope, the SLO you are designing to, and the ML framing (what is the label, what is the prediction, what is the feedback loop).
3. **`<section id="capacity">`** — **mandatory, and validator-enforced.** See below.
4. **`<section id="architecture">`** — the design. Components, data flow, the offline/online split, where the model lives, how features reach it. Name real systems (Kafka, Flink, Redis, Cassandra, Faiss, ScaNN, Triton, vLLM, Feast).
5. **`<section id="visualization">`** — interactive. The user drags DAU / corpus size / latency budget and watches QPS, shard count, replica count, storage and cost recompute. The arithmetic must genuinely run in JS — this viz *is* the capacity section made tangible.
6. **`<section id="tradeoffs">`** — the decisions that could have gone the other way, and what would flip each one. Precision/recall vs latency, freshness vs cost, batch vs online, exact vs approximate retrieval.
7. **`<section id="takeaways">`** — 4–6 bullets a candidate can recall under pressure.
8. **`<nav class="concept-nav">`** — prev/next links.

## The capacity section — the point of this track

`topics.json` gives each case study a `scale` object (the starting numbers) and a `capacity_anchors` list (the derivations that must appear). The section must **show the arithmetic**, not the conclusion.

Enforced by `validate.sh`:

- the section exists;
- it contains **at least 12 numbers**;
- it contains **actual arithmetic** — at least one of `×  x  *  /  =  ÷  +  →  ->`. Numbers asserted without derivation fail;
- **every anchor** named in that entry's `capacity_anchors` leaves a trace (a QPS anchor needs "qps", a storage anchor needs a byte unit, a GPU anchor needs "gpu"/"replica", and so on).

Write it as a senior candidate would say it out loud:

```
300M DAU × 20 requests/day = 6×10⁹ req/day
6×10⁹ / 86,400 s        ≈ 69,000 QPS average
peak = 3 × average       ≈ 208,000 QPS
feed row 512 B × 500M items = 256 GB  → 3 shards at 128 GB usable
p99 budget 150 ms = 20 retrieval + 60 ranking + 30 feature fetch + 40 slack
ranker 2,000 QPS/GPU → 208,000 / 2,000 = 104 GPUs, +30% headroom = 135
```

Round aggressively and say so. Showing that 86,400 ≈ 10⁵ is the skill; false precision is not.

## Per-case-study depth and code

- **`depth`** — `intro` | `core` | `advanced`. Word floor across the whole case study body: **500 / 800 / 1100** (700 if absent). These are higher than the concept tracks because a case study carries more ground.
- **`has_code`** — when `true`, at least one `<pre>` with real multi-line code: an ANN index build, a two-tower training step, a batched feature fetch, a CTR calibration formula.

Compound titles are checked: a title naming two things whose `<script>` never mentions the second is rejected.

## Design system

Same tokens as every other track (`--bg: #0d0f17`, `--accent: #00d4ff`, …). Inter + JetBrains Mono from Google Fonts only. Vanilla JS + Canvas/SVG — no D3, no Chart.js.

## Enforcement — these gates are binding

`validate.sh` exit codes are honoured by `once.sh` and `loop.sh`. A failing validation is never accepted, a `COMPLETE` promise is not believed unless validation passes, and a rejected item is regenerated with the exact `FAIL:` lines fed back in. After 3 failed attempts the run stops rather than accepting unverified content.

A `COMPLETE` promise is checked against the corpus itself, not just against the
files in it. A per-file validator iterates over what exists, so on an empty or
half-finished corpus it checks nothing and reports a clean pass — right for a
mid-run sweep, and a lie for the final gate. `ralph_require_complete` closes it:
every item in `plan.md`, and every item in the queue JSON in case the plan was
never re-scaffolded, must have produced a file. The same reasoning applies
per-item: an item the agent never wrote is SKIPped and passes, so `once.sh`
confirms the file exists before believing the validator.

An independent fact-check agent then reads the finished file alone, hunting wrong formulas, wrong mechanisms and false claims. **This track is the most exposed of any in the repo to fabricated numbers**, so its verdict is required before an item is accepted. Capacity arithmetic must be *correct*, not merely present — a derivation that shows its working and gets the wrong answer is worse than none.

`../validate-corpus.sh ml-system-design` flags near-duplicate case studies.

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

`<id>.html` — use the `id` field from `topics.json`.

## Progress log

```
2026-08-30 | 01-feed-ranking-system | Design a Feed Ranking System | OK
```
