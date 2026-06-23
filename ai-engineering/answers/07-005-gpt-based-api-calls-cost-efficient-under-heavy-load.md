# GPT-based API calls cost-efficient under heavy load?

**Category:** 07-cost-latency
**Question #:** 005
**Source section:** §9 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
Interviewers ask this at the system design or technical deep-dive stage to probe whether you can run a GPT-based product economically at production scale — not just prototype it. A weak candidate says "add caching." A strong candidate articulates a multi-layer efficiency stack: batching, prompt compression, model tiering, semantic caching, prefix caching, and rate-limit management — with numbers. The question tests whether you treat API cost as an engineering constraint with specific levers, not a billing afterthought.

### Trigger phrases
- "How do you keep API costs manageable under heavy load?"
- "You're hitting GPT-4o at 500 req/s — what breaks and how do you fix it?"
- "Walk me through how you'd make OpenAI calls cost-efficient at scale."
- "How do you handle rate limits and cost at 1M queries/day?"

### What it tests
Ability to enumerate and reason about concrete API cost and throughput levers — batching, semantic caching, prompt compression, model tiering, prefix caching, rate-limit management — with quantitative intuition about the impact of each.

---

## Answer

### Concept
Making GPT-based API calls cost-efficient under heavy load requires stacking multiple independent techniques, each cutting a different cost or throughput dimension: **avoid the call entirely** (semantic cache, exact cache), **shrink the call** (prompt compression, top-k reduction, max_tokens), **downgrade the model** (model tiering to GPT-4o-mini for routine tasks), **amortize tokens** (prefix caching, request batching), and **manage quota** (rate-limit retry with jitter, quota provisioning). No single lever is sufficient; production savings of 80-90% require applying all five layers.

### Mechanism

**Layer 1 — Avoid the call entirely (semantic cache)**

- Store recent query→response pairs in Redis or GPTCache with embedding-based similarity lookup (cosine similarity threshold 0.92–0.95)
- Cache hits return in <10ms with zero API cost
- Hit rate: 20-35% for support chatbots with similar phrasing across users; lower for open-ended creative tasks
- Include TTL (1-24h depending on freshness requirements) and invalidation on source-document updates

**Layer 2 — Exact cache for deterministic calls**

- For queries that always get the same input (static reports, scheduled summarizations, dashboard widgets): hash the full prompt and store in Redis with a long TTL
- Near-zero compute overhead; 100% cache efficiency for repeated identical calls
- Combine with content-addressed storage (prompt hash → S3 key → response)

**Layer 3 — Shrink the call (prompt compression + top-k reduction)**

- **LLMLingua / LLMLingua-2** (Microsoft): compress context tokens by 2-5× with <5% quality loss by dropping low-saliency tokens; saves proportionally on input token cost
- **Reduce top-k in RAG**: cross-encoder reranking narrows retrieved chunks from 10 to 3-5; at 512 tokens/chunk, going from 10→3 saves 3,584 input tokens per query
- **max_tokens discipline**: set `max_tokens` to the 95th-percentile response length for each endpoint; on a summarization pipeline, capping at 300 tokens instead of unlimited saves 200-400 output tokens/call (output tokens cost 4-10× input on most models)

**Layer 4 — Model tiering (cheapest sufficient model)**

- Route by task type:
  - Classification, intent detection, yes/no gates: GPT-4o-mini ($0.15/M input, $0.60/M output) or even a fine-tuned local model
  - RAG answer synthesis for factual questions: GPT-4o-mini
  - Complex reasoning, multi-document synthesis, code generation: GPT-4o ($2.50/M input, $10/M output)
- A tiering split of 80% GPT-4o-mini / 20% GPT-4o reduces cost by ~84% vs all-GPT-4o at the same traffic
- Implement as a router: classify the query first (cheap call), then dispatch to the appropriate model

**Layer 5 — Prefix caching (amortize static tokens)**

- OpenAI (November 2024) and Anthropic Claude both offer automatic prefix caching: repeated prefixes (system prompt, static RAG context) in requests are cached server-side and billed at a 50-90% discount
- A 1,000-token system prompt at 1M queries/day = 1B input tokens/day; with 90% prefix cache discount, that's $250/day saved on GPT-4o-mini alone
- Keep static content at the start of the context (system prompt → static examples → dynamic user query) to maximize the cacheable prefix length

**Layer 6 — Batching (throughput vs latency tradeoff)**

- Batch embeddings: OpenAI embeddings API accepts up to 2,048 inputs per call; batching reduces per-embedding overhead (rate-limit slots, HTTP overhead)
- For async workloads (nightly summarization, batch classification): use OpenAI Batch API (50% discount on batch jobs with 24h turnaround) for non-time-sensitive calls
- Avoid batching for real-time user-facing endpoints — latency dominates over throughput there

**Layer 7 — Rate-limit management**

- Instrument `429 Too Many Requests` and `503` responses; implement exponential backoff with jitter (base 1s, max 60s, ±25% jitter)
- Use a token-bucket or leaky-bucket rate limiter in front of the API client to smooth request bursts
- Request quota increases proactively (OpenAI/Anthropic: 1-2 weeks lead time for large increases); provision for peak QPS + 30-40% headroom, not average
- For self-hosted models (vLLM): tune `--max-num-seqs` and `--gpu-memory-utilization` to maximize continuous batching throughput via PagedAttention

### Example / Tradeoff

**Customer support chatbot — 1M queries/day before vs after optimization:**

