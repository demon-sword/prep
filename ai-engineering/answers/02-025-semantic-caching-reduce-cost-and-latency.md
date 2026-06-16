# Semantic caching — reduce cost and latency?

**Category:** 02-rag-systems
**Question #:** 025
**Source section:** §2 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
The interviewer is probing whether you think beyond naive LLM call-per-request patterns and understand the full cost/latency optimization toolkit. Semantic caching is a high-signal topic because it reduces both cost (fewer LLM tokens billed) and latency (sub-millisecond cache hits vs 2–10s LLM round-trips) simultaneously — a rare double win. At 1M queries/day, even a 20% cache hit rate can save thousands of dollars daily.

### Trigger phrases
- "How do you optimize cost at 1M queries/day?"
- "How do you reduce latency in GenAI applications?"
- "What caching strategies have you used in RAG or LLM systems?"
- "How do you handle repeated or similar user queries at scale?"

### What it tests
Ability to design multi-layer caching architectures for LLM applications, including the fuzzy-match insight that distinguishes semantic caching from traditional exact-match caching.

---

## Answer

### Concept
Semantic caching stores LLM responses keyed by the *meaning* of a query rather than its exact text. When a new query arrives, its embedding is compared against cached query embeddings; if the cosine similarity exceeds a threshold (typically 0.92–0.97), the cached response is returned without calling the LLM. This captures paraphrases, minor rewording, and near-duplicate intents that exact-match caching would miss entirely.

### Mechanism
**Three-layer caching stack (innermost to outermost):**

1. **Response cache (semantic)** — embed the incoming user query → compare against a vector index of previously-answered queries (Redis + FAISS, or GPTCache/Zep) → if similarity ≥ threshold, return cached answer directly. Cache hit path: ~5–20ms vs 2–10s LLM call.

2. **Embedding cache** — store `(text → embedding vector)` in Redis with a TTL of hours/days. Avoids re-calling the embedding model for repeated or near-identical document chunks during ingestion or repeated query terms. Saves ~$0.02/1M tokens (OpenAI text-embedding-3-small) at scale.

3. **Retrieval cache (retrieved chunks)** — for queries that pass the semantic cache miss but hit the same top-K documents repeatedly, cache the `(query_hash → [chunk_ids])` mapping with a short TTL (5–15 min). Avoids redundant vector DB round-trips for hot queries.

**Key implementation decisions:**
- **Similarity threshold**: 0.92–0.97 cosine similarity. Too low (0.85) → wrong answers served for different-intent queries. Too high (0.99) → effectively exact-match, low hit rate.
- **TTL management**: Cache entries must expire when underlying documents change (event-driven invalidation via webhook/CDC) or on a fixed TTL (1–24 hours depending on content freshness requirements).
- **Cache scope**: User-level vs global. For personalized responses, scope the cache per user. For factual Q&A (support docs, HR policies), a global shared cache gives the highest hit rate.
- **Cache backend**: GPTCache (open-source, pluggable backends), Redis + FAISS for custom implementations, or Zep for agent memory + caching combined.

**Math at scale:**
At 1M queries/day with a 30% semantic cache hit rate and avg LLM cost of $0.01/query:
- Without cache: $10,000/day
- With 30% hit rate: $7,000/day → **$3,000/day saved**
- Latency: 30% of requests return in ~10ms vs 3–5s → meaningful p95 improvement

### Example / Tradeoff
**GPTCache** (open-source, used at production scale) sits as middleware between the application and the LLM API. It embeds the query, checks a FAISS index, and returns a cached response on hit. Cache misses proceed normally, and the new (query_embedding, response) pair is stored.

**Tradeoff table:**

| Dimension | Benefit | Risk |
|-----------|---------|------|
| Cost | 20–40% reduction at scale | Stale responses if TTL too long |
| Latency | ~10ms hit vs 3–5s LLM call | Embedding cost on every query (mitigate: embed cache) |
| Accuracy | Identical for true semantic duplicates | Wrong answer if threshold too low (paraphrase ≠ same intent) |
| Personalization | High hit rate for shared factual content | Must scope per-user for personalized responses |

