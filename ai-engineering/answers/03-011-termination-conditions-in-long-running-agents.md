# Termination conditions in long-running agents?

**Category:** 03-agents-tool-use
**Question #:** 011
**Source section:** §3 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
Interviewers probe whether you know how to prevent runaway agents in production. Long-running agentic loops are the #1 cause of runaway costs and stuck pipelines. A strong candidate distinguishes *why* a task ends (success, failure, stuck, budget) and shows how each condition is enforced in code — not just in the prompt.

### Trigger phrases
- "How do you prevent an agent from running forever?"
- "What termination conditions do you set in your agent loop?"
- "Walk me through how your agent knows when to stop."
- "What happens if your agent gets stuck in a loop?"

### What it tests
Whether the candidate can design a safe, bounded agent loop with layered termination logic enforced in orchestrator code, not prompt instructions alone.

---

## Answer

### Concept
A long-running agent needs at least four independent stopping conditions: a **success signal** (task complete), a **failure/error signal** (unrecoverable state), a **budget ceiling** (max iterations and/or max tokens), and a **wall-clock timeout** (real-time deadline). Relying on any single condition leads to stuck or runaway agents in production.

### Mechanism
Termination conditions are enforced at three layers:

**1. Orchestrator hard limits (code-level — cannot be bypassed by the LLM)**
- `max_iterations`: e.g. 15–25 steps; rejects the next LLM call and emits `TIMEOUT_ITERATIONS`.
- `max_tokens_budget`: cumulative token counter across all calls in the run; kills the loop if exceeded.
- `wall_clock_timeout`: `asyncio.wait_for` or a background watchdog thread; emits `TIMEOUT_WALL_CLOCK`.

**2. LLM-generated termination signals (structured output)**
- Require the model to emit a typed `action` field: `{ "action": "FINISH", "result": "..." }` or `{ "action": "CLARIFY", "question": "..." }` or `{ "action": "ESCALATE", "reason": "..." }`.
- Instruct via ReAct format: `Final Answer:` token pattern triggers loop exit.
- Never rely on the model saying "I'm done" in free text — parse structured output.

**3. State-based stuck detection (orchestrator monitors progress)**
- Track a `last_new_information_at` counter. If the last N actions produced no new observations (same tool, same args, same result), flag as `STUCK` and either trigger HITL or abort.
- Idempotent retry budget: if a tool fails 3× in a row, escalate rather than retry infinitely.

**Termination taxonomy:**

| Signal | Trigger | Action |
|--------|---------|--------|
| `FINISH` | LLM emits Final Answer | Return result, close run |
| `ERROR_UNRECOVERABLE` | Tool throws non-retryable exception | Log, return error payload |
| `TIMEOUT_ITERATIONS` | `step >= max_iterations` | Return partial result + escalate |
| `TIMEOUT_WALL_CLOCK` | Real time > deadline | Return partial result + alert |
| `STUCK` | No new info in last K steps | HITL trigger or abort |
| `BUDGET_EXCEEDED` | Token count > max_budget | Return partial result + cost warning |

### Example / Tradeoff
In LangGraph, termination is modeled as conditional edges. A `should_continue` function checks the state dict after each node and routes to `END` or the next node:

```python
def should_continue(state: AgentState) -> str:
    if state["step"] >= MAX_STEPS:
        return "end"
    if state["finish_reason"] == "FINISH":
        return "end"
    if state["consecutive_no_progress"] >= 3:
        return "escalate_hitl"
    return "continue"

graph.add_conditional_edges("agent", should_continue, {
    "continue": "tools",
    "end": END,
    "escalate_hitl": "human_review",
})
```

For a customer support agent, `max_iterations=15`, `wall_clock_timeout=30s`, and stuck detection after 3 identical tool calls. Exceeding any ceiling routes to a canned escalation response rather than silently hanging.

**Tradeoff:** Tighter limits (lower `max_iterations`) improve cost predictability but increase false-positive timeouts on legitimately complex tasks. Production solution: tiered limits — `max_iterations=10` for Tier 1 (a small fast model), override to `25` for Tier 2 (a frontier model) on escalated tasks.

---

## Verbal script

**Opening (30s):**
"Termination conditions are one of the most important safety mechanisms in any production agent. I think about them in terms of four independent failure modes: success, error, budget exhaustion, and getting stuck. The key is that all of these need to be enforced in orchestrator code — not just instructed in the prompt — because an LLM can always fail to output the signal you asked for."

**Core explanation (2–3 min):**
"I layer three types of termination. First, hard limits in the orchestrator: a `max_iterations` counter, a cumulative token budget, and a wall-clock timeout via `asyncio.wait_for`. These are checked before every LLM call — if any is exceeded, we exit immediately and return a partial result or escalate.

Second, structured success and failure signals from the model. I require the LLM to emit a typed action field — something like `{ 'action': 'FINISH', 'result': '...' }` or `{ 'action': 'ESCALATE', 'reason': '...' }`. In a ReAct loop this maps to the `Final Answer:` token. I parse these in code, not in a regex on free text.

Third, a progress monitor for 'stuck' detection. I track whether the last K actions produced any new information. If the agent is calling the same tool with the same arguments and getting the same result three times in a row, that's a stuck state — I route to HITL rather than letting it loop.

In LangGraph, all of this lives in a `should_continue` conditional edge function that's evaluated after every node."

**Tradeoff / production angle (1 min):**
"The tension is between tight limits — which control cost and prevent runaway — and flexibility for legitimately complex tasks. My solution is tiered limits: default `max_iterations=15` for fast-path a small fast model tasks, and an escalation path that re-issues the same task with `max_iterations=30` and a frontier model if the first attempt hits a limit and the task is high-value. I also instrument every termination event with its reason code so I can monitor the distribution — if I'm seeing 20% `TIMEOUT_ITERATIONS`, my limit is too tight or the tasks are mis-scoped."

**Wrap-up (30s):**
"The summary is: four independent termination conditions (success, error, budget, stuck), enforced in orchestrator code, with structured output for success/failure signals and progress monitoring for stuck detection. Happy to go deeper on any of these layers."

---

## Pitfalls

- **Mistake:** Relying on prompt instructions alone ("respond with DONE when finished") — **Better:** Enforce `max_iterations` and `wall_clock_timeout` in orchestrator code; the LLM can always fail to emit the signal, so prompt-only termination is not a safety guarantee.
- **Mistake:** Using a single termination condition (only `max_iterations`) — **Better:** Layer all four: success signal, error signal, iteration cap, and wall-clock timeout, because each catches a different failure mode (e.g. a hung tool call never increments the iteration counter).
- **Mistake:** Not monitoring *why* agents terminated — **Better:** Instrument every exit with a reason code (`FINISH`, `TIMEOUT_ITERATIONS`, `STUCK`, etc.) and track the distribution in production; a high `STUCK` rate signals tool reliability problems, not just prompt issues.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q10: Design a safe and debuggable agent loop](03-010-design-a-safe-and-debuggable-agent-loop.md) | prerequisite — loop architecture where termination conditions live |
| [Q7: Prevent agents from over-reasoning or over-planning](03-007-prevent-agents-from-over-reasoning-or-over-planning.md) | related — over-planning is a precursor to runaway loops |
| [Q14: Detect and stop infinite planning loops](03-014-detect-and-stop-infinite-planning-loops.md) | follow-up — specialised termination for planning-specific stuck states |

---

## One-liner recall

> Enforce four independent termination conditions in orchestrator code — success signal, unrecoverable error, iteration/token budget cap, and wall-clock timeout — plus progress-based stuck detection; never rely on prompt instructions alone.
