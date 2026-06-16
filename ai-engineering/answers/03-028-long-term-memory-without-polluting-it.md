# Long-term memory without polluting it?

**Category:** 03-agents-tool-use
**Question #:** 028
**Source section:** §3 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
Long-term memory is the bridge between stateless LLM calls and agents that actually learn from past interactions. Interviewers ask this to probe whether you understand that naive memory accumulation — appending every conversation turn forever — quickly degrades retrieval precision, inflates context windows, and introduces privacy/compliance risks. Strong candidates know both the storage architecture and the quality-control mechanisms that keep the memory store useful over time.

### Trigger phrases
- "How does your agent remember things across sessions without getting confused by irrelevant history?"
- "Walk me through how you'd build long-term memory for an agent."
- "How do you prevent memory pollution or stale facts corrupting agent responses?"
- "What's the difference between episodic memory and semantic memory in an agentic system?"

### What it tests
Whether you can design a memory architecture with explicit write gates, TTL policies, deduplication, and retrieval filters — not just "store embeddings in Pinecone."

---

## Answer

### Concept
Long-term memory lets an agent recall facts, preferences, and outcomes across sessions, but unbounded append-only memory degrades quality rapidly: stale facts override new ones, contradictions confuse retrieval, and PII accumulates. The solution is **structured memory with write gates** — only promoted, validated, deduplicated facts enter the long-term store, and TTL / conflict-resolution policies keep it clean over time.

### Mechanism

**Four-layer memory pipeline:**

1. **Extraction pass (what to remember)**
   - After each session or at HITL-approved checkpoints, run an LLM extraction prompt over the conversation: `"Extract durable facts, user preferences, and task outcomes as structured JSON."` 
   - Schema-enforce the output (Pydantic / JSON schema) so only typed facts (not raw text) enter storage.
   - Filter by confidence score: only persist facts where extraction confidence > 0.85.

2. **Deduplication & conflict resolution (clean write)**
   - Embed the candidate fact and query the long-term store (Pinecone / Qdrant) for near-duplicates (cosine > 0.92).
   - If a near-duplicate exists: compare timestamps and confidence scores. Newer + higher confidence wins; old record is soft-deleted (tombstoned, not hard-deleted, for audit trail).
   - Use an LLM judge for semantic contradiction: `"Do fact A and fact B contradict each other?"` — if yes, escalate to HITL or replace old with new and log the conflict.

3. **TTL & staleness decay**
   - Attach `created_at`, `last_confirmed_at`, and `ttl_days` metadata to every memory record.
   - Facts with TTL defaults by type: user preferences (180 days), task outcomes (90 days), entity facts (365 days with periodic re-confirmation).
   - A nightly job soft-deletes expired records and triggers re-confirmation requests for high-value memories approaching TTL.

4. **Filtered retrieval (avoid pollution at read time)**
   - At retrieval, filter by `user_id`, `session_scope`, and `recency_score` (decay-weighted similarity: `score = cosine_sim × e^(-λ × age_days)`).
   - Cap retrieved memory chunks at 3–5 items to avoid flooding the context window with low-relevance history.
   - Separate personal memory (per-user episodic store) from shared knowledge (cross-user semantic store) — prevent one user's context polluting another's.

**Storage stack:**
- Short-term working memory: in-context window (last N turns)
- Mid-term episodic: Redis with TTL (session state, last 7 days)
- Long-term semantic: Pinecone or Qdrant (extracted, deduplicated facts, user preferences)
- Structured facts: PostgreSQL or DynamoDB (schema-enforced entity data: user profile, account settings)

### Example / Tradeoff

**ChatGPT Memory (2024) pattern:** OpenAI's memory system follows this architecture — it runs an extraction LLM pass after sessions, stores structured facts per user, surfaces them at session start with a dedicated memory block, and lets users explicitly delete or correct memories. The key production insight: the extraction model (GPT-4o-mini) costs ~$0.002/session but prevents quality degradation that would require expensive model retraining or user churn from wrong personalization.

**Tradeoff: recall vs precision**
- High recall (write everything): memory grows unbounded, contradictions accumulate, retrieval noise grows, context pollution increases.
- High precision (write only high-confidence, deduplicated facts): smaller, cleaner store; retrieval stays relevant; but some useful context may be lost.
- Production default: err toward precision — a missed memory is a minor UX miss; a wrong memory actively harms the agent's reasoning.

