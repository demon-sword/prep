# What logic belongs in orchestrator vs LLM?

**Category:** 03-agents-tool-use
**Question #:** 009
**Source section:** §3 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
This question probes whether the candidate understands the **architectural boundary** inside an agent system — a critical design decision that determines reliability, debuggability, and cost. Strong candidates know that dumping control logic into the LLM prompt makes the system fragile and expensive; they push deterministic concerns to the orchestrator and reserve the LLM for genuine reasoning.

### Trigger phrases
- "What should the orchestrator handle vs the LLM?"
- "Walk me through how you'd split responsibility in an agent loop."
- "How do you decide what goes in the prompt vs in your application code?"

### What it tests
Whether the candidate can draw a principled, production-validated boundary between deterministic orchestration code and stochastic LLM reasoning.

---

## Answer

### Concept
In an agent system the **orchestrator** is the deterministic host process (Python/Go/Node) that manages the agent loop, enforces policies, and calls tools. The **LLM** is the stochastic reasoning engine that interprets context and decides what to do next. The key principle: **anything that can be expressed as deterministic code should be**; the LLM should only handle tasks that genuinely require natural language understanding or open-ended reasoning.

### Mechanism

**Orchestrator owns (deterministic / policy):**

| Responsibility | Why it belongs here |
|---------------|---------------------|
| Loop control — `max_iterations`, wall-clock timeout, step counter | Prevents infinite loops; LLM can't reliably self-count |
| Tool dispatch — parse LLM's tool-call JSON, validate schema, route to handler | Deterministic JSON parse + routing is cheap and reliable |
| Retry / error handling — catch tool failures, apply backoff, decide whether to surface to LLM | Error recovery logic needs to be predictable and auditable |
| Budget enforcement — token budget, cost ceiling, turn limit | Hard limits that the LLM should never be allowed to override |
| HITL triggers — flag irreversible actions (delete, send email, charge card) for human approval | Compliance requirement; can't rely on LLM to self-regulate |
| State persistence — write checkpoints to Redis/DB between turns | LLM is stateless; session context must be managed externally |
| Security / allowlist — validate tool names against allowlist before calling | Prevent prompt-injection driven tool abuse |

**LLM owns (stochastic / reasoning):**

| Responsibility | Why it belongs here |
|---------------|---------------------|
| Goal decomposition — break a user intent into steps | Requires language understanding of ambiguous goals |
| Tool selection — given context, choose which tool and with what args | Semantic matching between tool schemas and current state |
| Intermediate reasoning (ReAct Thought step) — interpret tool output, decide next action | Dynamic multi-hop reasoning the orchestrator can't express as rules |
| Answer synthesis — combine tool outputs into a coherent response | Natural language generation |
| Ambiguity resolution — ask the user a clarifying question | Semantic judgment about what information is missing |

### Example / Tradeoff

**Support-ticket agent (LangGraph implementation):**

```
Orchestrator (LangGraph graph):
  - max_iterations = 10, wall_clock = 30s
  - Tool allowlist: ["search_kb", "get_order", "escalate"]
  - interrupt_before("escalate")  ← HITL gate
  - Checkpoints to Redis

LLM (a small fast model, T=0):
  - ReAct format: Thought → Action → Observation
  - Decides which tool to call and with what args
  - Synthesises final response
```

**Anti-pattern (logic in the prompt):**
```
❌ "If the issue is billing-related use get_order, 
     if escalation is needed use escalate, 
     but only escalate if severity > 3..."
```
This puts conditional routing logic in the prompt — the LLM may follow it inconsistently, it's hard to test, and it leaks policy into every API call. Instead, have the orchestrator inspect the tool call result and enforce the routing rule in code.

**Tradeoff:** Moving more logic to the orchestrator increases reliability and reduces tokens-per-turn, but makes the orchestrator more complex and harder to change without code deploys. Teams at scale (e.g., Anthropic's Claude.ai, LangChain's production templates) use a hybrid: a thin ReAct-style prompt for LLM reasoning + a rich orchestrator graph (LangGraph/Temporal) for all control flow.

---

## Verbal script

**Opening (30s):**
"The core design question for any agent is: what does the orchestrator own vs what does the LLM own? My rule of thumb is — if it can be expressed as deterministic code, it should be. The LLM is for reasoning; the orchestrator is for control. Let me walk through the split."

**Core explanation (2–3 min):**
"On the orchestrator side I put everything that needs to be reliable and auditable: the loop controller with a hard `max_iterations` limit and wall-clock timeout, tool dispatch parsing the LLM's JSON output and routing to the right handler, retry and backoff logic when a tool fails, budget enforcement so the LLM can never spend more tokens than we allow, HITL gates before irreversible actions like sending emails or charging cards, and state persistence to Redis between turns so the session survives a process restart.

The LLM gets the reasoning tasks: decomposing a vague user goal into concrete steps, selecting which tool to call and with what arguments, interpreting tool outputs to decide the next action, synthesizing a final answer, and asking the user for clarification when something is ambiguous.

In a LangGraph implementation for a support-ticket agent this looks like: the graph itself handles max_iterations, an allowlist of valid tool names, and an `interrupt_before('escalate')` node that pages a human. The LLM prompt is a clean ReAct format — Thought, Action, Observation — and it just reasons about the current context."

**Tradeoff / production angle (1 min):**
"The failure mode I see most often is teams putting conditional routing logic into the prompt — 'if the issue is billing, use get_order; if severity is above 3, escalate.' That logic belongs in the orchestrator as code. It's cheaper to execute, deterministic to test, and won't hallucinate. The tradeoff is that a richer orchestrator requires code deploys to change behavior, while prompt-based logic can be updated without a deploy. For high-velocity iteration early on, some logic in the prompt is pragmatic — but production systems should migrate it to code."

**Wrap-up (30s):**
"So the guiding principle is: orchestrator for determinism and policy, LLM for language and reasoning. In practice I use LangGraph for the orchestrator graph and a minimal ReAct prompt for the LLM — happy to go deeper on the LangGraph node structure or the HITL pattern if that's useful."

---

## Pitfalls

- **Mistake:** Putting routing conditionals and budget enforcement in the prompt ("Only call escalate if severity > 3") — **Better:** Express all deterministic policies in orchestrator code; the LLM should never be the gatekeeper for irreversible actions because it can be inconsistent or jailbroken.
- **Mistake:** Giving the LLM control over loop termination ("decide when you're done") without a hard orchestrator limit — **Better:** Always set `max_iterations` and a wall-clock timeout in the orchestrator; the LLM's self-assessment of "done" is unreliable and can lead to runaway cost or infinite loops.
- **Mistake:** Parsing tool-call JSON inside the prompt template or expecting the LLM to validate its own arguments — **Better:** Tool schema validation happens in the orchestrator; reject malformed calls with a structured error message that the LLM can correct in the next turn.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q8: Walk through a production-ready agent architecture](03-008-walk-through-a-production-ready-agent-architecture.md) | Prerequisite — full architecture context |
| [Q10: Design a safe and debuggable agent loop](03-010-design-a-safe-and-debuggable-agent-loop.md) | Follow-up — how to build the orchestrator loop safely |
| [Q14: Detect and stop infinite planning loops](03-014-detect-and-stop-infinite-planning-loops.md) | Same concept — orchestrator's role in loop safety |

---

## One-liner recall

> Orchestrator owns all deterministic policy (loop limits, tool dispatch, retries, HITL gates, budget); LLM owns only genuine reasoning (goal decomposition, tool selection, answer synthesis) — never put routing conditionals or safety policies in the prompt.
