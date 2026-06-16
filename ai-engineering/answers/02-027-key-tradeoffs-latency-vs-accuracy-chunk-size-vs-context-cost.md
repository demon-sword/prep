# Key tradeoffs: latency vs accuracy, chunk size vs context, cost vs quality?

**Category:** 02-rag-systems
**Question #:** 027
**Source section:** §2 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
This is a senior-level synthesis question. The interviewer wants to see that you understand RAG is not a single dial but a triangle of competing forces — and that every production decision forces an explicit tradeoff. Weak candidates treat each dimension independently; strong candidates expose the interactions (e.g. larger chunks → better accuracy but higher cost AND latency) and show they have a principled framework for resolving them.

### Trigger phrases
- "What are the main tradeoffs in a RAG pipeline?"
- "How do you balance latency, accuracy, and cost in RAG?"
- "Walk me through how chunk size affects performance."
- "What levers do you pull when RAG is too slow / too expensive / not accurate enough?"

### What it tests
Ability to reason across all three RAG optimization axes simultaneously and make explicit, metric-driven tradeoffs rather than treating each in isolation.

---

## Answer

### Concept
A production RAG system lives inside a **tradeoff triangle**: latency, retrieval/generation accuracy, and cost. Increasing chunk size improves context completeness (accuracy ↑) but raises token spend and LLM latency (cost ↑, latency ↑). Retrieving more candidates (higher top-k) helps recall but feeds more tokens to the LLM and adds reranking time. Swapping GPT-4o for GPT-4o-mini cuts cost 10–20× but may reduce answer quality. Every tuning decision moves at least two corners of the triangle simultaneously.

### Mechanism

**Tradeoff 1 — Latency vs Accuracy**

| Lever | Latency impact | Accuracy impact |
|-------|---------------|-----------------|
| Increase top-k (e.g. 5→20) | +30–60 ms reranker | +recall, but lost-in-middle risk |
| Add cross-encoder reranker | +80–200 ms | +precision@5 ~15–25 pts |
| Use larger LLM (GPT-4o vs mini) | +200–500 ms | +complex reasoning |
| Enable streaming (TTFT) | TTFT perceived ↓ | no change |
| Semantic cache hit | −400–800 ms | same as cached answer |

Key insight: **reranking is the highest ROI latency spend** — 80–200 ms buys 15–25 precision points. Semantic caching eliminates latency entirely for repeat queries.

**Tradeoff 2 — Chunk Size vs Context Quality**

| Chunk size | Pros | Cons |
|------------|------|------|
| Small (128–256 tokens) | High retrieval precision; cheap per chunk | Breaks cross-sentence reasoning; misses doc-level context |
| Medium (512–1024 tokens) | Best balance for most QA tasks | Some irrelevant context leaks in |
| Large (2048+ tokens) | Full-section coherence; good for summarization | Context pollution; "lost in the middle"; expensive per LLM call |

**Parent-child chunking** resolves the tension: index small child chunks (256 tokens) for precise retrieval, but return their parent (1024 tokens) to the LLM for coherent context. This gives retrieval precision AND generation quality without inflating LLM calls.

**Tradeoff 3 — Cost vs Quality**

| Decision point | Cost-first choice | Quality-first choice |
|---------------|-------------------|----------------------|
| Generation model | GPT-4o-mini (~$0.15/1M in) | GPT-4o (~$2.50/1M in) |
| Embedding model | text-embedding-3-small | text-embedding-3-large |
| Reranker | bi-encoder score only | Cohere Rerank / BGE-Reranker |
| Top-k | 3 | 10 + rerank to 3 |
| Response cache | Aggressive (θ=0.92) | Conservative (θ=0.97) |

**Cost math at 1M queries/day (typical customer support RAG):**
- GPT-4o-mini + aggressive caching: ~$800–1,200/day
- GPT-4o + no caching: ~$12,000–18,000/day
- Model tiering (mini for routing, GPT-4o for escalations): ~$2,000/day with better quality on hard queries

### Example / Tradeoff

**Real tuning sequence (customer support chatbot):**

1. **Baseline:** chunk=512, top-k=5, no reranker, GPT-4o-mini → 68% faithfulness, p95 latency 1.1 s, $0.0012/query
2. **Add cross-encoder reranker (Cohere Rerank):** faithfulness → 79% (+11 pts), latency → 1.35 s (+230 ms), cost → $0.0018/query
3. **Switch to parent-child chunking:** faithfulness → 84% (+5 pts), latency neutral, cost neutral
4. **Add semantic cache (GPTCache, θ=0.93, TTL=1 hr):** 28% hit rate, avg latency → 0.92 s (cache path ~0.1 s), cost → $0.0013/query
5. **Final state:** 84% faithfulness, 0.92 s p95, $0.0013/query — better accuracy and lower cost than baseline

