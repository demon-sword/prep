# Stateless vs stateful agents?

**Category:** 03-agents-tool-use
**Question #:** 018
**Source section:** §3 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
The interviewer is probing whether you understand production agent architecture — specifically how session context, cost, and failure-recovery tradeoffs inform the choice between stateless and stateful designs. It surfaces experience with real multi-turn agent deployments where state management becomes the dominant engineering challenge.

### Trigger phrases
- "How does your agent remember what happened in earlier steps?"
- "What happens if your agent crashes mid-task — does it restart from scratch?"
- "How do you handle multi-turn conversations in your agent?"
- "Walk me through how you'd architect a long-running agent that needs to pick up where it left off."

### What it tests
Whether you can articulate the memory/cost/resilience tradeoff and name concrete storage backends — not just say "stateful is better."

---

## Answer

### Concept
A **stateless agent** treats each invocation as independent — it receives the full context it needs in the prompt and produces a response with no memory of prior turns. A **stateful agent** maintains persistent state between invocations — session history, intermediate results, tool outputs — stored externally (Redis, Postgres, a vector store) and loaded selectively per turn. The choice is fundamentally a tradeoff between simplicity/scalability and resilience/continuity.

### Mechanism

**Stateless agent pattern:**
- Each API call includes the full conversation history in the prompt (up to the context window)
- No external storage required; trivially horizontally scalable
- Fails on: long tasks (context window overflow), crash recovery (all progress lost), cost (resending full history every turn)
- Best for: short-lived Q&A, single-turn tool calls, simple chatbots under ~10 turns

**Stateful agent pattern:**
- Orchestrator writes state to an external store after every step:
  - **Working memory (in-context):** last N turns + current plan, loaded from Redis/Postgres
  - **Episodic memory (vector store):** past task summaries, searchable by semantic similarity (Pinecone, Qdrant)
  - **Checkpoints:** full agent state snapshot after each tool call — enables resume on crash
- On resume: load checkpoint, inject last-N turns, continue from the saved step index
- Best for: multi-step research tasks, long-horizon agentic workflows (>10 turns), tasks requiring crash recovery, regulated domains needing audit trails

**Implementation with LangGraph:**
```python
# Checkpointed stateful loop
from langgraph.checkpoint.postgres import PostgresSaver
checkpointer = PostgresSaver(conn)
graph = agent_graph.compile(checkpointer=checkpointer)

# Resume: pass same thread_id — graph replays from last saved state
result = graph.invoke(input, config={"configurable": {"thread_id": "task-42"}})
```

### Example / Tradeoff

| Dimension | Stateless | Stateful |
|-----------|-----------|----------|
| Horizontal scaling | Trivial — no shared state | Requires external store; read-your-writes consistency |
| Crash recovery | Zero — restart from scratch | Resume from last checkpoint |
| Context window usage | Full history each call → window pressure | Selective load (last N turns + summary) → cheaper |
| Cost at scale | High — resend full history every turn | Lower — only load what's needed |
| Complexity | Low | High — cache invalidation, TTL, storage ops |
| Audit trail | None | Full step-by-step log in Postgres/Redis |

**Concrete example:** A support-ticket resolution agent handling 1,000 concurrent sessions. Stateless: each of 10 turns resends ~8K tokens of history → 80K tokens/session × 1K sessions = 80M tokens/day just for context, plus no crash recovery. Stateful: Redis stores last-3-turn window (∼2K tokens) + Postgres checkpoint per step; crash recovery reloads from step N-1; total context tokens drop ~60%; audit log satisfies compliance requirement.

The breaking point: once a task exceeds ~5 turns or takes >30 seconds wall-clock, stateless becomes untenable. At 10 turns with 2K tokens/turn, full-history injection hits 20K tokens — expensive and approaching window limits for smaller models.

---

## Verbal script

**Opening (30s):**
"The stateless vs stateful distinction comes down to where you store the agent's working memory — in the prompt or externally. I'll walk through both patterns, when each is appropriate, and the production tradeoffs that drive the choice."

**Core explanation (2–3 min):**
"A stateless agent is simple: every call gets the full conversation history stuffed into the prompt. No external storage, trivially scalable, but two problems emerge quickly. First, context window pressure — at 10 turns with 2K tokens each you're at 20K tokens per call, just for history. Second, zero crash recovery — if the agent dies at step 7 of 10, you restart from scratch.

A stateful agent externalizes that memory. After every step, the orchestrator checkpoints state to something like Redis for the recent window and Postgres for the full audit log. When the next turn starts, you load just the last three turns plus a rolling summary — maybe 2K tokens instead of 20K. And if the agent crashes, you resume from the last checkpoint via a thread ID, picking up at step N minus one.

In LangGraph this is built-in with the PostgresSaver checkpointer — you compile the graph with it and pass the same thread_id on resume. The graph replays confirmed steps from the journal and only re-executes from the failure point."

**Tradeoff / production angle (1 min):**
"The cost side is significant. If I have 1,000 concurrent agent sessions at 10 turns each and every turn resends 8K tokens of history, that's 80M context tokens per day — at $0.15/1M that's $12/day just for context overhead. Stateful with selective loading drops that to roughly 20M tokens, a 75% reduction.

The complexity cost is real too — now I need Redis TTLs, cache invalidation, Postgres schema migrations, and consistent reads across replicas. So my heuristic is: stateless for tasks under 5 turns or under 30 seconds, stateful for anything longer or in regulated domains where you need the audit trail."

**Wrap-up (30s):**
"So the answer is: stateless for simplicity and short tasks, stateful when you need crash recovery, cost efficiency at scale, or audit trails. The key engineering question is where you draw the checkpoint boundary — after each tool call is usually the right granularity. Happy to go deeper on checkpoint storage options or the LangGraph implementation."

---

## Pitfalls

- **Mistake:** Saying "stateful agents are always better because they have memory" — **Better:** Explain that stateless is the right default for short tasks; stateful adds storage complexity, cache invalidation risk, and consistency requirements that aren't worth it for simple Q&A or single-turn workflows.
- **Mistake:** Treating "stateful" as just "store the full chat history in a DB and reload it every turn" — **Better:** Explain selective loading (last N turns + rolling summary), checkpoint granularity (per-step vs per-session), and episodic memory (vector store for semantically relevant past context) as distinct mechanisms that prevent context bloat.
- **Mistake:** Ignoring crash recovery as a stateful benefit — **Better:** Name checkpoint-based resumability explicitly: "If the agent dies at step 7 of 10, stateful lets me resume from step 6 via thread_id; stateless means restart from zero — unacceptable for a 30-minute task."

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q6: Essential components of an agent beyond an LLM?](03-006-essential-components-of-an-agent-beyond-an-llm.md) | Memory taxonomy (working/episodic/semantic/procedural) underpins stateful agent design |
| [Q27: Types of memory: working, episodic, semantic, procedural?](03-027-types-of-memory-working-episodic-semantic-procedural.md) | Direct extension — maps memory types to stateful storage backends |
| [Q10: Design a safe and debuggable agent loop](03-010-design-a-safe-and-debuggable-agent-loop.md) | Checkpointing for resumability is a core safety/debuggability mechanism |

---

## One-liner recall

> Stateless agents inject full history into every prompt (simple, no recovery); stateful agents checkpoint to Redis/Postgres after each step (crash-resilient, 60–75% lower context cost at scale, needed for audit trails) — choose stateful once tasks exceed ~5 turns or 30 seconds.
