# What happens when you exceed the context window? How handle long documents?

**Category:** 01-llm-fundamentals
**Question #:** 036
**Source section:** §1 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
This question probes whether you understand the hard technical limit every LLM has, and — more importantly — whether you've actually shipped something that needed to work around it. At companies building document-processing pipelines, legal tools, or support bots, exceeding context is a daily reality. Interviewers want to hear a layered answer: what happens mechanically, plus the ranked set of practical mitigation strategies with real tradeoffs.

### Trigger phrases
- "Our documents are 200 pages — how do you feed them to an LLM?"
- "What happens if a user pastes a massive text into your chatbot?"
- "How do you handle long contexts in a RAG pipeline?"
- "Design a system that answers questions over 10K-page legal contracts."

### What it tests
Production architectural judgment around context-window constraints — knowing not just that truncation is bad, but which of several mitigation patterns (chunking + RAG, summarization hierarchies, long-context models, sliding windows) to apply and when.

---

## Answer

### Concept
Every LLM has a fixed context window (measured in tokens) that bounds the total input + output it can process in one call. When input exceeds this limit, the model cannot proceed — the API returns an error or silently truncates, and the model literally cannot attend to tokens outside the window. The problem is not just capacity: even within a very long context, attention quality degrades for content far from the query endpoints (the "lost in the middle" phenomenon).

### Mechanism
**What happens mechanically:**
- The transformer's attention matrix is O(n²) in token count — doubling the sequence length quadruples compute and memory cost.
- API providers hard-cap at their advertised context length. Exceeding it returns an error (`context_length_exceeded` in OpenAI) or triggers automatic truncation depending on the provider/SDK.
- Even if the model supports a million tokens, TTFT (time to first token) grows with context length because prefill is compute-bound; a 500K-token prompt takes far longer and costs far more than a 4K one. The window stopped being the wall; prefill cost and latency became the wall.

**Mitigation strategies (ordered by complexity / cost):**

| Strategy | When to use | Tools |
|---|---|---|
| **Chunking + RAG** | Knowledge retrieval over large corpora | FAISS, Pinecone, LangChain, LlamaIndex |
| **Sliding window** | Sequential text where adjacent context matters (transcripts) | Custom, LangChain `ConversationTokenBufferMemory` |
| **Map-Reduce / Refine summarization** | Summarize or extract from large docs | LangChain map-reduce chains |
| **Hierarchical summarization** | Very long docs needing full coverage | Custom pipeline, a frontier model |
| **Long-context model** | Moderate docs where recall precision > cost | a frontier model (1M tokens), a frontier model.7 (200K) |
| **Semantic routing / doc-level filter** | Multi-document retrieval to reduce candidates | Cohere Rerank, cross-encoders |

**Chunking + RAG (most common production path):**
1. Split document into chunks (512–2K tokens, with ~10–15% overlap).
2. Embed chunks with a retrieval model (e.g., `text-embedding-3-large`).
3. At query time, retrieve top-k most-relevant chunks (HNSW in FAISS/Pinecone).
4. Fit only retrieved chunks into the LLM context — typically 4–8 chunks.
5. Rerank with a cross-encoder (Cohere Rerank, `ms-marco-MiniLM`) for precision.

**Map-Reduce for summarization:**
1. Split document into chunks that each fit the context window.
2. **Map**: send each chunk to the LLM for partial summary.
3. **Reduce**: concatenate partial summaries and send a final summarization call.
4. Works well for summarization; loses cross-chunk reasoning.

### Example / Tradeoff
A 300-page legal contract (~120K words ≈ 160K tokens) now fits comfortably inside a current frontier model's ~1M-token window — so the question is no longer *can it fit* but *should you send it*, given prefill latency, per-query cost, and mid-context recall. Two practical approaches:

- **RAG approach**: chunk into 1,024-token segments, embed with `text-embedding-3-large`, index in Pinecone. At query time, retrieve 6 chunks → ~6K tokens, well within context. Works for specific clause lookups. Fails if the question requires integrating evidence scattered across 50 pages.
- **Long-context model**: route to a frontier model (1M context). Entire contract fits; latency ~30–90s, cost ~$1.50 per contract. Works well for holistic analysis but expensive at scale.

In production, a common pattern is **tiered routing**: use RAG by default for specific Q&A (cheap, fast), fall back to a long-context model only when the retriever confidence is low or the question explicitly requires full-doc reasoning. Anthropic's Claude claude-3-7-sonnet-20250219 at 200K tokens is a good middle tier.

