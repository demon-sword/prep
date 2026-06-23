# Prompt compression?

**Category:** 07-cost-latency
**Question #:** 011
**Source section:** §9 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
Prompt tokens directly drive API cost (billed per-token) and prefill latency (O(n) prefill time grows with input length). Interviewers ask this to see whether you know concrete, production-proven techniques to reduce prompt length without sacrificing answer quality — not just vague advice like "write shorter prompts."

### Trigger phrases
- "How do you reduce token costs at scale?"
- "Walk me through how you'd compress prompts without hurting quality"
- "Your RAG context is 8K tokens — how do you shrink that?"
- "How do you optimize latency when your prompt is very long?"

### What it tests
Knowledge of the compression tool stack (LLMLingua, selective context, reranking, summarization) and the ability to reason about quality/cost tradeoffs at each layer — not just awareness that shorter prompts are cheaper.

---

## Answer

### Concept
Prompt compression is the practice of reducing the number of tokens sent to an LLM for each call — on both the input (system prompt + retrieved context + conversation history) and output sides — while preserving the information needed for a correct answer. At 1M queries/day, every 100-token reduction in average prompt length saves approximately $15–150/day depending on the model, so this is a high-ROI optimization.

### Mechanism

There are four complementary techniques, applied in order from cheapest to most complex:

**1. Rerank + top-K reduction (highest ROI, zero quality loss)**
Before generating, run a cross-encoder reranker (Cohere Rerank, BGE-Reranker) over the retrieved chunks and pass only the top-3 instead of top-10. This shrinks the retrieval context by 5–7× with zero information loss relative to what the LLM actually uses — the discarded chunks were already the lowest-relevance ones. In practice this alone cuts 60–70% of RAG context tokens.

**2. Chunk-level summarization (medium cost, small quality risk)**
For each retrieved chunk, generate a 1–2 sentence extractive or abstractive summary that preserves key facts. The compressed chunk is cached with a hash of the original (TTL matched to source freshness). Effective for long parent chunks (512–1024 tokens) that contain mostly boilerplate. Implementation: GPT-4o-mini ($0.15/M) as the compression model; compression ratio 4–8×; latency overhead ~100ms if not cached.

**3. LLMLingua / selective token pruning (high compression, measurable quality risk)**
LLMLingua (Microsoft, 2023) uses a small proxy LLM (GPT-2 or Phi-1) to score each token's conditional perplexity, then drops the lowest-perplexity tokens (redundant or predictable words). The remaining tokens are passed to the target LLM as a compressed, grammatically imperfect but semantically dense string. Achieves 2–5× compression with approximately 2–8% accuracy degradation on QA benchmarks. LLMLingua-2 (2024) improves quality at the same compression ratios using a learned compression model rather than perplexity filtering.

**4. Conversation history summarization (critical for multi-turn)**
For multi-turn sessions, replace the raw turn-by-turn history with a rolling summary after N turns. LangChain's `ConversationSummaryBufferMemory` keeps the last 2–3 turns verbatim plus a compressed summary of older context. Typical reduction: 70–80% of conversation token cost beyond turn 5.

**Output token optimization (often overlooked):**
Output tokens cost 3–10× more than input tokens on most APIs (e.g., GPT-4o: $2.50/M input vs $10/M output). Set explicit `max_tokens` limits and use structured output (JSON schema / Instructor) to enforce concise responses — this alone can reduce output tokens 30–50% on verbose models.

### Example / Tradeoff

**Customer support RAG system — before/after:**

| Layer | Before | After | Reduction |
|-------|--------|-------|-----------|
| Retrieved context (top-10 → top-3 reranked) | 4,000 tokens | 600 tokens | 85% |
| Conversation history (raw turns → summary) | 2,000 tokens | 400 tokens | 80% |
| System prompt (manual audit + dedup) | 800 tokens | 400 tokens | 50% |
| **Total input per query** | **6,800 tokens** | **1,400 tokens** | **79%** |
| Output (`max_tokens` + structured JSON) | 500 tokens | 200 tokens | 60% |

At 1M queries/day with GPT-4o ($2.50/M input, $10/M output):
- Before: (6,800 × $2.50 + 500 × $10) / 1M × 1M = **$22,000/day**
- After: (1,400 × $2.50 + 200 × $10) / 1M × 1M = **$5,500/day**

79% cost reduction without changing the model.

**Tradeoff:** LLMLingua's perplexity-pruning compresses aggressively but is lossy — not appropriate for medical or legal RAG where a dropped qualifier ("not recommended for patients with renal failure") could cause a safety incident. Use reranking and summarization there; reserve LLMLingua for general-purpose or entertainment use cases.

