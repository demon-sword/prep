# Benchmark each LLM call in multi-step pipeline?

**Category:** 07-cost-latency
**Question #:** 015
**Source section:** §9 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
Multi-step pipelines (RAG chains, agents, summarization workflows) can have 5–10 LLM calls, and naive end-to-end timing tells you almost nothing actionable when performance degrades. The interviewer wants to know whether you instrument *per-call* latency, token counts, and cost — and whether you use that data to prioritize optimization. This probes production observability maturity: have you actually debugged a slow pipeline rather than just speculating about where time is spent?

### Trigger phrases
- "Benchmark each LLM call in multi-step pipeline?"
- "How do you profile a slow RAG or agent pipeline?"
- "Your pipeline's p95 jumped from 2s to 8s — how do you find the bottleneck?"
- "How do you know which step in a chain is the most expensive?"
- "How do you optimize a multi-step LLM workflow?"

### What it tests
Ability to instrument LLM pipelines with per-step observability (latency, tokens, cost) and use structured telemetry to isolate bottlenecks — moving beyond end-to-end guesswork to data-driven optimization.

---

## Answer

### Concept
Benchmarking a multi-step LLM pipeline means wrapping each call with a timing + token-count decorator that emits structured spans, then aggregating those spans into a per-step breakdown: TTFT, total latency, prompt tokens, completion tokens, and inferred cost. Without per-call instrumentation, a pipeline that takes 6 seconds looks like a black box — with it, you discover "3.2s is the cross-encoder reranker calling GPT-4o on 10 chunks, 1.8s is the final generation, and 0.4s is embedding."

### Mechanism

**Step 1: Wrap every LLM call with a timing + token span**

The minimal instrumentation pattern in Python:

```python
import time, logging
from dataclasses import dataclass

@dataclass
class LLMSpan:
    step: str
    model: str
    prompt_tokens: int
    completion_tokens: int
    latency_ms: float
    cost_usd: float

PRICES = {
    "gpt-4o": (2.50 / 1e6, 10.00 / 1e6),       # (input, output) per token
    "gpt-4o-mini": (0.15 / 1e6, 0.60 / 1e6),
    "text-embedding-3-small": (0.02 / 1e6, 0),
}

def timed_llm_call(step: str, fn, *args, **kwargs):
    t0 = time.perf_counter()
    response = fn(*args, **kwargs)
    latency_ms = (time.perf_counter() - t0) * 1000
    model = response.model
    usage = response.usage
    p_in, p_out = PRICES.get(model, (0, 0))
    cost = usage.prompt_tokens * p_in + usage.completion_tokens * p_out
    span = LLMSpan(step, model, usage.prompt_tokens,
                   usage.completion_tokens, latency_ms, cost)
    logging.info("LLM_SPAN %s", span)
    return response, span
```

Every call in the pipeline is wrapped: embed query, retrieve-and-rerank, query-rewriting, final generation.

**Step 2: Collect spans and aggregate per step**

At the end of each pipeline run, emit a structured summary:

```
Pipeline: customer-support-rag  total=5840ms  cost=$0.0087
  embed_query:       42ms    512 tok in   / 0 out    $0.000010
  rerank_gpt4o_mini: 1820ms  3840 tok in  / 120 out  $0.000648
  query_rewrite:     310ms   210 tok in   / 45 out   $0.000059
  final_generation:  3668ms  1100 tok in  / 380 out  $0.008020
  [retrieval HNSW]:  88ms    (non-LLM — measured separately)
```

This immediately reveals that `rerank_gpt4o_mini` and `final_generation` dominate both latency and cost.

**Step 3: Use a tracing framework for production-scale aggregation**

At production scale, emit spans as OpenTelemetry (OTel) traces or to LangSmith/Langfuse:

- **LangSmith** (LangChain): automatically captures per-step latency, token counts, and cost for every chain/agent run. Dashboard shows p50/p95 per step across thousands of runs.
- **Langfuse** (open-source): OTel-compatible, vendor-agnostic, supports custom span attributes (step name, experiment tag, model version).
- **OpenTelemetry + Grafana**: emit custom spans via `opentelemetry-sdk`, store in Tempo, visualize with Grafana — suitable when you already have an OTel stack.

```python
from opentelemetry import trace
tracer = trace.get_tracer("llm-pipeline")

with tracer.start_as_current_span("rerank") as span:
    span.set_attribute("model", "gpt-4o-mini")
    span.set_attribute("prompt_tokens", 3840)
    response = client.chat.completions.create(...)
    span.set_attribute("completion_tokens", response.usage.completion_tokens)
    span.set_attribute("cost_usd", cost)
```

**Step 4: Identify the critical path and set per-step SLOs**

Once you have per-step p50/p95 data across production traffic, classify each step:

| Step | p95 latency | Token cost | Action |
|------|-------------|------------|--------|
| embed_query | 50ms | Negligible | ✅ Fine |
| HNSW retrieval | 90ms | — | ✅ Fine |
| cross-encoder rerank (top-20→top-5) | 1.8s | High | 🔴 Bottleneck |
| final generation | 3.7s | Dominant cost | 🟡 Optimize output tokens |

**Step 5: Act on the bottleneck**

The most common fixes after benchmarking:

- **Reranker calling a large model on too many candidates** → reduce top-k from 20 to 10 before reranking, or switch from GPT-4o to GPT-4o-mini / a local BGE-Reranker
- **Final generation prompt is too long** → apply LLMLingua compression or trim retrieved chunks; use `max_tokens` cap
- **Sequential calls that could be parallel** → fan-out with `asyncio.gather()` for independent steps (e.g., simultaneous keyword + semantic retrieval)
- **Repeated calls with identical inputs** → add a semantic cache (GPTCache) or memoize embedding calls with SHA-256 key on content hash

### Example / Tradeoff

**RAG pipeline benchmark, before/after optimization:**

After adding per-step spans to a 5-step customer support RAG pipeline:

| Step | Before | After | Change |
|------|--------|-------|--------|
| embed_query | 45ms | 45ms (cached hit 40%) | ~27ms avg |
| HNSW retrieval | 85ms | 82ms | — |
| cross-encoder rerank (top-20, GPT-4o) | 3,200ms | 850ms | Switch to Cohere Rerank API (top-10) |
| query_rewrite | 280ms | — | Eliminated (moved to rerank prompt) |
| final_generation (GPT-4o, 4K ctx) | 3,800ms | 2,100ms | Reranked to top-3 chunks → 1.8K ctx |
| **Total p95** | **7.8s** | **3.1s** | **60% reduction** |

The critical insight only became visible with per-step instrumentation: 3.2 seconds was consumed by calling GPT-4o on 20 rerank candidates — an invisible cost when only measuring end-to-end time.

**Tradeoff:** Adding instrumentation overhead (OTel SDK, LangSmith callbacks) adds 2–10ms per span — negligible versus LLM call latency. The real cost is engineering time to set up the tracing pipeline, but the payoff (knowing exactly where to optimize) is consistently 2–5× faster than guessing.

---

## Verbal script

**Opening (30s):**
"This is a question I care a lot about because it's surprisingly common to optimize the wrong step. My answer is: you can't benchmark a multi-step pipeline by measuring end-to-end time — you need per-step spans with latency, token counts, and inferred cost on every LLM call. Once you have that, the bottleneck is usually obvious and the fix is targeted."

**Core explanation (2–3 min):**
"The pattern I use is wrapping each LLM call with a timing decorator that records step name, model, prompt tokens, completion tokens, latency, and calculated cost. I emit those as structured log lines or OTel spans. In practice, for LangChain pipelines I use LangSmith because it instruments automatically and gives me a p50/p95 dashboard per step across production traffic with no extra code. For custom pipelines I use the OpenTelemetry SDK with a Grafana Tempo backend, or Langfuse for open-source.

