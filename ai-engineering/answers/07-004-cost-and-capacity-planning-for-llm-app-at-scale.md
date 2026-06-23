# Cost and capacity planning for LLM app at scale?

**Category:** 07-cost-latency
**Question #:** 004
**Source section:** §9 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
Interviewers ask this at the system design or technical deep-dive stage to probe whether you can think in financial and infrastructure units — not just architecture diagrams. A weak candidate draws a box diagram; a strong candidate says "at 1M queries/day with a 2K input / 500 output token profile, the GPT-4o baseline is $10,500/day, here's how I size the budget and where I'd put capacity buffers." This tests production experience with real cost drivers and the discipline to model before building.

### Trigger phrases
- "How do you do cost and capacity planning for an LLM-powered product?"
- "Walk me through how you'd budget for an AI feature at scale"
- "How do you size infrastructure for a GenAI application?"
- "What would it cost to run this at 1M users?"

### What it tests
Ability to build a cost model from first principles (token math + traffic projections), size GPU/API capacity with headroom, and identify the levers that change the model most — before committing engineering effort.

---

## Answer

### Concept
Cost and capacity planning for an LLM app is a two-part exercise: **cost modeling** (build a per-query cost formula from token counts and provider pricing, project over traffic) and **capacity planning** (size API quotas or GPU nodes to meet p95 latency SLOs with burst headroom). The output is a spreadsheet-level model, not a vague estimate — broken down by cost driver, updated when traffic or token profiles change.

### Mechanism

**Step 1 — Build the per-query cost formula**

```
cost/query = (input_tokens × price_in) + (output_tokens × price_out)
```

- Input tokens = system prompt length + retrieved context (RAG) + user message
- Output tokens = average generated response length
- Example (GPT-4o): $2.50/M input, $10/M output
  - 2,000 input + 500 output = (2,000 × $0.0000025) + (500 × $0.00001) = $0.005 + $0.005 = $0.010/query

**Step 2 — Project over traffic and build a cost matrix**

```
daily_cost = QPS × 86,400 × cost/query
```

- 1M queries/day, baseline GPT-4o: $10,000/day → $300K/month → $3.6M/year
- Build a sensitivity matrix: vary QPS (0.5M / 1M / 5M) × model tier (GPT-4o / GPT-4o-mini / self-hosted)

| QPS (queries/day) | GPT-4o | GPT-4o-mini | Self-hosted Llama 3 70B |
|---|---|---|---|
| 0.5M | $5,250/day | $325/day | ~$150/day (hosting) |
| 1M | $10,500/day | $650/day | ~$300/day |
| 5M | $52,500/day | $3,250/day | ~$1,500/day |

**Step 3 — Identify the top cost drivers**

Not all tokens are equal in cost impact:
1. **Output tokens** cost 3-10× more than input — output length is the single biggest lever
2. **Retrieved context** in RAG: if chunks are 512 tokens and you pass 10 chunks, that's 5,120 input tokens per query — often the dominant input cost
3. **System prompt**: a 1,000-token system prompt at 1M queries/day = 1B tokens/day in input alone

**Step 4 — Capacity planning for API**

- Measure peak QPS (not average): if daily volume = 1M queries/day but 80% arrive in 4 hours, peak QPS = ~55 req/s
- Request provider quota increase **before** launch: OpenAI, Anthropic, Azure all require lead time (days-weeks)
- Build a rate-limit retry layer: exponential backoff with jitter, circuit breaker to shed load gracefully
- Reserve 30-40% headroom above expected peak for traffic spikes (viral launch, product announcement)

**Step 5 — Capacity planning for self-hosted GPU**

```
GPUs_needed = (peak_QPS × time_per_request_s) / batch_size
```
- Llama 3 70B in BF16 on 2× A100 80GB: ~12 req/s at 500 output tokens with batch_size=8
- At 55 peak req/s: 55/12 ≈ 5 serving replicas (10 A100 GPUs), plus 1-2 spare for rolling deploys
- vLLM PagedAttention increases effective batch throughput 2-3× vs naive HuggingFace inference — factor this in
- GPU instance cost: A100 80GB on AWS p4d.24xlarge ≈ $9.83/hr × 8 GPUs = ~$79/hr = ~$57K/month for 5 replicas

**Step 6 — Decide: managed API vs self-hosted breakeven**

```
self_host_breakeven: monthly_api_cost > self_host_infra_cost + engineering_cost
```
- Rule of thumb: self-hosting pays off at >$50K/month in API spend on GPT-4o-mini equivalent models
- Below that threshold, managed API + caching + tiering is almost always cheaper when factoring engineering and ops overhead

### Example / Tradeoff

**Enterprise internal knowledge base, 500K queries/day:**
- Baseline profile: 3,000 input tokens (1K system prompt + 2K RAG context) + 300 output tokens
- GPT-4o baseline: (3,000 × $0.0000025 + 300 × $0.00001) × 500,000 = $5,250/day
- After optimization: 70% to GPT-4o-mini + semantic cache 25% hit rate → $650/day
- Capacity plan: at peak 30 req/s on GPT-4o-mini, request 40 TPM quota (tokens per minute ≈ 30 × 3,300 × 60 = 5.94M TPM, buffer to 8M TPM)
- Budget model: $650/day API + $200/day infra (Redis, orchestration) = $255K/year vs $1.9M/year unoptimized baseline

