# Scale RAG to 10M+ articles — sharding, caching, retrieval optimization

**Category:** 02-rag-systems
**Question #:** 019
**Source section:** §2 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
This is a senior-level system design question that probes whether a candidate can reason about RAG beyond a single-machine prototype. Interviewers want to see awareness of distributed vector index sharding, caching hierarchies, retrieval latency budgets, and operational cost control at internet scale. It specifically tests production architecture instincts, not just algorithm knowledge.

### Trigger phrases
- "Scale RAG to 10M+ articles"
- "Your RAG system works for 10K docs — how do you scale it to 50 million?"
- "We're ingesting the whole web — how do you make retrieval still fast?"
- "How would you handle 10M+ documents in your vector store?"

### What it tests
Whether the candidate can design a distributed RAG architecture with sharded vector indexes, multi-layer caching, and retrieval latency controls at scale.

---

## Answer

### Concept
At 10M+ articles, a single-node vector index saturates memory and query throughput. The solution is a distributed RAG architecture built on three pillars: **shard the index horizontally**, **cache aggressively at multiple layers**, and **stage the retrieval pipeline** (approximate ANN → lightweight rerank on top-N, not all N).

### Mechanism

**1. Index sharding**
- Partition the corpus across multiple index shards (e.g., by topic cluster, source domain, or hash of doc ID)
- Each shard runs its own HNSW or IVF index; query fan-out hits all shards in parallel and merges results
- Managed services: Pinecone (pods auto-shard), Qdrant (sharded collections), Weaviate (multi-node clusters), or self-hosted FAISS with a scatter-gather service layer
- Rule of thumb: keep each shard ≤ 5M vectors for <50ms ANN latency on 1536-dim embeddings on A100-class GPU; at 10M articles with parent-child chunking you may have 30–60M vectors total, so 10–15 shards

**2. Multi-layer caching**

| Cache layer | What's cached | Tool | TTL |
|-------------|---------------|------|-----|
| Query embedding cache | Embedding vector for identical query strings | Redis (key: SHA256 of query text) | 1 h |
| Semantic similarity cache | Full retrieval result for near-duplicate queries (cosine ≥ 0.97) | GPTCache / custom Redis+Pinecone combo | 15 min |
| Response cache | Final LLM answer for identical (query, top-k context) pairs | Redis / CDN edge cache | 5–30 min |

Semantic caching is the highest-leverage lever: at scale, 20–40% of queries are near-duplicates, reducing LLM calls and p95 latency significantly.

**3. Retrieval pipeline staging**
- Stage 1: ANN over shards — top-100 candidates, ~20–40ms
- Stage 2: BM25 or lightweight bi-encoder rerank on top-100 → top-20, ~10–20ms
- Stage 3: Cross-encoder rerank on top-20 → top-5 for generation, ~80–120ms (only on ambiguous or high-stakes queries)
- Skip cross-encoder for high-confidence ANN matches (cosine > 0.92) to save ~100ms

**4. Ingestion at scale**
- Async batch embedding pipeline: pull new/updated docs from Kafka → deduplicate via MinHash → chunk (parent-child) → embed in batches of 2048 (OpenAI) or self-hosted BGE on GPU → write to shards
- CDC (Debezium) or webhook triggers for incremental index updates; avoid full re-indexing
- Maintain a "freshness score" in metadata for recency boosting

**5. Query routing**
- Route navigational queries (exact article name) → BM25 only, skips ANN entirely
- Route semantic queries → full hybrid pipeline
- Route repetitive/cached queries → response cache, zero LLM calls

### Example / Tradeoff

**Wikipedia-scale example:** 10M articles → ~60M chunks (parent-child) → 60M × 1536-dim float32 = ~370 GB of raw vectors. Pinecone p2 pods hold ~5M vectors each at the s1 size → need ~12 pods. At $0.096/hour per pod = ~$35/day just for index hosting. At this scale, self-hosting Qdrant on 4× A100 80GB nodes becomes cost-competitive (~$8/hr total vs $28/hr Pinecone equivalent) — worth evaluating at 50M+ queries/day.

**Latency budget (p95 target ≤ 500ms end-to-end):**

| Stage | Budget |
|-------|--------|
| Embedding the query | 20ms |
| Cache lookup | 5ms |
| ANN fan-out across shards | 40ms |
| BM25 rerank | 15ms |
| Cross-encoder rerank (optional) | 100ms |
| LLM generation (streaming) | 300ms |
| **Total** | **~480ms** |

---

## Verbal script

