# Weak evaluation hiding retrieval failures

**Category:** 02-rag-systems
**Question #:** 034
**Source section:** §2 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
This question probes whether you understand the subtlest and most dangerous failure mode in RAG systems: a pipeline that *appears* to work because your evaluation methodology is too weak to catch that retrieval is silently underperforming. Interviewers at mid/senior level ask this to distinguish engineers who build real eval infrastructure from those who rely on vibes, BLEU scores, or infrequent spot checks.

### Trigger phrases
- "Is there an actual eval framework, or vibes-based?"
- "How do you know your RAG pipeline is actually working?"
- "Your accuracy dropped 95% → 80% — how do you diagnose before retraining?"
- "How do you catch retrieval failures before users do?"

### What it tests
Whether you can design rigorous, layered evaluation that distinguishes retrieval failures from generation failures — and build regression infrastructure to catch regressions before production.

---

## Answer

### Concept
Weak evaluation hides retrieval failures when your metrics measure the final answer quality (user satisfaction, thumbs up/down, BLEU) but never instrument the retrieval layer independently. Because LLMs are surprisingly good at generating plausible-sounding answers even from irrelevant or partially relevant context, a failing retriever can produce mediocre answers that score acceptably on coarse metrics — masking the root cause. The result: hallucination and quality regressions accumulate silently until they're large enough to notice from user complaints.

### Mechanism
The failure pattern unfolds in three stages:

1. **No retrieval-layer metrics**: Teams deploy with only end-to-end eval (human thumbs-up, BLEU on answers, or LLM-as-judge on final response). Retrieval precision, recall, NDCG, and MRR are never measured.

2. **Masking by generation**: GPT-4o-mini fills in plausible answers from partial or irrelevant chunks. Answer quality scores stay at 85%+ even as context precision drops from 0.8 to 0.5. The vibes are fine.

3. **Delayed signal**: Only when the model can't compensate — new question domains, schema drift, embedding model changes — does end-to-end quality collapse visibly. By then the retrieval failure has been festering for weeks.

**The fix: two-layer eval with a golden dataset**

| Layer | Metric | Tool | Frequency |
|-------|--------|------|-----------|
| **Retrieval** | Recall@5, Precision@5, MRR, NDCG@10 | RAGAS `context_recall` + `context_precision`, or custom golden set | Every deploy |
| **Generation** | Faithfulness, Answer Relevancy | RAGAS `faithfulness`, `answer_relevancy` | Every deploy |
| **Production** | Deflection rate, thumbs-down rate, p95 latency | Datadog / Langfuse dashboards | Real-time |

**Golden dataset construction:**
- 100–500 curated (question, ideal answer, expected source documents) triples
- Cover edge cases: multi-hop queries, exact-match terms, negation, out-of-scope questions
- Run on every pipeline change; gate deployment if Recall@5 drops >3 pts or Faithfulness drops >0.05

**RAGAS diagnostic split (most important):**
- `context_recall` drops but `faithfulness` is fine → retriever is missing relevant chunks
- `faithfulness` drops but `context_recall` is fine → generator is hallucinating despite good context
- Both drop → likely a data quality / embedding drift issue

**Additional signals to wire up:**
- Log retrieved chunk IDs and cosine scores for every query in production (Langfuse / Weave)
- Run shadow retrieval: old index vs new index for 5% of traffic before full cutover
- Alert on cosine score distribution shifts — sudden drop in mean similarity signals embedding or index drift

### Example / Tradeoff
A real pattern: a legal-tech team updated their chunking strategy (fixed-size → semantic) and saw end-to-end LLM-judge scores stay flat at 84%. They assumed parity. Six weeks later users started complaining that clause references were wrong. Root cause: NDCG@10 had dropped from 0.72 to 0.51 because semantic chunks were breaking mid-clause — but the LLM filled in plausible (wrong) clauses from adjacent context. A 100-question golden dataset with document-level Recall@5 tracking would have surfaced the regression on day 1 of the chunking change.

**Tradeoff: eval cost vs eval coverage**
- Running RAGAS with GPT-4o-mini as judge: ~$0.002/question → $0.20/100-question golden set per deploy
- Running with GPT-4o: ~$0.02/question → $2/100 questions, higher accuracy for faithfulness
- Offline NDCG on retrieval layer requires pre-labeled relevance judgments (one-time human effort ~2–8 hours for 100 questions, then automated thereafter)
- The cost of one production hallucination incident (eng time + user trust) far exceeds the eval infrastructure cost

---

## Verbal script

