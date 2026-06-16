# Common RAG failure points — how debug them?

**Category:** 02-rag-systems
**Question #:** 013
**Source section:** §2 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
This is a senior-signal question that probes whether a candidate has actually debugged RAG in production. Interviewers want to know if you can isolate failures across the pipeline stages (retrieval vs. generation vs. data quality) rather than applying blanket fixes like "add more context" or "use a bigger model." The ability to decompose a failure systematically — without rebooting the whole pipeline — signals production maturity.

### Trigger phrases
- "Your RAG chatbot is giving wrong answers — how do you debug it?"
- "What are the most common ways RAG systems fail in production?"
- "Walk me through how you'd diagnose a RAG pipeline that's underperforming."
- "Our RAGAS faithfulness score dropped — where do you start?"

### What it tests
Systematic debugging instinct across a multi-stage pipeline — isolating retrieval failures from generation failures, and data-quality failures from architectural ones.

---

## Answer

### Concept
RAG failures fall into six canonical categories that map to specific pipeline stages. The key insight is that **retrieval failures and generation failures look identical to the end user** (wrong answer) but have completely different root causes and fixes. Conflating them leads to wasted effort — tuning prompts when the retrieval is broken, or re-chunking when the real issue is a stale index.

### Mechanism

**The six failure modes and their diagnostic signals:**

| # | Failure | Where in pipeline | Diagnostic signal |
|---|---------|-------------------|-------------------|
| 1 | **Bad chunking** | Ingest/chunk stage | Low RAGAS `context_recall`; retrieved docs have the right section but split mid-table or mid-argument |
| 2 | **Vocabulary mismatch** (dense-only missing keywords) | Retrieval stage | Dense retrieval returns semantically-similar but lexically-wrong docs; exact entity names (product SKUs, person names) are not found |
| 3 | **Lost in the middle** | Generation stage | Retrieved docs are correct but answer is wrong; gold document is in position 2–4 of a 5-doc context window |
| 4 | **Hallucination on absent context** | Generation stage | RAGAS `faithfulness` < 0.7; model answers confidently when retrieved context has no relevant passage |
| 5 | **Stale index / embedding drift** | Index freshness | Correct answer exists in source docs but not returned; answers match old versions of content |
| 6 | **Weak evaluation hiding failures** | Eval stage | Vibes-based "it looks good" eval; no golden dataset; retrieval failures invisible until users complain in production |

**Systematic debugging protocol:**

```
Step 1 — Isolate retrieval from generation:
  Run RAGAS:
    context_recall  < 0.7?  → retrieval problem (steps 2–5 apply)
    faithfulness    < 0.7?  → generation problem (step 4 or prompt fix)
    Both low?               → start with retrieval; it's the load-bearing stage

Step 2 — Inspect retrieved chunks manually:
  Log (query, top-5 chunks, answer) for 20–50 failing queries.
  Chunks are wrong/missing → vocab mismatch or bad chunking.
  Chunks are right but answer is wrong → generation or lost-in-middle.

Step 3 — Diagnose retrieval failure subtype:
  Missing exact entities/codes → add BM25 hybrid (vocab mismatch)
  Chunks contain the answer but split mid-sentence → fix chunking strategy
  Chunks are outdated → check index freshness / CDC pipeline

Step 4 — Diagnose generation failure subtype:
  Gold chunk in middle of context → reorder (place most-relevant first/last)
  LLM answers despite empty/irrelevant context → add cosine threshold gate + abstention prompt
  LLM contradicts cited chunk → faithfulness NLI check post-processing

Step 5 — Validate fix with golden dataset:
  Measure recall@5 and RAGAS before/after; require +5% lift to ship
```

### Example / Tradeoff

**Real incident pattern:** A customer support RAG was returning 78% user satisfaction initially. After six weeks it dropped to 61%. Investigation:
1. `context_recall` had dropped from 0.82 → 0.64 — retrieval was broken.
2. Manual inspection: product SKU queries (e.g. "error with SKU-4872") were returning semantically-related but wrong products.
3. Root cause: dense-only index; no BM25 hybrid; SKUs are lexically opaque to embedding models.
4. Fix: added Elasticsearch BM25 layer + RRF fusion. `context_recall` recovered to 0.79. Faithfulness unchanged (0.88 → 0.87), confirming generation was never the issue.

**Tool stack for debugging:** RAGAS (offline eval), LangSmith / Arize Phoenix (trace logging), Elasticsearch for BM25 hybrid, ms-marco-MiniLM cross-encoder for reranker, GPTCache for semantic cache monitoring.

