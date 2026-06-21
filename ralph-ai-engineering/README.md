# Ralph — AI Engineering Notes Generator

Headless Cursor Agent loop to generate AI engineering interview prep notes under `ai-engineering/` — **one category at a time**.

## Quick start

```bash
# 1. Queue a category (start small)
./ralph-ai-engineering/scaffold.sh 08-safety-guardrails

# 2. Single agent iteration
./ralph-ai-engineering/once.sh 08-safety-guardrails

# 3. Loop until category complete
./ralph-ai-engineering/loop.sh 08-safety-guardrails 16

# 4. Validate
./ralph-ai-engineering/validate.sh 08-safety-guardrails
```

## Next category

When a category passes validate:

```bash
./ralph-ai-engineering/scaffold.sh 04-fine-tuning-training
./ralph-ai-engineering/loop.sh 04-fine-tuning-training 18
```

Previous category is recorded under **Categories completed** in `ai-engineering/plan.md`.

## Category slugs

| # | Slug | Source § | Questions | Suggested max |
|---|------|----------|-----------|---------------|
| 1 | `01-llm-fundamentals` | §1 | 48 | 56 |
| 2 | `02-rag-systems` | §2 | 34 | 42 |
| 3 | `03-agents-tool-use` | §3 | 38 | 46 |
| 4 | `04-fine-tuning-training` | §4 | 12 | 18 |
| 5 | `05-evaluation-metrics` | §5 | 23 | 30 |
| 6 | `06-ml-fundamentals` | §6 | 26 | 34 |
| 7 | `07-cost-latency` | §9 | 16 | 22 |
| 8 | `08-safety-guardrails` | §10 | 10 | 16 |
| 9 | `09-system-design-ai` | §11 | 55 | 63 |
| 10 | `10-behavioral` | §18 | 74 | 80 |

## Recommended start order (fewest tasks first)

```bash
./ralph-ai-engineering/scaffold.sh 08-safety-guardrails   # 10 Q → 12 tasks
./ralph-ai-engineering/loop.sh 08-safety-guardrails 16

./ralph-ai-engineering/scaffold.sh 04-fine-tuning-training  # 12 Q → 14 tasks
./ralph-ai-engineering/loop.sh 04-fine-tuning-training 18

./ralph-ai-engineering/scaffold.sh 07-cost-latency   # 16 Q → 18 tasks
./ralph-ai-engineering/loop.sh 07-cost-latency 22
```

## What each run produces

Per category:

| File | Description |
|------|-------------|
| `ai-engineering/categories/NN-<slug>.md` | Category overview: interview signals, mental model, decision framework, question checklist |
| `ai-engineering/answers/NN-QQQ-<slug>.md` | One note per question: framing, structured answer, verbal script, pitfalls, related questions |
| `ai-engineering/plan.md` | Task queue (one category active) |
| `ai-engineering/progress.txt` | Append-only run log |

See `ralph-ai-engineering/spec.md` for required sections.

## Scripts

| Script | Purpose |
|--------|---------|
| `scaffold.sh <slug>` | Build `ai-engineering/plan.md` for one category |
| `once.sh <slug>` | One Cursor Agent iteration |
| `loop.sh <slug> [max]` | Repeat until `<promise>COMPLETE</promise>` (default MAX=80) |
| `validate.sh <slug>` | Structural checks for category |
| `scripts/question_data.py` | Parse `interview-questions.md` → category + question metadata |

## Agent env

- `CURSOR_MODEL` — optional model slug (e.g. `claude-sonnet-4`)
- `CURSOR_AGENT_TIMEOUT_SEC` — default `2700` (45 min)
- `CURSOR_AGENT_OUTPUT_FORMAT` — default `stream-json`

## Logs

`ralph-ai-engineering/.logs/<category-slug>-iter-*.log`

## Notes

- One plan item per iteration (category doc, then each answer note, then validate)
- Answer notes use **verbal scripts** — first-person spoken outlines for interview practice
- Generated notes default to `**Status:** review` — update after you practice the answer
- Category doc is always written first; the agent reads it when writing individual answer notes
