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
