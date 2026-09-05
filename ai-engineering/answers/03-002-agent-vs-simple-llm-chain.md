# Agent vs simple LLM chain?

**Category:** 03-agents-tool-use
**Question #:** 002
**Source section:** §3 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
This is the most common follow-up after "what is an agent?" — and one of the top-15 interview questions overall. The interviewer wants to see that you can draw a *precise* architectural boundary between two patterns that are easily conflated, and that you default to the simpler choice when it's appropriate. It probes engineering judgment: knowing when the agent's added complexity is justified, and when a chain is strictly better.

### Trigger phrases
- "What's the difference between an agent and a simple LLM chain?"
- "When would you use a chain vs an agent?"
- "Is what you built an agent or a chain — how do you know?"
- "Walk me through how an agent differs from a prompt pipeline."

### What it tests
Whether you can articulate the *dynamic control flow* distinction clearly, apply the right pattern for a given scenario, and reason about the cost/predictability/debuggability tradeoffs — not just name-drop LangChain.

---

## Answer

### Concept
A **chain** is a fixed, pre-defined sequence of LLM calls and transformations where the execution graph is known at design time — the developer decides every step upfront. An **agent** is a system where the LLM itself decides at runtime which tools to call, in what order, and whether to continue iterating — the execution path is dynamic and data-dependent.

The single clearest distinguishing property: **who decides the next step?**
- **Chain:** the developer (at write time).
- **Agent:** the LLM (at runtime, based on observations from the previous step).

### Mechanism

**Simple LLM chain (fixed pipeline):**
```
User query
   │
   ▼
Step 1: Retrieve context (vector DB lookup — always runs)
   │
   ▼
Step 2: LLM call with context → structured output
   │
   ▼
Step 3: Format and return response
```
Every request takes the same path. No branching, no iteration, no tool selection. Examples: RAG Q&A pipeline, summarization chain, classification step → generation step.

**Agent (dynamic loop):**
```
User query
   │
   ▼
LLM: "What tool should I call?"
   │
   ├──► search_kb("policy on X") → result appended to context
   │         │
   │         ▼
   │    LLM: "Need order info too"
   │         │
   │         ├──► lookup_order("ORD-9821") → result appended
   │         │         │
   │         │         ▼
   │         │    LLM: "I have enough. Final answer."
   │         │         │
   └─────────┴─────────▼
                  Response returned
```
The LLM observes each tool result and decides the next action — the graph is not known until runtime.

**Key architectural differences:**

| Dimension | LLM Chain | Agent |
|-----------|-----------|-------|
| Control flow | Fixed at design time | Dynamic at runtime (LLM decides) |
| Tool calls | Predetermined which tools, in what order | LLM selects tools based on observations |
| Iteration | None — single pass | Iterates until goal met or budget hit |
| Predictability | High — same steps every time | Lower — path varies by input |
| Latency | Bounded and predictable | Variable (depends on steps taken) |
| Token cost | Bounded and predictable | Variable — can explode |
| Debuggability | Easy — deterministic log replay | Requires trace tooling (LangSmith) |
| Testing | Straightforward unit + integration tests | Golden trajectory tests + probabilistic evals |
| When to use | Task graph known upfront, happy path stable | Path depends on runtime data / task complexity unknown |

### Example / Tradeoff
**Chain example — RAG pipeline for FAQ:**
User asks "what's your return policy?" → embed query → retrieve top-5 chunks → LLM synthesizes answer. The developer knows: always embed, always retrieve, always generate. A chain is perfect.

**Agent example — support ticket resolution:**
User asks "why was my order charged twice?" — the agent may need to: look up the order, check payment logs, query refund status, and *only if* a refund is pending, draft an email. Which of those steps run depends on what the tools return. A chain would have to hardcode every branch; an agent handles it dynamically.

**The "ReAct" pattern** (Yao et al., 2022) is the canonical agent loop — the LLM alternates between generating a "Thought" (reasoning trace) and an "Action" (tool call), and each "Observation" (tool result) feeds the next thought. LangChain's `AgentExecutor`, LangGraph, and LlamaIndex AgentRunner all implement this.

