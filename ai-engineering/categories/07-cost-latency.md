# 07. Cost & Latency Optimization — AI Engineering Interview Category

Covers how to measure, model, and systematically reduce the cost and latency of LLM-powered applications at production scale — one of the highest-signal topics for senior AI engineering roles.

---

## Interview signals

| You hear… | This category |
|-----------|---------------|
| "your app gets 1M queries/day — how do you keep costs down?" | cost optimization at scale |
| "how do you reduce latency in GenAI applications?" | latency reduction stack |
| "compare throughput vs latency for LLM serving" | serving architecture tradeoffs |
| "when is a small open-source model good enough?" | model tiering decision |
| "walk me through your caching strategy" | multi-layer caching |
| "what's the real bottleneck in LLM serving?" | PagedAttention / memory bandwidth |

---

## Mental model

Strong candidates understand that **cost and latency in LLM systems are almost always memory-bandwidth problems first, compute problems second**. The key insight is that decode is memory-bound (not compute-bound) — the GPU reads KV cache weights every token, so throughput is capped by HBM bandwidth, not FLOP count. From this root cause flows the entire optimization toolkit: KV cache quantization to shrink memory pressure, PagedAttention to eliminate fragmentation waste, batching to amortize fixed memory reads, speculative decoding to generate multiple tokens per forward pass, model tiering to route cheap requests to cheap models, and semantic caching to avoid the LLM call entirely. Weak candidates jump to "use a smaller model" or "add caching" without explaining *why* those levers work or how to size the tradeoffs — they lack the cost-per-token mental model ($input_tokens × price_in + $output_tokens × price_out) that lets them estimate impact before building.

---

## Sub-topics

### 1. Cost Modeling & Reduction Levers
**When:** "how do you optimize cost at 1M queries/day?" / "how do you reduce token costs at scale?" / "walk me through cost and capacity planning"
**What:** Token-level cost modeling (input × price_in + output × price_out) applied to a multi-lever reduction stack — model tiering, prompt compression, semantic caching, output truncation, and batching — with concrete before/after estimates.
**Key questions:**
- [Q1: Your app gets 1M queries/day — how optimize cost? ⭐](../answers/07-001-your-app-gets-1m-queriesday-how-optimize-cost.md)
- [Q2: How reduce token costs at scale? ⭐](../answers/07-002-how-reduce-token-costs-at-scale.md)
- [Q4: Cost and capacity planning for LLM app at scale?](../answers/07-004-cost-and-capacity-planning-for-llm-app-at-scale.md)

### 2. Latency Reduction Stack
**When:** "how do you reduce latency in GenAI applications?" / "what is TTFT and why does it matter?" / "how do you benchmark each LLM call?"
**What:** Latency in LLM systems decomposes into TTFT (time-to-first-token, dominated by prefill) and total generation time (dominated by decode bandwidth), each needing different mitigations — streaming, prompt compression, model tiering, and semantic caching for TTFT; speculative decoding, batching, and quantization for decode throughput.
**Key questions:**
- [Q3: How reduce latency in GenAI applications? ⭐](../answers/07-003-how-reduce-latency-in-genai-applications.md)
- [Q15: Benchmark each LLM call in multi-step pipeline?](../answers/07-015-benchmark-each-llm-call-in-multi-step-pipeline.md)
- [Q13: Latency/cost/relevancy tradeoff triangle?](../answers/07-013-latencycostrelevancy-tradeoff-triangle.md)

### 3. Multi-Layer Caching & Model Tiering
**When:** "walk me through your caching strategy" / "when is a smaller model good enough?" / "GPT-based API calls cost-efficient under heavy load?"
**What:** Multi-layer caching (response cache → semantic/embedding cache → retrieval cache) stacked with model tiering (route low-complexity requests to GPT-4o-mini or self-hosted Llama 3 8B, reserve GPT-4o for hard queries) eliminates a large fraction of expensive API calls before they reach the LLM.
**Key questions:**
- [Q9: Multi-layer caching: retrieval, prompt, response?](../answers/07-009-multi-layer-caching-retrieval-prompt-response.md)
- [Q10: Model tiering — small distilled vs large LLM?](../answers/07-010-model-tiering-small-distilled-vs-large-llm.md)
- [Q5: GPT-based API calls cost-efficient under heavy load?](../answers/07-005-gpt-based-api-calls-cost-efficient-under-heavy-load.md)

