# What RAG projects have you worked on?

**Category:** 02-rag-systems
**Question #:** 009
**Source section:** §2 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
This is a project deep-dive opener. Interviewers want to confirm you have hands-on, production-level experience with RAG — not just textbook knowledge. They're probing whether you made real design decisions, hit real failure modes, measured real outcomes, and learned from what broke. Senior interviewers immediately follow up with: "What broke?" "What metrics did you track?" "What would you do differently?"

### Trigger phrases
- "Walk me through a RAG project you've built."
- "Tell me about your experience with RAG."
- "What's the most complex RAG system you've shipped?"
- "Have you worked on retrieval-augmented generation in production?"

### What it tests
Hands-on RAG depth: end-to-end pipeline ownership, tradeoff decisions, failure debugging, and quantified outcomes — not just familiarity with the concept.

---

## Answer

### Concept
A strong answer to this question follows a structured project walkthrough: **problem → pipeline design decisions → what broke → how you fixed it → metrics before/after**. The goal is to demonstrate that you've owned a RAG system end-to-end, made non-obvious tradeoffs, and can speak to production realities — not just architecture diagrams.

### Mechanism
Use the **STAR + Tradeoffs** structure for the walkthrough:

1. **Situation** — business problem, scale, constraints (latency budget, doc corpus size, user volume)
2. **Pipeline decisions** — chunking strategy and why, embedding model choice, vector DB selection, retrieval strategy (dense/hybrid), reranking, generation prompt design
3. **What broke** — the first failure mode you hit and how you diagnosed it (retrieval failure? hallucination? latency?)
4. **Fix and outcome** — concrete change made + metric improvement
5. **What you'd do differently** — demonstrates mature engineering judgment

Then layer in the tradeoffs you navigated:
- **Cost vs quality** — smaller embedding model or GPT-4o-mini vs GPT-4o for generation
- **Latency vs recall** — adding a cross-encoder reranker improved precision but added 150ms
- **Freshness vs complexity** — real-time CDC-driven index updates vs nightly batch reindex

### Example / Tradeoff
**Example project: Customer support RAG for a SaaS product**

| Aspect | Decision | Why |
|--------|----------|-----|
| Chunking | Parent-child (1024 / 256 tokens) | Improved context quality while keeping retrieval precise |
| Embedding | `text-embedding-3-small` | 5× cheaper than large, acceptable recall@5 on golden set |
| Vector DB | Pinecone serverless | No ops, metadata filtering for product-tier ACL |
| Retrieval | Hybrid BM25 + dense (RRF fusion) | Dense missed exact product codes; BM25 gap-filled |
| Reranking | Cohere Rerank (cross-encoder) | Lifted RAGAS context_precision from 0.71 → 0.84 |
| Generation | GPT-4o-mini, T=0, citations required | Deterministic, auditable, 60% cost reduction vs GPT-4o |

**Failure arc:** After launch, deflection rate dropped 3 weeks in. Investigation showed embedding model had been frozen but doc corpus had added new product terminology. Fixed by adding nightly RAGAS golden-set regression run + model refresh trigger when context_recall < 0.75.

**Metrics:** RAGAS faithfulness 0.91, context_precision 0.84, p95 latency 1.4s, deflection rate 62% (from 0% pre-RAG).

---

## Verbal script

**Opening (30s):**
"Sure — I've worked on a few RAG projects. Let me walk you through the most production-relevant one: a customer support Q&A system I built for a SaaS product with about 50K support articles and 20K queries per day. I'll cover the architecture, what broke, and the metrics we hit."

**Core explanation (2–3 min):**
"The pipeline was: connectors pulling from Confluence and a Zendesk knowledge base, chunked with a parent-child strategy — 1024-token parent for generation context, 256-token child for precise retrieval. We embedded with `text-embedding-3-small` because benchmarking on our golden set showed it was within 3% of the large model at one-fifth the cost.

For storage, we used Pinecone serverless — straightforward ops, metadata filters for customer-tier access control. Retrieval was hybrid: BM25 via Elasticsearch for exact product codes and model numbers, dense vector search for semantic intent, fused with Reciprocal Rank Fusion. Then a Cohere Rerank cross-encoder on the top 20 chunks down to the top 5.

Generation was GPT-4o-mini at temperature 0 with a strict grounding prompt: 'Answer only using the provided context. If you cannot answer, say so.' Citations were required — every claim had to reference a source document."

**Tradeoff / production angle (1 min):**
"The first real failure was three weeks post-launch: deflection rate dropped from 62% to 48%. RAGAS showed context_recall collapsing — we'd added 400 new articles covering a product relaunch but hadn't re-evaluated embedding quality for that new vocabulary. We added a nightly regression run against our 150-question golden set, with an automatic Slack alert if context_recall fell below 0.75. That caught the next corpus update before it hit users.

The latency tradeoff was interesting — the Cohere reranker added about 150ms at p95, taking us from 1.2s to 1.4s. We accepted it because context_precision improved from 0.71 to 0.84 and the quality uplift reduced escalations by ~30%."

**Wrap-up (30s):**
"So to summarize: parent-child chunking, hybrid retrieval with RRF, cross-encoder reranking, GPT-4o-mini with strict grounding, and a continuous RAGAS eval loop. The biggest lesson was that retrieval quality degrades silently as your corpus changes — you need automated regression gating, not one-time evals. Happy to go deeper on any part of that."

---

## Pitfalls

- **Mistake:** Describing the RAG architecture without mentioning what broke or what metrics you tracked — **Better:** Always anchor to a failure mode you hit ("we saw context_recall drop") and a before/after metric ("deflection rate went from 62% to 48%, and here's how we diagnosed it")
- **Mistake:** Saying "we used RAG" without explaining *why* each design choice was made (e.g., "we used Pinecone" with no reasoning) — **Better:** Justify each decision with a tradeoff ("we chose hybrid over dense-only because our docs had exact product SKUs that dense embeddings couldn't reliably match")
- **Mistake:** Claiming you "implemented RAG with LangChain" and stopping there — **Better:** Demonstrate ownership of the hard parts: chunking strategy, evaluation framework, production failure modes, and what you changed post-launch

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q1: Design a RAG system for a customer support chatbot](02-001-design-a-rag-system-for-a-customer-support-chatbot-how-do-yo.md) | The design template your project walkthrough should map onto |
| [Q13: Common RAG failure points — how debug them?](02-013-common-rag-failure-points-how-debug-them.md) | Explains the failure arc you'll describe (retrieval degradation, embedding drift) |
| [Q21: How evaluate a RAG pipeline? NDCG, MRR, precision@k, recall?](02-021-how-evaluate-a-rag-pipeline-ndcg-mrr-precisionk-recall.md) | The eval metrics (RAGAS context_precision/recall, deflection rate) that make your answer credible |

---

## One-liner recall

> Structure your RAG project answer as: problem → pipeline decisions with justifications → what broke → fix + before/after metrics → what you'd do differently; never just name tools without owning the tradeoffs.
