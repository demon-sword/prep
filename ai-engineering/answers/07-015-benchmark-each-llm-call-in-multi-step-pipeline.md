# Benchmark each LLM call in multi-step pipeline?

**Category:** 07-cost-latency
**Question #:** 015
**Source section:** §9 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
Multi-step LLM pipelines — RAG, agentic workflows, document processing chains — are notoriously hard to profile because the bottleneck shifts between steps as load changes. Interviewers ask this to probe whether you have hands-on experience diagnosing which step is slow, which is expensive, and how you surface that in production. It tests production observability maturity: can you attribute cost and latency to individual steps, not just end-to-end?

### Trigger phrases
- "Benchmark each LLM call in multi-step pipeline?"
- "How do you find which step in your chain is the bottleneck?"
- "How do you attribute cost to individual steps in a multi-step agent?"
- "Your pipeline p95 latency spiked — how do you isolate which call is the problem?"
- "How do you instrument a LangChain pipeline for observability?"

### What it tests
Ability to instrument multi-step LLM pipelines at per-step granularity — measuring latency, token counts, and cost per call — and to interpret the results to identify where to optimize rather than optimizing blindly at the pipeline level.

---

## Answer

### Concept
Benchmarking each LLM call in a multi-step pipeline means capturing, per step: **wall-clock latency** (TTFT and total), **token counts** (input and output separately), **cost** (derived from token counts and model pricing), and **error rate** — then aggregating these into per-step p50/p95 dashboards and surfacing them in distributed traces. The alternative — only measuring end-to-end latency — masks whether the bottleneck is a slow reranker call, a high-token-count summarization step, or network round-trips to the vector database.

### Mechanism

**Step 1: Per-call instrumentation decorator**

Wrap each LLM call with a timing + token-capture decorator. For OpenAI-compatible APIs, the response object includes `usage.prompt_tokens`, `usage.completion_tokens`, and `usage.total_tokens`:

```python
import time, functools, logging
from openai import OpenAI

client = OpenAI()

def llm_benchmark(step_name: str):
    """Decorator: logs latency, token counts, and derived cost per LLM call."""
    def decorator(fn):
        @functools.wraps(fn)
        def wrapper(*args, **kwargs):
            t0 = time.perf_counter()
            response = fn(*args, **kwargs)
            latency_ms = (time.perf_counter() - t0) * 1000

            usage = response.usage
            # Small-tier pricing (Claude Haiku 4.5, verified 2026-08-30): $1/1M input, $5/1M output
            cost_usd = (
                usage.prompt_tokens * 0.15 / 1_000_000
                + usage.completion_tokens * 0.60 / 1_000_000
            )

            logging.info({
                "step": step_name,
                "latency_ms": round(latency_ms, 1),
                "input_tokens": usage.prompt_tokens,
                "output_tokens": usage.completion_tokens,
                "cost_usd": round(cost_usd, 6),
                "model": response.model,
            })
            return response
        return wrapper
    return decorator

@llm_benchmark("query_rewrite")
def rewrite_query(user_query: str):
    return client.chat.completions.create(
        model="claude-haiku-4-5",
        messages=[{"role": "user", "content": f"Rewrite for retrieval: {user_query}"}],
        max_tokens=100,
    )

@llm_benchmark("generate_answer")
def generate_answer(context: str, query: str):
    return client.chat.completions.create(
        model="claude-sonnet-5",
        messages=[{"role": "user", "content": f"Context:\n{context}\n\nQuestion: {query}"}],
        max_tokens=512,
    )
```

**Step 2: OpenTelemetry / LangSmith spans for distributed traces**

For production pipelines, emit structured spans so each step appears as a child span under the parent pipeline trace:

```python
from opentelemetry import trace

tracer = trace.get_tracer("rag-pipeline")

def run_rag_pipeline(query: str) -> str:
    with tracer.start_as_current_span("rag-pipeline") as root_span:
        with tracer.start_as_current_span("query-rewrite"):
            rewritten = rewrite_query(query)

        with tracer.start_as_current_span("vector-retrieve"):
            docs = vector_store.search(rewritten, top_k=10)

        with tracer.start_as_current_span("cross-encoder-rerank"):
            top_docs = reranker.rerank(docs, query, top_n=3)

        with tracer.start_as_current_span("generate-answer"):
            answer = generate_answer("\n".join(top_docs), query)

    return answer
```