**Mem0 (open-source):** Purpose-built memory layer that wraps LLMs with automatic extraction, deduplication, and TTL management. Drop-in alternative to rolling your own pipeline.

---

## Verbal script

**Opening (30s):**
"Long-term memory is powerful, but unbounded append-only storage is one of the most common ways agents degrade in production. My approach is to treat memory like a curated database — explicit write gates, deduplication, and TTL policies — rather than a raw conversation log."

**Core explanation (2–3 min):**
"I'd structure this as a four-stage pipeline. First, an *extraction pass* after each session: I run a small LLM over the conversation to pull out durable facts — user preferences, task outcomes, key entities — as typed JSON. I schema-enforce the output with Pydantic, and I only promote facts where extraction confidence exceeds 0.85.

Second, before writing to the long-term store, I run a *deduplication check*: embed the candidate fact, query Pinecone for near-duplicates above cosine 0.92, and if a near-duplicate exists, I compare timestamps and confidence to decide which wins. For semantic contradictions — 'user prefers Python' vs 'user prefers Go' — I either log the conflict and escalate to HITL, or automatically replace with the newer higher-confidence fact.

Third, every memory record gets TTL metadata: user preferences expire after 180 days, task outcomes after 90 days. A nightly job soft-deletes expired records — soft-delete because I need an audit trail.

Fourth, at retrieval time, I filter by user_id, apply a recency decay weight, and cap context injection at three to five memory items. This prevents context flooding from low-relevance history."

**Tradeoff / production angle (1 min):**
"The key design decision is write precision vs recall. If you write everything, the store grows unbounded and retrieval gets noisy. I prefer precision — only well-extracted, deduplicated facts — and accept that occasionally a useful memory is missed. A missed memory is a minor miss; a wrong memory actively corrupts the agent's reasoning and is much harder to debug. For regulated domains like healthcare, I'd also separate personal episodic memory from shared semantic memory at the storage layer to prevent cross-user data leakage."

**Wrap-up (30s):**
"So the short answer is: structured extraction, cosine-based deduplication, TTL policies, and capped retrieval with recency decay. If you want something off-the-shelf, Mem0 does most of this automatically. Happy to go deeper on the conflict-resolution logic or the TTL schema."

---

## Pitfalls

- **Mistake:** "Just store all conversation history in a vector database and retrieve the top-K" — **Better:** Explain that raw conversation chunks contain noise, greetings, and contradictions; you need an extraction pass to distill *facts* before storage, otherwise retrieval precision collapses as memory grows.
- **Mistake:** Treating all memories as equally permanent with no TTL or expiry — **Better:** Different fact types have different half-lives (preferences vs task outcomes vs entity facts); TTL policies prevent stale facts from corrupting future sessions, and soft-delete preserves the audit trail.
- **Mistake:** Storing one flat memory pool for all users — **Better:** Explicitly partition by `user_id` at the storage layer and at retrieval time enforce user-scoped filters; cross-user memory leakage is a privacy/compliance failure, not just a recall issue.
- **Mistake:** Not mentioning conflict resolution — **Better:** When two facts contradict (same attribute, different value), you need a defined policy: newer wins, higher-confidence wins, or HITL escalation; without this, the agent sees inconsistent context and hallucinates reconciliation.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q27: Types of memory: working, episodic, semantic, procedural?](03-027-types-of-memory-working-episodic-semantic-procedural.md) | Prerequisite — four-tier memory taxonomy this answer builds on |
| [Q18: Stateless vs stateful agents?](03-018-stateless-vs-stateful-agents.md) | Same concept — stateful persistence architecture, Redis vs Postgres checkpointing |
| [Q33: Filter PII before data reaches LLM?](03-033-filter-pii-before-data-reaches-llm.md) | Follow-up — PII must be scrubbed from memory writes; Presidio + extraction-phase redaction |

---

## One-liner recall

> Prevent memory pollution with an extraction-LLM write gate (typed JSON, confidence > 0.85), cosine-based deduplication in Pinecone, TTL by fact-type (90–365 days), and recency-decay-filtered retrieval capped at 3–5 items — never raw append-all.
