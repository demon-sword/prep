# How do you do memory management and context management with LLMs?

**Category:** 01-llm-fundamentals
**Question #:** 021
**Source section:** §1 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
This question probes whether you understand that context windows are finite, expensive, and degrade in quality as they fill — and whether you've designed production systems that handle memory gracefully across multi-turn conversations, long documents, and agentic loops. Weak candidates treat memory as a solved problem ("just pass the full history"). Strong candidates describe a layered architecture: what lives in-window, what lives in a vector store, what gets summarized, and what gets discarded.

### Trigger phrases
- "How do you handle long conversations with an LLM?"
- "How do you manage context in a multi-turn chatbot at scale?"
- "What happens when you run out of context window?"
- "How does an agent remember what it did three steps ago?"

### What it tests
Architectural thinking about context as a resource: scarcity, cost, degradation under load, and the memory tiers that compensate.

---

## Answer

### Concept
LLMs have no persistent memory between API calls — every call starts fresh from whatever tokens you put in the context window. "Memory management" means deciding what information to include, compress, offload, or retrieve so the model has the right context at the right time without blowing the token budget or hitting the "lost in the middle" degradation zone.

### Mechanism

There are four memory tiers, each with a different latency, cost, and fidelity profile:

**1. In-context (working memory) — the window itself**
- Holds the system prompt, recent turns, retrieved chunks, tool outputs
- Token budget: e.g. ~1M tokens on a current frontier model (Claude Opus 5 / Sonnet 5), 200K on a small fast tier like Claude Haiku 4.5
- Problem: cost grows O(n) per turn; quality degrades for content placed in the middle of a very long context (lost-in-the-middle); TTFT (time-to-first-token) rises with length
- Strategy: keep only the last N turns (sliding window) or compress older turns on the fly

**2. External semantic memory — vector store**
- Store conversation summaries, prior decisions, user facts, document chunks in Pinecone / FAISS / pgvector
- At query time, retrieve the top-k most relevant memories and inject them into the prompt
- Enables unbounded long-term memory with O(1) retrieval cost
- LangChain `ConversationSummaryBufferMemory` + Pinecone is a canonical implementation

**3. Episodic / summarization layer**
- When the conversation history exceeds a threshold (e.g. 8K tokens), run a summarization call: "Summarize the last 20 turns in 200 words preserving key decisions, open questions, and user preferences."
- Replace the raw history with the summary; the summary grows incrementally
- Reflexion-style agents write episodic summaries to durable storage after each task

**4. Structured/procedural memory — key-value or DB**
- For facts that need exact recall (user name, account ID, preferences), store in a DB or Redis, not in a vector store
- Retrieve deterministically by key, not by similarity — vector search introduces fuzzy recall that can corrupt facts

**Context window hygiene techniques:**
- **Prompt compression:** LLMLingua / Selective Context — compress retrieved chunks by 2–4× before injection, preserving information content
- **Context eviction policies:** LRU-style sliding window, or importance-weighted: keep turns that contain decisions/commitments, evict small-talk
- **RAG as memory:** for factual knowledge, don't keep it in the prompt — retrieve it at generation time. This is cheaper than always including a giant system prompt
- **Structured output + checkpoint:** in agentic loops, write intermediate results to disk/DB between steps so a crash or context-reset doesn't lose work

### Example / Tradeoff

**Production chatbot (1M conversations/day):**
- In-context: last 6 turns only (≈2K tokens per call)
- External memory: user profile + past session summaries in pgvector, retrieved top-3 per query
- Summarization: triggered when in-context turn count hits 10; async call using a cheap model (Haiku / a small fast model)
- Result: 40% reduction in average tokens/call; p95 latency down from 4.2s → 2.1s; user satisfaction unchanged (summaries preserved enough context)

**Tradeoff — summarization fidelity vs cost:**
Summarization loses exact quotes and specific numbers. For customer support bots, this can cause errors ("I told you the price was $149.99!"). Mitigation: keep the last 2 turns verbatim even when summarizing older history, and store structured facts (prices, order IDs) in the key-value layer, not in summarization text.

