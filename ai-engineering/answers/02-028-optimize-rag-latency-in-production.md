# Optimize RAG latency in production?

**Category:** 02-rag-systems
**Question #:** 028
**Source section:** §2 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
Interviewers want to see whether you can decompose a multi-stage pipeline into its latency contributors, apply targeted optimizations at each layer, and reason about accuracy/cost tradeoffs. Senior candidates are expected to quantify improvements and know when optimizations break down.

### Trigger phrases
- "How do you reduce latency in your RAG pipeline?"
- "Our p95 response time is 4 seconds — where do you start?"
- "What levers do you pull to speed up a RAG system at scale?"
- "How do you balance latency vs retrieval quality?"

### What it tests
Ability to profile a multi-stage system, identify the binding latency contributor at each layer, and apply layer-appropriate optimizations without sacrificing retrieval quality.

---

## Answer

### Concept
RAG latency is the sum of four stages: **embedding** (query vectorization), **retrieval** (ANN search + optional BM25), **reranking** (cross-encoder over top-N candidates), and **generation** (LLM prefill + decode). Optimizing the wrong layer wastes effort — profile first to identify the bottleneck.

### Mechanism

**1. Profile the pipeline — measure each stage independently**

| Stage | Typical latency (unoptimized) | % of total |
|-------|-------------------------------|------------|
| Query embedding | 20–50 ms | 5–10% |
| ANN retrieval (Pinecone / HNSW) | 20–100 ms | 5–20% |
| BM25 (Elasticsearch) | 10–50 ms | 2–10% |
| Cross-encoder reranking (top-50) | 100–300 ms | 20–40% |
| LLM generation (a small fast model, 500 tok) | 800–2000 ms | 50–70% |

The LLM call dominates. Target it first, then reranking.

**2. Generation layer — biggest lever**

- **Model tiering:** Route simple queries to a small fast model (~$1/1M tokens, ~500ms) and reserve a frontier model for complex ones. Can cut p95 latency by 50%+ for most traffic.
- **Streaming (SSE):** Return tokens as they generate. TTFT (time-to-first-token) drops to 200–400ms even if full response takes 2s — users perceive much faster response.
- **Prompt compression:** Use LLMLingua or selective summarization to reduce context tokens by 30–50%. Fewer input tokens → lower prefill time.
- **Reduce top-k:** Passing 20 chunks instead of 50 cuts both context length and reranker load. Use RAGAS `context_precision` to validate you're not losing signal.
- **Output length control:** Set `max_tokens` to match the use case — Q&A needs 150 tokens, not 500.

**3. Reranking layer**

- **Rerank only top-N, not all candidates:** ANN retrieves top-100, BM25 retrieves top-50; rerank only the top-50 merged candidates (RRF), not all 150. Cuts cross-encoder calls by 3×.
- **Bi-encoder reranker as a pre-filter:** Use a fast bi-encoder (Cohere Embed v3, 5ms) to score and trim from 100 to 20, then apply the cross-encoder only to those 20. Latency drops from 300ms to ~80ms.
- **Async reranking:** If the use case allows slightly stale results, pre-warm a cache of reranked results for common query clusters.

**4. Retrieval layer**

- **Semantic caching:** Embed the incoming query, compute cosine similarity against a Redis/GPTCache cache of past queries. Threshold ~0.93 → serve cached response in <5ms. Effective for high-query-repetition workloads (support bots: ~25–35% hit rate).
- **HNSW ef_search tuning:** Reduce `ef_search` (controls recall-speed tradeoff). ef_search=100 → ef_search=40 cuts ANN latency by ~40% at the cost of ~2pt Recall@5 drop — validate with golden dataset.
- **Pre-filter push-down:** Apply metadata filters (ACL, date range) at the index layer (Pinecone namespaces, Qdrant payload filters), not post-retrieval. Avoids fetching irrelevant candidates.

**5. Embedding layer**

- **Cache query embeddings:** Many repeated queries hit the same embedding — Redis with TTL=1h. Cost: negligible. Gain: ~30ms saved per cache hit.
- **Batch embedding at ingestion:** Amortize API call overhead by embedding 2048 chunks per call rather than one at a time.
- **Self-hosted embedding models:** For high-volume (>1M queries/day), self-host `text-embedding-3-small` on GPU (Triton/TGI). Latency drops from 50ms API round-trip to 5ms local inference.

**6. Infrastructure**

- **Co-locate vector DB and LLM service:** Cross-region hops can add 100–200ms. Pinecone and OpenAI both have us-east-1 and eu-west-1 — pin to the same region.
- **Connection pooling:** Reuse HTTP connections to OpenAI API. Cold TCP + TLS handshake adds ~50ms per request.
- **Speculative retrieval:** While the LLM is generating, pre-fetch retrieval candidates for likely follow-up queries (works well in multi-turn chat where next question is often predictable).

### Example / Tradeoff

**Before/after at 100K queries/day:**