---

## Verbal script

**Opening (30s):**
"Prompt compression is one of the highest-ROI cost levers because token costs compound at scale — at 1M queries/day, every 100-token reduction saves thousands of dollars per day. I'd approach it as a four-layer stack, applied cheapest-first, and I'd measure quality at each layer before proceeding."

**Core explanation (2–3 min):**
"The first and highest-ROI layer is reranking plus top-K reduction. If I'm retrieving 10 chunks from my vector store, I'll run a cross-encoder reranker — Cohere Rerank or BGE-Reranker — and pass only the top-3 to the LLM. That shrinks the retrieval context by 5–7× with essentially zero quality loss because the dropped chunks were the least relevant anyway. This alone often eliminates 60–70% of RAG context tokens.

The second layer is chunk-level summarization — for long parent chunks, I'll pre-generate a 1–2 sentence summary using a cheap model like GPT-4o-mini and cache it. The compression ratio is 4–8× with a small quality risk. Third, for aggressive cases, there's LLMLingua — a Microsoft technique that uses a proxy LLM to score token perplexity and drop the redundant ones, achieving 2–5× compression with about 2–8% accuracy degradation. That's acceptable for general QA but not for regulated domains.

Fourth, and often forgotten: output tokens cost 3–10× more than input tokens on most APIs. Setting explicit `max_tokens` and using structured JSON output can cut output tokens 30–50%.

A concrete example: on a customer support RAG system, combining reranking, history summarization, and a system prompt audit reduced our average prompt from 6,800 tokens to 1,400 tokens — a 79% reduction — saving roughly $16,500/day at GPT-4o pricing on 1M queries/day, without touching the model."

**Tradeoff / production angle (1 min):**
"The main risk is lossy compression — LLMLingua's perplexity pruning can drop semantically critical tokens. I'd never use it in medical or legal RAG where omitting a negation or qualifier could cause harm. I'd gate each compression layer with a RAGAS Faithfulness delta check on a golden dataset before deploying. The other tradeoff is latency: the reranker adds ~80–200ms, and LLMLingua adds inference time for the proxy model. For latency-sensitive paths, I'd precompute chunk summaries offline and cache them, so the hot path only sees the cached compressed version."

**Wrap-up (30s):**
"In short: rerank to top-3 first — it's free quality-wise. Then history summarization, then system prompt audit. Only add LLMLingua if you still need more compression and you've verified the quality hit is acceptable on your golden set. Always treat output tokens as a separate optimization since they're the most expensive per-token on most providers."

---

## Pitfalls

- **Mistake:** Mentioning LLMLingua as the go-to compression tool without discussing quality risk — **Better:** "LLMLingua is a lossy technique — perplexity pruning can drop semantically important tokens. I'd benchmark it on a golden set and restrict it to use cases where a 2–8% QA accuracy drop is acceptable; for medical, legal, or financial RAG I'd stick to lossless techniques like reranking and summarization."
- **Mistake:** Focusing only on input token compression and ignoring output tokens — **Better:** "Output tokens cost 3–10× more than input on most APIs. Setting `max_tokens` and enforcing structured JSON output is often the highest-ROI per-token optimization and is completely free to implement — it should be the first step, not an afterthought."
- **Mistake:** Compressing the system prompt to near-zero without quality checking — **Better:** "System prompt compression should be done by manual semantic audit first (remove duplicate instructions, collapse example lists), then validated on a golden set. Automated compression of the system prompt risks removing the behavioral constraints that keep the model on-task."

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q2: How reduce token costs at scale?](07-002-how-reduce-token-costs-at-scale.md) | prerequisite — broader token-cost playbook where compression is one of 5 levers |
| [Q3: How reduce latency in GenAI applications?](07-003-how-reduce-latency-in-genai-applications.md) | parallel benefit — shorter prompts reduce prefill time and TTFT |
| [Q8: Trim prompts + cache embeddings — before/after cost breakdown?](07-008-trim-prompts-cache-embeddings-beforeafter-cost-breakdown.md) | same concept with a numerical worked example |

---

## One-liner recall

> Compress prompts in four ordered layers — rerank to top-3 chunks (85% context reduction, lossless), summarize conversation history, manually audit the system prompt, then optionally apply LLMLingua (2–5× lossy compression) — and separately cap output tokens via `max_tokens` + structured JSON, since output costs 3–10× more than input per token.
