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

## Enforcement — these gates are binding

`validate.sh` exit codes are honoured by `once.sh` and `loop.sh`. A failing
validation is never accepted, a `COMPLETE` promise is not believed unless
validation passes, and a rejected item is regenerated with the exact `FAIL:`
lines fed back into the next attempt. After 3 failed attempts the run stops
with an error rather than accepting unverified content.

A `COMPLETE` promise is checked against the corpus itself, not just against the
files in it. A per-file validator iterates over what exists, so on an empty
corpus it checks nothing and reports a clean pass — right for a mid-run sweep,
and a lie for the final gate. `ralph_require_complete` requires that the run
actually produced something before COMPLETE is accepted.

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