**Where it breaks down:**
- **Dynamic content** (stock prices, real-time alerts) — any caching with TTL > seconds is wrong; disable semantic cache for these query types.
- **Long-tail queries** — if users ask highly diverse, specific questions, hit rate may be <5% and the overhead (embedding + similarity check) adds latency with no benefit. Profile hit rates and gate the cache selectively.
- **Threshold calibration** — requires empirical tuning per domain. A 0.95 threshold for a legal Q&A system may still conflate "can I terminate a contract?" with "can a contract be void?" — always validate with a golden set of known-different queries.

---

## Verbal script

**Opening (30s):**
"Semantic caching is one of the highest-leverage optimizations for LLM applications because it simultaneously reduces cost and latency. The key insight is that traditional exact-match caching captures almost nothing for LLM workloads — users rephrase the same question constantly. Semantic caching uses embedding similarity to recognize paraphrases and serve cached responses. Let me walk through how I'd implement a three-layer caching stack."

**Core explanation (2–3 min):**
"I'd build three layers. The outermost is the response cache — when a query arrives, I embed it and do a cosine similarity search against a FAISS index of previously answered query embeddings. If similarity exceeds ~0.95, I return the cached answer directly — that's a ~10ms response vs a 3–5 second LLM call.

The middle layer is an embedding cache in Redis. Re-embedding the same query text costs money and time. Storing `text → vector` with a day-long TTL means we call the embedding API once per unique string.

The innermost layer is a retrieval cache — for the same query shape that maps to the same top-K chunks, I cache the `(query_hash → chunk_ids)` mapping for 5–15 minutes. This saves vector DB round-trips for hot queries.

For the implementation I've used GPTCache, which plugs in as middleware between your app and the LLM API. You configure the similarity threshold, backend (FAISS, Redis, or in-memory), and TTL. At 1M queries/day with a 30% hit rate and $0.01/query average, that's $3,000/day in savings."

**Tradeoff / production angle (1 min):**
"The main risks are threshold calibration and TTL management. Set the threshold too low — say 0.85 — and you serve wrong answers for queries with similar surface form but different intent. I'd validate any threshold against a golden set of known-different query pairs from your domain.

TTL is the other failure mode. For dynamic content — real-time prices, live inventory — caching is wrong entirely; I'd disable the semantic cache for those query types via a routing layer. For static content like policy docs, a 24-hour TTL is usually safe if you add webhook-triggered invalidation on document updates."

**Wrap-up (30s):**
"To summarize: semantic caching uses embedding similarity rather than exact-match, capturing paraphrase hits that exact caching misses entirely. A three-layer stack — response cache, embedding cache, retrieval cache — covers all the cost and latency surfaces. The key production risk is threshold calibration and TTL-driven staleness, both of which require domain-specific tuning. Happy to go deeper on GPTCache internals or threshold selection."

---

## Pitfalls

- **Mistake:** Describing caching as "just using Redis to store LLM responses keyed by query string" — **Better:** Explain that exact-match string caching has near-zero hit rate for LLM workloads because users rephrase constantly; semantic caching uses embedding cosine similarity to capture paraphrases, which is the key architectural insight.
- **Mistake:** Ignoring threshold calibration risk — saying "set similarity to 0.9 and you're done" — **Better:** Explain that the threshold must be tuned per domain, validated against a golden set of known-different queries, and that too-low thresholds serve confidently wrong answers (which is worse than a cache miss).
- **Mistake:** Not mentioning TTL and invalidation strategy — treating the cache as permanent — **Better:** Discuss TTL policy (content-type dependent: hours for static docs, disabled for real-time data) and event-driven invalidation via webhooks/CDC when source documents change.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q28: Optimize RAG latency in production](02-028-optimize-rag-latency-in-production.md) | Semantic caching is the #1 latency lever — follow-up detail |
| [Q7: How efficiently generate and store embeddings](02-007-how-efficiently-generate-and-store-embeddings-for-products-a.md) | Embedding cache is a sub-component of semantic caching |
| [Q19: Scale RAG to 10M+ articles](02-019-scale-rag-to-10m-articles-sharding-caching-retrieval-optimiz.md) | Scale context where multi-layer caching architecture matters most |

---

## One-liner recall

> Semantic caching embeds incoming queries and returns cached LLM responses on cosine similarity hits (≥0.95), cutting 20–40% of LLM calls at scale — calibrate the threshold per domain and pair with TTL + invalidation for correctness.
