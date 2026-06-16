# How agents decide a task is "done"?

**Category:** 03-agents-tool-use
**Question #:** 016
**Source section:** §3 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
Termination is one of the hardest production problems in agentic systems. Interviewers probe whether you understand that "done" is not just the LLM saying "I'm finished" — it requires explicit, verifiable criteria enforced at the orchestrator level. Weak candidates leave termination entirely to the model; strong candidates design multi-signal stopping logic that is robust to goal drift, infinite loops, and malformed success signals.

### Trigger phrases
- "How does the agent know when to stop?"
- "What prevents your agent from running forever?"
- "How do you define completion criteria for a long-running agent?"
- "How do you handle agents that think they're done but aren't?"

### What it tests
Whether the candidate understands that termination must be orchestrator-enforced (not model-declared), structured (not free-text "I'm done"), and multi-signaled — combining goal detection, budget limits, and HITL escalation.

---

## Answer

### Concept
An agent is "done" when one of three signals fires: (1) the LLM emits a structured **success signal** that satisfies verifiable goal criteria, (2) a **budget limit** (step count, token count, or wall-clock time) is exhausted, or (3) an **error / stuck condition** triggers HITL escalation or graceful abort. Relying solely on the LLM's free-text "I have completed the task" is insufficient — models hallucinate completion, especially in long chains.

### Mechanism

**Layer 1 — Structured success signal (primary)**
Design the agent's ReAct/function-calling output to include a dedicated `FINAL_ANSWER` tool or a structured JSON field (`{"status": "complete", "result": ...}`). The orchestrator detects this schema match and exits the loop. LangGraph models this as a `conditional_edge` — if the output node is `FINAL_ANSWER`, route to `END`; otherwise continue.

```python
# LangGraph termination pattern
def should_continue(state: AgentState) -> str:
    last_message = state["messages"][-1]
    # Explicit tool call means keep going
    if last_message.tool_calls:
        return "tools"
    # No tool call = agent signaled done
    return END
```

**Layer 2 — Goal verification (trusted, not just LLM-declared)**
For high-stakes tasks, the orchestrator independently verifies the goal against an external system rather than trusting the LLM's self-report:
- Code agent: run the test suite — pass = done
- SQL agent: execute the query and validate row count / schema
- Research agent: check that all required citations are present and non-empty

**Layer 3 — Hard budget limits (safety net in orchestrator code)**
Always enforced by the loop controller, never by the LLM:
- `max_iterations`: typically 10–25 for complex tasks, 3–5 for simple ones
- `max_tokens_per_run`: prevents runaway cost (e.g. ≥$0.50/run → HITL)
- `wall_clock_timeout`: e.g. 60s for real-time, 10min for batch jobs

**Layer 4 — Stuck / no-progress detection**
If the agent takes the same action twice in a row (fingerprint the last N action hashes), or emits thought-only steps without any tool call for K consecutive turns, the orchestrator flags "stuck" and either forces a FINAL_ANSWER or escalates to HITL.

```python
if action_fingerprint == previous_fingerprint:
    stuck_count += 1
if stuck_count >= 3:
    escalate_to_human(state)
```

### Example / Tradeoff

**Support ticket agent (LangGraph):** A GPT-4o-mini agent routes, drafts, and resolves tickets. Termination signals in priority order:
1. `RESOLVE_TICKET` tool called with a resolution summary → orchestrator marks ticket closed, exits loop
2. `ESCALATE_TO_HUMAN` tool called → loop exits, human queue receives the ticket
3. `max_iterations=12` exceeded → force-emit `ESCALATE_TO_HUMAN` with reason `"max_iterations exceeded"`
4. Wall-clock timeout 45s → same escalation path

**Tradeoff — strict vs. loose success criteria:**
Strict (external verification via test suite) is most reliable but adds latency. Loose (structured `FINAL_ANSWER` schema from LLM) is fast but can accept hallucinated completions. For user-facing tasks with low error tolerance, combine both: structured signal required AND automated acceptance test.