---

## Verbal script

**Opening (30s):**
"LLMs have no built-in memory — every API call is stateless. So memory management is really about designing a layered system: what goes in the context window right now, what gets compressed or summarized, and what gets offloaded to external storage and retrieved on demand. I think about four tiers."

**Core explanation (2–3 min):**
"The first tier is the in-context window itself — that's your working memory. On a current frontier model that's on the order of a million tokens, but the size of the window is no longer the binding constraint — what you actually send is. You don't want to fill it blindly. Cost scales linearly with context length, TTFT rises, and there's a real 'lost in the middle' problem where the model underattends to content placed far from the edges. So I apply a sliding window — maybe the last 6–8 turns — and evict older content.

The second tier is external semantic memory in a vector store. I serialize old conversation turns or session summaries into embeddings and store them in Pinecone or pgvector. At each new turn, I retrieve the top-3 most relevant past memories and inject them into the prompt. This gives the model effective long-term memory without ballooning the context.

The third tier is a summarization layer. When the raw turn count hits a threshold — say 10 turns — I fire off an async summarization call using a cheap model like Claude Haiku: 'summarize the last N turns preserving decisions, open questions, and user preferences.' I replace the raw history with the summary and keep appending. This is how LangChain's ConversationSummaryBufferMemory works under the hood.

The fourth tier is structured storage — a DB or Redis — for facts that need deterministic recall: order IDs, user preferences, prices. I never trust vector search for these because similarity-based retrieval can return approximate results, and approximate is wrong for exact facts."

**Tradeoff / production angle (1 min):**
"The main tradeoff is summarization fidelity. Summarization loses exact quotes and specific numbers. In a customer support context that's a real problem — 'I told you the order total was $149.99!' So I layer the approaches: keep the last 2 turns verbatim, summarize older turns, and store structured facts in Redis. I also use prompt compression tools like LLMLingua to compress retrieved chunks by 2–4× before injection, saving tokens without losing too much information.

In agentic loops I also write intermediate results to durable storage between steps — so if the context resets or the agent crashes, the work isn't lost."

**Wrap-up (30s):**
"The key insight is that 'memory' isn't a single thing — it's a hierarchy. In-context for recency, vector store for semantic recall, summarization for long histories, and a DB for exact facts. Happy to go deeper on any tier, or on how I'd design this for a specific system."

---

## Pitfalls

- **Mistake:** Saying "just pass the full conversation history every time" — **Better:** Explain why that's unsustainable at scale (cost, TTFT, lost-in-the-middle) and describe the sliding window + summarization + vector memory tiers that replace it.
- **Mistake:** Treating the vector store as the only memory layer and using it for exact-recall facts (prices, IDs) — **Better:** Distinguish semantic memory (vector search, OK for approximate recall) from structured memory (DB/Redis, required for exact-match facts), and explain why mixing them causes correctness bugs.
- **Mistake:** Ignoring context eviction policy — "we just keep the last 10 turns" without thinking about *which* turns matter — **Better:** Describe importance-weighted eviction: retain turns containing decisions, user commitments, or unresolved questions; evict routine acknowledgments.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q5: Explain context windows and their limitations](01-005-explain-context-windows-and-their-limitations.md) | Prerequisite — context window mechanics underpin all memory strategies |
| [Q9: What is KV cache? How does it help in LLM inference?](01-009-what-is-kv-cache-how-does-it-help-in-llm-inference.md) | Related — KV cache is the server-side complement to client-side context management |
| [Q17: What is reflection in the context of LLM agents?](01-017-what-is-reflection-in-the-context-of-llm-agents.md) | Follow-up — episodic memory in agentic loops (Reflexion) is a specialized form of context management |

---

## One-liner recall

> Memory management = four tiers: sliding in-context window, vector store for semantic recall, summarization for long histories, and a structured DB for exact facts — each chosen by recency, fidelity, and cost.