Once I have per-step data, the breakdown usually looks something like: embed query 45ms, HNSW retrieval 85ms, cross-encoder rerank 3.2 seconds, final generation 3.8 seconds. That reranker step was invisible in end-to-end timing — it looked like 'the pipeline is slow' — but once I saw it, the fix was obvious: we were calling GPT-4o on 20 retrieved chunks for reranking. Switching to Cohere's Rerank API on the top 10 candidates dropped that step from 3.2s to 850ms.

Beyond latency, the token breakdown matters for cost. In the same pipeline, the final generation was consuming 4K context tokens because we were passing all 5 reranked chunks. After reducing to the top-3 chunks via the reranker, context dropped to 1.8K tokens and generation cost fell by 55%. You wouldn't know to do either of these without per-step instrumentation."

**Tradeoff / production angle (1 min):**
"The tradeoff is instrumentation overhead — OTel spans add 2–10ms per call, and LangSmith callbacks add a small async write. Neither matters versus LLM call latency. The bigger challenge is making sure you capture async parallel steps correctly — if you fan out embedding and retrieval in parallel with `asyncio.gather()`, the span timestamps need to reflect wall-clock parallelism, not sequential sum. For very high-traffic pipelines, you sample traces at 5–10% and use 100% coverage only for error traces, which keeps observability cost under control."

**Wrap-up (30s):**
"The core discipline is: treat every LLM call as a measurable unit of work with latency + tokens + cost attached, aggregate those spans in production, and let the data tell you where to optimize. In my experience, the bottleneck is almost always the reranker or context-window size — both invisible without per-step measurement. Happy to go into the OTel span structure or the LangSmith dashboard setup."

---

## Pitfalls

- **Mistake:** Measuring only end-to-end pipeline latency and guessing which step is slow — **Better:** Instrument every individual LLM call with a timing wrapper that records step name, model, prompt tokens, completion tokens, and cost; the critical-path step (often reranker or generation) is rarely where intuition points.
- **Mistake:** Tracking latency but ignoring token counts — **Better:** Token counts (especially completion tokens) are 3–10× more expensive per unit than prompt tokens on most APIs and directly drive cost; a call that takes 1s but produces 500 completion tokens costs more than a 3s call with 50 completion tokens.
- **Mistake:** Optimizing based on a single benchmark run at low traffic — **Better:** Collect per-step p50/p95 across production traffic (e.g., via LangSmith or OTel Grafana dashboard) because bottlenecks shift under concurrency: the HNSW retrieval that looks fast at 1 QPS may become the bottleneck at 100 QPS due to lock contention or connection pool saturation.
- **Mistake:** Not checking which sequential steps could be parallelized — **Better:** After identifying independent steps (e.g., keyword retrieval and dense retrieval, or multiple tool calls that don't depend on each other), run them concurrently with `asyncio.gather()`; this alone often cuts wall-clock time by 30–50% without any model change.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q3: How reduce latency in GenAI applications?](07-003-how-reduce-latency-in-genai-applications.md) | Application-level latency levers (caching, tiering, compression) — what you apply after finding the bottleneck |
| [Q14: Latency vs throughput for LLM serving?](07-014-latency-vs-throughput-for-llm-serving.md) | Serving-layer tuning knobs that complement pipeline-level per-step optimization |
| [Q9: Multi-layer caching: retrieval, prompt, response?](07-009-multi-layer-caching-retrieval-prompt-response.md) | Semantic and prefix caching are two of the most impactful fixes once benchmarking reveals repeated identical calls |

---

## One-liner recall

> Wrap every LLM call in a timing decorator emitting step + model + prompt_tokens + completion_tokens + latency + cost as OTel spans or LangSmith traces; aggregate per-step p95 across production traffic to find the critical path (almost always the reranker or context-window size), then apply targeted fixes (Cohere Rerank instead of GPT-4o, top-3 instead of top-10 chunks, asyncio.gather() for parallel steps).
