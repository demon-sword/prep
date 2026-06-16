# What makes a system truly agentic? What does NOT qualify?

**Category:** 03-agents-tool-use
**Question #:** 003
**Source section:** §3 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
Interviewers use this question to separate candidates who have shipped production agents from those who have only read blog posts. The term "agent" is badly overloaded — many teams call any multi-step prompt chain an "agent." This question probes whether you understand the *structural* distinction: who decides the next action, the developer or the model?

### Trigger phrases
- "Is your system actually agentic or just a pipeline?"
- "What makes something an agent vs a chain or workflow?"
- "When is calling something an agent justified?"

### What it tests
Ability to define the necessary and sufficient conditions for agency, and to distinguish genuine agents from chains, pipelines, and orchestrated workflows using precise technical criteria.

---

## Answer

### Concept
A system is truly agentic when the **LLM itself controls the control flow**: it decides which tool to call next, whether to loop, and when the task is complete — none of those decisions are pre-wired by the developer. The key test is: *"Can the sequence of actions change at runtime based on intermediate observations?"* If yes, and if the LLM makes those branching decisions, it's agentic.

### Mechanism
There are three necessary conditions for a system to qualify as agentic:

1. **Dynamic action selection** — The LLM chooses from a set of tools/actions at each step based on the current state and prior observations. The sequence is not fixed in advance.
2. **Observation-driven iteration** — The system feeds tool outputs back into the LLM as new context, and the LLM reasons about what to do next. This is the perceive→reason→act loop.
3. **Termination decided by the model** — The LLM determines when the goal is achieved (or when it cannot proceed), not a hard-coded `for i in range(N)` or fixed DAG.

**What does NOT qualify as agentic:**

| Pattern | Why it's NOT agentic |
|---------|----------------------|
| Fixed prompt chain (LangChain Sequential) | Sequence is developer-determined; LLM only fills in slots |
| Retry loop on tool failure | Control flow is in code, not the model |
| Router that classifies and dispatches | LLM classifies once; routing logic is in code |
| Map-reduce pipeline over documents | Parallelism is static; LLM doesn't decide the fanout |
| RAG pipeline (retrieve → generate) | Steps are fixed; the model doesn't choose whether to retrieve |
| Structured output extraction | Single LLM call; no iteration or tool selection |

**What DOES qualify:**

| Pattern | Why it's agentic |
|---------|-----------------|
| ReAct (Reason + Act) loop | LLM chooses tool + args each step based on prior observations |
| OpenAI function-calling with branching | Model decides which function(s) to call, can loop |
| LangGraph agent with conditional edges | Model's output determines which node to visit next |
| Multi-agent orchestration (Autogen, CrewAI) | Sub-agents select their own tools; orchestrator is also LLM-driven |

### Example / Tradeoff
A concrete example: a **support-ticket resolution agent** that can call `search_kb()`, `lookup_order()`, `send_email()`, and `escalate_to_human()`. At each step, the LLM reads the ticket + prior results and chooses the next tool. If the KB search returns nothing, it might call `lookup_order()` instead, then decide to `escalate_to_human()` — a path the developer never hard-coded. This is genuinely agentic.

Compare with a **support pipeline**: `classify_intent()` → `search_kb()` → `generate_response()`. Every step is fixed. The LLM generates text, but the pipeline structure is entirely in code. This is a chain, not an agent.

**Key tradeoff**: Agency buys flexibility at the cost of predictability. Agentic systems are harder to debug (non-deterministic paths), cost more (multiple LLM calls + tool calls), and can loop or hallucinate tool names. For well-defined, repeatable tasks, a chain is almost always the better choice.

---

## Verbal script

**Opening (30s):**
"I'd start by being precise about what 'agentic' actually means, because the term gets used for almost everything. The defining characteristic isn't 'it calls tools' or 'it has memory' — it's specifically that the LLM controls the control flow. The model decides what to do next based on observations, not the developer."

**Core explanation (2–3 min):**
"Three conditions need to hold for a system to be truly agentic. First, dynamic action selection — the LLM chooses which tool or action to take at each step. Second, observation-driven iteration — tool outputs flow back into the model as new context and it reasons about the next move. Third, LLM-controlled termination — the model decides when the task is done or when it should stop.

A lot of things that get called agents don't meet these criteria. A LangChain Sequential chain where the steps are `retrieve → rerank → generate` — that's a pipeline; the sequence is hard-coded. A router that classifies an intent and dispatches to a handler — that's a classifier plus a switch statement, not an agent. Even a retry loop on a failing tool call where the retry logic is in Python code isn't agentic — the model didn't decide to retry.

What does qualify? The ReAct pattern is the canonical example: the model emits a `Thought`, then an `Action` with tool name and args, receives an `Observation`, and decides what to do next. The path through tools depends entirely on what the model sees. With LangGraph, you can make individual edges conditional on the model's output — that's agentic structure. OpenAI's function-calling loop where you keep calling the model until it returns a final answer is agentic."

**Tradeoff / production angle (1 min):**
"The honest tradeoff is: agency buys flexibility but costs predictability and money. Each step is a separate LLM call plus tool call. A 10-step agent on GPT-4o can cost $0.10–0.50 per task, and the path is non-deterministic — you can't easily unit test it. In production I apply a simple heuristic: if you can enumerate the valid execution paths at design time, use a DAG or chain. Reach for an agent only when the set of paths is genuinely open-ended or depends on data you won't have until runtime."

**Wrap-up (30s):**
"So the key test I'd apply: can the sequence of actions change at runtime based on intermediate observations, and is the LLM making those branching decisions? If both answers are yes, it's agentic. Happy to go deeper on production patterns for bounding agent behavior — turn limits, confidence gates, HITL."

---

## Pitfalls

- **Mistake:** Saying "any system that uses tools is an agent" — **Better:** Clarify that tool use is necessary but not sufficient; the defining criterion is whether the *LLM controls the control flow* (action selection + loop termination), not just whether tools are called.
- **Mistake:** Calling a fixed prompt chain (retrieve → rerank → generate) an "agentic RAG pipeline" — **Better:** Correctly identify it as a chain or pipeline; the LLM fills in template slots but the developer controls the sequence. Acknowledge the term is overloaded and define your terms up front.
- **Mistake:** Treating agentic as always better or more sophisticated — **Better:** Argue the opposite when appropriate: for well-defined repeatable tasks, a chain is cheaper, more predictable, and easier to debug. Agency has real costs (multi-step LLM calls, non-deterministic paths, harder evals).

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q2: Agent vs simple LLM chain?](03-002-agent-vs-simple-llm-chain.md) | Prerequisite — establishes the agent/chain distinction |
| [Q4: When is agentic architecture the wrong solution?](03-004-when-is-agentic-architecture-the-wrong-solution.md) | Direct follow-up — when to avoid agents |
| [Q8: Walk through a production-ready agent architecture](03-008-walk-through-a-production-ready-agent-architecture.md) | Follow-up — what a real agentic system looks like end-to-end |

---

## One-liner recall

> A system is truly agentic when the LLM — not the developer — controls what action comes next, whether to loop, and when the task is done; fixed prompt chains, pipelines, and router patterns do not qualify no matter how many tools they call.