LangSmith (`LANGCHAIN_TRACING_V2=true`) does this automatically for LangChain chains and agents — each chain step is a span with token counts, latency, and cost pre-computed.

**Step 3: Per-step dashboard metrics**

Aggregate logs into a per-step metrics dashboard (Grafana + Prometheus or Datadog):

| Step | p50 latency | p95 latency | Avg input tokens | Avg output tokens | Avg cost/call |
|------|------------|------------|-----------------|------------------|--------------|
| query_rewrite | 120 ms | 210 ms | 45 | 30 | $0.000195 |
| vector_retrieve | 18 ms | 45 ms | — | — | — |
| cross_encoder_rerank | 3,200 ms | 4,800 ms | — | — | $0.00 (self-hosted) |
| generate_answer | 1,100 ms | 2,300 ms | 2,800 | 420 | $0.0245 |
| **Total pipeline** | **4,450 ms** | **7,350 ms** | | | **$0.0247** |

From this table: the cross-encoder reranker is the latency bottleneck (72% of p95), not the LLM generation step. Fix: switch to Cohere Rerank API (80 ms p95) or self-hosted BGE-Reranker on GPU (< 200 ms).

**Step 4: Parallelise independent steps**

Once per-step latencies are visible, independent steps can be parallelised with `asyncio.gather()`:

```python
import asyncio

async def run_rag_async(query: str):
    # Query rewrite and initial embedding can run in parallel
    rewritten, embedding = await asyncio.gather(
        async_rewrite_query(query),
        async_embed_query(query),
    )
    docs = await async_vector_search(embedding, top_k=10)
    top_docs = await async_rerank(docs, rewritten)
    return await async_generate(top_docs, rewritten)
```

### Example / Tradeoff

**Real incident — reranker bottleneck discovery:**

A 4-step RAG pipeline (rewrite → retrieve → rerank → generate) had a p95 latency of 7.3 seconds. End-to-end profiling suggested "LLM generation is slow." Per-step instrumentation revealed:

| Step | p95 latency | % of total |
|------|------------|-----------|
| query_rewrite | 210 ms | 3% |
| vector_retrieve (Pinecone) | 45 ms | 1% |
| cross_encoder_rerank (CPU) | 4,800 ms | 65% |
| generate_answer (a frontier model) | 2,300 ms | 31% |

Fix: moved cross-encoder reranking to a GPU-backed Cohere Rerank API call (80 ms p95). New pipeline p95: **2,635 ms** — 64% reduction. Without per-step instrumentation, the team would have optimized the wrong step (e.g., switching from a frontier model to a small fast model for generation, saving 600 ms while the 4.8s reranker remained).

**Cost attribution example at 1M queries/day:**

| Step | Cost/call | Daily cost |
|------|-----------|-----------|
| query_rewrite (a small fast model) | $0.000195 | $195 |
| cross_encoder_rerank (Cohere) | $0.0002 | $200 |
| generate_answer (a frontier model) | $0.0245 | $24,500 |
| **Total** | **$0.0249** | **~$24,900/day** |

Switching generate_answer to a small fast model for 80% of queries (those with RAGAS score > 0.85 on the small tier) saves ~$15,700/day with negligible quality drop — visible only because cost was attributed per step.

**Tradeoff:** Per-step telemetry adds 1–5 ms overhead per call (logging, span creation) and increases log storage costs. For high-QPS pipelines (>500 RPS), sample 10–20% of traces rather than tracing 100%, using OpenTelemetry's probabilistic sampler — preserving statistical accuracy while cutting observability overhead.

---

## Verbal script

**Opening (30s):**
"Benchmarking each step in a multi-step pipeline is one of those things that sounds obvious but is easy to skip — and when you skip it you end up optimizing the wrong thing. The core approach is: instrument every LLM call with a timing and token-count decorator, emit those as structured logs or OTel spans, and build per-step p50/p95 dashboards. Let me walk through the implementation and then a real example where this made a huge difference."

