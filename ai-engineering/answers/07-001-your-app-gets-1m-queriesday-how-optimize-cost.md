# Your app gets 1M queries/day — how optimize cost?

**Category:** 07-cost-latency
**Question #:** 001
**Source section:** §9 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
This is the canonical cost-optimization question for senior AI engineering roles. The interviewer is probing whether you have real production intuition — not just awareness that "caching exists," but the ability to quantify each lever, size its impact, and sequence optimizations by ROI. It reveals whether you think in token economics ($input × price_in + $output × price_out) rather than hand-waving about "efficiency."

### Trigger phrases
- "Your app gets 1M queries/day — how do you keep costs down?"
- "How do you scale an LLM application cost-efficiently?"
- "Walk me through your cost optimization strategy for a high-traffic AI product"
- "How do you reduce cost without sacrificing quality?"

### What it tests
Production cost modeling: the ability to decompose LLM spend by lever, quantify impact before building, and sequence optimizations by ROI.

---

## Answer

### Concept
LLM API cost is a function of token volume: **cost/query = (input_tokens × price_in) + (output_tokens × price_out)**. At 1M queries/day, even $0.001/query = $1K/day ($365K/year). The optimization hierarchy has six layers — arranged from highest-ROI to lowest: skip the call (cache), route to a cheaper model, send fewer tokens, improve GPU utilization (self-hosted), quantize weights, and speculate across tokens.

### Mechanism
Sequenced optimization stack (measure first, then apply in order):

**Step 0 — Profile before optimizing**
- Measure per-query token breakdown: system prompt / retrieved context / output
- Measure cost distribution: which query types account for the most spend?
- Example: at 1M queries/day with a frontier model ($5/M input, $25/M output), 2K input + 500 output tokens = ~$0.0225/query → $22,500/day

**Step 1 — Skip the LLM call entirely (semantic + exact-match cache)**
- Exact-match response cache in Redis: 5-15% hit rate for FAQ workloads, ~$0 cost per hit
- Semantic cache (GPTCache + FAISS/Redis): cosine similarity > 0.93 on query embedding — covers paraphrased repeats; 20-35% hit rate on support/FAQ traffic
- Embedding cache: store query embeddings by hash to avoid re-embedding repeat queries
- At 30% semantic cache hit rate: $22,500/day × 0.70 = $15,750/day — a saving of $6,750/day, or ~$2.46M/year

**Step 2 — Route to a cheaper model (model tiering)**
- Complexity classifier (lightweight: token count + TF-IDF topic signal + a small fast model confidence score) routes easy queries to a small fast model ($1/M input, $5/M output) — a 5× price difference on input tokens
- FAQ-style queries (≥60% of most support workloads) → a small fast model or self-hosted a small open-weight model (7–8B class)
- Hard queries (multi-step reasoning, long context, compliance) → frontier models
- Impact: 60% of traffic at 1/16th cost cuts total API spend by ~50%

**Step 3 — Reduce tokens sent**
- Prompt compression via LLMLingua: 30-50% reduction in system prompt + few-shot examples with <2% quality loss
- Cross-encoder reranking to top-3 retrieved chunks (from top-20) before generation: reduces context from ~4K to ~1K tokens
- Anthropic prompt caching: prefix cache on static system prompt (~90% discount on cached prefix tokens)
- max_tokens constraint + "be concise, respond in ≤3 sentences" instruction: output tokens cost 5× more than input; cutting average output from 500→200 tokens saves ~60% of output spend
- Combined: 40-60% token reduction possible before quality degrades meaningfully

**Step 4 — Improve throughput (self-hosted path)**
- Migrate high-volume, latency-tolerant workloads to self-hosted a 70B-class open-weight model (vLLM + PagedAttention)
- PagedAttention eliminates KV cache fragmentation → near-100% GPU utilization → 2-3× batch throughput improvement
- Note the 2026 reality: self-hosting is no longer primarily a cost play — hosted small-tier models are cheap enough that the cheap tier is a small share of a blended bill. Justify it on data residency, latency control, or a fine-tuned task-specific model, and measure your own GPU economics rather than quoting a published break-even figure

**Step 5 — Quantization (self-hosted)**
- AWQ/GPTQ INT4: ~4× VRAM reduction, 1-3% quality loss — validate on golden dataset (skip for math/code)
- INT8 bitsandbytes: ~2× VRAM reduction, <1% quality loss — safe default

### Example / Tradeoff
**Concrete before/after at 1M queries/day (a frontier model baseline):**

| Lever | Daily Cost | Reduction |
|-------|-----------|-----------|
| Baseline (a frontier model, no optimization) | ~$22,500/day | — |
| + Semantic cache (30% hit) | ~$15,750/day | 30% |
| + Model tiering (60% → a small fast model) | ~$8,190/day | 64% |
| + Prompt compression + reranking (40% token reduction) | ~$6,700/day | 70% |
| + Prompt caching on the static prefix + `max_tokens` discipline | ~$2,400/day | ~89% |

