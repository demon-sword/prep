# How reduce token costs at scale?

**Category:** 07-cost-latency
**Question #:** 002
**Source section:** §9 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
This is a focused companion to the 1M-queries/day question. The interviewer wants to see that you understand the token economy at a mechanical level — not just "compress prompts" but exactly *which* tokens are wasteful, *how* to measure the waste, and *which* levers (prompt engineering, caching, compression, structured output) apply to which token classes. It probes production depth: have you actually instrumented per-call token breakdowns and iterated on them?

### Trigger phrases
- "How do you reduce token costs at scale?"
- "Our LLM spend is $200K/month — what levers would you pull?"
- "Walk me through how you'd cut token usage without hurting quality"
- "How do you optimize token consumption in a production RAG pipeline?"

### What it tests
Token-level cost decomposition: the ability to classify prompt tokens by type, identify the highest-waste bucket, and apply targeted reduction strategies — with concrete before/after metrics and quality gates.

---

## Answer

### Concept
Token cost = (input_tokens × price_in) + (output_tokens × price_out). Every dollar of LLM spend is a function of exactly two numbers. The key insight is that a typical production prompt is 60-75% *static or semi-static* (system prompt, few-shot examples, retrieved context) — the parts that are most expensive and most compressible. Reducing token costs at scale means attacking each token class in priority order: skip the call, shrink static tokens, shrink dynamic tokens, shrink output.

### Mechanism
**Step 1 — Instrument first (measure per-call token breakdown)**
- Log `prompt_tokens` and `completion_tokens` per query, segmented by token class:
  - System prompt (static)
  - Few-shot examples (semi-static)
  - Retrieved context (dynamic, per-query)
  - User message (user-controlled)
  - Output tokens
- Identify which class dominates spend. In RAG systems, retrieved context is typically the largest bucket (40-60% of input tokens).

**Step 2 — Skip the LLM call entirely (semantic + exact-match cache)**
- Exact-match cache in Redis: free on repeated identical queries (5-15% hit on FAQ workloads).
- Semantic cache (GPTCache / Redis + FAISS): cosine similarity > 0.93 on query embedding catches paraphrased repeats; 20-35% hit on support or FAQ traffic.
- Impact: each cache hit saves 100% of the token cost for that query. This is always the highest-ROI lever — 0 tokens used.

**Step 3 — Compress static tokens (system prompt + few-shot examples)**
- **Prompt caching** (Anthropic cache_control / OpenAI cached_tokens): marks the static prefix as cacheable — 90% discount on cached prefix tokens (Anthropic); typically saves 60-80% of system prompt cost at >10 QPS where the prefix stays hot.
- **LLMLingua / LongLLMLingua**: perplexity-guided token-level compression achieves 2-5× reduction on system prompts and few-shot examples with <2% quality loss on RAG tasks. The model identifies low-perplexity (redundant) tokens and drops them.
- **Prompt audit**: manually remove redundant instructions, flatten nested bullet structures, eliminate hedge phrases ("Please note that…", "It is important to understand that…"). A careful prompt audit often achieves 20-30% reduction with zero tooling.

**Step 4 — Compress dynamic tokens (retrieved context)**
- **Cross-encoder reranking from top-K to top-3**: retrieve top-20 chunks, rerank with a cross-encoder (Cohere Rerank, BGE-Reranker), pass only top-3 to generation. Reduces context from ~4K to ~800 tokens — a 5× reduction in the most expensive dynamic token bucket.
- **Parent-child chunking**: retrieve from small child chunks (256 tokens), expand only matched child's parent for generation (1024 tokens) rather than passing all large chunks. Avoids padding irrelevant text.
- **Selective context**: if multi-turn conversation, summarize the conversation history (GPT-4o-mini for the summarization) rather than appending raw turn history. Rolling summary keeps conversation context at 200-400 tokens instead of 3K-5K.

**Step 5 — Shrink output tokens**
- Output tokens cost 3-10× more than input on most providers (GPT-4o: $2.50/M input vs $10/M output; Claude 3.5 Sonnet: $3/M input vs $15/M output).
- Set `max_tokens` explicitly — uncapped outputs balloon on verbose edge cases.
- Add a conciseness instruction: "Respond in ≤3 sentences" or "Be direct and concise; avoid preamble." Typically cuts output 30-50%.
- Use **structured output** (JSON schema / Instructor + Pydantic): deterministic output length, no verbose natural-language preamble. Often cuts output 40-60% for extraction or classification tasks.
- For summarization: Map-Reduce over smaller chunks with GPT-4o-mini, then final Reduce step with GPT-4o — only the expensive model sees the condensed summary, not the full document.

**Step 6 — Model tiering (not strictly token reduction, but reduces token spend)**
- Route easy/short queries to cheaper models: GPT-4o-mini is 16× cheaper on input than GPT-4o. Tokens still sent, but at a fraction of the cost.
- Combine with Steps 3-5: compress tokens *and* route to cheap model for the largest traffic class.

### Example / Tradeoff
**Concrete before/after for a RAG support chatbot at 500K queries/day:**

