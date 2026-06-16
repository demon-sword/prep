# What is tokenization, and why does it matter for cost and context windows?

**Category:** 01-llm-fundamentals
**Question #:** 039
**Source section:** §1 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
This is the #1 screening question for tokenization because it pivots from "what is it?" (Q3) to the *engineering consequences*. Interviewers want to know whether you can reason about billing, context budget, and how token count affects architectural choices — not just recite BPE mechanics. Candidates who can quantify "my prompt is 800 tokens, my retrieved context is 2 000 tokens, and I have 1 200 tokens left for the answer" show real production thinking.

### Trigger phrases
- "What is tokenization, and why does it matter for cost and context windows?"
- "How do tokens translate to cost?"
- "How do you estimate the number of tokens in a request?"
- "Why did my context window fill up faster than expected?"

### What it tests
Ability to translate low-level text-preprocessing concepts into concrete cost-and-capacity engineering decisions.

---

## Answer

### Concept
A **token** is the atomic unit an LLM reads and prices: roughly 3–4 characters of English, or ~0.75 words. Modern APIs (OpenAI, Anthropic, Google) charge **per input token + per output token**, and context windows are measured in tokens, not words or characters. Every engineering decision — prompt length, chunk size, retrieval top-k, output length — is fundamentally a token budget problem.

### Mechanism
**How tokenization works (brief):**
- BPE (GPT family via `tiktoken`) or SentencePiece splits text into frequent subword units.
- Rule of thumb: **1 000 English words ≈ 750 tokens**; code, JSON, and non-Latin scripts tokenize less efficiently (1:1 to 2:1 ratio).
- `tiktoken` (Python) counts tokens exactly before sending a request — always use it or `cl100k_base` encoder to pre-validate.

**Cost impact:**
| Component | Typical token count | GPT-4o cost (Jun 2026) |
|-----------|--------------------|-----------------------|
| System prompt | 300–800 | $0.0015–$0.004 |
| Retrieved context (top-5 chunks @ 400 tok each) | 2 000 | $0.010 |
| User query | 50–200 | ~$0.001 |
| LLM answer | 200–800 | $0.010–$0.040 (output 5× more expensive) |
| **Total per query** | **~3 000** | **~$0.025** |

At 1 M queries/day that's **$25 000/day** from token cost alone — making prompt compression, caching, and model tiering critical levers.

**Context window impact:**
- GPT-4o: 128 K tokens max. Sounds large; a 300-page PDF ≈ 75 000 tokens, leaving little room for retrieved chunks + answer headroom.
- "Lost in the middle" degrades when context > ~32 K tokens — relevant content placed in the middle of a huge context is frequently ignored.
- Practical budget allocation for RAG: system prompt ≤ 10%, retrieved context ≤ 60%, query + answer headroom ≥ 30%.

**Key engineering levers:**
1. **Measure before you build** — run `tiktoken.encode(prompt)` in unit tests; set hard limits.
2. **Compress prompts** — LLMLingua / Selective Context can cut 2–3× with minimal quality loss.
3. **Right-size chunks** — 400-token chunks balance context richness vs. context pollution.
4. **Cache repeated context** — semantic cache (GPTCache, Redis) serves repeated queries without re-billing input tokens.
5. **Model tier** — route short/simple queries to Claude Haiku or GPT-4o-mini (10–20× cheaper per token).

### Example / Tradeoff
A legal-document RAG system chunking 300 K contracts at 2 000 tokens each: embedding every chunk costs **600 M tokens** at ~$0.13/1 M = **$78** one-time indexing; querying with top-5 retrieval adds 10 000 tokens/query — at $0.010/query × 100 K queries/day = **$1 000/day** in input tokens before generation. Switching to `text-embedding-3-small` (5× cheaper) for indexing and caching the top-20% of repeated queries with Redis reduces that to **~$300/day** with the same answer quality — a 70% cost reduction purely from token economics.

---

## Verbal script

**Opening (30s):**
"Great question — tokenization is the billing and capacity unit of every LLM call. I'd frame my answer in two parts: how tokens relate to cost, and how they constrain context window budgeting, because both have direct architectural consequences."

**Core explanation (2–3 min):**
"A token is roughly 3–4 characters of English text — so 1 000 words is about 750 tokens. Modern LLM APIs charge separately for input and output tokens, and output is typically 3–5× more expensive per token than input. For GPT-4o, input is about $5/1 M tokens and output is $15/1 M. That sounds cheap, but at a million queries a day with a 3 000-token average request, you're looking at $15–25 K per day just in token costs.

The context window constraint is the other side. GPT-4o gives you 128 K tokens, which sounds huge, but a system prompt plus top-5 retrieved chunks plus the user query can easily consume 3–4 K tokens before the model writes a single word. If you're doing summarization over a 300-page PDF, you've burned 75 K tokens just on the document.

The key tool I use is `tiktoken` — I count tokens in unit tests and set hard budget limits per component: system prompt gets 10%, retrieved context gets 60%, and the rest is answer headroom. This prevents silent over-runs at runtime."

**Tradeoff / production angle (1 min):**
"The main tradeoff is context richness vs. cost. Adding more retrieved chunks improves answer quality up to a point, then the 'lost in the middle' effect kicks in — content placed in the middle of a long context gets underweighted. So there's a sweet spot around 4–8 chunks of 400 tokens each. Beyond that you're paying for context that hurts, not helps.

For cost optimization, I layer three levers: semantic caching to skip re-computation on repeated queries, model tiering to route simple queries to smaller models, and prompt compression (LLMLingua) to shrink system prompts 2–3× with minimal quality degradation."

**Wrap-up (30s):**
"So tokenization matters because tokens are the billing unit, the context budget, and a proxy for latency. Any AI engineer needs to be able to estimate, measure, and optimize token usage before shipping to production. Happy to go deeper on any of these levers."

---

## Pitfalls

- **Mistake:** Saying "tokens are just words" and not knowing the 1 000 words ≈ 750 tokens rule — **Better:** cite the rough ratio, explain it varies (code/JSON/non-Latin are worse), and mention `tiktoken` for exact counts.
- **Mistake:** Treating the context window as "basically unlimited" once you have 128 K tokens — **Better:** explain that cost scales linearly with context, output quality degrades with very long context ("lost in the middle"), and TTFT (time to first token) grows with prefill size.
- **Mistake:** Forgetting that output tokens are more expensive than input tokens — **Better:** explicitly distinguish input vs. output pricing and note that long-form generation (summaries, reports) is the main cost driver, not the prompt.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q3: What is tokenization and how does it affect LLM performance?](01-003-what-is-tokenization-and-how-does-it-affect-llm-performance.md) | Deeper dive into BPE mechanics and domain tokenization failures — prerequisite |
| [Q5: Explain context windows and their limitations](01-005-explain-context-windows-and-their-limitations.md) | Context window capacity and lost-in-the-middle — direct follow-up |
| [Q9: What is KV cache? How does it help in LLM inference?](01-009-what-is-kv-cache-how-does-it-help-in-llm-inference.md) | KV cache as the mechanism by which token prefill cost is amortized in multi-turn chats |

---

## One-liner recall

> Tokens are both the billing unit (input ~$5/1 M, output ~$15/1 M for GPT-4o) and the context budget — always count tokens with `tiktoken` before building, budget your context window (10% system / 60% retrieved / 30% answer headroom), and optimize via caching, compression, and model tiering.
