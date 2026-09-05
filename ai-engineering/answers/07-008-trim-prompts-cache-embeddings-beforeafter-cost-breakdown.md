# Trim prompts + cache embeddings — before/after cost breakdown?

**Category:** 07-cost-latency
**Question #:** 008
**Source section:** §9 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
This is a tactical depth check. The interviewer wants to see whether you can translate two specific techniques — prompt trimming and embedding caching — into concrete numbers. It's asked to test whether you've actually instrumented a production system, measured per-call costs, and executed a before/after comparison, rather than just knowing the technique names. It probes mechanical understanding: *what exactly* do you trim, *where exactly* do you cache embeddings, and *what numbers do you expect to see*?

### Trigger phrases
- "Walk me through how prompt trimming and embedding caching affect your cost"
- "Give me a before/after breakdown of trimming prompts and caching embeddings"
- "What's the ROI on prompt compression and embedding caching — concrete numbers?"
- "How would you measure the impact of these two optimizations on a production system?"

### What it tests
The ability to quantify two specific cost levers — prompt size reduction and embedding call elimination — with realistic before/after numbers, not vague "it reduces cost."

---

## Answer

### Concept
**Prompt trimming** shrinks the number of tokens sent to the LLM on each call — reducing input token spend directly. **Embedding caching** eliminates redundant embedding API calls by storing computed vectors for documents that haven't changed, so you pay for each document embedding exactly once regardless of how many queries reference it. Together, they attack two different cost buckets: generation cost (prompt trimming) and retrieval cost (embedding caching).

### Mechanism

**Prompt trimming — four levers:**

1. **Manual prompt audit** — remove hedge phrases ("It is important to note that…", "Please be advised…"), flatten redundant bullets, consolidate repeated instructions. Achieves 15-30% token reduction in 30 minutes with zero tooling risk.

2. **Cross-encoder reranking to reduce retrieved context** — retrieve top-20 chunks, rerank with a cross-encoder (Cohere Rerank or BGE-Reranker), pass only top-3 to generation. The retrieved context bucket is typically 40-60% of total input tokens in a RAG system; cutting from 20 chunks (~4,000 tokens) to 3 chunks (~600 tokens) is a **6-7× reduction** on the largest single cost bucket.

3. **LLMLingua / prompt compression** — perplexity-guided token-level compression on system prompt and few-shot examples; achieves **2-5× reduction** on static content with <2% quality loss on RAG tasks. Apply after manual trimming.

4. **max_tokens cap + conciseness instruction** — output tokens cost 5× more than input (a frontier model: $5/M input, $25/M output); setting `max_tokens=300` and adding "respond in ≤3 sentences" cuts average output 30-50%.

**Embedding caching — two layers:**

1. **Document-level embedding cache (Redis / Pinecone store)** — compute embeddings once at ingestion; store vector + SHA-256 hash of the raw chunk text in the vector DB or Redis. On each update, hash the new content; if the hash matches, skip the embedding call. For a corpus that changes <5% per day (e.g., an internal knowledge base), this eliminates 95%+ of ongoing embedding API calls.

2. **Query embedding cache (Redis, 1-hour TTL)** — cache the embedding of each unique query string. Exact-match repeated queries (e.g., "What is your return policy?") reuse the cached vector instead of re-calling the embedding API. For FAQ-heavy workloads, 20-40% of queries are repeats within a rolling hour window.

**Measurement protocol:**

```
Before: Log (query_id, prompt_tokens, completion_tokens, embedding_calls, total_cost) per request
Apply one optimization at a time — measure change in each bucket
After: Re-log same fields; compute reduction per bucket
```

### Example / Tradeoff

**Concrete before/after — RAG support chatbot, 500K queries/day, corpus of 100K documents:**

**Embedding cost (corpus ingestion + serving):**

| State | Embedding calls/day | Tokens/call | Daily embedding cost (text-embedding-3-small @ $0.02/1M) |
|-------|---------------------|-------------|----------------------------------------------------------|
| Baseline (no cache) | ~500K query embeds + 100K doc re-embeds/day | 512 avg | ~$6/day |
| + Query embedding cache (Redis, 30% hit rate) | ~350K query + 100K doc | 512 | ~$4.60/day |
| + Doc embedding cache (hash-match, 95% skip rate) | ~350K query + 5K doc | 512 | ~$3.65/day |
| **Saving: ~$2.35/day (~40% reduction on embedding line)** | | | |

*Note: Embedding costs are low relative to generation; the real ROI of document embedding caching is latency (avoiding ingestion recomputation) and preventing embedding model API rate-limit pressure, not dollar savings.*

**Generation cost (prompt trimming):**

| Optimization | Avg Input Tokens | Avg Output Tokens | Daily Generation Cost (a frontier model) |
|---|---|---|---|
| Baseline | 4,200 (system 800 + context 3,000 + user 400) | 400 | ~$15,500/day |
| + Manual prompt audit (-25% system prompt) | 4,000 | 400 | ~$15,000/day |
| + Rerank to top-3 chunks (context: 3K→600 tokens) | 1,600 | 400 | ~$9,000/day |
| + LLMLingua on system prompt+few-shots (2× compression) | 1,200 | 400 | ~$8,000/day |
| + max_tokens=250 + conciseness instruction | 1,200 | 400→200 | **~$5,500/day** |
| **Total reduction: $15,500 → $5,500/day (~65%)** — note output tokens now dominate the residual bill | | | |