Key tradeoff: more granular token profiling (sampling 1% of traffic for token counts) dramatically improves accuracy of the cost model; running on averages causes 2-3× budget overruns when prompt templates change.

---

## Verbal script

**Opening (30s):**
"I'd approach cost and capacity planning as a two-part model: first, build a per-query cost formula from real token counts and provider pricing, then project over traffic to size API quotas or GPU nodes with burst headroom. The critical thing is to measure before estimating — I've seen 3× budget overruns from teams who used average token counts without accounting for their 1,000-token system prompt going out on every single query."

**Core explanation (2–3 min):**
"Starting with cost modeling: the formula is cost-per-query equals input tokens times price-in plus output tokens times price-out. For GPT-4o — $2.50 per million input, $10 per million output — at 2,000 input and 500 output tokens, that's $0.01 per query, or $10,500 per day at 1M queries. The first thing I do is break down where the input tokens actually come from — system prompt, retrieved context, user message — because the retrieved context in a RAG pipeline often dominates. If you're passing 10 chunks at 512 tokens each, that's 5,120 input tokens per query, which is the single biggest lever to cut.

Then I build a sensitivity matrix: I vary traffic (0.5M, 1M, 5M queries/day) against model tiers (GPT-4o, GPT-4o-mini, self-hosted) to see where the cost curves intersect. That's the decision boundary for self-hosting. The rule of thumb I use is: self-hosting pays off above about $50K/month in API spend — below that, the engineering and ops overhead eats the savings.

For capacity planning on the API side, I focus on peak QPS, not average. If 80% of daily traffic arrives in 4 hours, that's 55 req/s at the peak, not 11.5 req/s average. I request quota headroom with the provider weeks before launch — OpenAI and Anthropic both take days to weeks to grant large quota increases — and I build a rate-limit retry layer with exponential backoff and a circuit breaker so we shed load gracefully rather than failing hard."

**Tradeoff / production angle (1 min):**
"The tradeoff I always flag: output tokens cost 3-10× more than input on most providers, but teams often optimize input and forget output. Controlling output length — max_tokens plus a conciseness instruction in the system prompt — is frequently the single biggest cost lever in workloads that generate long responses.

If we're on the self-hosted path with vLLM, I'd factor in that PagedAttention can give 2-3× throughput improvement over naive inference, so you need fewer GPUs than a naive calculation suggests. But I always build in one spare replica for rolling deploys and at least 30% headroom above expected peak — traffic spikes from product launches can be 5-10× normal."

**Wrap-up (30s):**
"So the output is a living spreadsheet: per-query cost formula, traffic projection at P50/P95/P99, sensitivity matrix across model tiers, and GPU/quota sizing with headroom. I'd revisit it whenever prompt templates, traffic patterns, or model prices change — which in the LLM space is roughly every quarter."

---

## Pitfalls

- **Mistake:** Estimating cost from average token counts without measuring actual production token profiles — **Better:** Sample 1% of production traffic to get real token distributions by query type; average counts underestimate by 2-3× when system prompts or RAG context are large; instrument per-call token breakdowns with the provider's usage response field.
- **Mistake:** Planning capacity around average QPS and requesting quota at average, not peak — **Better:** Model diurnal traffic patterns (80% of enterprise queries in business hours = 3× peak vs daily average); request API quota and provision GPU nodes for peak QPS plus 30-40% headroom, not daily average divided by 86,400.
- **Mistake:** Ignoring output token cost and only modeling input tokens — **Better:** On GPT-4o, output costs $10/M vs $2.50/M for input (4× difference); in summarization or code-gen workloads, output tokens dominate; name this explicitly and add max_tokens + conciseness instructions as a first-order cost lever.
- **Mistake:** "We'll self-host to save money" without modeling the break-even — **Better:** Self-hosting a Llama 3 70B cluster on A100s costs ~$57K/month for 5 replicas; below ~$50K/month in API spend, managed API + semantic cache + model tiering almost always wins when you include engineer time and ops overhead.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q1: Your app gets 1M queries/day — how optimize cost?](07-001-your-app-gets-1m-queriesday-how-optimize-cost.md) | Optimization levers once you have the cost model |
| [Q5: GPT-based API calls cost-efficient under heavy load?](07-005-gpt-based-api-calls-cost-efficient-under-heavy-load.md) | API-specific efficiency techniques (batching, rate limits) |
| [Q14: Latency vs throughput for LLM serving?](07-014-latency-vs-throughput-for-llm-serving.md) | Capacity planning for GPU serving throughput vs latency tradeoffs |

---

## One-liner recall

> Cost planning = (input_tokens × price_in + output_tokens × price_out) × daily_QPS as a sensitivity matrix across model tiers; capacity planning = peak QPS (not average) × request quota/GPU nodes with 30-40% headroom, and self-hosting only makes economic sense above ~$50K/month in API spend.
