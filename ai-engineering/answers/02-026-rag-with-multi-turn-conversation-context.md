# RAG with multi-turn conversation context?

**Category:** 02-rag-systems
**Question #:** 026
**Source section:** §2 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
Multi-turn RAG is where most naive implementations fall apart in production. The interviewer is probing whether you understand that retrieval must be grounded in the *full conversational intent*, not just the latest user message — and whether you can design the right architectural layers (query rewriting, conversation summarization, session state) without blowing up latency or cost.

### Trigger phrases
- "How would you handle follow-up questions in your RAG chatbot?"
- "User says 'tell me more about that' — what does your system do?"
- "How do you maintain context across turns in a RAG pipeline?"
- "Design a conversational search/assistant that remembers prior exchanges."

### What it tests
Ability to design stateful retrieval pipelines: query reformulation, conversation memory architectures, and cost/latency tradeoffs at session scale.

---

## Answer

### Concept
In a single-turn RAG system, each query is independent — you embed it, retrieve chunks, and generate an answer. In multi-turn conversations, subsequent queries are often elliptical ("What about the pricing?" or "Can you expand on that?") and cannot be correctly resolved without knowing what "that" refers to. The core problem is **query resolution**: you must transform the user's latest message into a self-contained retrieval query that captures the full conversational intent before hitting the vector store.

### Mechanism

**Three-layer architecture for multi-turn RAG:**

1. **Session state store (Redis / DynamoDB)**
   - Store the last N turn pairs (user message + assistant response) keyed by `session_id`.
   - Keep a rolling window of 5–10 turns; older turns feed the summarization layer.
   - TTL the session key (e.g. 30 min inactivity = session reset).

2. **Query reformulation (condense + rewrite)**
   - Before retrieval, call a cheap LLM (GPT-4o-mini, ~50 tokens in + 30 out) with a *standalone-question* prompt:
     ```
     Given this conversation history:
     {last 3 turns}
     Rewrite the user's latest message as a self-contained search query.
     User: {current_message}
     Standalone query:
     ```
   - This resolves coreferences ("it", "that policy", "the earlier figure") and ellipses ("what about for enterprise?").
   - LangChain: `ConversationalRetrievalChain` does this automatically; LlamaIndex: `CondenseQuestionChatEngine`.

3. **Retrieval on reformulated query**
   - Run the condensed query through the normal hybrid retrieval pipeline (BM25 + dense HNSW → cross-encoder rerank).
   - Optionally append the last 1–2 assistant turns as "conversation context" chunks with lower weight so retrieved docs stay dominant.

4. **Generation with conversation history**
   - Include recent turns in the system/user prompt (kept short — last 2–3 turns max) plus the retrieved chunks.
   - Context layout: `[system instruction] [recent history] [retrieved chunks] [current query]`
   - This lets the model refer back to prior answers for coherence without re-retrieving them.

5. **Summarization layer for long sessions**
   - After ~10 turns, summarize older history into a single paragraph using a cheap model and store it in the session store.
   - LangChain `ConversationSummaryBufferMemory` does this: keeps the last K turns verbatim + a rolling summary of older turns.
   - This keeps the prompt within context budget while preserving long-range coherence.

### Example / Tradeoff

**Production example — customer support chatbot:**
- Turn 1: "What's your refund policy?" → retrieved policy chunks → answered.
- Turn 2: "What about for digital products?" → naive system embeds "what about for digital products?" → retrieves unrelated chunks.
- With query reformulation: condensed query = "What is the refund policy for digital products?" → correct retrieval.

**Cost breakdown at 1M sessions/day (avg 5 turns):**
| Component | Cost |
|-----------|------|
| Query reformulation (GPT-4o-mini, 80 tokens) | ~$0.04/1K sessions = $40/day |
| Retrieval (unchanged from single-turn) | ~$200/day |
| Generation (GPT-4o-mini, 600 tokens) | ~$600/day |
| Session store (Redis, 1KB/session, 30-min TTL) | ~$5/day |

The reformulation step adds only ~2% cost overhead for a major retrieval quality improvement.

**Key tradeoff: how many turns to include in reformulation context?**
- Too few (1 turn): misses longer coreference chains ("the policy you mentioned three messages ago").
- Too many (full history): reformulation prompt grows → latency and cost creep; condensed query becomes over-specified.
- Sweet spot: last 3–5 turns for reformulation; full summary for generation.

