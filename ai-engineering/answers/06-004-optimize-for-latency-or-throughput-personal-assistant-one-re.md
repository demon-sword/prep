# Optimize for latency or throughput? (personal assistant, one request)

**Category:** 06-ml-fundamentals
**Question #:** 004
**Source section:** §6 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
The interviewer is probing whether you understand the fundamental tension between latency and throughput in ML serving, and whether you can apply that understanding to a concrete scenario. A personal assistant serving one interactive user has completely different optimization priorities than a batch pipeline processing 10,000 documents overnight. Strong candidates distinguish these objectives immediately and explain the architectural implications.

### Trigger phrases
- "Optimize for latency or throughput — personal assistant, one request"
- "Your model needs to respond to a user — what do you optimize for?"
- "What's the difference between latency optimization and throughput optimization in ML serving?"

### What it tests
Whether the candidate can apply the latency-vs-throughput tradeoff to a specific production scenario and explain the architectural decisions that follow from that choice.

---

## Answer

### Concept
**Latency** is the time from request submission to response delivery for a single request. **Throughput** is the number of requests completed per unit time across all concurrent users. For an interactive personal assistant serving one request, **latency is the primary optimization target** — the user is waiting, and every millisecond of delay degrades perceived quality. Throughput optimizations (batching, queue depth, high concurrency) introduce latency for the sake of aggregate efficiency, which is the wrong tradeoff for an interactive single-user scenario.

### Mechanism
The key insight is that latency and throughput pull in opposite directions:

| Optimization | Effect on latency | Effect on throughput |
|---|---|---|
| Batching requests | ↑ increases (wait for batch to fill) | ↑ increases (amortized GPU overhead) |
| Large batch size | ↑ increases | ↑↑ increases |
| Streaming (token-by-token) | ↓ TTFT improves perceived latency | ↓ reduces per-request throughput |
| Greedy decoding (T=0) | ↓ single forward pass | neutral |
| Smaller/distilled model | ↓↓ decreases | ↑ increases (more capacity for batching) |
| Speculative decoding | ↓ reduces p50 latency on structured output | ↑ slight increase |
| Semantic caching | ↓↓ cache hit → ~10ms | ↑ reduces load on serving tier |

**For a personal assistant (one interactive user, one request at a time):**
1. **Optimize for TTFT (time to first token)** — stream tokens as they're generated so the user sees a response immediately, even if total generation takes 5s. vLLM and TGI both support streaming via SSE.
2. **Use the smallest model that meets quality bar** — a 7B distilled model at 200ms vs a 70B model at 2s. Model tiering (Gemini Flash / a small fast model / Claude Haiku for routine turns) directly cuts p50 latency.
3. **Avoid unnecessary batching** — batch size = 1 is correct for a dedicated single-user assistant. Batching other users' requests into the same inference call would add queue-wait latency.
4. **Semantic caching** — if the assistant handles repeated queries (e.g., "what's my calendar today?"), a Redis semantic cache with cosine > 0.93 delivers ~10ms responses vs 800ms inference.
5. **Prompt compression** — LLMLingua or conversation summarization reduces prefill tokens, which directly reduces time-to-first-token.

**When throughput becomes the right objective:** batch processing (overnight document summarization, embedding generation for 1M products), shared multi-tenant services where amortizing GPU cost matters, or offline evaluation pipelines.

### Example / Tradeoff
A voice-powered personal assistant (think Apple Siri or a Claude mobile agent): the UX bar is <500ms TTFT so the user doesn't feel they're waiting. The architecture choices are:
- **A small fast model** for calendar/todo queries (latency: ~150ms TTFT, cost: $1/1M tokens) vs **A frontier model** for complex reasoning (latency: ~400ms TTFT, cost: $5/1M tokens)
- **Streaming SSE** to the frontend — user sees "I checked your calendar…" immediately
- **Semantic cache** in Redis for repeated patterns ("do I have meetings today?" answered from cache in 8ms)
- **Batch size = 1** on the vLLM server for this user's session; other users get separate sessions, not co-batched

At scale (10k concurrent users), the serving tier switches objective: maximize throughput by increasing vLLM's `--max-num-seqs` and using PagedAttention to share KV cache blocks, accepting higher p95 latency per user in exchange for cost efficiency.

