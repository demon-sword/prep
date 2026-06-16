# Detect and stop infinite planning loops?

**Category:** 03-agents-tool-use
**Question #:** 014
**Source section:** §3 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
Interviewers use this question to probe production maturity. An agent that loops forever burns tokens, maxes out API spend, and — without hard limits in the orchestrator — will never terminate gracefully. Candidates who have shipped agents in production immediately think about the termination problem; candidates who have only read tutorials assume the LLM will always know when to stop.

### Trigger phrases
- "How do you prevent an agent from running forever?"
- "What happens when your agent gets stuck in a loop?"
- "How do you detect and stop infinite planning loops?"
- "What are your termination safeguards for long-running agents?"

### What it tests
The ability to design hard, code-enforced loop-control mechanisms in the orchestrator layer — not relying on the LLM to self-terminate.

---

## Answer

### Concept
An infinite planning loop occurs when an agent repeatedly selects actions that don't advance the goal — either cycling through the same tool calls, failing and retrying identically, or re-planning without ever executing. The LLM cannot reliably detect this itself because it lacks a global view of iteration history. The fix is to enforce termination in the **orchestrator**, not in the prompt.

### Mechanism
Use a four-signal detection stack — implement all four; each catches a different loop class:

| Signal | What it catches | Implementation |
|--------|----------------|----------------|
| **Hard iteration cap** | Any loop, guaranteed | `if steps >= MAX_STEPS: raise BudgetExceededError` |
| **Wall-clock timeout** | Slow-loop cycles, network hangs | `asyncio.wait_for(agent_loop(), timeout=120)` |
| **No-progress detector** | Agent selects same tool+args repeatedly | Hash `(tool_name, canonicalized_args)` per step; if last N hashes identical → stuck |
| **Token budget cap** | Cost-runaway loops | Cumulative token counter; halt when `total_tokens > BUDGET` |

**No-progress detection in detail:**
```python
from collections import Counter
import hashlib, json

tool_fingerprints = []
STUCK_WINDOW = 3  # if last 3 steps are identical → stuck

def is_stuck(tool_name: str, args: dict) -> bool:
    fp = hashlib.md5(
        json.dumps({"tool": tool_name, "args": args}, sort_keys=True).encode()
    ).hexdigest()
    tool_fingerprints.append(fp)
    window = tool_fingerprints[-STUCK_WINDOW:]
    return len(window) == STUCK_WINDOW and len(set(window)) == 1
```

**Goal-drift re-planning loop:** a subtler variant where the LLM keeps re-decomposing the goal into slightly different sub-plans without executing any tool. Detect by counting consecutive `thought`-only steps (no tool call). After N=3 thought-only steps in LangGraph, force a `forced_action` interrupt that requires a tool call or escalates to HITL.

**LangGraph concrete pattern:**
```python
from langgraph.graph import StateGraph

def loop_controller(state):
    if state["steps"] >= 20:
        return "hitl_escalate"
    if is_stuck(state["last_tool"], state["last_args"]):
        return "hitl_escalate"
    if state["total_tokens"] > 50_000:
        return "hitl_escalate"
    return "continue"

graph.add_conditional_edges("agent", loop_controller,
    {"continue": "agent", "hitl_escalate": "human_review"})
```

### Example / Tradeoff
**Real incident pattern:** a code-review agent repeatedly called `search_codebase("authentication")` with the same query because the tool returned empty results but the LLM kept re-trying with identical args, not reformulating. No-progress detector (identical fingerprint × 3) caught the loop at step 9, escalated to HITL, and a human added `max_results=50` to the initial query. Without the detector, the agent would have burned ~$4 in API calls and timed out at the API level after 120s.

**Tradeoff table:**

| Control | Catches | Miss | Latency cost |
|---------|---------|------|--------------|
| Hard step cap | All loops | Legitimate long tasks | None (counter check) |
| Wall-clock timeout | Network hangs | Fast tight loops under limit | None |
| No-progress detector | Stuck identical calls | Varied but purposeless calls | Negligible (hashing) |
| Token budget | Cost explosion | Free slow loops | None |
| Re-planning counter | Goal-drift re-planning | Action-level loops | None |