---

## Verbal script

**Opening (30s):**
"Multi-turn RAG is one of the trickiest production problems because it looks simple until users start saying things like 'tell me more about that' — and your retrieval completely fails because 'that' means nothing to the vector store. I'd tackle it with three layers: query reformulation, session state management, and a summarization buffer for long sessions."

**Core explanation (2–3 min):**
"The root problem is query resolution — user messages in a conversation are elliptical. So before I ever touch the vector store, I run a cheap query reformulation step using GPT-4o-mini with a 'condense to standalone question' prompt. I pass the last 3 turns and the current message, and the model rewrites it as a self-contained search query. In LangChain this is `ConversationalRetrievalChain`; in LlamaIndex it's `CondenseQuestionChatEngine`.

"The session state — the last N turns — lives in Redis keyed by session ID with a TTL. I keep about 5–10 turns verbatim. Once the session gets longer, I run a summarization pass using `ConversationSummaryBufferMemory`: older turns collapse into a rolling paragraph summary, and recent turns stay verbatim. That keeps my generation prompt within context budget.

"For generation, I structure the prompt as: system instruction → rolling summary (if any) → last 2–3 turns verbatim → retrieved chunks → current query. The retrieved chunks should dominate — I don't want the model drifting into conversation history for factual claims.

"A concrete production example: in a support bot, a user asks 'What's your refund policy?' in turn 1, then 'What about for digital downloads?' in turn 2. Without reformulation, the embedding for 'what about for digital downloads?' retrieves nothing useful. With reformulation: 'What is the refund policy for digital product downloads?' → correct retrieval."

**Tradeoff / production angle (1 min):**
"The main tradeoffs are: how many turns to feed the reformulation step — I've found 3–5 is the sweet spot, more than that and the condensed query gets over-specified. And when to summarize vs keep verbatim — I trigger summarization after 8–10 turns to avoid context window inflation. At scale (1M sessions/day, 5 turns avg), the reformulation step costs about $40/day on GPT-4o-mini — roughly 2% of total pipeline cost, well worth the retrieval quality improvement. One failure mode to watch: if the reformulation model hallucinates topic continuity that doesn't exist, you get retrieval for questions the user never actually asked — I validate by checking if the reformulated query is semantically similar to recent turns before firing."

**Wrap-up (30s):**
"So the mental model is: treat each turn's retrieval query as a first-class citizen that must be self-contained. Query reformulation + session state + summarization buffer — those three layers give you robust multi-turn RAG without blowing up latency or cost. Happy to go deeper on any of these layers."

---

## Pitfalls

- **Mistake:** Concatenating the full conversation history directly into the retrieval query — **Better:** Use a dedicated reformulation step (cheap LLM call) to produce a self-contained, focused query; full history makes the embedding too diffuse and retrieval degrades.
- **Mistake:** Storing only the current message in session state, then passing the raw history verbatim to generation without a summarization layer — **Better:** Use a rolling summary for older turns (e.g. LangChain `ConversationSummaryBufferMemory`) so context budget doesn't explode over long sessions; concretely, 20 turns × 300 tokens = 6K tokens just for history before you add any retrieved chunks.
- **Mistake:** Not invalidating or scoping the session store per user — **Better:** Key sessions by `user_id + session_id` with a TTL (30–60 min inactivity), and clear the session on explicit "new conversation" signals; leaking one user's context into another is both a correctness bug and a data privacy issue.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q1: Design a RAG system for a customer support chatbot](02-001-design-a-rag-system-for-a-customer-support-chatbot-how-do-yo.md) | Foundation — single-turn RAG pipeline this extends |
| [Q21: How evaluate a RAG pipeline?](02-021-how-evaluate-a-rag-pipeline-ndcg-mrr-precisionk-recall.md) | Evaluation — multi-turn adds turn-level coherence metrics alongside standard RAGAS |
| [Q21 (LLM fundamentals): How do you do memory management and context management with LLMs?](../answers/01-021-how-do-you-do-memory-management-and-context-management-with.md) | Same architectural concepts applied at the LLM layer |

---

## One-liner recall

> Multi-turn RAG requires a query reformulation step (condense last 3–5 turns into a self-contained query via cheap LLM call) before retrieval, plus Redis session state with a rolling summarization buffer to keep context within budget across long conversations.