The **"lost in the middle" trap**: Liu et al. 2023 showed that even when all relevant content fits in the context window, LLMs perform significantly worse when relevant passages are placed in the middle vs. at the beginning or end. Mitigation: put the most relevant retrieved chunks at the top and bottom of the context, not buried in the center.

---

## Verbal script

**Opening (30s):**
"This is a really practical constraint every production AI system hits. The short answer is: you can't attend to what isn't in the window, so the question is really which of several mitigation strategies fits your use case. I'd organize it around three levers: chunking + RAG, summarization hierarchies, and long-context models — and the right choice depends on query type, latency budget, and cost."

**Core explanation (2–3 min):**
"First, the mechanics. Every transformer has an O(n²) attention matrix, so context has a hard limit — both a technical cap and a cost/latency penalty as you approach it. When you exceed the limit, you get a hard API error or silent truncation. Even well within a 1M window, there's a subtler problem: the 'lost in the middle' phenomenon — models reliably attend better to content at the beginning and end of context than to content buried in the middle.

So for long documents, I think of it as a routing decision. For specific question-answering — 'what does clause 12 say about liability?' — chunking and RAG is the right move. I'd chunk the document into overlapping 512–1K token segments, embed them, index in a vector DB like Pinecone or FAISS, retrieve the top-6 most relevant chunks at query time, rerank with a cross-encoder, then feed only those chunks to the LLM. That keeps the context tight, fast, and cheap.

For holistic tasks — 'summarize this 300-page contract' — chunking loses cross-chunk reasoning. There I'd use a map-reduce pattern: summarize each chunk independently in parallel, then combine. Or, if the doc is critical and cost allows, route to a long-context model like a frontier model at 1M tokens or Claude claude-3-7-sonnet-20250219 at 200K.

In production I've seen a tiered routing pattern work well: RAG first by default, then fall back to a long-context model when retriever confidence is low or the query semantically requires full-document reasoning."

**Tradeoff / production angle (1 min):**
"The tradeoffs: RAG is cheap and fast but fails on questions that require synthesizing scattered evidence. Long-context models cover those cases but at 10–100× the cost and latency. Sliding windows work for transcripts but lose context from earlier parts of the conversation. And for 'lost in the middle' — even if you fit everything in, placement matters: put the highest-relevance chunks at the top and bottom of your context, not buried in the center."

**Wrap-up (30s):**
"So to summarize: exceeding context causes a hard error or truncation, and even within context 'lost in the middle' degrades quality. The fix is a tiered strategy — RAG for Q&A, map-reduce for summarization, long-context models as a fallback. Happy to go deeper on any of those or discuss how to implement retrieval quality evaluation."

---

## Pitfalls

- **Mistake:** Saying "just use a bigger context window" or "switch to Gemini 1M" without discussing cost, latency, or when RAG is strictly better — **Better:** Frame it as a tiered routing decision: RAG is default for Q&A (cheap, fast), long-context is the fallback for holistic tasks, and explain the cost/latency numbers (e.g., a frontier model at full 1M context can cost $1–2 per query).
- **Mistake:** Not mentioning the "lost in the middle" problem — treating context overflow as purely a capacity issue — **Better:** Explicitly flag that even when content fits in the window, placement degrades quality; mitigation is to front-load and back-load the highest-relevance chunks.
- **Mistake:** Describing chunking without mentioning overlap or reranking — **Better:** Explain that naive fixed-size chunking breaks semantic units, overlap preserves cross-boundary context, and reranking (cross-encoder) improves precision after ANN retrieval.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q5: Explain context windows and their limitations](01-005-explain-context-windows-and-their-limitations.md) | Prerequisite — foundational context window mechanics |
| [Q14: How does chunking happen?](01-014-how-does-chunking-happen.md) | Core mitigation technique — chunking strategies |
| [Q44: What is the "lost in the middle" problem?](01-044-what-is-the-lost-in-the-middle-problem.md) | Direct follow-up — quality degradation within long contexts |

---

## One-liner recall

> Exceeding the context window causes a hard API error or truncation; mitigate with tiered strategies — chunking + RAG for Q&A, map-reduce summarization for full-doc tasks, and long-context models as a costly fallback — and always guard against "lost in the middle" by placing high-relevance chunks at the context boundaries.
