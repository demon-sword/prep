# Latency/cost/relevancy tradeoff triangle?

**Category:** 07-cost-latency
**Question #:** 013
**Source section:** §9 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
The interviewer wants to see whether you can reason about system-level tradeoffs rather than optimizing a single dimension in isolation. In production RAG and LLM systems, every architectural decision — chunk size, top-k, reranker choice, model tier, caching threshold — simultaneously moves all three axes. Strong candidates demonstrate they have a mental model that lets them quantify the tradeoff and make a deliberate decision; weak candidates treat each dimension as independent knobs they can tune separately.

### Trigger phrases
- "How do you balance latency, cost, and relevancy in a RAG system?"
- "What tradeoffs do you accept when optimizing for latency?"
- "Walk me through the key tradeoffs in your retrieval pipeline."

### What it tests
Ability to reason about three-way production tradeoffs and make principled, quantified decisions rather than optimizing greedily along a single axis.

---

## Answer

### Concept
In LLM-powered retrieval systems, **latency, cost, and relevancy form a constrained tradeoff triangle**: improving any one dimension almost always degrades at least one of the others. There is no free lunch — you must decide which constraint to treat as a hard SLO and which to sacrifice, and you must be able to *quantify* the tradeoff so the business can make an informed decision.

### Mechanism

**The three axes defined:**

| Axis | Production proxy metric | Primary driver |
|------|------------------------|----------------|
| **Latency** | p95 TTFT / end-to-end response time | Number of serial LLM calls, context length (prefill cost), reranker depth |
| **Cost** | $/query | Input+output tokens × model price, embedding calls, reranker inference |
| **Relevancy** | RAGAS Faithfulness / Recall@5 / NDCG | Chunk size, top-k, reranker quality, model capability |

**How they pull against each other — concrete examples:**

1. **Increasing top-k (relevancy ↑):**
   - More retrieved chunks → longer context → higher prefill cost (cost ↑, latency ↑)
   - "Lost in the middle" risk increases past k=5-7 (relevancy non-linearly degrades)
   - *Mitigation:* cross-encoder reranking on top-k, then pass top-3 to the LLM — buy relevancy cheaply

2. **Using a stronger model (relevancy ↑):**
   - A frontier model vs a small fast model: 5× input cost ($5/M vs $1/M), 2-4× higher latency
   - *Mitigation:* model tiering — route ≥60% of simple queries to the cheap model

3. **Semantic caching (latency ↓, cost ↓):**
   - Cosine similarity threshold is the tradeoff knob: θ=0.97 → near-zero false-hit rate, low hit rate; θ=0.90 → higher hit rate but occasional stale/wrong responses
   - *Mitigation:* domain-specific threshold tuning on golden set; segment cache by query type

4. **Cross-encoder reranking (relevancy ↑):**
   - BGE-Reranker / Cohere Rerank on top-20 candidates adds ~80-200ms
   - NDCG@5 typically +15-25% — often worth it for answer quality
   - *Mitigation:* rerank on top-20 only (not top-100); self-host BGE-Reranker for latency control

5. **Smaller chunk size (relevancy ↑ for precision, ↓ for recall):**
   - Smaller chunks → more precise retrieval, but risk splitting context across boundaries
   - Larger chunks → more context per chunk, but "lost in the middle" risk, higher cost
   - *Sweet spot:* parent-child chunking (256-token child for retrieval, 1024-token parent for generation)

### Example / Tradeoff

**Production tuning example — enterprise RAG at 100K queries/day:**

| Configuration | Recall@5 | p95 latency | Cost/query |
|---------------|----------|-------------|------------|
| Baseline: top-5 dense, a frontier model | 0.74 | 4.2s | $0.0225 |
| + hybrid BM25+dense (RRF) | 0.81 (+9%) | 4.6s (+10%) | $0.0232 (+3%) |
| + cross-encoder rerank top-20→3 | 0.86 (+16%) | 3.1s (−26%) | $0.0100 (−57%) |
| + model tiering 80% small tier / 20% frontier | 0.84 (−2%) | 2.8s (−7%) | $0.0040 (−60%) |
| + semantic cache θ=0.93 | 0.84 (0%) | 1.4s (−50%) | $0.0029 (−28%) |

