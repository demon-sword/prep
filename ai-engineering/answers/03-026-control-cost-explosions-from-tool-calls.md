# Control cost explosions from tool calls?

**Category:** 03-agents-tool-use
**Question #:** 026
**Source section:** §3 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
Agents that call tools in a loop can spend 10–100× more than a single LLM call — each iteration incurs LLM tokens (system prompt re-sent, growing tool history), plus tool execution cost (API credits, database reads, external service fees). Interviewers use this question to find out whether you've actually run agents in production and had to contain runaway spend, or whether you've only built demos that never hit real budgets.

### Trigger phrases
- "Your app gets 1M queries/day — how do you optimize cost?"
- "How do you prevent an agent from making 50 tool calls on a simple question?"
- "What guardrails do you put on agentic systems for cost?"
- "How do you control cost in a multi-step agent loop?"

### What it tests
Production cost-engineering discipline: ability to quantify the cost drivers, enumerate concrete control levers (turn budgets, model tiering, caching, tool batching, HITL gates), and articulate the cost/capability tradeoff without breaking agent functionality.

---

## Answer

### Concept
Cost explosions in tool-using agents come from three compounding factors: (1) **token inflation** — the system prompt and full tool-call history are re-sent on every LLM call, so a 10-turn agent loop passes ~10× the base context; (2) **unbounded iteration** — without hard turn limits an agent can loop indefinitely on ambiguous tasks; (3) **redundant tool calls** — the same tool is called multiple times with equivalent arguments. Controlling costs requires rate-limiting at three layers: the orchestrator (turn budgets, token caps), the tool layer (caching, batching, deduplication), and the model layer (tiering to cheaper models for routine steps).

### Mechanism

**Layer 1 — Orchestrator hard limits (always-on)**

Set hard limits in the orchestrator code, not the prompt:
```python
MAX_TURNS = 10           # per-task ceiling
MAX_TOKENS_PER_TASK = 50_000   # input + output tokens combined
WALL_CLOCK_TIMEOUT = 120       # seconds
cost_budget_usd = 0.10         # per-task spend cap
```
If any limit is exceeded, the orchestrator stops the loop and returns whatever partial result exists (or escalates to HITL). These are non-negotiable guardrails — never rely on the LLM to self-limit.

**Layer 2 — Prompt and context compression**

The system prompt is re-sent every turn. Aggressively compress it:
- Keep system prompt under 500 tokens; move reference content to a retrieval tool
- Prune tool-call history: keep only the last N turns in context (sliding window) or summarize prior turns with a cheap model (GPT-4o-mini at $0.15/M tokens) into a one-paragraph state summary
- Use LangChain's `ConversationSummaryBufferMemory` or a custom summarization step at turn 5+

At 10 turns, a naive agent sending the full history on every call costs ~10× the single-call baseline. A sliding window of 3 turns reduces this to ~3×.

**Layer 3 — Model tiering (use the cheapest model that works)**

Not every step needs GPT-4o. Assign models by task complexity:

| Step | Model | Approx cost |
|------|-------|-------------|
| Tool-result summarization | GPT-4o-mini | $0.15/M input |
| Tool selection (simple) | GPT-4o-mini | $0.15/M input |
| Multi-step reasoning / synthesis | GPT-4o | $2.50/M input |
| Code generation / verification | Claude 3.5 Sonnet | $3.00/M input |

A LangGraph conditional edge can route based on task type or turn count: use GPT-4o-mini for the first 3 turns; escalate to GPT-4o only when the agent hits a reasoning-heavy step.

**Layer 4 — Tool-call caching and deduplication**

Identical tool calls waste tokens and external API credits:
- **Semantic cache** (GPTCache / Redis): hash `(tool_name, args)` → cache response with TTL keyed to data freshness (e.g., 60s for weather, 24h for product catalog)
- **Exact deduplication**: before dispatching a tool call, check whether the same `(tool, args)` was already called in this session and return the cached result
- **Batch tool calls**: some providers (OpenAI parallel tool calls, Anthropic tool_use blocks) support calling multiple tools in a single LLM turn; use this to collapse `get_order(123)` + `get_order(456)` into one LLM request instead of two

**Layer 5 — Tool design: narrow scope reduces tokens**

Wide-scope tools (e.g., `query_database(sql: str)`) require the LLM to generate and validate long SQL strings, consuming more tokens per call. Narrow purpose-built tools (`get_order_status(order_id: str)`) reduce argument tokens, reduce hallucination retries, and make the response predictable (fewer tokens back).

**Layer 6 — HITL gate on expensive multi-step branches**

Before the agent enters a long tool chain (e.g., "research 10 competitors" → 10 web-fetch calls), gate with a HITL confirmation:
```
"This task will require ~15 tool calls (estimated cost: $0.45). Proceed? [Yes/No]"
```
LangGraph's `interrupt_before` node handles this without breaking the resumable state machine.

### Example / Tradeoff

**Cost math at 1M queries/day:**

