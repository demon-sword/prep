# What is an AI agent and its role in a broader system?

**Category:** 03-agents-tool-use
**Question #:** 001
**Source section:** §3 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
The interviewer is checking whether you have a precise, production-grounded understanding of what an "agent" actually is — not just the hype definition. They want to see that you can articulate the perceive→reason→act loop, distinguish it from simpler LLM pipelines, and place it inside a realistic system architecture (tools, memory, orchestrator, safety rails).

### Trigger phrases
- "What is an AI agent?"
- "Can you define what you mean by agent in your system?"
- "How does an agent differ from a regular LLM call?"
- "Walk me through what an agent is and where it fits in a production architecture."

### What it tests
Whether you can draw a crisp conceptual boundary around "agent," name its required components, and situate it within a realistic multi-layer system — not just recite a marketing definition.

---

## Answer

### Concept
An AI agent is a software system that uses an LLM as its reasoning core to **perceive an environment, plan actions, execute tools, observe results, and iterate** — continuing until a goal is achieved or a stopping condition is met. Unlike a single-shot LLM call or a fixed chain, an agent's execution path is determined dynamically at runtime: the model decides what to do next based on tool outputs and accumulated context.

### Mechanism
The core perceive → reason → act loop:

1. **Perceive** — the agent receives a task description, current state, and available tool schemas (JSON schemas describing each tool's name, parameters, and return type).
2. **Reason / Plan** — the LLM (e.g., GPT-4o, Claude 3.5 Sonnet) generates a structured action: which tool to call and with what arguments. Frameworks like ReAct interleave reasoning traces ("Thought:") with action calls.
3. **Act** — the orchestrator executes the selected tool (web search, code interpreter, SQL query, API call) in a sandboxed environment.
4. **Observe** — the tool's output is appended to the context window.
5. **Iterate** — steps 2–4 repeat until the LLM produces a final answer or a budget/turn-count limit is hit.

**Role in a broader system:**
```
User request
     │
     ▼
Orchestrator (LangChain / LlamaIndex / custom)
     │
     ├─► LLM (reasoning core) ◄─ Tool schemas, system prompt, memory
     │
     ├─► Tool layer: web search, SQL, code exec, file I/O, external APIs
     │
     ├─► Memory layer: working context, vector store (episodic), KV store (semantic)
     │
     ├─► Safety layer: input/output guardrails, PII filter, action allowlist
     │
     └─► Observability: LangSmith / Arize traces, token budget, turn counter
```

The agent sits **between** the user interface and downstream services; the orchestrator handles routing, budget enforcement, human-in-the-loop triggers, and logging.

### Example / Tradeoff
**Concrete example:** A customer-support agent built on GPT-4o + LangGraph:
- Tools: `search_knowledge_base(query)`, `lookup_order(order_id)`, `create_ticket(details)`, `escalate(reason)`
- On each turn the LLM decides which tool to call; the orchestrator executes it and appends the result.
- A turn budget (max 8 iterations) and a confidence threshold (<0.7 → escalate) prevent runaway loops.

**Tradeoff — agent vs. simpler chain:**
| Dimension | Fixed chain | Agent |
|-----------|-------------|-------|
| Flexibility | Low — hardcoded steps | High — dynamic branching |
| Predictability | High | Lower — harder to test |
| Cost | Predictable | Variable (token explosion risk) |
| Debuggability | Easy | Requires tracing (LangSmith) |
| Right when | Happy path is stable | Path depends on runtime data |

---

## Verbal script

**Opening (30s):**
"I think of an AI agent as a system that uses an LLM not just to generate text, but to actively control a loop — perceive, reason, act, observe, and repeat — until a goal is met. The key word is *loop*: unlike a single LLM call or a fixed chain, an agent's next step is determined by what it got back from the last tool call."

**Core explanation (2–3 min):**
"The basic architecture has five components working together. First, the LLM is the reasoning core — it takes the task, current context, and tool schemas, and decides what action to take next. Second, the tool layer is where real work happens: web search, SQL queries, code execution, external APIs. Third, memory gives the agent persistence — working memory is the context window, episodic memory is a vector store for past interactions, and semantic memory is structured data like user preferences. Fourth, the orchestrator — LangChain, LlamaIndex, or a custom loop — sits around the LLM and handles execution: it calls the tools, appends results, enforces a turn budget, and triggers safety checks. Fifth, observability: you need full traces — I'd use LangSmith or Arize — to debug why the agent made a particular decision.

In terms of role in a broader system: the agent is a layer that sits between the user interface and your downstream services. The user request hits the orchestrator, which drives the LLM through the loop, calling tools that reach your databases, APIs, or knowledge base. The orchestrator also owns safety — it runs the action through an allowlist, strips PII before tool calls, and decides when to hand off to a human."

**Tradeoff / production angle (1 min):**
"The big tradeoff versus a fixed chain is flexibility vs. predictability. An agent can handle cases where the execution path isn't known upfront — say, a support agent that may need to look up an order, check a policy, and then draft a response. But that flexibility comes at a cost: token budgets are variable, failures are harder to reproduce, and you need explicit stopping conditions to prevent infinite loops. My rule of thumb: if the happy path is stable, use a chain or DAG. If the path depends on runtime data or user intent that you can't enumerate, that's when an agent earns its complexity."

**Wrap-up (30s):**
"So in summary: an agent is an LLM-driven perceive-reason-act loop with tool access, memory, and an orchestrator enforcing budgets and safety. Its role in a system is to handle tasks where the execution path is dynamic. Happy to go deeper on any component — the memory architecture, the orchestration patterns, or how to make agents debuggable in production."

---

## Pitfalls

- **Mistake:** Defining agent as "an LLM that can use tools" without mentioning the iterative loop, stopping conditions, or orchestrator — **Better:** Emphasise the *loop* structure, that the LLM's output determines the *next* action, and that the orchestrator enforces turn budgets and safety rails; a one-shot tool call is not an agent.
- **Mistake:** Describing agents as a silver bullet without mentioning cost and predictability risks — **Better:** Proactively note that agents have variable token costs, require explicit turn/budget limits, and are harder to test; frame the agent vs. chain tradeoff as a deliberate engineering choice, not a default.
- **Mistake:** Leaving memory and observability out of the architecture description — **Better:** Name all five components (LLM, tools, memory, orchestrator, observability) and explain why each is required for a production agent — tracing tools like LangSmith are essential for debugging non-deterministic multi-step behavior.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q2: Agent vs simple LLM chain?](03-002-agent-vs-simple-llm-chain.md) | Direct follow-up — the interviewer will push here next |
| [Q6: Essential components of an agent beyond an LLM?](03-006-essential-components-of-an-agent-beyond-an-llm.md) | Deeper dive into the architecture components named here |
| [Q8: Walk through a production-ready agent architecture.](03-008-walk-through-a-production-ready-agent-architecture.md) | System-design expansion of this answer |

---

## One-liner recall

> An AI agent is an LLM-driven perceive→reason→act loop that dynamically selects and executes tools, observes results, and iterates until a goal is met — distinguished from a chain by runtime-determined control flow, and requiring an orchestrator, memory layer, turn budget, and observability stack to be production-safe.
