# AI Engineering Notes Generator — Spec

Generates AI engineering interview prep notes under `ai-engineering/` — **one category at a time**.

## Scope per run

Each Ralph session completes **one category block**:

1. Category overview doc
2. One answer note per question in that category
3. Category validation

## Output artifacts

| Artifact | Path | Required sections |
|----------|------|-------------------|
| Category overview | `ai-engineering/categories/NN-<slug>.md` | Interview signals, Mental model, Sub-topics (≥2), Decision framework, Common mistakes, Question checklist, One-page summary |
| Answer note | `ai-engineering/answers/NN-QQQ-<slug>.md` | Framing, Answer, Verbal script, Pitfalls (≥2), Related questions (≥2 links), One-liner recall |
| Plan | `ai-engineering/plan.md` | Queue for current category only |
| Progress log | `ai-engineering/progress.txt` | Append-only run log |

## File naming

- Category overview: `categories/NN-<slug>.md` — NN is the 2-digit category number (01–11), independent of the source section number
- Answer note: `answers/NN-QQQ-<slug>.md` — NN=2-digit category, QQQ=3-digit question number within that category
- Slug: lowercase, spaces→dash, strip non-word chars, cap 60 chars, no trailing dash

## Category overview format

Follow `ai-engineering/categories/_template.md`:

1. **Interview signals** — 4–6 trigger phrases that signal this topic area
2. **Mental model** — 1-paragraph conceptual frame
3. **Sub-topics** — 2–4 named sub-areas: When / What / Key questions
4. **Decision framework** — decision tree: when to use which technique
5. **Common mistakes** — what weak candidates miss (specific, concrete)
6. **Question checklist** — table: # | Question | Difficulty signal | Status
7. **One-page summary** — 3–5 bullets for morning-of review

## Answer note format

Follow `ai-engineering/answers/_template.md`:

1. **Framing** — why asked, what competency it probes, trigger phrases
2. **Answer** — Concept → Mechanism → Example/Tradeoff
3. **Verbal script** — 3–5 min spoken outline (first person, interview voice)
4. **Pitfalls** — ≥2 concrete mistakes weak candidates make
5. **Related questions** — 2–3 cross-links within or across categories
6. **One-liner recall** — single sentence to reconstruct the answer

## Quality rules

- **No template stubs** — every HTML comment in templates must be replaced with real content
- **Interview-accurate** — reflects current industry practice (2025–2026), not textbook theory
- **Cross-link** — answer notes reference related questions from the same or other categories
- **Concrete** — include real system names, metrics, tools (FAISS, Pinecone, RAGAS, LoRA, HNSW, vLLM, etc.)
- **Verbal script is first-person** — `"I'd start by…"`, `"The key insight is…"`, `"A concrete example is…"`
- **Category doc written first** — agent may read it when writing individual answer notes

## Section headers (exact strings — validate checks these)

Category overview doc:
```
## Interview signals
## Mental model
## Sub-topics
## Decision framework
## Common mistakes
## Question checklist
## One-page summary
```

Answer note:
```
## Framing
## Answer
## Verbal script
## Pitfalls
## Related questions
## One-liner recall
```

## Category slugs

| # | Slug | Source § | Questions |
|---|------|----------|-----------|
| 1 | `01-llm-fundamentals` | §1 | 48 |
| 2 | `02-rag-systems` | §2 | 34 |
| 3 | `03-agents-tool-use` | §3 | 38 |
| 4 | `04-fine-tuning-training` | §4 | 12 |
| 5 | `05-evaluation-metrics` | §5 | 23 |
| 6 | `06-ml-fundamentals` | §6 | 26 |
| 7 | `07-cost-latency` | §9 | 16 |
| 8 | `08-safety-guardrails` | §10 | 10 |
| 9 | `09-system-design-ai` | §11 | 55 |
| 10 | `10-behavioral` | §18 | 74 |
| 11 | `11-context-management` | §22 | 15 |

## Reference docs

| Doc | Use |
|-----|-----|
| `ai-engineering/interview-questions.md` | Question bank — source of truth |
| `ai-engineering/categories/_template.md` | Category overview template |
| `ai-engineering/answers/_template.md` | Answer note template |
| `ai-engineering/README.md` | Study conventions |

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

