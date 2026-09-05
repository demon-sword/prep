# Ralph MLOps — Interactive HTML Generator

Generates **self-contained interactive HTML concept files** under `mlops/concepts/` — one file per concept, theory + live visualization + the interview line.

## Why this track exists

The repo had **no production-ML coverage at all**. A repo-wide search before this track found two passing mentions of "drift" and nothing else — no feature stores, no training-serving skew, no monitoring, no rollout strategy, no retraining triggers.

This is the interview round that asks "your model is live and something is wrong — what do you look at, in what order, and what do you change?" It is not a modelling round.

## Quick start

```bash
# 1. Scaffold the plan from concepts.json
./ralph-mlops/scaffold.sh

# 2a. Generate one concept — next in queue
./ralph-mlops/once.sh

# 2b. Generate a specific concept by id
./ralph-mlops/once.sh 20-psi

# 3a. Run the full loop
./ralph-mlops/loop.sh

# 3b. Retry a single concept
./ralph-mlops/loop.sh 22-adwin-online-drift

# 4. Validate
./ralph-mlops/validate.sh
./ralph-mlops/validate.sh 20-psi

# 5. Cross-file redundancy
../validate-corpus.sh mlops

# 6. End-of-run gate — also fails an empty or short corpus
../validate-corpus.sh --final mlops
```

List available ids: `./ralph-mlops/once.sh --help`

## The 30 concepts

| Group | Count | Covers |
|---|---|---|
| data | 7 | data validation, dataset versioning, feature pipelines, feature stores, online/offline parity, point-in-time joins, training-serving skew |
| training | 4 | experiment tracking, pipeline orchestration, model registry, evaluation gates |
| serving | 6 | batch/online/streaming, latency budgets, shadow deploy, canary, champion-challenger, A/B testing models |
| monitoring | 7 | monitoring & alerting, drift types, PSI, KS vs KL, ADWIN, label lag, retraining triggers |
| governance | 2 | governance & lineage, slice-based fairness |
| platform | 4 | CI/CD for ML, GPU serving & autoscaling, incident response, cost management |

Depth spread: 4 intro / 17 core / 9 advanced. 20 of 30 carry `has_code: true`.

Ordering is prerequisite-respecting: data contracts → feature parity → training artifacts → registry → serving rollout → monitoring/drift → retraining → governance → platform.

## What the validator enforces

- Required sections: header, `#theory`, `#visualization`, `#interview-line`, `#takeaways`, `.concept-nav`
- At least one event listener or animation loop — the viz must actually be interactive
- No placeholder text (scanned in prose only, so a page *depicting* a TODO in a code sample is fine)
- Self-contained — no local asset files; sibling concept `.html` nav links are required and allowed
- **Depth-scaled word floor** on `#theory`: `intro` 300 / `core` 500 / `advanced` 700
- **`has_code`** — when true, at least one `<pre>` with real multi-line code
- **Compound-title coverage** — `Data Drift vs Concept Drift` must implement *both* drift types in the JS, not one. Same for `KS Test vs KL Divergence`

## Binding validation

Validation is binding from day one — there is no `|| true` anywhere in this track.

- `once.sh` resolves the target concept, runs the agent, then runs `validate.sh <id>` and **honours its exit code**
- on failure it feeds the exact `FAIL:` lines back into the next attempt's prompt
- capped at `RALPH_MAX_ATTEMPTS` (default 3), then exits **3** rather than accepting unverified content
- a `COMPLETE` promise is only believed if a full-corpus validation also passes
- `loop.sh` treats exit 3 as fatal

## Adversarial fact-check

After generation, a **separate** `claude -p` invocation is handed only the finished file and told it did not write it. It hunts wrong formulas, wrong mechanisms, false claims, and JS that contradicts the prose. It runs read-only (`--allowedTools "Read,Grep,Glob"`) so it cannot edit what it audits, and must emit `<factcheck>PASS</factcheck>` — a missing verdict counts as unverified, not as a pass.

This track is particularly exposed to invented thresholds and figures (PSI cut-offs, canary percentages, tool latencies), which is exactly what that pass is there to catch.

## Environment

| Var | Default | Effect |
|---|---|---|
| `RALPH_MAX_ATTEMPTS` | 3 | Regeneration attempts before giving up |
| `RALPH_FACTCHECK_TIMEOUT` | 900 | Seconds for the fact-check pass |
| `RALPH_SKIP_FACTCHECK` | 0 | `1` skips the adversarial pass |
| `RALPH_MLOPS_MODEL` | — | Model slug for generation |
| `RALPH_MLOPS_TIMEOUT` | 3600 | Seconds per generation attempt |

## Files

```
ralph-mlops/
├── spec.md         what a concept page must contain
├── prompt.md       the agent's per-iteration instructions
├── concepts.json   30 concepts + depth + has_code + viz
├── plan.md         queue (built by scaffold.sh)
├── progress.txt    append-only run log
├── scaffold.sh     builds plan.md from concepts.json
├── once.sh         one concept, with binding validation + fact-check
├── loop.sh         runs once.sh until done
└── validate.sh     structural + depth + code + title checks
```

Shared helpers live in `../ralph-common.sh`.
