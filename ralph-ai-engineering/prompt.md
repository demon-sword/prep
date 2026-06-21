# Ralph — AI Engineering Notes Generator

## Inputs (read every iteration)

| Doc | Path |
|-----|------|
| Spec | `ralph-ai-engineering/spec.md` |
| Plan | `ai-engineering/plan.md` |
| Question bank | `ai-engineering/interview-questions.md` |
| Conventions | `ai-engineering/README.md` |
| Category template | `ai-engineering/categories/_template.md` |
| Answer template | `ai-engineering/answers/_template.md` |

**Category:** {{CATEGORY}} ({{CATEGORY_NAME}})

## Rules

1. Read `ai-engineering/plan.md` — complete **exactly ONE** unchecked item from **Next** (first item only).
2. Use **Task/subagent** when research helps (model internals, production architectures, benchmark data).
3. **One task per run** — do not start the next plan item.
4. After completing the task:
   - Check off the item in `plan.md` (`- [ ]` → `- [x]`, move to Done, remove from Next)
   - Append one line to `ai-engineering/progress.txt` with date + category + what you did
5. If **all** plan items are done and `bash ralph-ai-engineering/validate.sh {{CATEGORY}}` passes, output `<promise>COMPLETE</promise>`.

## Task-specific guidance

### categories/NN-<slug>.md

- Copy structure from `ai-engineering/categories/_template.md`
- Read all questions for this category from `interview-questions.md`
- **Interview signals** — 4–6 trigger phrases or question shapes that indicate this topic (`"walk me through your…"`, `"how would you design…"`, `"compare X and Y"`)
- **Mental model** — 1 paragraph: the conceptual frame a strong candidate holds that a weak candidate doesn't
- **Sub-topics** — 2–4 named sub-areas each with: When (interview trigger), What (concept in one sentence), Key questions (2–3 referenced Q# from the bank)
- **Decision framework** — decision tree: when to choose technique A vs B vs C (e.g. prompt vs RAG vs fine-tune, sparse vs dense vs hybrid retrieval)
- **Common mistakes** — table of what unprepared candidates say or skip; be specific and concrete
- **Question checklist** — markdown table with one row per question in this category: `#` | `Question` | `Difficulty signal` | `Status`
- **One-page summary** — 3–5 bullets; the highest-signal facts to recall on interview morning

### answers/NN-QQQ-<slug>.md

- Copy `ai-engineering/answers/_template.md` and fill every section — no HTML comments left as placeholders
- Set `**Status:**` to `review` and `**Generated:**` to `ralph-ai-engineering`
- **Framing** — why the interviewer asks this, what competency it probes, 2–3 trigger phrasings
- **Answer** — Concept (what it is) → Mechanism (how it works) → Example/Tradeoff (concrete: real system names, metrics, tools — FAISS, RAGAS, LoRA, HNSW, Pinecone, etc.)
- **Verbal script** — 3–5 min spoken outline, first person, interview voice: `"I'd start by…"`, `"The key tradeoff here is…"`, `"A concrete example is…"`
- **Pitfalls** — ≥2 concrete mistakes weak candidates make; specific phrasing: `"Saying 'just increase chunk size' without mentioning context pollution"` not `"doesn't understand chunking"`
- **Related questions** — 2–3 cross-links as relative markdown links (e.g. `[Q2: Compare sparse vs dense retrieval](02-002-compare-sparse-vs-dense-retrieval.md)`); cross-category links are valid
- **One-liner recall** — single sentence that lets you reconstruct the full answer from memory

### validate

- Run: `bash ralph-ai-engineering/validate.sh {{CATEGORY}}`
- If any sections are missing or placeholders remain, fix them before emitting COMPLETE
- If validate passes, emit `<promise>COMPLETE</promise>`

## Verification

After substantive edits:

```bash
bash ralph-ai-engineering/validate.sh {{CATEGORY}}
```

Report failures in `ai-engineering/progress.txt` if blocked.

## Commit

One commit per plan item: `feat(ai-eng): {{CATEGORY}} — <short description>`

Do not push unless asked.