| Technique | Impact | Cost before | Cost after |
|-----------|--------|------------|------------|
| Baseline (all GPT-4o, 2K input + 500 output tokens) | — | $10,500/day | $10,500/day |
| + Semantic cache (30% hit rate) | −30% calls | — | $7,350/day |
| + Model tiering (80% GPT-4o-mini) | −84% on tiered calls | — | $1,470/day |
| + Prefix caching (1K static system prompt) | −90% on system prompt tokens | — | $1,120/day |
| + Top-k reduction via reranking (10→3 chunks) | −3,584 input tokens/non-cached query | — | $870/day |
| + max_tokens cap (500→200 output) | −60% output tokens | — | $680/day |
| **Total savings** | **~94%** | **$10,500/day** | **~$630/day** |

**Key tradeoff:** semantic cache threshold tuning — a threshold of 0.90 gives 40% hit rate but 5% wrong-answer rate; 0.95 gives 25% hit rate and <0.5% wrong-answer rate. Tune against a golden eval set, not intuition. For support bots, 0.93 is a common production default.

---

## Verbal script

**Opening (30s):**
"Making GPT-based APIs efficient under heavy load is a stacking problem — no single technique gets you there. I think about it in layers: avoid the call entirely with caching, shrink the call with compression and top-k reduction, downgrade the model for routine tasks, amortize tokens with prefix caching and batching, and manage quotas to avoid rate-limit failures. Applying all five layers typically gets you 80-90% cost reduction from a naive baseline."

**Core explanation (2–3 min):**
"Starting with the highest-leverage lever: semantic caching. I store recent query-response pairs in Redis with embedding-based similarity lookup — if the new query is within cosine distance 0.07 of a cached result, return the cache hit in under 10ms at zero API cost. For support chatbots where many users ask similar questions, we typically see 25-35% hit rates.

Next is model tiering. I route by task type: intent classification and yes/no gates go to GPT-4o-mini at $0.15 per million input tokens; complex multi-document synthesis goes to GPT-4o at $2.50 per million. An 80/20 split cuts the blended model cost by about 84%.

Then I look at the call itself: I use a cross-encoder reranker to trim retrieved context from 10 chunks down to 3 — that saves roughly 3,500 input tokens per non-cached query. And I always set max_tokens to the 95th-percentile of my actual response length distribution — output tokens cost 4-10× more than input on most providers, so every uncapped token is expensive.

If the provider supports prefix caching — OpenAI added this in late 2024, Anthropic has it too — I structure prompts so the static system prompt and examples come first. That gets a 50-90% discount on the repeated prefix tokens, which at 1M queries/day on a 1K-token system prompt is hundreds of dollars per day saved.

Finally for async workloads, I use OpenAI's Batch API — 50% discount in exchange for 24h turnaround — for things like nightly report summaries or batch classification jobs."

**Tradeoff / production angle (1 min):**
"The main tension is between cache hit rate and answer accuracy. Too low a similarity threshold and you return stale or wrong responses; too high and you lose the cost benefit. I tune this against a golden eval set — typically 0.92-0.95 is the production sweet spot for support use cases.

The other trap is that rate-limit management is often treated as an afterthought. At 500 req/s, a single traffic spike can exhaust your RPM quota. I always instrument 429s, implement exponential backoff with jitter, and request quota headroom weeks before launch — not the night before."

**Wrap-up (30s):**
"So the full stack is: semantic cache to avoid calls, model tiering to downgrade routine ones, prompt compression and top-k reduction to shrink them, prefix caching to amortize static tokens, Batch API for async workloads, and rate-limit management for reliability. At 1M queries/day, stacking all five layers moved a client from $10,500/day to ~$630/day — about 94% reduction."

---

## Pitfalls

- **Mistake:** Saying "add caching" without specifying semantic vs exact, threshold, TTL, or invalidation — **Better:** Explain that semantic caching uses embedding similarity (cosine ≥0.93 threshold in Redis/GPTCache), that cache TTL depends on source freshness requirements (1-24h typical), and that index updates must invalidate affected cache entries; mention that wrong-answer rate vs hit-rate curve needs to be benchmarked against a golden eval set, not set by intuition.
- **Mistake:** Focusing only on input token cost and ignoring output tokens — **Better:** Point out that output tokens cost 4-10× more than input on GPT-4o ($10/M vs $2.50/M); in summarization or code-gen workloads, output is the dominant cost; max_tokens cap and a conciseness instruction in the system prompt are first-order output-cost levers.
- **Mistake:** Treating model tiering as "use a cheaper model for everything" and accepting quality loss — **Better:** Route at the task level — classify query intent first (cheap GPT-4o-mini call), dispatch GPT-4o only for complex multi-hop reasoning or regulated-domain synthesis; validate quality per tier with a golden task set before routing production traffic.
- **Mistake:** Not mentioning prefix caching — **Better:** OpenAI (November 2024) and Anthropic both offer server-side prefix caching at 50-90% discount; structure prompts with static content first; a 1K-token system prompt at 1M queries/day saves hundreds of dollars daily on GPT-4o-mini alone; this is a free optimization that requires only prompt ordering discipline.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q1: Your app gets 1M queries/day — how optimize cost?](07-001-your-app-gets-1m-queriesday-how-optimize-cost.md) | Broader cost optimization hierarchy that this answers in API-specific depth |
| [Q9: Multi-layer caching: retrieval, prompt, response?](07-009-multi-layer-caching-retrieval-prompt-response.md) | Deep-dive on the caching layer touched here |
| [Q4: Cost and capacity planning for LLM app at scale?](07-004-cost-and-capacity-planning-for-llm-app-at-scale.md) | Upstream capacity model and quota sizing |

---

## One-liner recall

> Make GPT API calls cost-efficient under heavy load by stacking five layers: semantic cache (avoid the call), model tiering (downgrade routine calls), prompt compression + top-k reranking (shrink the call), prefix caching (amortize static tokens at 50-90% discount), and Batch API for async workloads — together achieving 80-94% cost reduction from a naive baseline.