Key tradeoff: each layer adds complexity and potential quality risk — measure quality regression with a golden dataset at each step before shipping.

---

## Verbal script

**Opening (30s):**
"I'd approach this as a six-step optimization hierarchy — ordered by ROI and implementation simplicity. The key mental model is that cost per query equals input tokens times price-in plus output tokens times price-out, so at 1M queries/day, shaving even a cent per query saves $3.6M/year. I'd measure first, then work through the layers from highest to lowest impact."

**Core explanation (2–3 min):**
"The first and highest-ROI step is skipping the LLM call entirely with a multi-layer cache. I'd start with exact-match Redis for literally identical queries — maybe 5-15% hit on FAQ workloads. On top of that, a semantic cache using GPTCache with cosine similarity above 0.93 on the query embedding catches paraphrased repeats. At a 30% combined cache hit rate, that alone cuts daily cost by 30%.

The second step is model tiering. Not all queries need a frontier model at $5 per million input tokens — the small tier is $1, a 5× difference. I'd build a lightweight complexity router — token count, topic classifier, confidence threshold — to send 60% of FAQ-style traffic to the cheap model. That typically cuts the remaining API spend roughly in half.

Third, I'd reduce tokens. Prompt compression with LLMLingua gives 30-50% reduction in system prompt length. Cross-encoder reranking from top-20 to top-3 retrieved chunks before generation cuts context from 4K to 1K tokens. And I'd add a max_tokens constraint with a conciseness instruction — output tokens cost 5× more than input, so cutting average output from 500 to 200 tokens is a huge lever people often miss."

**Tradeoff / production angle (1 min):**
"If we're self-hosting, I'd add PagedAttention via vLLM to eliminate KV cache fragmentation and improve batch throughput 2-3×, and AWQ/GPTQ INT4 quantization for a 4× VRAM reduction at 1-3% quality cost — but I'd always validate against a golden dataset before shipping quantization changes, especially for math or code tasks where the quality drop is higher.

The tradeoff I'd flag: each optimization layer adds complexity and a potential quality regression. The semantic cache threshold is tricky — too high (0.98) and hit rate drops; too low (0.88) and semantically distinct queries get the same cached answer. I'd tune it per query type."

**Wrap-up (30s):**
"So the sequence is: profile first to know where the spend is concentrated, then cache, then tier, then compress tokens, then optimize the serving layer. I can walk through the cost math for any specific stage, or discuss how I'd validate quality at each step."

---

## Pitfalls

- **Mistake:** "I'd just add caching" without specifying cache layers, thresholds, or TTL — **Better:** Name all three layers (exact-match → semantic at cosine > 0.93 → embedding hash cache), state the expected hit rate for each, and mention TTL tied to data freshness; hit rate and threshold tuning are where the real work is.
- **Mistake:** "I'd switch to a smaller model" without mentioning a complexity router or quality validation — **Better:** Explain that routing everything to a cheap model degrades quality on hard queries; you need a classifier to route correctly, and you gate deployment on golden-dataset quality regression <2%.
- **Mistake:** Ignoring output token cost and focusing only on input tokens — **Better:** State that output tokens cost 5× more than input on most providers (a frontier model: $5/M in vs $25/M out); controlling output length via max_tokens and conciseness instructions is often the single biggest lever in summarization or code generation workloads.
- **Mistake:** Jumping to self-hosted quantization/PagedAttention before exhausting API-level levers — **Better:** The cost case for self-hosting has weakened — hosted small-tier models are cheap enough that the cheap tier is a small share of a blended bill. Justify self-hosting on data residency, latency control, or a fine-tuned task-specific model, and measure your own GPU economics rather than quoting a published break-even figure.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q2: How reduce token costs at scale?](07-002-how-reduce-token-costs-at-scale.md) | Deep-dive on token reduction levers (this question is broader) |
| [Q9: Multi-layer caching: retrieval, prompt, response?](07-009-multi-layer-caching-retrieval-prompt-response.md) | Full caching architecture detail |
| [Q10: Model tiering — small distilled vs large LLM?](07-010-model-tiering-small-distilled-vs-large-llm.md) | Model tiering router design and quality tradeoffs |

---

## One-liner recall

> At 1M queries/day, work through the cost hierarchy in ROI order: skip the call (semantic cache 30% hit), route cheap (model tiering 60% of traffic at 1/16th cost), send fewer tokens (prompt compression + reranking + max_tokens), then optimize GPU utilization (PagedAttention + quantization) — always measure token cost math first and validate quality regression at each step.