Quality gate at each step: RAGAS Faithfulness ≥ 0.85 and Answer Relevancy ≥ 0.80 on a 200-query golden dataset.

**Key insight:** The embedding cache cost saving looks small in dollars but is essential at scale for: (a) idempotent ingestion pipelines that re-process data, (b) avoiding re-embedding on trivial doc updates, (c) serving query embeddings without API latency (~1ms Redis vs ~50ms API). The generation cost saving from prompt trimming — especially reranking to reduce retrieved context — is where the material dollar impact lives.

---

## Verbal script

**Opening (30s):**
"I'd split this into two separate cost buckets: generation cost, which is where the real money is, and embedding cost, which is lower in absolute dollars but worth eliminating for latency and rate-limit reasons. Both have concrete before/after breakdowns if you instrument per-call token counts and API calls separately. Let me walk through each."

**Core explanation (2–3 min):**
"On the generation side — prompt trimming — the highest-impact lever is reducing the retrieved context. In a typical RAG system, retrieved chunks make up 60-70% of total input tokens. If I'm passing 20 chunks at ~150 tokens each, that's around 3,000 tokens of context. Running a cross-encoder reranker — Cohere Rerank or BGE-Reranker — and passing only the top 3 reduces context to around 600 tokens. That's a 5× reduction on the largest token bucket, before touching anything else.

After that, I'd do a manual prompt audit — removing hedge phrases, flattening bullet structures — which typically saves another 20-30% on the system prompt with zero tooling. Then LLMLingua on the few-shot examples for another 2-5× compression. And finally, setting max_tokens and adding a conciseness instruction for output: output tokens cost 4× more than input on a frontier model, so cutting average output from 400 to 200 tokens is a significant lever.

A concrete example: at 500K queries/day on a frontier model, I'd expect to go from about $15,500/day to around $5,500/day with these four steps combined — roughly 65% reduction, and what's left is dominated by output tokens.

On the embedding side: document embedding caching works by storing the SHA-256 hash of each chunk alongside its vector in the vector DB. On re-ingestion, you hash the content first; if it matches, you skip the embedding API call. For a knowledge base that changes less than 5% per day, this eliminates 95% of document embedding calls. For query embeddings, I'd cache in Redis with a 1-hour TTL — FAQ workloads get 20-40% hit rates on repeated queries. The dollar savings on embeddings are modest — text-embedding-3-small is very cheap — but the latency and rate-limit benefits are material at scale."

**Tradeoff / production angle (1 min):**
"The main tradeoff with prompt trimming is that each compression step needs to be validated on a golden dataset — RAGAS Faithfulness above 0.85 — before you roll to production. LLMLingua compression is task-dependent: it's safe for summarization and RAG but can hurt precision tasks like code generation or math. I'd apply it conservatively and test. For embedding caching, the main risk is serving stale vectors after content updates — the hash-based check handles this, but you need a robust CDC pipeline (Debezium/Kafka) to trigger re-hashing on source changes, not just a nightly batch."

**Wrap-up (30s):**
"So: prompt trimming delivers the material dollar savings — mostly from reranking context down and capping output — and embedding caching delivers latency and rate-limit protection with modest but real dollar savings. Instrument both separately, optimize in ROI order, and gate each step on your golden dataset."

---

## Pitfalls

- **Mistake:** Treating embedding caching as a major cost-saving measure and spending time architecting it — **Better:** Quantify that embedding costs are typically 5-10% of total LLM spend; the real ROI of document embedding caching is eliminating redundant API calls, reducing ingestion latency, and avoiding rate-limit pressure — not dollar savings. Lead with the generation-side optimization (prompt trimming) where the material dollars are, and mention embedding caching as a latency/reliability win.
- **Mistake:** Saying "I'd trim the prompt" without specifying *which* tokens and by *how much* — **Better:** Break down the prompt by bucket (system prompt, few-shot examples, retrieved context, user message, output) and give a realistic percentage for each lever: manual audit (~25% on system prompt), cross-encoder rerank to top-3 (5× context reduction), LLMLingua (2-5× on static content), max_tokens + conciseness (~50% output reduction). The interviewer wants numbers, not generic technique names.
- **Mistake:** Describing optimization without mentioning the quality gate — **Better:** For every compression step, name the validation bar: RAGAS Faithfulness ≥ 0.85 on a 200-query golden dataset before shipping. This signals production discipline, not just academic knowledge of the techniques.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q2: How reduce token costs at scale?](07-002-how-reduce-token-costs-at-scale.md) | Broader token-cost reduction framework; this question is the specific before/after drill-down |
| [Q11: Prompt compression?](07-011-prompt-compression.md) | Deep-dive on LLMLingua and perplexity-guided compression techniques |
| [Q9: Multi-layer caching: retrieval, prompt, response?](07-009-multi-layer-caching-retrieval-prompt-response.md) | Embedding caching fits into the broader caching stack architecture |

---

## One-liner recall

> Prompt trimming saves 75-80% of generation cost via reranking to top-3 chunks (5× context reduction), manual audit, LLMLingua, and output caps; embedding caching saves 95% of document embedding API calls via SHA-256 hash-match at ingestion, delivering latency and rate-limit benefits more than dollar savings — validate each step on a 200-query golden dataset.