The reranker is the key insight: **it simultaneously improves relevancy AND reduces cost** by cutting context length to the LLM from 5 chunks to 3 — a rare win-win. The only pure tradeoff is model tiering (−2% Recall@5 for 60% cost savings), which is acceptable for FAQ-style queries.

---

## Verbal script

**Opening (30s):**
"I think of latency, cost, and relevancy as a constrained triangle — you can't optimize all three simultaneously. Every architectural decision moves all three axes, and the right answer depends on which constraint you treat as a hard SLO. Let me walk through how I reason about this in practice."

**Core explanation (2–3 min):**
"The three axes each have a concrete production proxy. Latency is p95 end-to-end response time, ideally split into TTFT and total time. Cost is dollars per query — input tokens times price-in plus output tokens times price-out. Relevancy is typically RAGAS Faithfulness and Recall@5 on a golden dataset.

The key tensions are: first, increasing top-k improves recall but raises cost and latency because you're sending more context to the LLM — and past k=5-7, you hit 'lost in the middle' diminishing returns. Second, a stronger model improves relevancy but costs 16 times more and adds 2-4x latency. Third, semantic caching drops latency and cost dramatically but has a correctness tradeoff at the threshold — if you set cosine similarity too low, you serve stale or wrong cached responses.

The insight I've found most useful in practice is that cross-encoder reranking is the rare optimization that wins on two axes simultaneously: it improves relevancy by reordering candidates, AND it lets you cut context length from top-k=10 to top-3 chunks, which reduces both latency and cost. In one system I tuned, adding a BGE-Reranker on top-20 candidates cut p95 latency by 26% and cost by 57% while improving Recall@5 by 16%."

**Tradeoff / production angle (1 min):**
"Where I accept a tradeoff is model tiering: routing 80% of simple queries to a small fast model costs 60% less but sacrifices about 2% on Recall@5. That's a business decision — for FAQ-style queries, 2% recall loss is fine; for high-stakes compliance queries, I'd route everything to the full model. The key discipline is to quantify the tradeoff on a golden dataset before committing, not assume it's acceptable."

**Wrap-up (30s):**
"So my framework is: treat one constraint as the hard SLO — usually p95 latency for interactive use cases — then use the decision tree to reduce cost without sacrificing relevancy: cache first, rerank to fewer chunks, tier the model, and compress the prompt. Happy to go deeper on any specific lever."

---

## Pitfalls

- **Mistake:** Saying "I'd tune top-k until relevancy is good" without mentioning cost or latency impact — **Better:** "Increasing top-k improves recall but raises both latency (longer context prefill) and cost (more input tokens); I'd offset this by reranking to top-3 chunks before generation, which buys relevancy without the full cost penalty."
- **Mistake:** Treating caching as a pure win — "I'd add a semantic cache to reduce latency and cost" — **Better:** "Semantic caching has a correctness tradeoff: the cosine threshold is the knob. I'd set θ=0.93–0.95 for most domains and validate false-hit rate on a golden set — at θ=0.90 the hit rate is higher but stale responses start leaking through, which hurts measured relevancy."
- **Mistake:** Conflating throughput optimization with latency optimization — "I'd batch requests to reduce latency" — **Better:** "Batching improves throughput (tokens/sec, GPU utilization) but increases per-request latency because requests wait for the batch to fill. For interactive, latency-SLO-bound workloads, I'd use streaming SSE and semantic caching instead of batching."

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q3: How reduce latency in GenAI applications? ⭐](07-003-how-reduce-latency-in-genai-applications.md) | Latency lever deep-dive — same framework applied to latency-first optimization |
| [Q1: Your app gets 1M queries/day — how optimize cost? ⭐](07-001-your-app-gets-1m-queriesday-how-optimize-cost.md) | Cost lever deep-dive — same triangle, cost-first framing |
| [Q18: What is re-ranking? Cross-encoder vs bi-encoder?](../answers/02-018-what-is-re-ranking-cross-encoder-vs-bi-encoder.md) | Reranking as the win-win lever — improves relevancy while reducing context cost |

---

## One-liner recall

> Latency, cost, and relevancy form a constrained triangle where cross-encoder reranking is the rare win-win (relevancy ↑, cost ↓, latency ↓ via fewer chunks to LLM), while top-k, model tier, and cache threshold are the primary three-way tradeoff knobs.