---

## Verbal script

**Opening (30s):**
"The answer depends on the serving scenario. For an interactive personal assistant handling one request at a time, I'd optimize for latency — specifically time to first token, since the user is actively waiting. Throughput optimizations like batching help when you're serving many users concurrently and want to amortize GPU cost, but they hurt individual response time. Let me walk through the specific levers."

**Core explanation (2–3 min):**
"The fundamental tension is that batching — the main driver of throughput — adds latency because you wait for a batch to fill before processing. For a single interactive user, batch size = 1 is correct. Beyond that, there are four main latency levers:

First, streaming. Instead of waiting for the full response, I'd use SSE or WebSockets to stream tokens as they're generated. The user sees output almost immediately, so perceived latency drops even if wall-clock generation time stays the same.

Second, model tiering. A 7B distilled model might give 150ms TTFT vs 2 seconds for a 70B model. For routine turns — calendar queries, reminders, small talk — I'd route to the smaller model automatically, falling back to the larger model only for complex reasoning.

Third, semantic caching. For a personal assistant, many queries are semantically similar day-to-day. I'd put a Redis-based semantic cache in front of inference with a cosine similarity threshold around 0.93. Cache hits return in 8–10ms instead of 800ms.

Fourth, prompt compression. Tools like LLMLingua reduce the number of prefill tokens by 30–50% without significant quality loss, directly cutting time-to-first-token.

A concrete example: a voice assistant with a 500ms TTFT SLO. A small fast model for routine queries, a frontier model for complex ones, streaming enabled, semantic cache in Redis. The cache alone hits 25-30% of queries in a personal assistant context."

**Tradeoff / production angle (1 min):**
"The calculus flips when you're serving many concurrent users. At 10k QPS, throughput is the optimization objective — you want high batch utilization, large `--max-num-seqs` in vLLM, PagedAttention for KV cache sharing, and aggressive caching at every layer. But you'd also accept higher p95 latency per user, maybe 2-3 seconds instead of 500ms. That's fine for a shared API but not for a voice assistant where the user is staring at a spinner.

One pitfall: people conflate throughput and scalability. A system can handle high throughput but still have high per-request latency if batches are large. Always clarify which metric matters for the use case."

**Wrap-up (30s):**
"In short: personal assistant, one request → optimize for latency via streaming, model tiering, semantic caching, and prompt compression. Batch pipeline or multi-tenant API → optimize for throughput via batching, PagedAttention, and high concurrency. Happy to go deeper on any of those levers."

---

## Pitfalls

- **Mistake:** Saying "optimize for throughput to handle more users" when the question specifies a personal assistant handling one request — **Better:** Recognize the scenario immediately: single interactive user = latency first. TTFT is the metric that matters. Batching is the wrong lever here.
- **Mistake:** Defining latency and throughput in the abstract without connecting them to concrete architectural choices (model size, batch size, streaming) — **Better:** Name the specific levers: streaming SSE reduces *perceived* TTFT; model tiering (a small fast model vs a frontier model) cuts *actual* TTFT by 3-10x; semantic caching eliminates inference latency for repeated queries.
- **Mistake:** Treating "reduce latency" as synonymous with "use a faster GPU" — **Better:** GPU is rarely the bottleneck for a single interactive request. The primary levers are model selection, prompt size (prefill latency), and avoiding unnecessary wait (batching). Streaming is a UX latency fix even without changing inference speed.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q5: Data parallelism for single-request assistant?](06-005-data-parallelism-for-single-request-assistant.md) | Direct follow-up — data parallelism helps throughput, not single-request latency |
| [Q11: How do you reduce latency in GenAI applications?](../answers/07-003-how-do-you-reduce-latency-in-genai-applications.md) | Broader latency optimization catalogue (§9 cost & latency category) |
| [Q3: Diagnose performance bugs in a model?](06-003-diagnose-performance-bugs-in-a-model.md) | Related diagnostic mindset — profile before optimizing |

---

## One-liner recall

> For a personal assistant serving one interactive request, optimize for **latency** (streaming + model tiering + semantic caching), not throughput — batching helps multi-tenant cost efficiency but adds queue-wait latency the user directly feels.
