# How reduce latency in GenAI applications?

**Category:** 07-cost-latency
**Question #:** 003
**Source section:** §9 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
This is the top latency question in AI engineering interviews and a near-universal senior signal. The interviewer wants to know whether you can think beyond "use a faster model" — specifically: whether you can decompose LLM latency into its distinct phases (TTFT vs total latency), identify which phase dominates for a given use case, and apply the right lever at the right layer. Weak candidates treat latency as a single dial; strong candidates know it's a stack.

### Trigger phrases
- "How do you reduce latency in GenAI applications?"
- "Our LLM responses feel slow — how do you debug and fix that?"
- "What are the bottlenecks in an LLM serving stack and how do you address them?"
- "How do you hit a p95 latency SLO for an LLM feature?"

### What it tests
Production latency engineering: the ability to decompose TTFT vs total latency, identify the dominant bottleneck at each layer (retrieval, model, post-processing), and select the right mitigation without sacrificing quality or exploding cost.

---

## Answer

### Concept
GenAI application latency is not one number — it splits into **Time to First Token (TTFT)** (prefill phase: how fast the model starts responding) and **Time to Last Token (TLTT)** / total latency (decode phase: how fast it finishes). These have different bottlenecks and different mitigations. For interactive use cases, TTFT dominates perceived responsiveness; for batch/async use cases, throughput (tokens/second) matters more. The full latency budget also includes retrieval, reranking, and any post-processing steps.

### Mechanism

**Step 0 — Profile the latency budget end-to-end before optimizing**

Instrument every stage with a timer and trace with a correlation ID. Typical breakdown for a RAG + LLM call:

| Stage | Typical share | Notes |
|-------|--------------|-------|
| Query embedding | 20–50 ms | Often cacheable |
| Vector retrieval (HNSW) | 10–30 ms | ef_search tuning |
| Reranker (cross-encoder) | 80–200 ms | Biggest non-LLM cost |
| LLM prefill (TTFT) | 200–800 ms | Scales with input tokens |
| LLM decode (output tokens) | 500–3000 ms | Scales with output length |
| Post-processing / formatting | 10–50 ms | Often negligible |

**Layer 1 — Skip the LLM call (semantic cache)**
- Semantic cache with Redis + cosine similarity > 0.93 on query embeddings returns cached responses in < 5 ms
- Exact-match cache for identical queries: sub-millisecond
- Particularly high-value for FAQ, support, and autocomplete workloads where query distribution is heavy-tailed
- Expected hit rate: 20–35% on real-world support traffic → those queries drop from 1–3 s to < 10 ms

**Layer 2 — Reduce TTFT (prefill latency)**
- **Prompt compression** (LLMLingua): 30–50% token reduction → proportional prefill speedup (prefill is compute-bound and scales with input length)
- **Anthropic/OpenAI prefix caching**: static system prompt tokens served from KV cache at ~90% latency discount; requires stable prefix ordering
- **Reduce retrieval context**: cross-encoder reranking to top-3 chunks (from top-20) cuts input tokens from ~4K to ~1K — large prefill speedup
- **Streaming (SSE)**: doesn't reduce TTFT but makes it *perceived* faster — user sees tokens arriving in < 1 s even if total latency is 3 s; critical for interactive UX

**Layer 3 — Reduce decode latency (output generation)**
- **Constrain output length**: `max_tokens` + "respond in ≤2 sentences" instruction; decode time scales linearly with output tokens
- **Speculative decoding**: small draft model (e.g. A small open-weight model (7–8B class)) generates K tokens, large target model (a 70B-class open-weight model) verifies in one forward pass; 2–4× speedup on structured/predictable outputs (code, JSON, SQL); vLLM `--speculative-model` flag
- **Model tiering**: route short-answer and FAQ queries to a smaller, faster model (a small fast model: ~400 ms vs a frontier model: ~1500 ms for typical 500-token response)

**Layer 4 — Reduce retrieval and reranking latency**
- **HNSW ef_search tuning**: lower ef_search → faster ANN search at slight recall cost; Pinecone/Qdrant expose this parameter
- **Skip or narrow the reranker**: apply cross-encoder only when retrieval score is ambiguous (e.g., cosine spread < 0.05); use bi-encoder score for high-confidence single-result queries
- **Parallel retrieval**: fan out to multiple sources concurrently with `asyncio.gather()` rather than sequential; saves N-1 round trips

**Layer 5 — Serving infrastructure (self-hosted)**
- **vLLM + PagedAttention**: eliminates KV cache memory fragmentation → higher GPU utilization and consistent low latency under load
- **Tensor parallelism** (vLLM `--tensor-parallel-size`): splits model across GPUs to reduce per-token decode time for large models
- **Continuous batching**: unlike static batching, new requests join in-flight batches → lower queue wait time at high throughput
- **GPU co-location**: place embedding and LLM inference on the same machine to avoid network hop for embeddings

### Example / Tradeoff

**Concrete p95 latency before/after for a RAG support chatbot (target: p95 < 2s TTFT):**

