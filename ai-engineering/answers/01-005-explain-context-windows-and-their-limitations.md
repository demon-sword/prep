# Explain context windows and their limitations

**Category:** 01-llm-fundamentals
**Question #:** 005
**Source section:** §1 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
Interviewers want to know whether you understand a fundamental constraint that shapes almost every LLM architectural decision — from RAG chunking strategies to multi-turn memory to long-document processing. Strong candidates treat the context window not as a spec-sheet number but as a first-class engineering constraint with cost, latency, accuracy, and architectural implications.

### Trigger phrases
- "How do you handle long documents with LLMs?"
- "What happens when a user's conversation history gets too long?"
- "Explain context windows and their limitations."
- "How would you process a 200-page PDF with a frontier model?"

### What it tests
Whether the candidate understands context windows as a hard engineering constraint and can describe practical mitigation strategies (RAG, summarization, sliding window, hierarchical retrieval) rather than just citing a token number.

---

## Answer

### Concept
A context window is the maximum number of tokens an LLM can attend to in a single forward pass — input + output combined. It is the model's working memory: anything outside the window is invisible to the model. As of 2026 the frontier has converged on roughly **1M input tokens** — Claude Opus 5, Sonnet 5 and Fable 5 are all 1M, and the current OpenAI and Google flagships are within a rounding error of the same figure; smaller tiers such as Claude Haiku 4.5 sit at 200K. The old "128K is the ceiling" framing is dead. But larger does not mean "problem solved" — cost, latency, and accuracy all still degrade with window size, so the constraint moved from *hard wall* to *economics and quality*.

### Mechanism
**How the limit arises:** Self-attention has O(n²) memory complexity in the sequence length n. Doubling the context ≈ 4× the attention computation and memory. KV cache stores K and V matrices for every token, so a million-token context can run to hundreds of gigabytes of KV cache on a large model — which is why long-context serving depends on GQA/MQA, paged KV cache, and KV quantization rather than on raw VRAM.

**What breaks near the limit:**
1. **Lost in the middle** — empirical research (Liu et al., 2023) shows LLMs reliably recall content at the beginning and end of a long context but forget material buried in the middle. The effect did not disappear when windows grew to 1M — it moved outward, so recall in the middle of a very long context is still measurably worse than at the edges.
2. **Cost scales linearly — and providers now price long context differently.** Anthropic bills its full 1M window at the standard per-token rate with no surcharge. OpenAI re-rates a GPT-5.6 Sol request above 272K input tokens at 2x input and 1.5x output *for the whole request*, and Google charges a higher rate above 200K on its Pro tiers. Knowing which of those three shapes your provider uses is the difference between a predictable bill and a surprise one.
3. **Latency (TTFT)** — time-to-first-token scales with prompt length because the prefill phase must process all input tokens before generation begins. A 100K prompt may add 5–15s of TTFT.
4. **Attention dilution** — with very long contexts, attention heads spread across millions of candidate positions and may fail to focus on the most relevant span.

**Mitigation strategies (production):**
- **RAG** — retrieve only the top-k relevant chunks (e.g. 5–20 chunks × 512 tokens = 2.5–10K tokens) instead of loading the whole document. This is almost always the right answer for long documents.
- **Sliding window / chunked summarization** — process document in overlapping windows (e.g. 2K stride over 4K chunks) and summarize each; feed summaries into a final pass.
- **Hierarchical indexing** — store both full chunks and their summaries; retrieve summaries first, then fetch full chunks if needed.
- **Prompt compression** — LLMLingua / Selective Context compress prompts by 2–10× with minimal accuracy loss.
- **Long-context models as a deliberate choice, not a default** — reach for the full ~1M window only when the structure genuinely requires it (e.g. whole-codebase reasoning, legal contract cross-referencing), and budget accordingly.

### Example / Tradeoff
A customer support RAG system at Intercom processes support tickets averaging 500 tokens and a knowledge base of 50K articles. Naively dumping all articles into a 200K context would cost ~$0.50/query at a frontier model pricing and hit 8s TTFT. Instead: embed + HNSW index in Pinecone, retrieve top-5 chunks (~2.5K tokens), total cost drops to ~$0.003/query — 160× cheaper — with lower latency and often higher faithfulness (less noise).

