# How evaluate a RAG pipeline? NDCG, MRR, precision@k, recall?

**Category:** 02-rag-systems
**Question #:** 021
**Source section:** §2 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
RAG evaluation is the most under-prepped area in AI engineering interviews, yet it's the skill that separates engineers who ship reliable systems from those who ship vibes-based demos. Interviewers probe whether you understand the two-layer evaluation problem (retrieval quality *and* generation quality) and whether you have a concrete measurement framework — golden datasets, offline metrics, and production signals.

### Trigger phrases
- "How do you evaluate a RAG pipeline? What metrics?"
- "How would you know if your RAG system is working well?"
- "Walk me through how you measure retrieval quality vs answer quality."
- "What's your eval strategy for a customer support RAG — offline and online?"

### What it tests
Whether the candidate can decompose RAG evaluation into retrieval and generation layers, name concrete metrics for each, and connect offline eval to production monitoring.

---

## Answer

### Concept
RAG evaluation is a **two-layer problem**: retrieval quality (did we surface the right documents?) and generation quality (did the LLM produce a faithful, relevant answer from those docs?). Each layer has its own metrics and failure modes. Most weak candidates only think about generation — but retrieval is almost always where RAG breaks first.

### Mechanism

**Layer 1 — Retrieval metrics** (offline, using labeled query→relevant-doc pairs):

| Metric | What it measures | Formula / intuition |
|--------|-----------------|---------------------|
| **Recall@k** | Did the correct doc appear in the top-k results? | \|relevant ∩ retrieved@k\| / \|relevant\| |
| **Precision@k** | How many of the top-k results are actually relevant? | \|relevant ∩ retrieved@k\| / k |
| **MRR** (Mean Reciprocal Rank) | How high did the first relevant result rank? | avg(1/rank of first relevant result) — good for QA where one answer exists |
| **NDCG@k** (Normalized Discounted Cumulative Gain) | Graded relevance — rewards relevant docs ranked higher | DCG@k / IDCG@k — best when docs have tiered relevance (0/1/2 scale) |
| **MAP** (Mean Average Precision) | Average precision across all recall levels | mean of AP over all queries |

**Practical choice:** MRR for QA (one right answer), NDCG for ranked search (graded relevance), Recall@5 as a primary retrieval health KPI.

**Layer 2 — Generation metrics** (RAGAS framework):

| Metric | What it measures | How computed |
|--------|-----------------|--------------|
| **Faithfulness** | Is the answer entailed by the retrieved context? | LLM-as-judge: break answer into claims, check each claim against context chunks |
| **Answer Relevancy** | Is the answer on-topic for the question? | Embedding similarity: generate reverse questions from the answer, measure cosine sim to original |
| **Context Precision** | Are the retrieved chunks relevant to the question? | Fraction of retrieved chunks that are relevant (LLM-judged) |
| **Context Recall** | Were all relevant facts retrieved? | Fraction of ground-truth answer facts found in retrieved context |

**RAGAS** (Retrieval Augmented Generation Assessment) is the standard open-source framework that automates all four metrics using an LLM-as-judge and embedding similarity.

**Layer 3 — Production / business metrics:**

| Metric | Threshold / target |
|--------|--------------------|
| Deflection rate | % of support tickets resolved without human escalation (target: ≥ 80%) |
| p95 latency | End-to-end wall clock (target: < 3s for chat UX) |
| Cost per query | Token cost × LLM pricing (target: depends on use case) |
| Thumbs-down rate | User negative feedback rate (target: < 5%) |
| Hallucination SLO | Faithfulness < 0.8 triggers alert or HITL |

**Evaluation workflow:**
1. **Build a golden dataset**: 200–500 (question, ground-truth answer, relevant doc IDs) triples — sourced from historical support tickets, SME annotations, or synthetic generation with human review.
2. **Run offline eval** before every deployment: Recall@5 on retrieval, Faithfulness + Answer Relevancy via RAGAS.
3. **Gate on regressions**: block deploys where Recall@5 drops > 3 pts or Faithfulness < 0.8.
4. **Monitor production**: sample 5% of live traffic, run RAGAS faithfulness asynchronously, alert on drift.
5. **Close the loop**: add production failures to the golden set; retune retrieval (chunk size, top-k, reranker threshold) based on Recall@5 regressions.

### Example / Tradeoff
On a customer support RAG over 50K docs: baseline Recall@5 = 61% with dense-only retrieval. Adding BM25 hybrid search lifted it to 73%. Adding a cross-encoder reranker (Cohere Rerank) lifted Precision@5 from 55% → 78% — RAGAS Faithfulness went from 0.71 to 0.86. The reranker added ~120ms latency but eliminated the most egregious hallucination class (irrelevant context injected into answers).

NDCG vs MRR: for customer support QA (one correct answer), MRR is most interpretable to stakeholders — "on average, the right doc is the 1.3rd result." NDCG is better for search where docs have tiered relevance (a doc that partially answers is better than an irrelevant one).

