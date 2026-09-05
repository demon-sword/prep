# Walk through a production-ready agent architecture.

**Category:** 03-agents-tool-use
**Question #:** 008
**Source section:** §3 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
The interviewer is testing whether you have actually *shipped* an agent system — not just prototyped one with LangChain in a notebook. Production-ready implies you've reasoned about failure modes (infinite loops, cost explosions, tool errors), observability (how do you debug a multi-step trace?), safety (HITL, sandboxing, prompt injection), and rollback. Candidates who describe a bare ReAct loop with no guardrails signal prototype-level experience.

### Trigger phrases
- "Walk me through how you'd architect an agent for production"
- "What does a production agent look like beyond the demo?"
- "How would you design an agentic system that's actually reliable?"

### What it tests
Depth of production agent experience: can you describe every layer — loop, tools, memory, orchestration, observability, safety — with concrete tooling and tradeoffs?

---

## Answer

### Concept
A production-ready agent is a **stateful perceive → plan → act → observe loop** wrapped in an **orchestration layer** that enforces budget caps, HITL triggers, retry semantics, checkpointing, and distributed tracing — on top of the core ReAct or Plan-and-Execute reasoning pattern.

### Mechanism

The architecture has **six layers**, each with a distinct responsibility:

**1. Interface / Session layer**
- Accepts user input; manages session ID and conversation state
- Routes to agent loop; returns streamed SSE/WebSocket responses
- Tools: FastAPI + Redis session store (TTL 30 min)

**2. Orchestrator / Loop controller**
- Runs the agent step loop; enforces hard limits
- Config: `max_iterations=15`, `max_tokens_per_step=2048`, `wall_clock_timeout=120s`
- On each step: calls LLM → parse action → dispatch tool → inject observation → repeat
- Termination: goal-completion signal OR budget exhausted OR HITL escalation
- Tools: LangGraph (`StateGraph`), custom Python loop, or CrewAI depending on multi-agent needs

**3. LLM reasoning layer**
- A frontier model (or a frontier model) for planning/synthesis steps requiring deep reasoning
- A small fast model for routing, tool-arg generation, and simple extraction (3–5× cheaper)
- Prompt: system persona + tool schema + conversation history (sliding window ≤8K tokens) + current observation
- Temperature: 0.0 for deterministic tool dispatch; 0.7 for open-ended synthesis

**4. Tool execution layer**
- Tools are JSON-schema–typed functions with `name`, `description`, `parameters` (required fields, constrained enums, concrete examples in `description`)
- Pre-call middleware: schema validation, input sanitization, auth/credential injection, PII scrub
- Execution: sandboxed for code/shell (E2B or Docker with seccomp + network egress restrictions)
- Post-call: result truncation to `max_observation_tokens` (avoids context pollution), error normalization
- Retry policy: up to 3 retries with exponential backoff for transient errors; idempotency key for write operations

**5. Memory layer**
- **Working memory**: current context window — sliding window keeps last N messages + system prompt
- **Episodic memory**: Redis or PostgreSQL — stores prior task summaries; retrieved by session_id on continuation
- **Semantic memory**: vector store (Pinecone/Qdrant) — long-term user facts and past resolved cases retrieved via similarity search
- **Procedural memory**: hard-coded tool definitions and system prompt — how the agent "knows" what to do

**6. Observability & Safety layer**
- Every step emits a structured trace: `{step, action, tool, args, observation, token_count, latency_ms}`
- Traces exported to LangSmith or Arize Phoenix; dashboards on step count distribution, tool error rate, task completion rate
- HITL triggers: LangGraph `interrupt_before` on irreversible tools (email send, DB write) or when confidence < threshold
- Guardrails: NeMo Guardrails or custom Pydantic validators on output; Presidio for PII on both inputs and observations
- Rollback: agent state checkpointed at each successful step (Redis); resume from last checkpoint on crash

### Example / Tradeoff

**Support-ticket routing agent (production example):**
- Stack: LangGraph `StateGraph` + a small fast model (routing) + a frontier model (drafting) + 5 tools (ticket_lookup, kb_search, draft_response, escalate_to_human, update_ticket_status)
- HITL: `interrupt_before(['update_ticket_status', 'escalate_to_human'])` — human approves any status change
- Checkpointing: Redis-backed `MemorySaver` — restart from last good step on worker crash
- Observability: LangSmith trace per ticket; p95 step count = 4, p95 wall-clock = 8s, cost/ticket ≈ $0.012
- The hardest production issue: agents that "decide they're done" too early when the KB returns no results — fixed by adding an explicit `no_results_found` observation branch that forces escalation

