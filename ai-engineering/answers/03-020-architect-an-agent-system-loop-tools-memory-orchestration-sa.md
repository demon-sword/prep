# Architect an agent system: loop, tools, memory, orchestration, safety.

**Category:** 03-agents-tool-use
**Question #:** 020
**Source section:** §3 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
This is a **system design question** disguised as a conceptual one. The interviewer wants to see whether you can describe a complete, production-grade agentic system — not just "LLM + tool calls." They are probing architectural breadth (can you name every layer?), production instincts (how do you prevent cost explosions, infinite loops, and unsafe actions?), and multi-agent awareness (orchestration vs. choreography, how do agents hand off to each other?). A weak candidate describes a ReAct loop from a tutorial; a strong candidate draws a layered architecture with concrete tooling for each layer.

### Trigger phrases
- "Architect an agent system end-to-end"
- "Design an agentic AI platform from scratch"
- "What does a full agent system look like in production?"
- "Walk me through every component of your agent framework"

### What it tests
System-level architectural breadth: can you specify every layer of a production agent — loop, tool execution, memory, orchestration pattern, and safety controls — with concrete tooling and the right tradeoffs for each?

---

## Answer

### Concept
A production agent system is **five interlocking subsystems** — loop controller, tool layer, memory layer, orchestration layer (multi-agent), and safety/observability — that wrap the core LLM reasoning capability. The loop alone is never enough; each subsystem exists to contain a failure mode that the bare loop cannot handle.

### Mechanism

**1. Agent loop**

The loop is the perceive → plan → act → observe cycle. Every production loop must have:
- `max_iterations` (e.g. 15) — hard cap in orchestrator code, not a prompt instruction
- `wall_clock_timeout` (e.g. 120 s) — kills a hung tool call or runaway reasoning chain
- `max_tokens_per_step` (e.g. 2048) — prevents a single step from consuming the entire budget
- Structured action format: ReAct (`Thought / Action / Observation`) or JSON tool call — never free text
- Termination signals: `FINAL_ANSWER` tool call OR error/exception OR budget exhausted

Implementation: **LangGraph `StateGraph`** for DAG-shaped tasks (known steps); **custom Python loop** for open-ended ReAct; **CrewAI / AutoGen** for multi-agent with role specialization.

**2. Tool layer**

Every tool is a **typed contract**, not a Python function:
- JSON Schema with `name`, `description` (include concrete examples), `parameters` (constrained `enum` where possible, `required` fields explicit)
- Pre-call middleware: schema validation, input sanitization, auth/credential injection, PII scrub (Presidio)
- Execution sandboxing: user-facing code/shell tools run in **E2B** or **Docker** (seccomp + no-network-egress)
- Post-call: result truncated to `max_observation_tokens` (e.g. 1024) to prevent context flooding
- Retry policy: up to 3 attempts, exponential backoff, idempotency key on all write operations
- Tool allowlist enforced in orchestrator code — the LLM cannot call tools outside the declared set

**3. Memory layer (four tiers)**

| Tier | What's stored | Implementation | Lifecycle |
|------|--------------|----------------|-----------|
| Working | Current context window — messages, observations | Sliding window ≤8K tokens | Per step |
| Episodic | Session history — prior task summaries for this user | Redis (TTL 30 min) or Postgres | Per session |
| Semantic | Cross-session facts — user preferences, resolved cases, knowledge base | Pinecone / Qdrant vector store | Long-lived |
| Procedural | Agent's "how-to" — tool schemas, system prompt, hard-coded policies | System prompt / code | Static per deploy |

Retrieval: at session start, top-3 episodic summaries + top-5 semantic facts are injected into the system prompt (≈500 tokens). Working memory uses a sliding window that summarizes older turns via a small fast model before they fall off.

**4. Orchestration layer (multi-agent)**

For systems with more than one agent, choose **orchestration** (central controller knows all agents, routes tasks) vs. **choreography** (agents subscribe to events and self-coordinate):

