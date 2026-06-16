# Design a safe and debuggable agent loop.

**Category:** 03-agents-tool-use
**Question #:** 010
**Source section:** §3 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
This question tests whether the candidate can move beyond "just call the LLM in a loop" and articulate the production-grade controls that prevent runaway costs, infinite loops, silent failures, and unauditable behavior. Interviewers want to see concrete engineering decisions — not just conceptual awareness.

### Trigger phrases
- "How would you design an agent loop that's safe enough to run in production?"
- "Walk me through how you'd make an agent system debuggable."
- "What guardrails do you put around an autonomous agent?"

### What it tests
Whether the candidate can engineer a loop that is bounded, observable, and recoverable — applying deterministic controls at the orchestrator layer so the stochastic LLM can't cause unauditable or unbounded behavior.

---

## Answer

### Concept
A **safe and debuggable agent loop** is a structured execution harness that wraps LLM calls with hard limits, structured logging, idempotent tool execution, and human-in-the-loop (HITL) gates — so that any run can be replayed, audited, and interrupted without side effects. Safety and debuggability are two sides of the same coin: a loop that is observable is inherently safer because deviations are caught early.

### Mechanism

The loop has five layers:

**1. Bounded execution (hard limits in orchestrator code)**
```
max_iterations = 10          # absolute step ceiling
wall_clock_timeout = 30s     # kills hung tool calls
max_tokens_per_step = 2000   # prevents context bloat per turn
cumulative_token_budget = 20K # total session ceiling
```
These limits live in orchestrator code, not the prompt — the LLM cannot override them.

**2. Structured trace logging (every turn)**
Each iteration emits a structured JSON event:
```json
{
  "run_id": "uuid",
  "step": 3,
  "thought": "...",
  "action": {"tool": "search_kb", "args": {...}},
  "observation": "...",
  "token_count": 312,
  "latency_ms": 420
}
```
`run_id` is threaded through every LLM call and tool execution — this is the key to replaying or debugging any run in LangSmith / OpenTelemetry.

**3. HITL gates before irreversible actions**
The orchestrator classifies tools as *read* vs *write*:
- Read tools (search_kb, get_order) → proceed automatically
- Write tools (send_email, charge_card, delete_record) → emit a HITL checkpoint

In LangGraph: `interrupt_before(["send_email", "charge_card"])` pauses the graph, persists state to Redis/Postgres, and surfaces the pending action to a human approval queue. The graph resumes once approved or is cancelled.

**4. Idempotent tool execution with retries**
Tools must be safe to call twice (idempotent) — either by nature (reads) or by design (upserts, deduplication keys). The orchestrator wraps tool calls:
```
try:
    result = call_tool(action, timeout=5s)
except ToolTimeout:
    result = call_tool(action, timeout=5s)  # single retry
except ToolError:
    return structured_error_to_llm(action, error)  # LLM corrects next turn
```
Tool failures return a structured error to the LLM rather than raising to the user — the LLM can attempt recovery (different args, different tool) before the orchestrator gives up.

**5. Checkpointed state persistence**
After every step, the full agent state (messages, tool_results, step_count) is written to Redis (or Postgres for durable runs). This enables:
- **Resumability** — restart after crash without re-running completed steps
- **Replay** — reproduce any past run from the checkpoint log
- **Observability** — ops team can inspect in-flight agent state

LangGraph's built-in checkpointer (`SqliteSaver` / `PostgresSaver`) implements this natively.

### Example / Tradeoff

**Support-ticket agent (LangGraph + LangSmith):**

```
Loop iteration (LangGraph node):
  1. LLM call (GPT-4o-mini, T=0, ReAct format)  ← traced with LangSmith run_id
  2. Orchestrator parses tool call JSON
  3. Allowlist check: tool ∈ {search_kb, get_order, escalate}?  ← rejects unknown tools
  4. HITL gate: is tool "escalate"?  → interrupt_before, await human
  5. Tool execution (timeout=5s, one retry)
  6. Observation appended to message history
  7. Step counter incremented; check max_iterations, wall_clock, token budget
  8. Checkpoint written to Redis
  → repeat or terminate
```

