# Ralph ML System Design — Interactive Case Study Generator

Generates **self-contained interactive HTML case studies** under `ml-system-design/` — one per case study — for the ML system design round.

## Why this track exists

The repo's existing `system-design/` folder is **frontend** system design: its spec requires a `<topic>-frontend-architecture.html` artifact, and across its 108 files there are 9 total mentions of "QPS" and no capacity estimation anywhere.

This track is backend/ML system design, and its load-bearing skill is **back-of-envelope numeracy** — turning "300M DAU" into a replica count, a shard count, a storage bill and a latency budget, out loud. That is what these interviews test and what the existing material never trains.

So every case study has a **mandatory, validator-enforced `#capacity` section**. A page that asserts "we need about 100 GPUs" without showing the arithmetic fails the build.

## Quick start

```bash
# 1. Scaffold the plan from topics.json
./ralph-ml-system-design/scaffold.sh

# 2a. Generate one case study — next in queue
./ralph-ml-system-design/once.sh

# 2b. Generate a specific case study by id
./ralph-ml-system-design/once.sh 05-embedding-retrieval-system

# 3a. Run the full loop
./ralph-ml-system-design/loop.sh

# 3b. Retry a single case study
./ralph-ml-system-design/loop.sh 05-embedding-retrieval-system

# 4. Validate
./ralph-ml-system-design/validate.sh
./ralph-ml-system-design/validate.sh 05-embedding-retrieval-system

# 5. Cross-file redundancy
../validate-corpus.sh ml-system-design

# 6. End-of-run gate — also fails an empty or short corpus
../validate-corpus.sh --final ml-system-design
```

List available ids: `./ralph-ml-system-design/once.sh --help`

## The 14 case studies

| Group | Case studies |
|---|---|
| ranking | feed ranking, search ranking, ads CTR prediction, push notification ranking |
| retrieval | embedding retrieval, near-duplicate detection |
| realtime | real-time personalization, fraud detection, ETA prediction |
| platform | model serving platform, feature store, content moderation, LLM inference serving |
| experimentation | experimentation platform |

Each entry in `topics.json` carries a `scale` object (the starting numbers) and `capacity_anchors` (the derivations the page must show).

## What the validator enforces

Beyond the usual structural checks (required sections, interactivity, no placeholders, self-contained, depth-scaled word floor, `has_code`, compound-title coverage):

**The capacity gate** — for every case study:

- `<section id="capacity">` exists
- it contains **≥12 numbers**
- it contains **real arithmetic** (`× x * / = ÷ + →`) — numbers asserted without derivation are rejected
- **every anchor** in that entry's `capacity_anchors` leaves a trace (a QPS anchor needs "qps", a storage anchor a byte unit, a GPU anchor "gpu"/"replica", …)

Word floors are higher than the concept tracks because a case study carries more ground: `intro` 500 / `core` 800 / `advanced` 1100.

## Binding validation

Validation is binding from day one — there is no `|| true` anywhere in this track.

- `once.sh` resolves the target case study, runs the agent, then runs `validate.sh <id>` and **honours its exit code**
- on failure it feeds the exact `FAIL:` lines back into the next attempt's prompt
- capped at `RALPH_MAX_ATTEMPTS` (default 3), then exits **3** rather than accepting unverified content
- a `COMPLETE` promise is only believed if a full-corpus validation also passes
- `loop.sh` treats exit 3 as fatal

## Adversarial fact-check

After generation, a **separate** `claude -p` invocation is handed only the finished file and told it did not write it. It hunts wrong formulas, wrong mechanisms, false claims, and JS that contradicts the prose. It runs read-only (`--allowedTools "Read,Grep,Glob"`) so it cannot edit what it audits, and must emit `<factcheck>PASS</factcheck>` — a missing verdict counts as unverified, not as a pass.

This matters more here than anywhere else in the repo: **the capacity arithmetic must be correct, not merely present.** A derivation that shows its working and reaches the wrong answer is worse than none.

## Environment

| Var | Default | Effect |
|---|---|---|
| `RALPH_MAX_ATTEMPTS` | 3 | Regeneration attempts before giving up |
| `RALPH_FACTCHECK_TIMEOUT` | 900 | Seconds for the fact-check pass |
| `RALPH_SKIP_FACTCHECK` | 0 | `1` skips the adversarial pass |
| `RALPH_MLSD_MODEL` | — | Model slug for generation |
| `RALPH_MLSD_TIMEOUT` | 3600 | Seconds per generation attempt |

## Files

```
ralph-ml-system-design/
├── spec.md         what a case study must contain
├── prompt.md       the agent's per-iteration instructions
├── topics.json     14 case studies + scale + capacity_anchors
├── plan.md         queue (built by scaffold.sh)
├── progress.txt    append-only run log
├── scaffold.sh     builds plan.md from topics.json
├── once.sh         one case study, with binding validation + fact-check
├── loop.sh         runs once.sh until done
└── validate.sh     structural + capacity gate
```

Shared helpers live in `../ralph-common.sh`.