| Lever | Avg Input Tokens/Query | Daily Input Token Spend | Output Tokens/Query | Daily Output Spend |
|-------|------------------------|--------------------------|----------------------|--------------------|
| Baseline (GPT-4o, no opt.) | 3,800 | ~$4,750 | 450 | ~$2,025 |
| + Semantic cache (25% hit) | — (25% skipped) | ~$3,560 | — | ~$1,520 |
| + Prompt caching on system prompt | 3,800 → ~1,000 cached prefix saved | ~$2,100 | unchanged | ~$1,520 |
| + LLMLingua on few-shots | 2,900 effective tokens | ~$1,800 | unchanged | ~$1,520 |
| + Rerank to top-3 chunks | 2,900 → 1,200 tokens | ~$750 | unchanged | ~$1,520 |
| + max_tokens + conciseness | 1,200 (input) | ~$750 | 450 → 180 | ~$610 |
| **Combined** | **1,200** | **~$750** | **180** | **~$610** |
| **Total: ~$1,360/day vs $6,775/day baseline (~80% reduction)** | | | | |

Key quality gate: validate each compression step on a golden dataset (150-200 labeled queries). Semantic similarity ≥ 0.85 and RAGAS Faithfulness ≥ 0.85 are the typical bar before shipping each reduction.

---

## Verbal script

**Opening (30s):**
"I'd approach token cost reduction as a classification problem first — you need to know *which* tokens are burning the money before you touch anything. In a typical RAG system, the token budget breaks down into system prompt, few-shot examples, retrieved context, user message, and output — and the allocation is usually dominated by retrieved context and output, both of which are very compressible. I'd instrument that breakdown on day one, then work through levers in ROI order."

**Core explanation (2–3 min):**
"The highest-ROI move is always skipping the LLM call entirely. An exact-match Redis cache for repeated queries and a semantic cache — I'd use GPTCache with cosine similarity above 0.93 on the query embedding — together hit 20-30% of FAQ traffic. Zero tokens consumed on a cache hit; that's the best possible compression ratio.

For static tokens — system prompt and few-shot examples — I'd apply Anthropic's prompt caching or OpenAI's cached_tokens prefix caching, which gives a 90% discount on that prefix. On top of that, I'd run LLMLingua for perplexity-guided token compression on the few-shot examples; it typically achieves 2-5× reduction with under 2% quality loss. A manual prompt audit is also worth doing — removing hedging language and flattening redundant bullet structures often gets you 20-30% reduction with no tooling.

For dynamic tokens — the retrieved context — cross-encoder reranking from top-20 to top-3 chunks is the single biggest lever: it cuts context from around 4K tokens to under 1K before the generation call. I'd also add an explicit max_tokens cap and a conciseness instruction in the prompt, because output tokens cost 3-10× more than input on most providers — cutting average output from 450 to 180 tokens is a massive lever that people often skip."

**Tradeoff / production angle (1 min):**
"The main tradeoff with semantic caching is threshold calibration. Too high (0.98) and the hit rate collapses; too low (0.88) and you serve stale or wrong answers to semantically adjacent but distinct queries. I'd tune the threshold per query cluster type and monitor the false-hit rate. For compression with LLMLingua, the quality loss is task-dependent — it's benign for summarization and RAG but riskier for precise math or code tasks, so I'd always gate on a golden dataset before shipping."

**Wrap-up (30s):**
"The sequence is: instrument, cache, compress static tokens, compress dynamic context, shrink output, then tier to cheaper models. Each step has a concrete quality gate. I'd run this as a progressive rollout — one lever per sprint — with golden-dataset regression at each stage before moving to the next."

---

## Pitfalls

- **Mistake:** Saying "I'd add prompt caching" without explaining the static prefix constraint — **Better:** Specify that prompt caching only applies to a stable, identical prefix (e.g., system prompt + few-shot block) that appears at the start of the call; if the system prompt varies per user or session, caching doesn't engage. You need to architect the prompt so static content is front-loaded and invariant.
- **Mistake:** Focusing only on input token reduction and ignoring output tokens — **Better:** Name the output-to-input price ratio explicitly (e.g., 4× on GPT-4o) and explain that for extraction, classification, and summarization tasks, structured output (JSON schema via Instructor) can cut output tokens 40-60% while also improving parse reliability — this is often the single largest remaining lever after caching.
- **Mistake:** Jumping straight to LLMLingua compression without first auditing the prompt manually — **Better:** A manual prompt audit (removing hedging phrases, collapsing redundant instructions) achieves 20-30% reduction in 30 minutes with zero risk of quality degradation; LLMLingua adds complexity and should come after the easy wins are captured.
- **Mistake:** Treating all 16 retrieved context chunks as equal in cost — **Better:** Explain that cross-encoder reranking to top-3 chunks before the LLM call is both a cost reduction (5× context token reduction) *and* a quality improvement (lost-in-middle mitigation); it's one of the few optimizations that reduces cost and increases quality simultaneously.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q1: Your app gets 1M queries/day — how optimize cost?](07-001-your-app-gets-1m-queriesday-how-optimize-cost.md) | Broader cost hierarchy; this question focuses specifically on token-level levers |
| [Q9: Multi-layer caching: retrieval, prompt, response?](07-009-multi-layer-caching-retrieval-prompt-response.md) | Deep-dive on the caching layer (Step 2 of token cost reduction) |
| [Q11: Prompt compression?](07-011-prompt-compression.md) | Full treatment of LLMLingua and compression techniques (Step 3 above) |

---

## One-liner recall

> Reduce token costs at scale by working through five levers in ROI order: skip the call (semantic cache 20-30% hit), prefix-cache the static system prompt (90% discount), cross-encoder rerank to top-3 chunks (5× context reduction), compress few-shot examples with LLMLingua (2-5×), and cap output with max_tokens + structured JSON — validating quality on a golden dataset at each step.