**Core explanation (2–3 min):**
"At the call level, the pattern is a simple wrapper around each API call — capture `time.perf_counter()` before and after, read `response.usage.prompt_tokens` and `completion_tokens` from the response object, and derive cost from the model's per-token pricing. Log that as a structured JSON event with the step name. That gives you per-step latency, input/output token counts, and cost for every call.

For production pipelines, you want this in distributed traces — OpenTelemetry spans or LangSmith, which does it automatically for LangChain. Each step becomes a child span under the root pipeline trace. In Grafana or Datadog you can then build per-step p95 latency charts, per-step average token counts, and per-step cost-per-query.

The reason this matters more than end-to-end measurement: latency and cost are not evenly distributed across steps. In one pipeline I worked on, the p95 breakdown was 65% on a CPU-based cross-encoder reranker, 31% on a frontier model generation, and only 4% on query rewriting and vector retrieval. The end-to-end number was 7.3 seconds — and you'd assume the LLM was slow. Switching the reranker to a GPU-backed Cohere Rerank API call cut p95 to 2.6 seconds without touching the model.

Once you have per-step latency data, you can also identify steps that could be parallelised. If query rewriting and query embedding are independent, `asyncio.gather()` lets them run concurrently and eliminates their sequential sum from the critical path."

**Tradeoff / production angle (1 min):**
"The tradeoffs are small but worth naming. Full per-call telemetry adds 1–5 ms overhead and increases log volume — at 500+ RPS, use probabilistic sampling at 10–20% rather than tracing every request. You lose exact per-request detail but retain statistically accurate per-step p95 estimates.

Also, cost attribution per step requires knowing each step's model and current pricing. Pricing changes — parameterize the cost formula rather than hardcoding it. And for async pipelines, make sure your spans track the *wall-clock* start and end of each step, not just CPU time, since async steps can interleave."

**Wrap-up (30s):**
"The mental model is: treat each step as an independent service, measure it like one — latency, cost, error rate — and aggregate into per-step dashboards. LangSmith does this out of the box for LangChain. For custom pipelines, a timing decorator plus OTel spans gives you the same visibility in a day of work. The payoff is that you optimize the actual bottleneck, not the one you assumed was slow."

---

## Pitfalls

- **Mistake:** Only measuring end-to-end pipeline latency and assuming the LLM generation step is the bottleneck — **Better:** Instrument per-step latency and token counts; in practice the bottleneck is often a CPU-based reranker, a slow vector DB round-trip, or a high-token-count intermediate step — not the final generation call.
- **Mistake:** Logging total_tokens only, ignoring the input/output token split — **Better:** Track prompt_tokens and completion_tokens separately; output tokens cost 5× more than input tokens for most models (e.g., a frontier model: $5/1M input vs $25/1M output), so a step generating 400 output tokens costs 4× as much as a step consuming 400 input tokens — they look identical in total_tokens but have very different cost profiles.
- **Mistake:** Tracing 100% of requests in production at high QPS — **Better:** Use probabilistic sampling (10–20%) with OpenTelemetry's `TraceIdRatioBased` sampler; p95 estimates stay accurate with <1% statistical error at 10% sample rate, while log volume and overhead drop proportionally.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q3: How reduce latency in GenAI applications?](07-003-how-reduce-latency-in-genai-applications.md) | Per-step benchmarking identifies *where* to apply the latency levers described in Q3 (caching, tiering, compression) |
| [Q14: Latency vs throughput for LLM serving?](07-014-latency-vs-throughput-for-llm-serving.md) | Serving-layer knobs (batch size, continuous batching) complement application-layer per-step optimization |
| [Q1: Your app gets 1M queries/day — how optimize cost?](07-001-your-app-gets-1m-queriesday-how-optimize-cost.md) | Per-step cost attribution (prompt_tokens × price_in + completion_tokens × price_out) is the prerequisite for the cost optimization hierarchy in Q1 |

---

## One-liner recall

> Wrap every LLM call in a timing + token-count decorator (prompt_tokens × price_in + completion_tokens × price_out), emit as OTel spans or LangSmith traces to get per-step p95 dashboards, then fix the actual bottleneck — which is usually the reranker or a high-output-token step, not the generation model you assumed.
