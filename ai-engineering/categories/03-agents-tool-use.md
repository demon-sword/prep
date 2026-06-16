# 03. Agents & Tool Use — AI Engineering Interview Category

Covers autonomous LLM agents that perceive state, plan actions, call tools, and iterate toward goals — one of the fastest-rising interview topics in 2025–2026.

---

## Interview signals

| You hear… | This category |
|-----------|---------------|
| "what's the difference between an agent and a chain?" | Agent fundamentals |
| "when would you NOT use an agentic approach?" | Agent design tradeoffs |
| "walk me through a production-ready agent architecture" | Architecture deep dive |
| "how do you prevent prompt injection / tool abuse?" | Safety & security |
| "how do you control cost with tool-calling agents?" | Cost & latency |
| "how do you evaluate agent performance?" | Observability & eval |

---

## Mental model

A strong candidate understands that an agent is not just an LLM with tools bolted on — it is a **perceive → plan → act → observe loop** where the LLM acts as a reasoning engine, not an orchestrator. The key distinction is *dynamic control flow*: agents decide at runtime which tools to call and whether to continue iterating, whereas chains follow a fixed pre-defined path. Weak candidates conflate the two, overuse agents for problems that a deterministic pipeline would solve more reliably and cheaply, and underestimate that the hardest production problems are termination conditions, cost explosions, and invisible planning failures — not the tool-calling API itself. Strong candidates can articulate *when not to use agents* as clearly as when to use them, and always reason about HITL triggers, cost caps, and observability from the start.

---

## Sub-topics

### 1. Agent Fundamentals & Architecture
**When:** "What is an agent?", "agent vs chain?", "what makes a system truly agentic?"
**What:** An agent is an LLM-driven system that dynamically selects and executes tools across multiple steps, updating its plan based on observations, with no fixed execution graph.
**Key questions:**
- [Q1: What is an AI agent and its role in a broader system?](../answers/03-001-what-is-an-ai-agent-and-its-role-in-a-broader-system.md)
- [Q2: Agent vs simple LLM chain?](../answers/03-002-agent-vs-simple-llm-chain.md)
- [Q3: What makes a system truly agentic?](../answers/03-003-what-makes-a-system-truly-agentic-what-does-not-qualify.md)
- [Q8: Walk through a production-ready agent architecture](../answers/03-008-walk-through-a-production-ready-agent-architecture.md)

### 2. Planning, Memory & Tool Use
**When:** "How do agents decompose goals?", "what types of memory do agents have?", "how do they pick tools?"
**What:** Agents decompose goals via chain-of-thought or plan-and-execute patterns, maintain working/episodic/semantic/procedural memory across turns, and select tools via LLM function-calling schemas with strict typing to reduce hallucinated actions.
**Key questions:**
- [Q12: How decompose high-level goals into executable steps?](../answers/03-012-how-decompose-high-level-goals-into-executable-steps.md)
- [Q21: How agents decide which tool to use?](../answers/03-021-how-agents-decide-which-tool-to-use.md)
- [Q27: Types of memory: working, episodic, semantic, procedural?](../answers/03-027-types-of-memory-working-episodic-semantic-procedural.md)
- [Q22: Tool schemas that reduce hallucinated actions?](../answers/03-022-tool-schemas-that-reduce-hallucinated-actions.md)

### 3. Safety, Cost & Production Guardrails
**When:** "How do you prevent prompt injection?", "how do you control cost explosion?", "how do you handle HITL?"
**What:** Production agents require budget caps, tool sandboxing, prompt injection defenses, HITL escalation triggers, and idempotent retry patterns — all designed before the first line of agent code.
**Key questions:**
- [Q25: Biggest security risks with tool-using agents?](../answers/03-025-biggest-security-risks-with-tool-using-agents.md)
- [Q26: Control cost explosions from tool calls?](../answers/03-026-control-cost-explosions-from-tool-calls.md)
- [Q29: Human-in-the-loop patterns — when trigger human review?](../answers/03-029-human-in-the-loop-patterns-when-trigger-human-review.md)
- [Q23: Sandbox tool execution safely?](../answers/03-023-sandbox-tool-execution-safely.md)

### 4. Observability, Evaluation & Multi-Agent Systems
**When:** "How do you monitor agents in production?", "orchestration vs choreography?", "how do you evaluate agent performance?"
**What:** Agent eval requires step-level traces (LangSmith/Arize Phoenix), tool-selection accuracy, trajectory comparison against golden paths, and business metrics (task completion rate, escalation rate, cost/task).
**Key questions:**
- [Q30: Monitor autonomous agent behavior in production?](../answers/03-030-monitor-autonomous-agent-behavior-in-production.md)
- [Q34: Evaluate agent performance — tool selection, action advancement, context adherence?](../answers/03-034-evaluate-agent-performance-tool-selection-action-advancement.md)
- [Q32: Orchestration vs choreography for multi-agent systems?](../answers/03-032-orchestration-vs-choreography-for-multi-agent-systems.md)

---

## Decision framework

```
Need dynamic multi-step reasoning with tool calls?
  No  → use an LLM chain (fixed pipeline, cheaper, more debuggable)
  Yes → continue

Is the task graph predictable at design time?
  Yes → use a DAG orchestrator (LangGraph, Prefect) — agentic routing, deterministic edges
  No  → use a ReAct / plan-and-execute agent

How many steps until goal?
  ≤3 steps, structured output needed → function-calling chain (no loop overhead)
  >3 steps OR unknown depth       → agent loop with step budget + HITL trigger

Tool execution risk level?
  Low (read-only APIs, web search)  → auto-approve tool calls
  Medium (DB writes, emails)        → require confirmation schema + idempotency
  High (code execution, payments)   → sandboxed execution (Docker/E2B) + HITL

Multi-agent needed?
  Decomposable subtasks + parallelism → orchestrator-worker (central planner dispatches)
  Peer agents, event-driven           → choreography (message bus, e.g. Kafka)

Regulated domain (healthcare, finance)?
  Yes → HITL at every consequential action, full audit trail, human-approval gate before irreversible ops
  No  → configurable HITL thresholds (confidence < X OR cost > Y → escalate)
```