The lesson: **fix accuracy first (reranker + chunking strategy), then recover cost/latency via caching** — not the reverse.

**RAGAS metric targets for production:**
- Faithfulness ≥ 0.85
- Answer Relevancy ≥ 0.80
- Context Recall ≥ 0.75 (retrieval health)
- p95 latency ≤ 2.0 s
- Cost per query ≤ $0.002 (customer support SLO)

---

## Verbal script

**Opening (30s):**
"RAG tuning is really about navigating a three-way tradeoff — latency, accuracy, and cost — where almost every dial you turn moves at least two of those simultaneously. I like to think of it as a triangle: you can optimize any two corners, but the third usually suffers unless you're clever about it. Let me walk through the three main tension axes and how I'd resolve them."

**Core explanation (2–3 min):**
"The first axis is **chunk size vs context quality**. Smaller chunks — say 128 to 256 tokens — give you precise retrieval because you're matching tight semantic units. But when you feed those tiny chunks to the LLM, it often lacks the surrounding context to reason across a paragraph. Large chunks flip the problem: retrieval precision suffers because you're matching big blocks, and the LLM hits the 'lost in the middle' problem where content in the middle of a long context gets ignored. The best production pattern I've seen is parent-child chunking — index small child chunks for precise ANN search, but return the parent chunk to the LLM. You get retrieval precision AND generation coherence without a penalty.

The second axis is **latency vs accuracy**. Adding a cross-encoder reranker — Cohere Rerank or BGE-Reranker — typically costs 80 to 200 milliseconds but buys you 15 to 25 points of precision improvement. That's usually the highest ROI latency spend in the pipeline. The way I offset that latency is semantic caching: if 25–30% of queries hit the cache at a cosine threshold around 0.93, your average latency actually drops even after adding the reranker.

The third axis is **cost vs quality**. The biggest lever is model tiering. GPT-4o-mini is roughly 15× cheaper than GPT-4o for generation, so I route routine queries to mini and escalate hard or low-confidence queries to GPT-4o. A concrete example: at 1M queries/day, GPT-4o-only runs about $15K/day; tiered routing with caching brings it under $2K/day with comparable end-user quality on the queries that matter."

**Tradeoff / production angle (1 min):**
"The failure pattern I see most often is teams trying to fix accuracy by blindly increasing chunk size or top-k without measuring the cost and latency impact. A team I've seen bumped top-k from 5 to 20 to recover recall — their faithfulness went up 4 points but latency doubled and token cost tripled. The better move is to fix the underlying retrieval failure (usually vocab mismatch → add BM25 hybrid), then tune from a healthier baseline. Always measure RAGAS faithfulness and context_recall independently so you know whether you have a retrieval problem or a generation problem before pulling levers."

**Wrap-up (30s):**
"So my framework: fix retrieval first — chunking strategy and hybrid search — then add a reranker for precision, then recover cost and latency with semantic caching and model tiering. Measure everything with RAGAS before and after each change. Happy to go deeper on any of those individual levers."

---

## Pitfalls

- **Mistake:** Discussing latency, accuracy, and cost as three independent dials and optimizing each separately — **Better:** Explain the interactions (e.g. larger chunks → higher cost AND latency AND potential accuracy drop from lost-in-middle; cross-encoder reranker → latency cost but accuracy gain that caching can offset)
- **Mistake:** Saying "just use a larger chunk size to improve context quality" without acknowledging context pollution or token cost at scale — **Better:** Recommend parent-child chunking as the production pattern that decouples retrieval precision from generation context size, and cite the cost impact of larger chunks at 1M queries/day
- **Mistake:** Treating semantic caching as a pure optimization add-on rather than a key part of the tradeoff resolution — **Better:** Show that caching at a 25–30% hit rate is what makes the reranker's latency cost acceptable and model tiering cost savings compound

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q28: Optimize RAG latency in production](02-028-optimize-rag-latency-in-production.md) | Deep dive on latency lever specifically |
| [Q25: Semantic caching — reduce cost and latency](02-025-semantic-caching-reduce-cost-and-latency.md) | Core tool for resolving cost/latency tension |
| [Q18: What is re-ranking? Cross-encoder vs bi-encoder?](02-018-what-is-re-ranking-cross-encoder-vs-bi-encoder.md) | The highest-ROI latency spend in the pipeline |

---

## One-liner recall

> RAG's tradeoff triangle — latency, accuracy, cost — means every tuning decision moves multiple axes: fix retrieval first (parent-child chunking + hybrid search + cross-encoder reranker), then recover cost/latency with semantic caching and model tiering, measuring RAGAS faithfulness and context_recall before and after each change.