### 4. LLM Serving Architecture & Throughput
**When:** "what's the real bottleneck in LLM serving?" / "latency vs throughput for LLM serving?" / "how does PagedAttention help?"
**What:** LLM decode is memory-bandwidth-bound; PagedAttention (vLLM) eliminates KV cache fragmentation to increase batch size and GPU utilization; quantization (INT8/AWQ) reduces HBM pressure; speculative decoding uses a draft model to generate multiple tokens per step.
**Key questions:**
- [Q16: Real bottleneck in LLM serving throughput? PagedAttention?](../answers/07-016-real-bottleneck-in-llm-serving-throughput-pagedattention.md)
- [Q14: Latency vs throughput for LLM serving?](../answers/07-014-latency-vs-throughput-for-llm-serving.md)
- [Q6: Quantization and model distillation for inference?](../answers/07-006-quantization-and-model-distillation-for-inference.md)

---

## Decision framework

```
Goal: Reduce cost/query or latency — where to start?

Step 1: Measure first
  → Profile per-stage latency (embed / retrieve / rerank / LLM call / post-process)
  → Compute token breakdown (system prompt / retrieved context / output) and cost per query
  → Identify the dominant cost/latency driver before optimizing

Step 2: Can we skip the LLM call entirely?
  Exact-match response cache hit (Redis, cosine > 0.93 for semantic)?
    → Return cached response: ~0ms latency, ~$0 cost per hit
  Retrieved embedding cached?
    → Save embed API cost (~$0.0001 per 1K tokens) on repeated queries

Step 3: Can we use a cheaper model?
  Query complexity is low (FAQ, simple lookup, classification)?
    → Route to GPT-4o-mini (~$0.15/M input) or self-hosted Llama 3 8B
  Complex reasoning / long context / low tolerance for error?
    → Use GPT-4o / Claude 3.5 Sonnet

Step 4: Can we reduce tokens?
  System prompt > 2K tokens?
    → Prompt compression (LLMLingua, ~30-50% reduction) or prefix caching (Anthropic prompt cache, ~90% discount on cached prefix)
  Retrieved context large?
    → Cross-encoder reranking to top-3 before generation; parent-child chunking
  Output unnecessarily long?
    → Add max_tokens constraint + "be concise" instruction

Step 5: Can we improve throughput (self-hosted)?
  KV cache fragmentation causing low batch utilization?
    → PagedAttention (vLLM) — near-100% GPU memory utilization
  Memory pressure from large KV cache?
    → GQA (group query attention) or KV quantization (INT8)
  Decode-bound latency?
    → Speculative decoding (2-4× speedup on structured output) or batching

Step 6: Quantization (for self-hosted)?
  Need 4× memory reduction, can tolerate <2% quality drop?
    → AWQ/GPTQ INT4 quantization
  Need safer quality floor (summarization, classification)?
    → INT8 / BF16 with per-channel scaling (bitsandbytes, TensorRT-LLM)
```

---

## Common mistakes