**Opening (30s):**
"Weak evaluation hiding retrieval failures is what I'd call the most dangerous silent failure mode in RAG. The core problem is that if you only measure final answer quality — thumbs-up rates, LLM-judge scores — a failing retriever can stay hidden for weeks because the LLM is good enough at generating plausible text from bad context. I'd approach this by explaining what weak eval looks like, why it masks retrieval failures, and what a proper two-layer eval framework looks like."

**Core explanation (2–3 min):**
"The failure pattern is this: you deploy with only end-to-end metrics. Your LLM-as-judge score sits at 85%, vibes are fine. But under the hood, context precision has dropped from 0.8 to 0.5 because you changed your chunking strategy, or your embedding model was updated, or a new document category landed in the corpus. The model papers over the gap by generating plausible-sounding answers from partial or irrelevant context. This continues until the retriever is so broken that the LLM can't compensate — then quality falls off a cliff and you have a production incident.

The fix is a two-layer eval framework with a golden dataset. Layer one is the retrieval layer: you measure Recall@5, Precision@5, and NDCG@10 against a pre-labeled set of 100–500 (question, expected source docs) pairs. I use RAGAS `context_recall` and `context_precision` for this, plus a custom offline NDCG script. Layer two is the generation layer: RAGAS `faithfulness` tells you whether the answer is grounded in retrieved context, and `answer_relevancy` tells you whether it actually addresses the question.

The diagnostic split between these two is the key insight: if `context_recall` drops but `faithfulness` stays high, the retriever is missing relevant chunks. If `faithfulness` drops but retrieval looks fine, the generator is hallucinating. If both drop, you likely have data quality or embedding drift. That split tells you exactly where to debug."

**Tradeoff / production angle (1 min):**
"In production I'd wire up three additional signals: log retrieved chunk IDs and cosine scores for every query to Langfuse or Weave so you have retrieval telemetry, run shadow retrieval against a new index for 5% of traffic before any index cutover, and alert on cosine score distribution shifts — a sudden drop in mean similarity is often the first signal of embedding or schema drift, days before user complaints arrive. The cost of this eval infrastructure is minimal — a 100-question golden set costs about $0.20 to run with GPT-4o-mini — but it catches regressions before they become incidents."

**Wrap-up (30s):**
"So the summary is: weak eval hides retrieval failures by measuring the wrong layer. The fix is a two-layer golden-dataset framework that instruments retrieval (Recall@5, NDCG, RAGAS context_recall) and generation (faithfulness, answer_relevancy) independently, gates deployments on both, and wires production telemetry to surface drift before users do. Happy to go deeper on golden dataset construction or the RAGAS diagnostic split."

---

## Pitfalls

- **Mistake:** Saying "we use thumbs-up/thumbs-down rates to evaluate our RAG" without mentioning retrieval-layer metrics — **Better:** Distinguish retrieval eval (Recall@5, NDCG, context_recall) from generation eval (faithfulness, answer_relevancy) and explain why end-to-end metrics alone can't diagnose the root cause of quality regressions.

- **Mistake:** Treating RAGAS as a single score ("we run RAGAS and it's 0.85") rather than decomposing its sub-metrics — **Better:** Explain the diagnostic split: `context_recall` drop → retriever failing; `faithfulness` drop → generator hallucinating; use both to triage.

- **Mistake:** Saying "we spot-check 10 queries every sprint" as the eval process — **Better:** Describe a 100–500 question golden dataset with labeled source documents, automated Recall@5 and faithfulness scoring on every deploy, and a deployment gate on metric regressions >3 pts.

- **Mistake:** Not mentioning production telemetry — **Better:** Add that logging cosine scores per query and monitoring their distribution is the earliest signal of embedding drift or schema changes, often days before LLM-judge scores degrade.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q21: How evaluate a RAG pipeline? NDCG, MRR, precision@k, recall?](02-021-how-evaluate-a-rag-pipeline-ndcg-mrr-precisionk-recall.md) | Prerequisite — the full eval metric vocabulary and RAGAS framework |
| [Q13: Common RAG failure points — how debug them?](02-013-common-rag-failure-points-how-debug-them.md) | Sibling — weak eval is one of the 6 RAG failure modes; debugging framework overlaps |
| [Q33: Stale indexes, embedding drift](02-033-stale-indexes-embedding-drift.md) | Follow-up — embedding drift is a primary cause of retrieval regressions that weak eval misses |

---

## One-liner recall

> Weak eval hides retrieval failures by measuring only final answer quality — the fix is a two-layer golden-dataset framework that instruments retrieval (Recall@5, NDCG, `context_recall`) and generation (`faithfulness`) independently, with a deployment gate on both.