**Opening (30s):**
"Scaling RAG to 10M+ articles hits three constraints simultaneously: the vector index no longer fits on one node, retrieval latency blows up without caching, and ingestion needs to be continuous without full re-indexing. I'd address each of those independently. Let me walk through sharding, caching, and pipeline staging."

**Core explanation (2–3 min):**
"First, index sharding. At 10M articles with parent-child chunking, you're looking at 30–60 million vectors. A single HNSW index at that scale would need ~200GB of RAM and query latency climbs past 100ms. The fix is horizontal sharding — partition the corpus across 10–15 shards, each holding 5M vectors, with a scatter-gather service that fans queries out to all shards in parallel and merges the top-K results. Managed options like Pinecone or Qdrant handle this automatically; at very high scale you'd consider self-hosted Qdrant for cost control.

Second, multi-layer caching. At scale, 20–40% of queries are near-duplicates. I'd build three cache layers: a query embedding cache in Redis keyed on the query string's hash, a semantic similarity cache using something like GPTCache that returns stored results for queries with cosine similarity ≥ 0.97, and a response cache for identical (query, context) pairs. This cuts LLM calls dramatically and is the cheapest latency win.

Third, pipeline staging. Rather than running a cross-encoder on all candidates, I stage it: ANN gives top-100 in ~40ms, BM25 or a lightweight bi-encoder reranks to top-20 in ~15ms, and a cross-encoder only runs on ambiguous queries to produce the final top-5. High-confidence ANN matches skip the cross-encoder entirely, saving ~100ms.

For ingestion, I'd use a Kafka-driven async pipeline: docs arrive via CDC from the source system, get deduplicated with MinHash, chunked with parent-child strategy, embedded in GPU batches, and written to index shards incrementally — never a full re-index."

**Tradeoff / production angle (1 min):**
"The main tensions are cost vs. latency vs. freshness. Pinecone is easy to operate but costs ~$35/day at 60M vectors; self-hosted Qdrant halves that at 50M+ queries/day but requires ML infra. The semantic cache improves both cost and latency but introduces a staleness window — if an article is updated and the cache hasn't expired, users get stale answers. I'd manage that by setting cache TTLs to match source update frequency: news → 5-minute TTL, internal docs → 30-minute TTL, legal/compliance docs → no response cache at all.

Another gotcha: scatter-gather across 15 shards means your p99 latency is the slowest shard's latency. I'd add a speculative timeout — if 80% of shards respond within 35ms, return the partial result rather than waiting for the stragglers."

**Wrap-up (30s):**
"So the short version: shard the vector index to keep per-shard ANN fast, cache at the semantic layer to avoid redundant LLM calls, stage the reranking pipeline to apply expensive cross-encoders only where needed, and drive ingestion through a CDC-triggered async pipeline for continuous freshness. Happy to go deeper on any of those layers."

---

## Pitfalls

- **Mistake:** Saying "just use a bigger Pinecone tier" without discussing shard fan-out, scatter-gather latency, or p99 tail latency from the slowest shard — **Better:** Explain sharding mechanics, how top-K results are merged across shards, and the speculative-timeout pattern to bound p99
- **Mistake:** Mentioning caching only at the response level (full LLM output cache) without the semantic similarity layer — **Better:** Walk through all three cache layers (embedding → semantic → response) and explain that semantic caching is the biggest win because 20–40% of production queries are near-duplicates
- **Mistake:** Describing re-indexing as a batch job that runs nightly — **Better:** Explain CDC-triggered incremental ingestion (Debezium/Kafka) so the index stays fresh without expensive full re-indexes, and note that embedding drift requires a re-embedding campaign when switching models

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q17: What is hybrid search? When combine vector + BM25?](02-017-what-is-hybrid-search-when-combine-vector-bm25.md) | Prerequisite — hybrid search is the retrieval core inside each shard |
| [Q18: What is re-ranking? Cross-encoder vs bi-encoder?](02-018-what-is-re-ranking-cross-encoder-vs-bi-encoder.md) | Pipeline stage 3 in the scaled architecture |
| [Q25: Semantic caching — reduce cost and latency?](02-025-semantic-caching-reduce-cost-and-latency.md) | Deep dive on the semantic cache layer described here |

---

## One-liner recall

> Scale RAG to 10M+ docs via horizontal shard fan-out (5M vectors/shard → scatter-gather merge), three-layer caching (embedding → semantic similarity → response), staged retrieval (ANN top-100 → BM25 rerank top-20 → cross-encoder top-5), and CDC-driven incremental ingestion — never full re-index.