| | Orchestration (LangGraph, AutoGen) | Choreography (event bus, Kafka) |
|---|---|---|
| Debuggability | High — central trace | Low — distributed events |
| Flexibility | Low — routes defined upfront | High — agents self-organize |
| Latency | Sequential by default | Parallel naturally |
| Best for | Support ticket triage, code review pipeline | Real-time alert processing, data enrichment |

For most enterprise use cases, **orchestration wins** because auditability and debuggability matter more than flexibility. Use a **supervisor agent** (a frontier model) that decomposes the goal and delegates to specialist sub-agents (retrieval agent, drafting agent, verification agent) via typed handoff messages.

**5. Safety & observability layer**

- **Structured trace per step**: `{run_id, step, thought, tool, args, observation, token_count, latency_ms, cost_usd}` — exported to LangSmith or Arize Phoenix
- **HITL gates**: LangGraph `interrupt_before` on irreversible tools (email send, DB write, code execution) — surfaces an approval widget; auto-approve after N seconds in low-stakes environments
- **Guardrails**: input/output NeMo Guardrails or Pydantic validators; Presidio PII scan on inputs AND observations before they re-enter the loop
- **Prompt injection defense**: sanitize user-controlled strings that reach tool args; never `eval()` user input; use structured tool calls not free-text commands
- **Checkpointing**: agent state (step index, observation history, memory) persisted in Redis after each successful step — resume from last checkpoint on worker crash
- **Cost monitoring**: `cumulative_cost_usd` tracked per run; hard budget cap (e.g. $0.50/run) kills the loop and escalates to human

### Example / Tradeoff

**Production example — multi-agent legal contract reviewer:**
- **Supervisor agent** (a frontier model): receives contract PDF, decomposes into clauses, routes each to specialist
- **Clause extraction agent** (a small fast model): PyMuPDF + chunking tool, extracts clause objects as structured JSON
- **Risk assessment agent** (a frontier model): for each clause, queries legal KB (Pinecone RAG), returns risk score + rationale
- **Drafting agent** (a frontier model): proposes redline language for high-risk clauses
- **HITL**: interrupt before any clause is marked "approved" — lawyer reviews in UI
- Stack: LangGraph multi-agent `StateGraph`, Redis episodic store, Pinecone semantic memory, LangSmith observability
- Outcome: 300 clauses reviewed in 4 min, lawyer reviews 12 flagged items (vs. reading all 300)
- Cost: $0.18/contract at 300 clauses, gated by $0.50 hard cap

**Key tradeoff — ReAct loop vs. LangGraph DAG:**
| | ReAct open loop | LangGraph DAG |
|---|---|---|
| Flexibility | High — any next step | Low — edges pre-defined |
| Debuggability | Low — dynamic branching | High — graph visualization |
| Cost control | Poor — unpredictable iterations | Good — bounded by graph shape |
| Best for | Open-ended research, coding agents | Support triage, document review, known pipelines |

**Decision rule:** default to a LangGraph DAG unless you have evidence the task genuinely needs open-ended exploration (debugging an unknown codebase, multi-hop research). Open loops should always have a `max_iterations` budget.

---

## Verbal script

**Opening (30s):**
"I'd architect this as five interlocking subsystems: the agent loop, the tool layer, the memory layer, an orchestration layer for multi-agent coordination, and a safety and observability layer. Each one exists to contain a specific failure mode that the bare LLM reasoning loop can't handle. Let me walk through each."

**Core explanation (2–3 min):**
"Starting with the **loop**: this is the perceive-plan-act-observe cycle. In production, the loop controller lives in orchestrator code — not a prompt — and enforces three hard limits: max iterations (say, 15), a wall-clock timeout (120 seconds), and a per-step token cap. The action format is structured — either ReAct JSON or a typed tool call — never free text. Termination triggers when the model emits a FINAL_ANSWER tool call, hits a budget cap, or the orchestrator detects a no-progress loop via action fingerprinting.

The **tool layer** is where safety lives. Every tool is a typed JSON schema — name, description with concrete examples, parameters with constrained enums. Pre-call middleware runs schema validation, PII scrubbing, and auth injection. Code tools run in E2B or Docker sandboxes with no network egress. Write operations always carry an idempotency key. Tool observations are truncated to a max token budget before re-entering the loop — otherwise a single web scrape floods the context.