| Optimization | p95 latency before | p95 latency after | Change |
|---|---|---|---|
| Streaming enabled | 3200ms (full wait) | 350ms TTFT | −90% perceived |
| A frontier model → a small fast model (80% traffic) | 2100ms | 550ms | −74% |
| Rerank top-50 → top-20 | 280ms rerank | 80ms rerank | −71% |
| Semantic cache (30% hit rate) | 3500ms avg | 2450ms avg | −30% |
| ef_search 100 → 40 | 90ms ANN | 40ms ANN | −56% |

**Tradeoff:** Reducing `top-k` and `ef_search` can hurt Recall@5 by 2–5 points. Always validate with a golden dataset (RAGAS `context_recall` ≥ 0.80 SLO) before shipping.

---

## Verbal script

**Opening (30s):**
"I'd approach this as a profiling problem first — RAG latency comes from four stages (embedding, retrieval, reranking, generation), and the fix depends on which one is binding. In my experience, the LLM call dominates at 60–70% of total latency, so I start there."

**Core explanation (2–3 min):**
"For the generation layer, the biggest wins are model tiering and streaming. I'd route simpler queries — keyword lookups, FAQs — to a small fast model, which is 5× cheaper and roughly 3× faster than a frontier model. For the user experience angle, I'd enable token streaming (SSE) immediately — even if the full response takes 2 seconds, TTFT drops to 300–400ms and the UI feels snappy.

Next I'd look at the reranking layer. A cross-encoder over 100 candidates is expensive — 200–300ms. The fix is two-stage: use ANN to get 100, a fast bi-encoder to trim to 20, then cross-encoder on those 20 only. That cuts reranker latency by ~70%.

On the retrieval side, semantic caching is the highest-ROI lever for repetitive workloads — embed the query, do a cosine similarity lookup in Redis, and if it's above 0.93 just serve the cached answer. For a support bot with high query repetition you get 25–35% hit rates, saving the entire pipeline cost and latency for those queries.

I'd also tune HNSW `ef_search` — dropping from 100 to 40 cuts ANN latency by half at a small recall cost — and validate that Recall@5 stays above our SLO on a golden dataset."

**Tradeoff / production angle (1 min):**
"The main tension is accuracy vs speed. Reducing `ef_search` or `top-k` can hurt context recall. Smaller models hallucinate more on complex queries. The right approach is layered SLOs: p50 latency target (e.g. <800ms), p95 target (e.g. <2s), and a RAGAS faithfulness floor (e.g. ≥0.80). If an optimization improves latency but drops faithfulness below the floor, it's not worth it. I'd A/B test model tiering in particular — route 10% of traffic to the smaller model, measure answer quality via thumbs-down rate and golden-set regression before full rollout."

**Wrap-up (30s):**
"In summary: stream first for perceived latency, tier models for generation speed, cache for high-repetition traffic, and tune retrieval parameters with golden-set validation. Happy to go deeper on any layer — semantic caching architecture, reranker design, or model tiering routing logic."

---

## Pitfalls

- **Mistake:** Saying "just use a faster model" without specifying which model, the accuracy tradeoff, or how you'd route traffic — **Better:** Name a small fast model vs a frontier model, explain the routing heuristic (query complexity classifier or regex-based fast-path), and describe the A/B test to validate accuracy before full rollout.
- **Mistake:** Treating semantic caching as the first lever without mentioning threshold tuning — cache at cosine>0.80 will return wrong answers for superficially similar but semantically different queries — **Better:** Explain the threshold tuning process (0.92–0.97 depending on query variance), TTL strategy, and cache invalidation on knowledge base updates.
- **Mistake:** Ignoring streaming and treating TTFT as the same as total latency — **Better:** Distinguish TTFT (user-perceived) from total response time, and explain that streaming makes a 2s response feel like a 350ms response to the user.
- **Mistake:** Optimizing only the LLM call while ignoring that reranking can be the bottleneck in some pipelines — **Better:** Profile all four stages independently before assuming which is dominant; reranking on a large candidate set can exceed LLM latency.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q25: Semantic caching — reduce cost and latency?](02-025-semantic-caching-reduce-cost-and-latency.md) | Deep dive on the highest-ROI retrieval-layer optimization |
| [Q27: Key tradeoffs — latency vs accuracy, chunk size vs context, cost vs quality?](02-027-key-tradeoffs-latency-vs-accuracy-chunk-size-vs-context-cost.md) | Broader tradeoff framework this question fits into |
| [Q18: What is re-ranking? Cross-encoder vs bi-encoder?](02-018-what-is-re-ranking-cross-encoder-vs-bi-encoder.md) | Reranking layer — the second-biggest latency contributor |

---

## One-liner recall

> Profile the four RAG stages (embed→retrieve→rerank→generate), then hit the biggest contributor first: stream LLM output for perceived latency, tier to a small fast model for speed, semantic-cache repetitive queries, and trim reranker candidates from 100 to 20 with a fast bi-encoder pre-filter.