---

## Common mistakes

| Mistake | What to say instead |
|---------|---------------------|
| "Agents are just LLMs with tools" without explaining the loop | Explain the perceive→plan→act→observe loop and how the LLM dynamically decides next steps based on observations |
| Recommending agents for every use case without discussing when NOT to use them | Lead with: "I'd first ask whether a fixed pipeline covers the task — agents add latency, cost, and debugging complexity that isn't justified for deterministic workflows" |
| Ignoring termination conditions and infinite loops | Always specify: max_iterations cap, goal-completion detector, and HITL escalation as the three required termination mechanisms |
| "Just use tool_choice='auto'" without discussing schema design to reduce hallucinations | Strict JSON schemas with required fields, constrained enums, and concrete examples in descriptions reduce hallucinated tool calls by 40–60% in production |
| Forgetting cost: "you can just call GPT-4 for every step" | Discuss token budget per step, model tiering (GPT-4o-mini for routing/simple tools, GPT-4o for reasoning), and step-count caps with async HITL |
| No mention of prompt injection when discussing tool-using agents | Explicitly mention: user input → tool args → code/SQL injection risk; mitigate with schema validation, input sanitization, and sandboxed execution |

---

## Question checklist

| # | Question | Difficulty signal | Status |
|---|----------|-------------------|--------|
| 1 | What is an AI agent and its role in a broader system? | E | `todo` |
| 2 | Agent vs simple LLM chain? ⭐ | E | `todo` |
| 3 | What makes a system truly agentic? What does NOT qualify? | M | `todo` |
| 4 | When is agentic architecture the wrong solution? | M | `todo` |
| 5 | How define and enforce agent autonomy boundaries? | M | `todo` |
| 6 | Essential components of an agent beyond an LLM? | E | `todo` |
| 7 | Prevent agents from over-reasoning or over-planning? | M | `todo` |
| 8 | Walk through a production-ready agent architecture. | S | `todo` |
| 9 | What logic belongs in orchestrator vs LLM? | S | `todo` |
| 10 | Design a safe and debuggable agent loop. | S | `todo` |
| 11 | Termination conditions in long-running agents? | M | `todo` |
| 12 | How decompose high-level goals into executable steps? | M | `todo` |
| 13 | Chain-of-thought vs tree-of-thought vs graph planning? | S | `todo` |
| 14 | Detect and stop infinite planning loops? | M | `todo` |
| 15 | Partial observability or missing information? | S | `todo` |
| 16 | How agents decide a task is "done"? | M | `todo` |
| 17 | Planning failures hardest to detect in production? | S | `todo` |
| 18 | Stateless vs stateful agents? | M | `todo` |
| 19 | Version and roll back agent behavior? | S | `todo` |
| 20 | Architect an agent system: loop, tools, memory, orchestration, safety. | S | `todo` |
| 21 | How agents decide which tool to use? | E | `todo` |
| 22 | Tool schemas that reduce hallucinated actions? | M | `todo` |
| 23 | Sandbox tool execution safely? | M | `todo` |
| 24 | Tool failures, retries, idempotency? | M | `todo` |
| 25 | Biggest security risks with tool-using agents? | S | `todo` |
| 26 | Control cost explosions from tool calls? | M | `todo` |
| 27 | Types of memory: working, episodic, semantic, procedural? | M | `todo` |
| 28 | Long-term memory without polluting it? | S | `todo` |
| 29 | Human-in-the-loop patterns — when trigger human review? | M | `todo` |
| 30 | Monitor autonomous agent behavior in production? | S | `todo` |
| 31 | Agents in regulated domains (financial, healthcare)? | S | `todo` |
| 32 | Orchestration vs choreography for multi-agent systems? | S | `todo` |
| 33 | Filter PII before data reaches LLM? | M | `todo` |
| 34 | Evaluate agent performance — tool selection, action advancement, context adherence? | S | `todo` |
| 35 | Explain agentic systems to non-technical stakeholders? | E | `todo` |
| 36 | Agent analyzing support tickets, drafting responses, escalating. | S | `todo` |
| 37 | Agents collaborating on research reports with citations. | S | `todo` |
| 38 | Agent reviewing code and suggesting improvements. | S | `todo` |

---

## One-page summary

- **Agent = perceive → plan → act → observe loop**: unlike a chain, control flow is dynamic — the LLM decides at runtime whether to call another tool or stop. This is the core distinction interviewers probe.
- **When NOT to use agents**: if the task graph is known at design time, a deterministic pipeline (LangGraph DAG, Airflow) is cheaper, more debuggable, and easier to test. Agents are justified only when step count or branching is unknown.
- **Three required production safeguards**: (1) `max_iterations` hard cap to prevent infinite loops; (2) HITL escalation trigger (confidence threshold OR irreversible action); (3) sandboxed tool execution (Docker/E2B) for any code or write operations.
- **Cost control**: model-tier routing (GPT-4o-mini for tool selection, GPT-4o for synthesis), token budget per step enforced in the loop controller, semantic caching of repeated sub-queries, and async HITL to avoid blocking expensive model calls.
- **Eval stack**: LangSmith or Arize Phoenix for step-level traces; golden trajectory comparison (tool selection accuracy, step count vs optimal); business metrics (task completion rate, escalation rate, cost/task, p95 wall-clock latency).