| Mistake | What to say instead |
|---------|---------------------|
| "I'd just use a smaller model to cut costs" | "Model tiering requires a complexity classifier to route correctly — routing everything to a cheap model hurts quality; I'd profile queries first, then route based on complexity signals (token count, topic classifier, confidence score)" |
| "I'd add caching" without specifying layers or thresholds | "There are three cache layers with different hit rates: exact-match response cache (low hit rate, free), semantic cache (cosine > 0.93 on query embedding, GPTCache/Redis), and embedding cache; I'd measure each layer's hit rate and TTL separately" |
| "Quantization makes the model worse" without quantifying | "INT8 costs < 1% quality loss on most tasks and cuts VRAM in half; INT4/AWQ costs 1-3% and halves again — the risk is highest on math and code tasks; I'd validate on a golden set before shipping" |
| "Just reduce context window to speed up inference" | "Truncating context risks losing critical information; better to rerank retrieved chunks to top-3-5 before generation, and use LLMLingua prompt compression on the system prompt rather than truncating task context" |
| Talking about throughput optimizations when asked about latency | "Throughput (tokens/sec, batching) and latency (TTFT, p95 response time) pull in opposite directions — batching improves throughput but increases per-request latency; I'd clarify which metric the business cares about before choosing a strategy" |
| Ignoring output token cost | "Output tokens cost 3-10× more than input tokens (GPT-4o: $2.50/M input vs $10/M output); in summarization or code generation workloads, controlling output length via max_tokens is often the single biggest cost lever" |

---

## Question checklist

| # | Question | Difficulty signal | Status |
|---|----------|-------------------|--------|
| 1 | Your app gets 1M queries/day — how optimize cost? ⭐ | M | `todo` |
| 2 | How reduce token costs at scale? ⭐ | M | `todo` |
| 3 | How reduce latency in GenAI applications? ⭐ | M | `todo` |
| 4 | Cost and capacity planning for LLM app at scale? | S | `todo` |
| 5 | GPT-based API calls cost-efficient under heavy load? | M | `todo` |
| 6 | Quantization and model distillation for inference? | M | `todo` |
| 7 | Cost vs quality: when is small open-source model "good enough"? | M | `todo` |
| 8 | Trim prompts + cache embeddings — before/after cost breakdown? | M | `todo` |
| 9 | Multi-layer caching: retrieval, prompt, response? | S | `todo` |
| 10 | Model tiering — small distilled vs large LLM? | M | `todo` |
| 11 | Prompt compression? | M | `todo` |
| 12 | Budget estimate for RAG at enterprise scale (e.g. 300K legal contracts)? | S | `todo` |
| 13 | Latency/cost/relevancy tradeoff triangle? | S | `todo` |
| 14 | Latency vs throughput for LLM serving? | S | `todo` |
| 15 | Benchmark each LLM call in multi-step pipeline? | M | `todo` |
| 16 | Real bottleneck in LLM serving throughput? PagedAttention? | S | `todo` |

---

## One-page summary

- **Memory bandwidth is the root cause:** LLM decode is memory-bound (reads KV cache weights every token from HBM); the optimization hierarchy flows from this: semantic caching (avoid the call) → model tiering (use cheaper model) → prompt compression (fewer tokens) → quantization (smaller weights) → PagedAttention + batching (higher GPU utilization) → speculative decoding (more tokens per pass).
- **Token cost math drives every decision:** cost/query = (input_tokens × price_in + output_tokens × price_out); output tokens cost 3-10× more than input — max_tokens discipline and conciseness instructions are underrated levers; at 1M queries/day, even $0.001/query = $1K/day = $365K/year.
- **Three caching layers, three hit rates:** exact-match response cache (Redis, ~5-15% hit, zero LLM cost) → semantic cache (GPTCache cosine > 0.93, ~20-35% hit, saves LLM call) → embedding cache (repeat queries, saves embed API cost) — measure each layer independently; TTL should match data freshness requirements.
- **Model tiering requires a router:** complexity classifier (token count + topic + confidence signal) routes ≥60% of FAQ-style queries to GPT-4o-mini ($0.15/M) vs GPT-4o ($2.50/M) — a 16× cost reduction on routed traffic; validate routing accuracy on golden set before deploying.
- **Latency and throughput are in tension:** batching improves GPU utilization (throughput) but increases individual request latency; streaming (SSE) reduces perceived latency (TTFT < 500ms SLO) without changing total generation time — always clarify which metric matters for the use case before optimizing.