**Tradeoff:** RAGAS faithfulness uses an LLM judge — costs money (~$0.001/query at gpt-4o-mini). For 10K golden queries, that's $10/eval run. Use a cheaper judge for nightly runs and gpt-4o for pre-release gates.

---

## Verbal script

**Opening (30s):**
"RAG evaluation is a two-layer problem that most engineers under-prepare for. Layer one is retrieval quality — did we surface the right documents? Layer two is generation quality — did the LLM produce a faithful answer from those docs? I'd instrument both layers with different metrics and tie it all to a golden dataset and production monitoring. Let me walk through each."

**Core explanation (2–3 min):**
"For retrieval, the core metrics are Recall@k, Precision@k, MRR, and NDCG. The right choice depends on the use case. For a QA system where there's one right answer, MRR is most intuitive — it tells you the average rank of the first correct doc. For a ranked search where docs have tiered relevance, NDCG is better because it rewards you for putting the *most* relevant doc at the top. I typically use Recall@5 as my primary retrieval health KPI — it's easy to explain: 'In 73% of queries, the right document appears in the first 5 results.'

For generation, I use RAGAS — an open-source framework that measures four things: Faithfulness (is the answer entailed by the retrieved context?), Answer Relevancy (is the answer on-topic?), Context Precision (are the retrieved chunks actually relevant?), and Context Recall (did we retrieve all the facts needed to answer?). Faithfulness is the most important — it directly measures hallucination risk.

The workflow is: build a golden dataset of 200–500 annotated (question, answer, relevant doc IDs) triples, run offline eval before every deploy, and gate on regressions — I block any deploy where Recall@5 drops more than 3 points or Faithfulness falls below 0.8."

**Tradeoff / production angle (1 min):**
"In production I sample about 5% of live traffic and run RAGAS faithfulness asynchronously — it adds cost (about a dollar per thousand queries at gpt-4o-mini), but it's worth it to catch model drift. I also track business metrics: deflection rate for support use cases, p95 latency under 3 seconds, and thumbs-down rate. The key thing I've learned is that you can have great NDCG and still have poor deflection rate — because the user experience depends on how well the answer is synthesized, not just whether the right doc was retrieved. So you need both layers."

**Wrap-up (30s):**
"So the mental model is: retrieval metrics catch the 'we didn't find the right doc' failures, RAGAS catches the 'we found the doc but the LLM hallucinated' failures, and production metrics catch the 'technically correct but useless in practice' failures. Happy to go deeper on any layer — RAGAS internals, how to build the golden dataset, or the production monitoring setup."

---

## Pitfalls

- **Mistake:** Only mentioning BLEU/ROUGE for RAG evaluation — **Better:** Explain that BLEU/ROUGE are n-gram overlap metrics designed for MT/summarization; they miss faithfulness entirely (a hallucinated answer with good vocabulary scores well). Use RAGAS Faithfulness + Answer Relevancy for generative eval.
- **Mistake:** Skipping retrieval metrics entirely and only evaluating the final answer — **Better:** Explicitly separate retrieval eval (Recall@5, MRR, NDCG) from generation eval (RAGAS). The most common RAG failures are retrieval failures, not generation failures — if you only measure the final answer, you can't distinguish "retrieved wrong doc → hallucinated" from "retrieved right doc → hallucinated."
- **Mistake:** Saying "I'd use human evaluators" without mentioning the scalability problem — **Better:** Human eval is the gold standard for a 50-query spot check, but not scalable. Use RAGAS LLM-as-judge for automated eval at scale, validated against human labels on a calibration set. Also mention the cost tradeoff: gpt-4o judge is expensive; gpt-4o-mini is 10× cheaper and good enough for nightly runs.
- **Mistake:** Omitting the golden dataset build process — **Better:** Explain how to create it: start with historical support tickets that have known resolutions, add SME-annotated edge cases, and use synthetic generation (have GPT-4 generate questions from each doc, then human-review). Stress that the golden set must grow with production failures.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q13: Common RAG failure points — how debug them?](02-013-common-rag-failure-points-how-debug-them.md) | Complementary — failure taxonomy maps to which eval layer catches each |
| [Q20: RAG returns relevant docs but users can't find the answer](02-020-rag-returns-relevant-docs-but-users-cant-find-the-answer-sea.md) | Follow-up — context_recall vs answer_relevancy diagnostic split |
| [Q34: Weak evaluation hiding retrieval failures](02-034-weak-evaluation-hiding-retrieval-failures.md) | Same theme — why answer-only eval masks retrieval problems |

---

## One-liner recall

> RAG eval = retrieval layer (Recall@5, MRR, NDCG on a golden dataset) + generation layer (RAGAS Faithfulness, Answer Relevancy, Context Precision/Recall) + production signals (deflection rate, p95 latency, thumbs-down), with golden dataset regression gates before every deploy.