**Tradeoff — safety vs throughput:**
- HITL gates add latency (minutes for human approval vs milliseconds). Scope them tightly — only irreversible, high-stakes actions.
- Checkpointing adds ~5–20ms per step (Redis round-trip). Acceptable for agent workloads; skip for latency-critical sub-second chains.
- Structured logging doubles the token and storage overhead per run. Use sampling (log 100% of errors, 10% of successes) for cost control at scale.

---

## Verbal script

**Opening (30s):**
"Designing a safe agent loop is really about preventing four failure modes: runaway cost, infinite loops, unauditable behavior, and irreversible side effects. I'll walk through the five layers I put around any production agent loop."

**Core explanation (2–3 min):**
"Layer one is hard limits in orchestrator code — `max_iterations`, a wall-clock timeout, a per-step token cap, and a cumulative session token budget. These are enforced in Python, not in the prompt, so the LLM can never negotiate its way past them.

Layer two is structured trace logging. Every iteration emits a JSON event with the run ID, step number, the LLM's thought, the action it chose, the tool observation, and token counts. Threading a `run_id` through every call means I can pull the entire trace for any run in LangSmith and replay it step by step.

Layer three is HITL gates. I classify all tools as read (safe to auto-execute) or write (irreversible). Write tools — send email, charge card, delete record — trigger an `interrupt_before` in LangGraph that pauses the graph, persists state to Redis, and puts the pending action into an approval queue. The graph only resumes once a human approves or cancels.

Layer four is idempotent tool execution with retries. Every tool call has a 5-second timeout and a single retry. On failure, I return a structured error message to the LLM — it gets a chance to recover — rather than surfacing to the user immediately.

Layer five is checkpointed state. After every step, the full agent state is written to Redis or Postgres. This means a crashed agent can resume from the last checkpoint, and ops can inspect any in-flight run."

**Tradeoff / production angle (1 min):**
"The tradeoffs are real. HITL gates can add minutes of latency — so I scope them tightly to genuinely irreversible actions. Checkpointing adds 5–20ms per step, which is fine for agent workloads but I'd skip it for sub-second chains. And full trace logging can be expensive — at scale I sample: log 100% of errors and 10% of successful runs.

The deeper tradeoff is debuggability vs throughput. Rich logging, HITL gates, and checkpointing all add overhead. But in production the cost of an undebuggable or out-of-control agent is far higher than the overhead of observability."

**Wrap-up (30s):**
"So the pattern is: bound it with hard limits in code, make it observable with structured traces and a run ID, gate irreversible actions behind HITL, make tools idempotent with retries, and checkpoint state so any run is resumable and replayable. LangGraph plus LangSmith implements most of this natively. Happy to go deeper on any layer."

---

## Pitfalls

- **Mistake:** Relying on the prompt to enforce safety ("only escalate if the user confirms") — **Better:** Irreversible-action gates must live in the orchestrator as `interrupt_before` nodes or equivalent code; the LLM can be jailbroken or simply hallucinate, so policy enforcement must be outside the LLM's control path.
- **Mistake:** No run ID or structured logging — debugging by reading raw LLM message histories — **Better:** Thread a `run_id` (UUID) through every LLM call, tool call, and checkpoint; every step emits a structured JSON event so any run can be replayed or filtered in LangSmith/OpenTelemetry without manually reconstructing what happened.
- **Mistake:** Non-idempotent tools without retry handling — tool failure raises directly to the user — **Better:** Wrap every tool call with a timeout and a single retry; on persistent failure, return a structured error object to the LLM so it can attempt recovery (different args, fallback tool) before the orchestrator escalates.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q9: What logic belongs in orchestrator vs LLM?](03-009-what-logic-belongs-in-orchestrator-vs-llm.md) | Prerequisite — the principle behind where loop controls live |
| [Q14: Detect and stop infinite planning loops](03-014-detect-and-stop-infinite-planning-loops.md) | Follow-up — specific mechanisms for loop detection |
| [Q29: Human-in-the-loop patterns — when trigger human review?](03-029-human-in-the-loop-patterns-when-trigger-human-review.md) | Follow-up — HITL gate design in detail |

---

## One-liner recall

> A safe agent loop has five layers: hard limits in orchestrator code (max_iterations, wall-clock, token budget), structured trace logging with a threaded run_id, HITL interrupt_before gates on irreversible tools, idempotent tool execution with retries, and checkpointed state for resumability — all enforced in the orchestrator, never in the prompt.