| Termination method | Reliability | Latency overhead | Use case |
|--------------------|-------------|-----------------|----------|
| Structured FINAL_ANSWER tool | High | Minimal | All agents (required baseline) |
| External goal verification | Very high | 200ms–2s | Code agents, data validation |
| Budget hard limit | Absolute | None | Safety net for all agents |
| Stuck detection (fingerprint) | High | Negligible | Long reasoning chains |
| Free-text "I'm done" | Low | None | Never use in production |

---

## Verbal script

**Opening (30s):**
"This is one of the most important production design decisions for any agent. The short answer is: you can never rely solely on the LLM declaring itself done — models hallucinate completion, especially after long reasoning chains. Instead, I design termination as a multi-layer system enforced by the orchestrator, not the model."

**Core explanation (2–3 min):**
"I'd start by designing a structured success signal — typically a `FINAL_ANSWER` tool or a JSON field with `status: complete`. The orchestrator checks for this schema in every step output. In LangGraph, that's a `conditional_edge` that routes to `END` when the success schema is detected.

But structured signals alone aren't enough — a model can emit a premature `FINAL_ANSWER`. For high-stakes tasks, I add an independent goal verification step: for a code-writing agent, that means running the test suite and checking all tests pass before accepting the completion. For a data agent, that means executing the generated SQL and validating the result schema. The orchestrator owns this check, not the LLM.

On top of that, I always set hard budget limits in orchestrator code — `max_iterations`, a token budget, and a wall-clock timeout. When any of these fire, the agent doesn't just die — it emits an escalation event so the work isn't lost.

Finally, stuck detection: I fingerprint the last N action hashes. If the agent repeats the same tool call three times or produces thought-only steps without acting, that's a planning loop — I break it and escalate to HITL with the current state preserved for a human to resume."

**Tradeoff / production angle (1 min):**
"The core tradeoff is strict vs. loose termination. Strict — external verification via test suite or DB query — is most reliable but adds latency. Loose — structured schema from the LLM — is fast but trusts the model. In practice I combine them: structured signal is required for the loop to exit, and then for high-stakes paths, I run a fast automated acceptance test asynchronously. If it fails, I re-open the task rather than shipping a hallucinated completion."

**Wrap-up (30s):**
"So: structured success tool, independent goal verification where stakes are high, hard budget limits as a safety net, and stuck detection for infinite planning loops. Happy to go deeper on any of those layers."

---

## Pitfalls

- **Mistake:** "The agent just outputs 'I'm done' in its final message and we check for that string" — **Better:** Use a typed `FINAL_ANSWER` tool with a required structured schema; string matching on free text fails on paraphrase variants and is trivially fooled by hallucination mid-task.
- **Mistake:** "We set `max_iterations=100` to give it plenty of room" — **Better:** Over-generous budgets hide infinite-loop bugs and explode cost; start at 10–15 and tighten based on p95 observed step counts from LangSmith traces. Every budget limit should also trigger an escalation event, not a silent abort.
- **Mistake:** Treating "no tool call in the final message" as the only termination signal without independent goal verification — **Better:** For any agent that writes to an external system or produces code, always verify the goal externally before marking complete; the LLM's self-assessment is untrustworthy without ground-truth feedback.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q11: Termination conditions in long-running agents?](03-011-termination-conditions-in-long-running-agents.md) | Companion question — broad termination framework; this Q focuses on goal-completion detection specifically |
| [Q14: Detect and stop infinite planning loops?](03-014-detect-and-stop-infinite-planning-loops.md) | Stuck detection layer — the "no-progress fingerprint" pattern applied here |
| [Q10: Design a safe and debuggable agent loop?](03-010-design-a-safe-and-debuggable-agent-loop.md) | Loop architecture context — where termination logic lives in the orchestrator |

---

## One-liner recall

> Agents stop via a four-layer termination stack: structured FINAL_ANSWER tool (not free text), independent goal verification (test suite / DB check), hard orchestrator budget limits (iterations + tokens + wall-clock), and stuck detection (repeated action fingerprint) — all enforced in orchestrator code, never left to the LLM's self-report.
