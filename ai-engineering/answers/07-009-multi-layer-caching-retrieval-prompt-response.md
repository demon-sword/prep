# Multi-layer caching: retrieval, prompt, response?

**Category:** 07-cost-latency
**Question #:** 009
**Source section:** §9 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
The interviewer is probing whether you understand that caching in a GenAI system has multiple distinct layers — each with different hit-rate profiles, invalidation strategies, and latency impact — and that naively caching only at the response level misses 60–70% of potential savings. This tests production architecture depth and cost-engineering instinct.

### Trigger phrases
- "How would you reduce cost at 1M queries/day?"
- "Walk me through your caching strategy for a RAG system."
- "What are the different layers you'd cache in a GenAI pipeline?"
- "How do you balance cache freshness with cost savings?"

### What it tests
Ability to design a multi-tier caching architecture across the full RAG pipeline — retrieval, embedding, LLM prompt, and final response — with appropriate TTL and invalidation strategies per layer.

---

## Answer

### Concept
A production RAG system has three independently cacheable stages: (1) **retrieval cache** — reuse vector search results for semantically similar queries; (2) **prompt / embedding cache** — skip re-embedding repeated queries and reuse static prefix tokens; (3) **response cache** — return cached final answers for exact or near-exact repeated requests. Each layer has a different hit rate, staleness risk, and latency profile, so each needs its own TTL and invalidation logic.

### Mechanism

**Layer 1 — Retrieval cache (embedding + ANN results)**

- **Embedding cache:** SHA-256 hash of normalized query text → Redis KV store → skip `text-embedding-3-small` API call on hit. TTL: 24 h (embeddings rarely change unless model is swapped).
- **Query-result cache:** After ANN search, store `query_embedding → [doc_ids, scores]` in Redis with cosine-similarity gating. On new query, compare to cached query embeddings (GPTCache / FAISS index of past queries); if cosine > 0.93, return cached chunks. TTL: 1–4 h (indexed content may update).
- Hit rate: 15–25% for high-repetition corpora (support bots, internal docs).

**Layer 2 — Prompt / prefix cache**

- **LLM prefix caching:** For a static system prompt + few-shot examples (often 500–2 000 tokens), providers like Anthropic (cache_control breakpoints) and OpenAI (automatic prompt caching) cache the KV state of the common prefix. Subsequent requests with the same prefix pay ~10% of normal input token cost for cached tokens.
- Effective when system prompt > 1 024 tokens and doesn't vary per user. Requires keeping the cached prefix at the start of every message, batching requests to the same model instance.
- Cost reduction: 50–90% on static prefix tokens; 0% on dynamic user content.

**Layer 3 — Response cache**

- **Exact cache:** MD5/SHA-256 hash of (system_prompt_version + user_query) → Redis → return cached answer string. TTL: 15 min – 4 h depending on freshness SLA. Useful for FAQ bots where the same question recurs verbatim.
- **Semantic response cache (GPTCache):** Encode query → compare to FAISS index of past query embeddings → if cosine > 0.92–0.95, return cached answer. Hit rate: 20–35% for repetitive support workflows.
- Invalidation: content update webhook (CMS/Confluence) triggers cache flush for affected document namespaces.

**End-to-end flow:**

```
User query
  │
  ▼
[L3 semantic response cache hit?] ──yes──► return cached answer   (< 5 ms)
  │ no
  ▼
[L1 embedding cache hit?] ──yes──► skip embed API call            (cache miss avoided)
  │ no
  ▼
embed query → [L1 query-result cache hit?] ──yes──► skip ANN search
  │ no
  ▼
ANN search → rerank → build prompt
  │
  ▼
[L2 prefix cache applies] ──► 90% discount on static prefix tokens
  │
  ▼
LLM call → response → store in L3 cache → return
```

### Example / Tradeoff

**Before caching (1M queries/day, a frontier model, avg 1 200 input / 300 output tokens):**
- Embedding: 1M × $0.00002 = $20/day
- LLM: 1M × (1 200 × $0.005 + 300 × $0.025) / 1 000 = ~$13 500/day
- **Total: ~$13 520/day**

**After 3-layer caching:**
- L3 semantic cache: 30% hit → 700K LLM calls remain
- L2 prefix cache (1 000-token static prefix, cache reads at 0.1x): saves ~$3 150/day
- L1 embedding cache: 40% hit → 420K embed calls → $8.40/day
- **Total: ~$6 310/day (53% reduction)**

**Key tradeoffs:**
| Layer | Hit rate | Staleness risk | Invalidation complexity |
|-------|----------|----------------|-------------------------|
| L3 response (semantic) | 20–35% | High (content changes) | Medium — namespace flush |
| L2 prefix (LLM KV) | 50–90% on static tokens | Low | Low — version system prompt |
| L1 retrieval (query-result) | 15–25% | Medium (index updates) | Medium — TTL + CDC webhook |
| L1 embedding | 30–40% | Very low | Low — SHA-256 hash key |