---

## Verbal script

**Opening (30s):**
"I'd approach this by treating RAG as a pipeline of independent failure modes — six canonical ones — because the fix for a retrieval failure is completely different from the fix for a generation failure. The biggest mistake is trying to tune prompts when retrieval is actually broken. So my first move is always to split the eval."

**Core explanation (2–3 min):**
"The six failure modes I look for are: bad chunking, vocabulary mismatch, lost in the middle, hallucination on absent context, stale indexes, and weak evaluation that's hiding everything else.

To triage, I run RAGAS metrics. If `context_recall` is low — say below 0.7 — that's a retrieval problem. If `faithfulness` is low but `context_recall` is fine, that's a generation problem. If both are low, I fix retrieval first because it's the load-bearing stage.

For retrieval failures, I'll log 20 or 30 failing queries and manually inspect the top-5 retrieved chunks. If the chunks are missing entirely or wrong, I look for two subtypes: vocab mismatch — where dense embeddings fail on exact-match entities like product codes or names — which I fix by adding BM25 hybrid with RRF fusion. Or bad chunking — where the right section is retrieved but split mid-table or mid-argument — which I fix by switching to semantic or parent-child chunking.

For generation failures, I look at whether the gold chunk is in the middle of the context window — which Liu et al. 2023 showed degrades accuracy from 70% to 45% — so I reorder context to place the most relevant chunks first and last. If the model is hallucinating on absent context, I add a cosine-similarity gate before the LLM call: if no retrieved chunk clears a threshold like 0.70, return a canned 'I don't have that information' response rather than calling the LLM at all.

The stale index is sneaky — content updates without re-embedding mean the source has the right answer but the vector store doesn't. I fix that with a CDC pipeline via Debezium or a scheduled delta re-embed job."

**Tradeoff / production angle (1 min):**
"The hardest failure to catch is weak evaluation — if the team is doing vibes-based review rather than a golden dataset with ground-truth docs, retrieval failures are invisible until users start complaining. I've seen pipelines with 65% `context_recall` that the team thought were 'working fine' because the generated answers sounded fluent. Fluent hallucinations are the worst outcome. The fix is a golden set of 50–200 Q&A pairs with tagged ground-truth chunks, evaluated with RAGAS on every deployment."

**Wrap-up (30s):**
"In summary: isolate retrieval from generation using RAGAS, inspect failing queries manually, fix the root cause — hybrid retrieval for vocab mismatch, chunking strategy for structural failures, context reordering for lost-in-middle, a cosine gate for absent-context hallucination. And never ship without a golden dataset eval. Happy to go deeper on any of the six failure modes."

---

## Pitfalls

- **Mistake:** Jumping to "tune the prompt" or "use a bigger model" as the first debug step when the answer is wrong — **Better:** Always split eval first: run RAGAS `context_recall` vs `faithfulness`; if recall is low the retrieval is broken and no prompt change will fix it.
- **Mistake:** Treating all RAG failures as a single category ("the RAG is bad") without decomposing by stage — **Better:** Name the six failure modes by stage: chunking → retrieval → generation → eval; each has a distinct diagnosis and fix.
- **Mistake:** Using only dense retrieval and then increasing top-k when queries with exact entity names fail — **Better:** "Dense embeddings treat 'SKU-4872' as semantically similar to other product numbers; the fix is BM25 hybrid retrieval, not a larger top-k which just adds noise."
- **Mistake:** Not mentioning the stale index problem — **Better:** "After a content update without re-embedding, the vector store diverges from source truth; I'd add a CDC pipeline or scheduled delta-embed job with index-age monitoring."

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q12: Compare sparse vs dense retrieval. When use each?](02-012-compare-sparse-vs-dense-retrieval-when-use-each.md) | Vocabulary mismatch failure → fix with BM25 hybrid |
| [Q21: How evaluate a RAG pipeline? NDCG, MRR, precision@k, recall?](02-021-how-evaluate-a-rag-pipeline-ndcg-mrr-precisionk-recall.md) | Metrics used in the debugging protocol |
| [Q34: Weak evaluation hiding retrieval failures](02-034-weak-evaluation-hiding-retrieval-failures.md) | Failure mode #6 — vibes-based eval masks broken retrieval |

---

## One-liner recall

> Debug RAG by splitting RAGAS `context_recall` (retrieval) from `faithfulness` (generation), then trace the root cause through the six canonical failure modes: bad chunking, vocab mismatch, lost-in-middle, hallucination-on-absent-context, stale index, or weak eval — fixing retrieval before touching generation.