**Setting MAX_STEPS:** too low risks cutting off legitimate multi-step tasks; too high wastes money when loops occur. Rule of thumb: set `MAX_STEPS = expected_steps × 3`, with async HITL at `expected_steps × 2` so a human can review before hard termination.

---

## Verbal script

**Opening (30s):**
"Infinite planning loops are one of the most expensive failure modes in production agents, and the key insight is that you can't rely on the LLM to self-terminate — you need hard limits enforced in the orchestrator code. I'd design a four-signal stack to detect and halt loops."

**Core explanation (2–3 min):**
"The first line of defense is a hard iteration cap — something like `MAX_STEPS = 20`, enforced with a simple counter in the loop controller. If we hit it, we route to HITL escalation, not a silent failure. This catches any loop, guaranteed.

Second is a wall-clock timeout — `asyncio.wait_for(agent_loop(), timeout=120s)` — which catches slow cycles and API hangs that the step counter misses.

Third, and the most production-critical, is a no-progress detector. I hash `(tool_name, canonicalized_args)` for each step and check if the last N hashes are identical. If the agent calls `search_codebase('auth')` with the same args three times in a row, it's stuck — the no-progress detector flags it and escalates. This is the one candidates always miss.

Fourth is a token budget cap — a cumulative token counter that halts the loop when we exceed, say, 50K tokens. This prevents cost explosions even when step counts are varied.

There's also a subtler variant: goal-drift re-planning loops where the LLM keeps generating new sub-plans without calling any tool. I handle that with a thought-only step counter — after 3 consecutive reasoning steps with no tool call, I force an action or escalate."

**Tradeoff / production angle (1 min):**
"The tricky calibration is MAX_STEPS. Too low and you interrupt legitimate long-horizon tasks; too high and you burn money before catching runaway loops. My rule of thumb: set the hard cap at 3× expected steps, but trigger async HITL at 2× so a human can intervene before the hard kill. Also, when routing to HITL on loop detection, preserve the full step history in the escalation payload — the human reviewer needs to see exactly which tool was cycling to fix the root cause."

**Wrap-up (30s):**
"So the key principle is: loop control belongs in the orchestrator, not the prompt. The four signals — step cap, wall-clock timeout, no-progress hash, and token budget — together cover the full class of infinite-loop failure modes. Happy to go deeper on any of them."

---

## Pitfalls

- **Mistake:** "I'd put a note in the system prompt telling the agent to stop if it's looping" — **Better:** Prompts cannot enforce hard limits; the LLM has no reliable self-awareness of its iteration count. The orchestrator must enforce `MAX_STEPS` in code with a counter checked before every step, and route to error handling or HITL on breach.
- **Mistake:** Relying solely on `MAX_STEPS` and missing the no-progress variant where an agent calls different tools but none advance the goal — **Better:** Add the no-progress detector (fingerprint hash over last N steps) AND a re-planning counter (consecutive thought-only steps without a tool call); the step cap alone won't catch stuck identical-call loops early enough to be cost-effective.
- **Mistake:** Hard-terminating the loop without preserving state — **Better:** Checkpoint agent state (step history, tool outputs, current plan) to Redis or Postgres before raising the budget exception, so the human reviewer or retry mechanism has full context; silent failure discards debugging information.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q11: Termination conditions in long-running agents?](03-011-termination-conditions-in-long-running-agents.md) | Parent concept — general termination framework; this Q14 is the infinite-loop-specific subtopic |
| [Q7: Prevent agents from over-reasoning or over-planning?](03-007-prevent-agents-from-over-reasoning-or-over-planning.md) | Adjacent — over-planning leads to goal-drift re-planning loops; same prompt-budget + forced-action techniques |
| [Q26: Control cost explosions from tool calls?](03-026-control-cost-explosions-from-tool-calls.md) | Follow-up — once you detect a loop, token-budget enforcement and model tiering are the cost-control levers |

---

## One-liner recall

> Detect infinite loops with four orchestrator-enforced signals — hard step cap, wall-clock timeout, no-progress hash (fingerprint identical tool+args across last N steps), and token budget — then route to HITL with preserved state rather than silently failing.