| Config | Cost/query | Daily cost |
|--------|-----------|------------|
| Naive agent, GPT-4o, 10 turns, no caching | $0.25 | $250K/day |
| Turn cap=5, model tiering (GPT-4o-mini for 4 turns), 30% cache hit | $0.04 | $40K/day |
| Turn cap=3, full GPT-4o-mini, 50% cache hit | $0.008 | $8K/day |

The 30× cost reduction (naive → tiered+cached) comes almost entirely from model tiering and cache hits, not from sacrificing capability.

**Real pattern:** Support-ticket agents at scale typically cap at 5 turns, use GPT-4o-mini for tool selection and result summarization, escalate to GPT-4o only when the agent emits a `NEED_ESCALATION` structured output. This alone cuts per-query cost from ~$0.20 to ~$0.03.

---

## Verbal script

**Opening (30s):**
"Cost explosions in agents are a real production problem — I've seen naive agent loops burn 50× more than expected because the system prompt and full tool history were re-sent on every turn, and there was no turn limit. I'd organize the control levers into three layers: orchestrator hard limits, model tiering, and tool-layer caching and deduplication."

**Core explanation (2–3 min):**
"The first and most important layer is hard limits in the orchestrator — not in the prompt. I set a `max_turns` ceiling (usually 5–10 depending on task complexity), a `max_tokens_per_task` cap, and a wall-clock timeout. If any of these are hit, the loop stops and returns a partial result or escalates to a human. This is the non-negotiable baseline.

"The second big lever is context compression. In a naive agent, the full tool-call history is appended to the prompt on every turn. At turn 10, you're sending ~10× the baseline context. The fix is a sliding window — keep only the last 3 turns in context — or a summarization step that compresses prior turns into a one-paragraph state summary using a cheap model like GPT-4o-mini. This alone can cut token costs by 60–70%.

"The third lever is model tiering. Not every step in the agent loop needs GPT-4o. I assign GPT-4o-mini for tool selection, result summarization, and routine data extraction — it's about 15× cheaper per token. I only escalate to GPT-4o or Claude Sonnet when the agent hits a reasoning-heavy synthesis step. In LangGraph, I implement this as a conditional edge that checks the step type before routing to the LLM call.

"At the tool layer, I add semantic caching — hash the tool name plus arguments, cache the response in Redis with a TTL matched to data freshness. I also deduplicate: if the agent calls `get_order(123)` twice in the same session, the second call returns the cached result. And I use OpenAI's parallel tool calls feature to batch multiple tool requests into a single LLM turn when possible."

**Tradeoff / production angle (1 min):**
"The main tradeoff is cost vs. task completion rate. Tighter turn budgets mean some genuinely complex tasks fail and escalate to humans — which is actually the right outcome, because agent-HITL handoff is cheaper than an agent burning $2 on a task it can't resolve. The real mistake is treating agents as an unlimited resource. Every agent task should have a documented cost SLO — for example, 'support-ticket deflection at $0.05/query or cheaper' — and the turn cap and model tier settings are calibrated to hit that SLO while maintaining quality."

**Wrap-up (30s):**
"So: hard limits in the orchestrator as the always-on backstop, model tiering for the biggest cost reduction, context compression for the token overhead, and tool-layer caching to eliminate redundant calls. Happy to go deeper on any of these — model tiering logic or the caching architecture."

---

## Pitfalls

- **Mistake:** Saying "I'd add a max_iterations parameter to the prompt" — **Better:** Hard limits must be enforced in orchestrator code, not prompts; the LLM will often ignore a prompt-level iteration instruction when it believes more turns are needed, so `max_turns` must be a Python/code-level guard that stops the loop unconditionally
- **Mistake:** Focusing only on per-turn LLM cost without mentioning context token inflation across turns — **Better:** Explain that the system prompt and tool-call history are re-sent on every turn (doubling, tripling cost per turn), so context pruning and summarization are required to prevent quadratic cost growth in long sessions
- **Mistake:** Not mentioning model tiering — **Better:** Articulate that not all steps need the frontier model; routing tool-selection and summarization turns to GPT-4o-mini (15× cheaper) while reserving GPT-4o for synthesis steps is the single highest-ROI cost lever in practice

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q11: Termination conditions in long-running agents](03-011-termination-conditions-in-long-running-agents.md) | Turn-budget termination is the primary cost control |
| [Q9: What logic belongs in orchestrator vs LLM](03-009-what-logic-belongs-in-orchestrator-vs-llm.md) | Hard cost limits belong in orchestrator code, never the prompt |
| [Q7: Prevent agents from over-reasoning or over-planning](03-007-prevent-agents-from-over-reasoning-or-over-planning.md) | Over-planning is the behavioral root cause of cost explosions |

---

## One-liner recall

> Control agent cost explosions with three compounding levers: orchestrator hard limits (max_turns=5–10, token cap, wall-clock timeout in code not prompts), model tiering (GPT-4o-mini for routine steps, GPT-4o only for synthesis), and context compression + tool-call caching to prevent the quadratic token growth that accumulates across turns.