The real production tradeoff: larger context ≠ better answers. More tokens in the prompt introduce noise and can actually hurt recall for the specific relevant passage (lost-in-the-middle effect). The right engineering answer is almost always "retrieve less, more precisely" rather than "use a bigger context window."

---

## Verbal script

**Opening (30s):**
"Context windows are one of the most fundamental constraints in LLM engineering — and one of the most misunderstood. The naive answer is 'just use a model with a bigger context window,' but that ignores cost, latency, and the lost-in-the-middle effect, which are all real production problems. Let me walk through what context windows actually are, why they're limiting, and what I'd do about it in practice."

**Core explanation (2–3 min):**
"A context window is the maximum number of tokens a model can attend to in a single forward pass — input plus output combined. This matters because LLMs have no external memory: anything not in the window simply doesn't exist for the model.

The limit exists for a physical reason: self-attention is O(n²) in sequence length, so memory and compute grow quadratically as you add tokens. A million-token context requires a KV cache that can run to hundreds of gigabytes on GPU.

Even if you have the VRAM, three problems remain. First, cost — cloud APIs charge per token, so sending 100K tokens per query gets expensive fast. Second, latency — the prefill phase (processing all input tokens before generation starts) adds seconds at long context lengths. Third, and most subtle, is the lost-in-the-middle effect: empirical research shows LLMs reliably recall content at the start and end of a long context, but forget things buried in the middle. So filling the context window does not guarantee the model will use everything you put in it.

The production mitigation hierarchy I use is: RAG first — retrieve only the 5–15 most relevant chunks rather than loading the full document. If the document structure genuinely requires cross-referencing across the full text — like legal contracts or large codebases — then I'd look at hierarchical summarization or, as a last resort, a long-context model like a frontier model with explicit prompt structure that puts the most critical content at the beginning and end."

**Tradeoff / production angle (1 min):**
"The key tradeoff is precision vs. completeness. A larger context window feels safer — you can include more — but it often hurts faithfulness because the model attends weakly to material in the middle. At 1M queries/day, even a 10K-token average prompt is 10B tokens of API spend daily. That's a significant cost center. My default is always: make retrieval better and more precise before reaching for a bigger context window. Semantic caching and prompt compression (like LLMLingua) are also worth layering in before paying for long-context inference."

**Wrap-up (30s):**
"So the short answer: context window = working memory, it's expensive and has an accuracy cliff in the middle, and the right fix is almost always tighter retrieval rather than a bigger window. Happy to go deeper on RAG strategies, KV cache mechanics, or how you'd handle something like a 200-page PDF specifically."

---

## Pitfalls

- **Mistake:** Saying "just use Claude or Gemini with a 1M token context" as the solution to long documents — **Better:** Acknowledge that long-context models are more expensive and slower (TTFT), and that the lost-in-the-middle effect means a 100K-token context often has lower accuracy on middle-position content than a well-tuned RAG pipeline with a 4K window.
- **Mistake:** Conflating context window size with model capability — e.g. "this model is better because it has a 1M context" — **Better:** Explain that context window is an architectural constraint, not a quality metric; a smaller, precisely-targeted context often outperforms a bloated one.
- **Mistake:** Forgetting to mention the cost dimension — stating "I'd use long-context models" without cost/latency numbers — **Better:** Quantify: at $15/1M input tokens (a frontier model), 100K tokens = $1.50/query; at 1M queries/day that's $1.5M/day.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q9: What is KV cache? How does it help in LLM inference?](01-009-what-is-kv-cache-how-does-it-help-in-llm-inference.md) | KV cache is the mechanism that makes long contexts expensive — prerequisite |
| [Q44: What is the "lost in the middle" problem?](01-044-what-is-the-lost-in-the-middle-problem.md) | Core limitation of long contexts — direct follow-up |
| [Q36: What happens when you exceed the context window? How handle long documents?](01-036-what-happens-when-you-exceed-the-context-window-how-handle-l.md) | Production mitigation strategies — same concept, production angle |

---

## One-liner recall

> Context windows are the model's finite working memory (O(n²) attention cost, lost-in-the-middle accuracy cliff, linear cost scaling) — the fix is tighter RAG retrieval, not a bigger window.