| Optimization | p95 TTFT | Notes |
|-------------|---------|-------|
| Baseline (a frontier model, top-20 chunks, no cache) | ~2400 ms | Over SLO |
| + Streaming SSE | ~2400 ms total, ~300 ms perceived | UX win, no structural change |
| + Semantic cache (30% hit → < 5 ms) | ~1700 ms (blended p95) | Significant but depends on hit rate |
| + Prompt compression + top-3 rerank (60% token reduction) | ~1100 ms | Prefill speedup + smaller context |
| + Model tiering (60% traffic → a small fast model) | ~700 ms blended | ~3× faster for tier-1 queries |
| + Prefix caching on system prompt | ~550 ms | High discount if prefix is stable |

**Key tradeoff:** semantic caching threshold is latency vs correctness — at cosine < 0.92, semantically distinct queries can get stale cached answers. Tune threshold per query type with a quality golden set.

---

## Verbal script

**Opening (30s):**
"I'd start by separating latency into two distinct buckets: time to first token — which drives perceived responsiveness — and total latency, which matters for throughput and batch pipelines. These have different root causes and different fixes, so I'd profile the pipeline end-to-end before touching anything. Once I know where the time is going, I work through five layers from highest to lowest leverage."

**Core explanation (2–3 min):**
"The highest-leverage lever is skipping the LLM call entirely with a semantic cache. I'd use Redis with a cosine similarity threshold — something around 0.93 — on the query embedding. For a support workload, 20-35% of queries are near-duplicates. Those go from two seconds to under ten milliseconds. That's the single biggest perceived-latency win before you touch model serving at all.

Second, I'd add streaming. This doesn't reduce actual latency, but for interactive chat, the user experiencing tokens arriving in 300 milliseconds feels dramatically faster than waiting 2 seconds for a complete response. This should be step one for any user-facing feature.

Third, I'd reduce the prefill cost — which is what drives TTFT. The two best levers here are prompt compression with something like LLMLingua, which can cut system prompt length by 30-50%, and reducing retrieved context via cross-encoder reranking from top-20 down to top-3 chunks. That can take input tokens from 4K to 1K, proportionally cutting TTFT since prefill is compute-bound and scales with input length.

Fourth, model tiering. A small fast model is roughly 3-4× faster than a frontier model for a typical 500-token response, and 80% of FAQ-style queries don't need the more capable model. A lightweight complexity router lets you send those to the fast path.

For self-hosted systems, I'd look at vLLM's PagedAttention for continuous batching and consistent decode throughput, and speculative decoding for structured outputs like JSON or SQL — a small draft model generates candidates that the large model verifies in one forward pass, giving 2-4× decode speedup."

**Tradeoff / production angle (1 min):**
"The key tradeoffs: the semantic cache threshold is the trickiest parameter — too aggressive and you return wrong cached answers; too conservative and hit rate collapses. I'd tune it per query class. Streaming adds infrastructure complexity and means you can't do post-processing before the user sees output. Speculative decoding only helps on predictable outputs; it degrades on highly creative or long-form generation. And model tiering requires a complexity router that itself needs to be fast — otherwise you eat back the savings on the routing latency."

**Wrap-up (30s):**
"So the playbook is: profile first to find the bottleneck, add streaming immediately for UX, implement semantic caching for the skip-call wins, then reduce prefill via compression and context trimming, then tier models, then optimize serving infrastructure. I can go deeper on any of these or talk through how I'd set the p95 SLO and instrument each stage."

---

## Pitfalls

- **Mistake:** "I'd use a faster/smaller model" as the first and only answer — **Better:** Lead with profiling to identify *which* stage is slow (retrieval? prefill? decode?), then apply the right lever; a smaller model doesn't help if the bottleneck is a 200 ms cross-encoder reranker running on CPU.
- **Mistake:** Treating TTFT and total latency as the same thing — **Better:** Distinguish them explicitly; for interactive UX, TTFT < 1s is the key SLO and streaming is the fastest fix; total latency matters for throughput-limited batch workloads where speculative decoding and PagedAttention are more relevant.
- **Mistake:** Adding streaming as an afterthought — **Better:** Streaming SSE should be step one for any user-facing LLM feature; it's the highest perceived-latency improvement for zero model or infrastructure change, and it's architecturally simpler to add early than to retrofit later.
- **Mistake:** Skipping the cache threshold discussion — **Better:** Mention that the cosine similarity threshold for semantic caching is a precision-recall tradeoff; 0.93 is a reasonable default for FAQ queries, but it needs tuning per query type with quality evaluation on a golden set.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q1: Your app gets 1M queries/day — how optimize cost?](07-001-your-app-gets-1m-queriesday-how-optimize-cost.md) | Cost and latency optimizations overlap — caching and tiering help both |
| [Q14: Latency vs throughput for LLM serving?](07-014-latency-vs-throughput-for-llm-serving.md) | Deep-dive on the serving-layer tradeoff between TTFT and tokens/sec |
| [Q16: Real bottleneck in LLM serving throughput? PagedAttention?](07-016-real-bottleneck-in-llm-serving-throughput-pagedattention.md) | vLLM / PagedAttention mechanism for decode throughput |

---

## One-liner recall

> Reduce GenAI latency in priority order: semantic cache (skip call, 20–35% hit → < 10 ms), streaming SSE (perceived TTFT fix), prompt compression + top-3 reranking (cut prefill tokens 60%), model tiering (a small fast model 3–4× faster for easy queries), then vLLM PagedAttention + speculative decoding for self-hosted serving — always profile first to find which stage owns the budget.