Semantic caching carries false-positive risk: cosine threshold too low (< 0.90) returns wrong answers for semantically close but distinct queries (e.g., "cancel subscription" vs "pause subscription"). Set threshold conservatively (0.93–0.95) and monitor cache accuracy via thumbs-down rate on cached responses separately from non-cached.

---

## Verbal script

**Opening (30s):**
"Great question — caching in a GenAI pipeline isn't a single switch. I think of it as three independent layers, each with a different hit rate and invalidation strategy: a retrieval cache, a prompt/prefix cache, and a response cache. The highest-leverage move is usually the response cache combined with prefix caching, but all three compound to give 60–70% cost reduction in practice."

**Core explanation (2–3 min):**
"Let me walk through each layer. Starting at the top: the **response cache**. For repetitive queries — think support bots where the same questions recur — I use GPTCache or a Redis FAISS index. I embed the incoming query, compare cosine similarity to past queries, and if it's above 0.93 I return the cached answer directly. This can hit 20–35% of traffic in high-repetition workflows, completely skipping the LLM call.

One layer down is the **prompt/prefix cache**. Most RAG prompts have a large static system prompt — instructions, few-shot examples — that's identical across thousands of requests. Providers like Anthropic and OpenAI now cache the KV state of that prefix, so subsequent requests pay roughly 10% of normal input token cost for those cached tokens. If my system prompt is 1 500 tokens and I send 700K calls a day after the response-cache hit, I'm saving 90% on 1 500 × 700K tokens — that's material.

The third layer is the **retrieval cache**. I SHA-256 hash the query text to skip the embedding API call on repeated queries. I also cache the ANN search results — the [doc_ids, scores] tuple — keyed by the query embedding in Redis for 1–4 hours. This hits 15–25% of queries and is especially valuable when embeddings cost money at scale.

The full flow is: check L3 response cache → if miss, check L1 embedding cache → run embed if needed → check L1 retrieval cache → run ANN if needed → build prompt → L2 prefix cache applies automatically → run LLM → store in L3."

**Tradeoff / production angle (1 min):**
"The main risk with semantic response caching is false positives — 'cancel subscription' and 'pause subscription' might be above the cosine threshold but need different answers. I set the threshold conservatively at 0.93–0.95 and monitor thumbs-down rate on cached vs non-cached responses separately. If cached responses get flagged at higher rates, I tighten the threshold.

For freshness: L3 responses need content-update webhooks — when Confluence or a product page updates, I flush the affected namespace, not the whole cache. L1 retrieval results get 1–4 h TTLs aligned with my re-indexing cadence. Prefix caches are versioned: I include a `system_prompt_version` in the cache key so a prompt update invalidates cleanly."

**Wrap-up (30s):**
"In production I've seen 3-layer caching reduce LLM costs by 60–70% with minimal accuracy impact when thresholds are tuned. The key insight is: each layer targets a different redundancy pattern — exact/semantic repetition at the top, static prefix in the middle, repeated embeddings at the bottom — so they stack multiplicatively rather than competing."

---

## Pitfalls

- **Mistake:** Describing only response caching (or only semantic caching) as "the caching solution" — **Better:** Enumerate all three layers (retrieval/embedding, prompt/prefix, response) and explain that each has a different hit rate and invalidation strategy; the compound saving is multiplicative.
- **Mistake:** Setting the semantic similarity threshold too low (e.g., 0.85) and not validating accuracy on cached vs uncached responses — **Better:** Start at 0.93–0.95, monitor thumbs-down and hallucination rates separately on cache-hit traffic, and tune from there; mention that "cancel subscription" and "pause subscription" are a classic false-positive pair at 0.88.
- **Mistake:** Treating cache invalidation as a simple TTL problem — **Better:** Describe namespace-scoped invalidation triggered by content-update webhooks (CMS/Confluence → flush affected doc namespace in L3), separate from TTL-based expiry on retrieval caches, so a product page update doesn't force a full cache flush.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q1: Your app gets 1M queries/day — how optimize cost?](07-001-your-app-gets-1m-queriesday-how-optimize-cost.md) | Parent framework — caching is the first lever in the cost hierarchy |
| [Q2: How reduce token costs at scale?](07-002-how-reduce-token-costs-at-scale.md) | Prefix caching and semantic caching are the top token-cost levers |
| [Q25: Semantic caching — reduce cost and latency?](../answers/02-025-semantic-caching-reduce-cost-and-latency.md) | Deep dive on the L3 semantic response cache layer |

---

## One-liner recall

> Multi-layer caching stacks three independent wins: L3 semantic response cache (30% hit, GPTCache/Redis-FAISS, cosine > 0.93), L2 LLM prefix cache (50–90% discount on static system-prompt tokens), and L1 retrieval cache (embedding SHA-256 hash + ANN result Redis TTL) — together cutting 60–70% of GenAI pipeline cost with namespace-scoped invalidation on content updates.
