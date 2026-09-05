# Types of memory: working, episodic, semantic, procedural?

**Category:** 03-agents-tool-use
**Question #:** 027
**Source section:** §3 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
Interviewers ask this to probe whether a candidate understands the *memory architecture* of a production agent — not just that "agents have memory," but the distinct purpose, storage backend, and lifetime of each memory tier. Weak candidates treat memory as a monolith (one chat history buffer); strong candidates map cognitive psychology's memory taxonomy onto concrete engineering choices (Redis, Pinecone, system prompts, fine-tuning).

### Trigger phrases
- "How does your agent remember things across turns?"
- "What types of memory should an agent have?"
- "How do you handle long-term memory without polluting context?"
- "Walk me through the memory architecture in your agent system."

### What it tests
Ability to design a multi-tier agent memory system with appropriate backends, lifetimes, and retrieval strategies for each memory type.

---

## Answer

### Concept
Agent memory mirrors the cognitive science taxonomy: **working memory** holds the current context window; **episodic memory** stores past interaction sessions; **semantic memory** holds general world/domain knowledge; and **procedural memory** encodes *how* to do things — skills, workflows, tool-call patterns. Each type has a different lifetime, storage backend, and retrieval strategy, and conflating them is the most common production mistake.

### Mechanism

| Memory type | Cognitive analogy | Storage backend | Lifetime | Retrieval |
|-------------|------------------|-----------------|----------|-----------|
| **Working** | RAM / scratchpad | In-context window (prompt tokens) | Single agent turn/run | Implicit — already in prompt |
| **Episodic** | Personal diary | Redis / Postgres (serialised JSON) keyed by session_id | Session or user-lifetime | Fetch last N turns or summarise with a small fast model |
| **Semantic** | Encyclopedia | Vector store (Pinecone / Qdrant) + optional KG (Neo4j) | Long-lived, updated async | ANN cosine search; refreshed by CDC on knowledge updates |
| **Procedural** | Muscle memory | System prompt snippets, few-shot examples, or fine-tuned weights (LoRA) | Encoded at deploy time | Always-on (system prompt) or retrieved by task classifier |

**Integration flow:**

1. **Turn start** — orchestrator loads working memory (last N messages, current tool call queue) into the prompt.
2. **Episodic lookup** — query Redis for recent session state; if session is cold, summarise prior episodes with LangChain `ConversationSummaryBufferMemory`.
3. **Semantic retrieval** — embed the user's current intent and query Pinecone; inject top-k relevant facts/docs into working context.
4. **Procedural injection** — task classifier routes to the correct system-prompt section (e.g. "billing workflow" vs "escalation policy") or triggers a tool-call sequence stored as a LangGraph DAG node.
5. **Post-turn write-back** — append new turn to Redis session store; async upsert any new facts to Pinecone; update episodic summary if session length exceeds token budget.

**Context budget management:**

```
Working (in-context):    ~2,000–8,000 tokens  (current turn + sliding window)
Episodic (injected):     ~500–1,500 tokens    (summary or last 3–5 turns)
Semantic (injected):     ~1,000–3,000 tokens  (RAG top-k chunks)
Procedural (system):     ~500–2,000 tokens    (stable system prompt instructions)
─────────────────────────────────────────────────────────────
Total context budget:    ~5,000–14,500 tokens of a ~1M-token window
```

### Example / Tradeoff
**LangGraph support agent:**
- Working memory: current ticket + tool outputs in the active ReAct scratchpad.
- Episodic: Redis hash `session:{user_id}:{ticket_id}` with 30-day TTL; LangGraph `PostgresSaver` for checkpointing resumable runs.
- Semantic: Pinecone index of 50K KB articles queried at turn start; updated nightly via Confluence webhook.
- Procedural: `billing_agent.system_prompt` hard-codes escalation SLA rules; LangChain `ConversationSummaryBufferMemory` triggers when episodic exceeds 4K tokens, summarising to ~300 tokens.

**Key tradeoff — episodic vs semantic boundary:**  
Facts that *generalise across users* (product docs, policies) belong in semantic memory (vector store). Facts that are *user-specific and session-scoped* (what the user just said, what tools were called) belong in episodic memory (session store). Mixing them — storing per-user session turns in Pinecone — causes privacy leakage and relevance pollution.