**Key tradeoff — LangGraph DAG vs open-ended ReAct loop:**
| | LangGraph DAG | ReAct loop |
|---|---|---|
| Debuggability | High (fixed edges) | Low (dynamic branching) |
| Flexibility | Low (graph must be pre-defined) | High (any next step) |
| Cost predictability | High | Low |
| Best for | Known step sequences | Unknown-depth exploration |

---

## Verbal script

**Opening (30s):**
"I'd structure this as six distinct layers: an interface/session layer, a loop controller with hard budget caps, a tiered LLM reasoning layer, a sandboxed tool execution layer, a multi-tier memory system, and an observability and safety layer. Let me walk through each."

**Core explanation (2–3 min):**
"Starting at the top — the **interface layer** accepts user input, creates or resumes a session stored in Redis, and streams the response back. Below that is the **loop controller** — this is where I'd enforce hard limits: max 15 iterations, a wall-clock timeout of 120 seconds, and a per-step token budget. Without these, you get cost explosions in production.

The **LLM layer** is tiered: a small fast model for tool dispatch and argument generation, a frontier model for synthesis or planning steps that need deep reasoning — about a 3–5× cost difference. Both use temperature 0 for deterministic tool calls. The prompt is: system persona + typed tool schemas + sliding window of the last N turns + the current observation.

The **tool layer** is critical for safety. Every tool has a strict JSON schema with constrained enums and concrete examples in the description — this alone cuts hallucinated tool args by 40–60%. Pre-call middleware runs schema validation, PII scrubbing via Presidio, and auth injection. Write operations go through sandboxed execution — E2B or Docker with network egress restricted. Every write tool gets an idempotency key, and retries use exponential backoff up to 3 attempts.

**Memory** is four-tier: working memory in the context window with a sliding window cap, episodic memory in Redis for session continuity, semantic memory in Pinecone for cross-session knowledge retrieval, and procedural memory baked into the system prompt and tool definitions.

**Observability**: every step emits a structured trace to LangSmith — step number, tool called, latency, token count. HITL is wired via LangGraph's `interrupt_before` — any irreversible action like sending an email or writing to a DB pauses the loop and surfaces an approval widget."

**Tradeoff / production angle (1 min):**
"The hardest call in production is: LangGraph DAG vs open-ended ReAct. If the task graph is knowable at design time — fixed sequence with routing — I'd use a DAG: more debuggable, cheaper, easier to test. If the step count is genuinely unknown at design time, I'd use a ReAct loop with a hard budget cap. I'd default to DAG and only move to open-loop when I have evidence the task needs it."

**Wrap-up (30s):**
"So the production version is less about the LLM and more about the six layers around it — loop control, tool safety, memory management, and step-level observability. Happy to go deeper on any layer — HITL patterns, memory architecture, or multi-agent orchestration."

---

## Pitfalls

- **Mistake:** Describing a ReAct loop with no budget caps, no HITL, no sandboxing — "just an LLM calling tools" — **Better:** Immediately lead with the three required production guardrails — `max_iterations`, HITL trigger for irreversible actions, and sandboxed execution for code/write tools; explain that without these, agents loop indefinitely and rack up unbounded costs.
- **Mistake:** Using a frontier model for every step in the loop without mentioning model tiering — **Better:** Distinguish routing/dispatch steps (a small fast model, cheap) from reasoning/synthesis steps (a frontier model), and explain how model tiering cuts cost per task by 60–80% without sacrificing quality.
- **Mistake:** Treating memory as "just the context window" — **Better:** Describe the four memory types (working/episodic/semantic/procedural) and explain that a production agent retrieves relevant past context from Pinecone/Redis rather than stuffing everything into one prompt, which would blow the context window and inflate cost.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q6: Essential components of an agent beyond an LLM?](03-006-essential-components-of-an-agent-beyond-an-llm.md) | prerequisite — covers each component this architecture assembles |
| [Q9: What logic belongs in orchestrator vs LLM?](03-009-what-logic-belongs-in-orchestrator-vs-llm.md) | follow-up — digs into the orchestrator/LLM boundary within this architecture |
| [Q20: Architect an agent system: loop, tools, memory, orchestration, safety](03-020-architect-an-agent-system-loop-tools-memory-orchestration-sa.md) | same concept, system-design framing — broader scope including multi-agent |

---

## One-liner recall

> A production agent wraps the ReAct loop in six layers — session/interface, loop controller (max_iterations + wall-clock timeout), tiered LLM (a small fast model for dispatch, a frontier model for synthesis), sandboxed tool execution (E2B/Docker + idempotency keys), four-tier memory (working/episodic/semantic/procedural in Redis+Pinecone), and step-level observability with HITL on irreversible actions via LangGraph `interrupt_before`.