**Spectrum — not binary:**
- Fixed chain → RAG pipeline, summarization
- DAG with conditional routing (LangGraph nodes/edges) → structured workflow with known branches
- Plan-and-execute agent → upfront task decomposition, then parallel sub-agents
- ReAct agent → fully dynamic, single-agent loop
- Multi-agent system → multiple specialized agents orchestrated by a planner

---

## Verbal script

**Opening (30s):**
"The cleanest way I think about this: in a chain, the *developer* decides at write time what happens next. In an agent, the *LLM* decides at runtime based on what it got back from the last tool call. That's the core distinction — dynamic control flow."

**Core explanation (2–3 min):**
"A chain is a fixed pipeline. Think of a RAG Q&A system: embed the query, retrieve top-5 chunks, generate an answer. Every request takes the same path — you could draw it as a flowchart before the first user ever shows up. That predictability is a huge advantage: latency is bounded, cost is predictable, testing is straightforward, and a bug means rewinding a deterministic log.

An agent, by contrast, runs a loop: the LLM observes its current context and tool results, then decides which tool to call next — or whether it's done. Take a support-ticket agent. User reports a double charge. The agent might check the order, find a pending refund, and stop — two tool calls. Or it might check the order, check the payment processor, check the refund ledger, draft an email, and escalate — five tool calls. The developer can't know upfront; the LLM determines the path at runtime.

The practical implication is the tradeoff table: chains give you predictable latency and cost, easy unit testing, and simple debugging. Agents give you flexibility for tasks where the execution path depends on runtime data — but you pay with variable cost, harder-to-reproduce failures, and the need for trace tooling like LangSmith or Arize.

I'd also call out the spectrum between them: a LangGraph DAG with conditional edges is not purely a chain, but it's not a full agent either — it's a structured workflow with known branches. That middle ground is often the right answer for production: you get some flexibility without the full non-determinism of a ReAct loop."

**Tradeoff / production angle (1 min):**
"The failure mode I see most is over-indexing on agents. Teams reach for an agent because they want flexibility, but the task graph was actually enumerable — they just didn't model it. The result is variable cost, flaky tests, and debugging nightmares. My default is: if I can draw the flowchart at design time, I use a chain or a LangGraph DAG. I upgrade to a ReAct agent only when the step count or branching is genuinely unknown at design time. And when I do use an agent, I always add a `max_iterations` cap, model-tiered routing (a small fast model for tool selection, a frontier model for synthesis), and LangSmith traces from day one."

**Wrap-up (30s):**
"So the one-line answer: chain = developer controls flow at write time; agent = LLM controls flow at runtime. Use chains when the path is predictable, agents when it's genuinely dynamic, and LangGraph DAGs when you need structured branching without full non-determinism."

---

## Pitfalls

- **Mistake:** Saying "agents are more powerful so I'd just use an agent" without discussing when chains are the better choice — **Better:** Lead with the decision criterion — "if the execution graph is known at design time, a chain or DAG is strictly better: cheaper, faster, more debuggable, and easier to test; agents are justified only when the path is data-dependent and unknowable upfront."
- **Mistake:** Defining the difference as "agents use tools and chains don't" — **Better:** Many chains use tools (e.g. a RAG chain calls a vector DB); the distinction is *who decides the next step* — the developer (chain) or the LLM dynamically based on observations (agent).
- **Mistake:** Treating the chain/agent distinction as binary and not mentioning the LangGraph DAG / structured workflow middle ground — **Better:** Describe the spectrum: fixed chain → conditional DAG → plan-and-execute → ReAct; production systems often land on the DAG tier for reliability while retaining conditional flexibility.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q1: What is an AI agent and its role in a broader system?](03-001-what-is-an-ai-agent-and-its-role-in-a-broader-system.md) | Prerequisite — defines the agent concept this question contrasts |
| [Q3: What makes a system truly agentic? What does NOT qualify?](03-003-what-makes-a-system-truly-agentic-what-does-not-qualify.md) | Direct extension — sharpens the boundary with concrete examples |
| [Q4: When is agentic architecture the wrong solution?](03-004-when-is-agentic-architecture-the-wrong-solution.md) | Applies the chain-vs-agent tradeoff to anti-patterns |

---

## One-liner recall

> A chain is a fixed pipeline where the developer controls every step at write time; an agent is a dynamic loop where the LLM decides at runtime which tool to call next based on observations — use chains when the execution graph is predictable, agents only when the path is genuinely unknowable upfront.