---

## Verbal script

**Opening (30s):**
"I'd frame agent memory in four tiers borrowed from cognitive science — working, episodic, semantic, and procedural — because each has fundamentally different storage needs and retrieval patterns. The design mistake I see most often is treating all memory as one big chat history buffer, which quickly blows the context window and creates privacy problems."

**Core explanation (2–3 min):**
"Working memory is just the active context window — the current turn, tool outputs, and a sliding window of recent messages. It's implicit: it's already in the prompt. You need to actively *budget* it: I typically reserve 2–8K tokens for working memory, leaving room for the other tiers.

Episodic memory is per-session state — what this user said in prior turns, what tools were called, what actions were taken. I store that in Redis keyed by session ID with a TTL that matches business requirements — say 30 days for support tickets. When a session gets long, I use LangChain's `ConversationSummaryBufferMemory` to compress old turns into a 300-token rolling summary rather than truncating blindly.

Semantic memory is the agent's general domain knowledge — product docs, KB articles, policies — stored in a vector database like Pinecone or Qdrant. It's retrieved via ANN search at the start of each turn: embed the user's query, pull top-k relevant chunks, inject into context. The critical operational point is keeping this index fresh via CDC — Confluence webhooks or nightly batch jobs. An agent giving answers from a six-month-old index is worse than no agent.

Procedural memory is *how* to do things — task-specific workflows, tool-call sequences, domain rules. This lives in the system prompt for stable policies, in LangGraph DAG nodes for multi-step workflows, or in LoRA-fine-tuned weights for behaviour you can't capture in prompt text. It's always-on or task-routed, not retrieved dynamically."

**Tradeoff / production angle (1 min):**
"The subtlest tradeoff is the episodic-vs-semantic boundary: user-specific session state must never go into the shared semantic vector store — that causes cross-user leakage and relevance noise. Another common pitfall is over-injecting from all four tiers simultaneously, exhausting your context window on boilerplate. I address this with a priority hierarchy: procedural first (stable, small), then semantic retrieval, then episodic summary, leaving the bulk of the window for working memory and LLM reasoning. At scale, the Redis session store becomes a hotspot — I shard by user_id modulo and set aggressive TTLs, and I use LangGraph's PostgresSaver for agents that need durable checkpointing across failures."

**Wrap-up (30s):**
"So the design principle is: four tiers, four backends, explicit budget allocation, and a strict boundary between user-scoped episodic state and shared semantic knowledge. Happy to go deeper on any tier — the procedural memory vs fine-tuning tradeoff is especially interesting."

---

## Pitfalls

- **Mistake:** Describing memory as "just storing the chat history in a list" without distinguishing session-scoped episodic state from shared semantic knowledge — **Better:** Explain all four types with their specific backends (Redis for episodic, Pinecone for semantic) and explain the privacy/relevance reason to separate them.
- **Mistake:** Saying "we put everything in the vector database" — conflating user-session state with domain knowledge causes cross-user data leakage and relevance pollution — **Better:** State explicitly that only generalizable, non-user-specific knowledge belongs in the semantic vector store; per-session state belongs in a keyed session store like Redis with TTLs.
- **Mistake:** Not mentioning context budget management — candidates describe all four types but don't explain how they fit into a finite token window — **Better:** Give a concrete token allocation (e.g. 2K working + 1K episodic summary + 2K semantic + 1K procedural) and explain the compression strategy (summarisation, top-k tuning) when budgets are exceeded.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q28: Long-term memory without polluting it?](03-028-long-term-memory-without-polluting-it.md) | Direct follow-up — applies the four-type taxonomy to the specific problem of long-term memory hygiene |
| [Q6: Essential components of an agent beyond an LLM?](03-006-essential-components-of-an-agent-beyond-an-llm.md) | Memory is one of the four core agent components — prerequisite framing |
| [Q18: Stateless vs stateful agents?](03-018-stateless-vs-stateful-agents.md) | Stateful agents require episodic memory backends; working memory is the stateless mode |

---

## One-liner recall

> Agents need four memory tiers — working (in-context window), episodic (Redis session store, per-user/session), semantic (Pinecone vector store, shared domain knowledge), and procedural (system prompt or fine-tuned weights for task workflows) — each with its own backend, lifetime, and strict privacy boundary.
