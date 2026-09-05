# Ralph Backend — Spec

Generates **self-contained interactive HTML concept files** under `backend/concepts/` — one concept per file — targeting a 7–8 years experienced backend engineer's interview depth on distributed systems primitives.

## Goal

Each HTML teaches one primitive the way senior backend interviews actually probe it: not "what is X" but "what's the trade-off X is a specific answer to, and what's the one sentence you'd say out loud when it comes up." A candidate studying these should be able to:
1. Understand the mechanism deeply (not the textbook definition)
2. See it animate — ideally the real mechanism computed live in JS, not a canned animation
3. Interact with parameters to build intuition for the trade-off
4. Walk away with the exact interview-ready sentence for this concept

## Source material — read this first, every time

Eight of the concepts (`01`–`08`) have **hand-written source notes** at the path in their `concepts.json` `source` field. These notes already hit the target depth and voice. For those:

- **Read the source file in full before writing anything.**
- Adapt/expand it into the `#theory` section, preserving its structure (sub-headings), its terminology, and — critically — **its "In the room" quote verbatim or near-verbatim** in the `#interview-line` section (see below). Do not simplify away its specifics or replace its examples with blander ones.
- You may reorganize for HTML (e.g. `<h3>` per sub-heading) and add visual callouts, but the substance and phrasing should read as the same author's voice, not a rewrite.
- If the source includes a "Where this appeared in the Simbian design" note, keep it as a small dimmed aside in the theory section — it's a real-system anchor, not filler.

The remaining concepts (`09`–`22`) have **no source file** — write the theory from scratch, matching the exact same voice and structure as the sourced ones: mechanism → variants/options → the trade-off that actually matters → the one sentence to say in an interview. Read `sources/_cross-links.md` for how these primitives relate to each other and to the sourced eight; draw at least one explicit connection to another concept where it's genuinely true (not forced).

## Output artifact per concept

| Attribute | Requirement |
|-----------|-------------|
| Path | `backend/concepts/<id>.html` |
| Format | Fully self-contained HTML — no external dependencies except Google Fonts CDN |
| Theme | Dark terminal theme (see Design System below) — matches the rest of the repo |
| Sections | Header, Theory, Visualization, Interview Line, Key Takeaways |
| Visualization | Interactive (JS-driven) — not a static diagram |
| Code | All CSS and JS inline in `<style>` and `<script>` tags |
| Mobile | Responsive — works on tablet and desktop |

## Required HTML sections (in order)

1. **`<header>`** — concept title, group badge, one-sentence description
2. **`<section id="theory">`** — deep theory, sub-sectioned with `<h3>`: mechanism, variants/options, the trade-off that matters, named failure modes where relevant. Word floor set by the entry's `depth` field — `intro` 300, `core` 500, `advanced` 700 (400 if `depth` is absent) — of real content, adapted from the source file when one exists. No placeholders.
3. **`<section id="visualization">`** — the interactive viz. Must be functional JS, not a placeholder. Controls (sliders, buttons, toggles) must do something real. Follow the `viz` field from `concepts.json`.
4. **`<section id="interview-line">`** — a visually distinct callout (quote-styled) containing the exact sentence(s) to say in an interview when this topic comes up. For sourced concepts, use the source's "In the room" quote. For unsourced concepts, write an equivalent one: specific, references a real trade-off, sounds like something a senior engineer actually says out loud (not a definition).
5. **`<section id="takeaways">`** — 4–6 bullet points. Senior-level insights, not beginner summaries. Include real numbers, real tool/system names (Redis, Kafka, Debezium, Raft, PgBouncer, etc.), and production gotchas.
6. **`<nav class="concept-nav">`** — prev/next links to adjacent concept files (use relative paths `../concepts/<id>.html`)

## Design system (match exactly — same tokens as `ai-engineering/concepts/` and `machine_learning/concepts/`)

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
No other external dependencies — no D3 CDN, no Chart.js CDN. All visualization logic, and any "live" mechanism computation (token bucket refill, consistent-hash ring remap, Raft log replication, etc.), must be vanilla JS + Canvas or SVG, computed client-side from scratch.

## Visualization quality bar

The viz must be **genuinely interactive** and, wherever the concept allows, **mechanistically real** — actually simulate the algorithm/protocol step by step in JS, not a pre-baked animation:
- At minimum: user can click, drag, or adjust a slider and see the diagram change
- Prefer: animated flows / protocol steps that show the mechanism in motion (use `requestAnimationFrame`)
- Avoid: static SVG with no interaction, or a viz that's just a colored rectangle

## Theory quality bar

- Explain the mechanism, not just the definition — this is for engineers who already know the vocabulary and want the trade-off
- Include real numbers where the source or general knowledge supports them (e.g. "N=3, W=2, R=2 is the common quorum config")
- Include production-relevant tradeoffs and named failure modes
- Reference real tools/systems (Redis, Kafka, Debezium, Raft, Consul, PgBouncer, SQS, etc.)
- Write for a candidate who's shipped distributed systems before — skip trivial definitions, go deep on mechanism and the "which sentence do I say" payoff

## Validation checks (agent self-checks after writing)

1. HTML parses without error (no unclosed tags)
2. All required sections present (`header`, `#theory`, `#visualization`, `#interview-line`, `#takeaways`, `.concept-nav`)
3. Visualization has at least one event listener (click, input, or animation loop)
4. No placeholder text (no "TODO", "PLACEHOLDER", "Lorem ipsum", "coming soon")
5. File is self-contained (no `src=` pointing to local files, no `href=` to local CSS)
6. Playwright screenshot shows rendered content (not blank)
7. Browser console has no uncaught JS errors
8. For sourced concepts (`01`–`08`): the theory section doesn't contradict or omit any named failure mode / pattern from the source file

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
9. For sourced concepts (`01`–`08`): every **bolded named term** in the source
   note (failure modes, pattern names, eviction policies) must appear on the
   page. This is the check spec previously only promised; `validate.sh` now
   implements it.

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
- `01-caching-strategies.html`
- `11-consensus-algorithms.html`
- `19-indexing-storage-engines.html`

## Plan format

`ralph-backend/plan.md` — tracks which concepts are done:

```
## Done
- [x] scaffold

## Next
- [ ] 01-caching-strategies — Caching Strategies
- [ ] 02-queues-backpressure — Queues and Backpressure
...
```

## Progress log

Append one line per completed concept to `ralph-backend/progress.txt`:
```
2026-08-19 | 01-caching-strategies | Caching Strategies | OK
```