**Memory** is four tiers: working memory is the sliding context window, episodic is Redis session state, semantic is a Pinecone vector store for cross-session facts, and procedural is the system prompt and tool schemas. At session start I inject top-3 episodic summaries and top-5 semantic hits — about 500 tokens — to give the agent continuity without bloating the context.

For **multi-agent orchestration**, I default to a centralized supervisor pattern: a frontier model supervisor decomposes the goal and routes typed tasks to specialist sub-agents. That's more debuggable and auditable than choreography — which works for event-driven pipelines but is hard to trace. LangGraph or AutoGen both support this pattern well.

Finally, **safety and observability**: every step emits a structured trace to LangSmith — step, tool, args, token count, latency, cost. HITL is wired via LangGraph interrupt_before for irreversible actions. Guardrails run on inputs and observations. And the agent state is checkpointed in Redis after each successful step so a worker crash doesn't lose progress."

**Tradeoff / production angle (1 min):**
"The most consequential architectural decision is: LangGraph DAG vs. open ReAct loop. If the task graph is knowable at design time — like a three-stage review pipeline — I use a DAG: bounded cost, easy to visualize, easy to test. If the task genuinely requires dynamic step selection — like a coding agent that doesn't know how many debug iterations it'll need — I use an open loop with a hard budget cap. I've seen teams default to open loops and then struggle to contain cost at scale; the DAG-first approach forces you to think through the workflow, which usually exposes scope you hadn't considered."

**Wrap-up (30s):**
"So the production agent system is mostly about the infrastructure surrounding the LLM: loop budget enforcement, typed tool contracts, four-tier memory management, orchestration pattern selection, and step-level observability with HITL on irreversible actions. The LLM is the reasoning engine, but the five layers around it are what make it reliable. Happy to go deeper on any layer."

---

## Pitfalls

- **Mistake:** Describing "an LLM calling tools in a loop" and stopping there, with no mention of budget caps, HITL, or sandboxing — **Better:** Lead immediately with the three production guardrails — `max_iterations`, wall-clock timeout, and HITL gates for irreversible actions — and explain that without these, agents loop indefinitely, rack up unbounded costs, and take irreversible real-world actions with no human approval.
- **Mistake:** Treating memory as "just the chat history passed in the prompt" — **Better:** Describe the four memory tiers explicitly: working (sliding window), episodic (Redis TTL), semantic (vector store retrieval), and procedural (system prompt). Explain that stuffing all history into the context window blows the budget and degrades quality; retrieval-based episodic and semantic memory are the production pattern.
- **Mistake:** Ignoring multi-agent orchestration and treating the question as single-agent only — **Better:** Proactively raise the orchestration vs. choreography distinction; explain the supervisor-specialist pattern and when you'd use a centralized DAG versus an event-driven choreography, with specific tooling (LangGraph, AutoGen, Kafka).

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q8: Walk through a production-ready agent architecture.](03-008-walk-through-a-production-ready-agent-architecture.md) | prerequisite — single-agent detail; Q20 extends to multi-agent orchestration |
| [Q32: Orchestration vs choreography for multi-agent systems?](03-032-orchestration-vs-choreography-for-multi-agent-systems.md) | follow-up — deep dive on the multi-agent coordination pattern raised here |
| [Q27: Types of memory: working, episodic, semantic, procedural?](03-027-types-of-memory-working-episodic-semantic-procedural.md) | follow-up — deep dive on the four memory tiers from the memory layer |

---

## One-liner recall

> Architect a production agent as five subsystems: a loop controller with hard budget caps (max_iterations + wall-clock + cost ceiling), a typed sandboxed tool layer (JSON schema + idempotency + E2B), four-tier memory (working/episodic-Redis/semantic-Pinecone/procedural), a supervisor-specialist orchestration pattern (LangGraph DAG for known pipelines, open ReAct for exploration), and step-level observability with HITL gates on irreversible actions.
