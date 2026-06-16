# Essential components of an agent beyond an LLM?

**Category:** 03-agents-tool-use
**Question #:** 006
**Source section:** §3 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
The interviewer is testing whether you can think architecturally about agents — not just the LLM reasoning core, but the surrounding infrastructure that makes an agent safe, reliable, and debuggable in production. A weak candidate describes the LLM and maybe mentions tools. A strong candidate draws out a five-component system and explains why each non-LLM component is essential.

### Trigger phrases
- "What does an agent need beyond the model itself?"
- "Walk me through the components of an agent system."
- "What infrastructure does an agent require?"
- "If I just wrap an LLM with a loop, what am I missing?"

### What it tests
Whether you have a production-grounded architectural model of agents — specifically: tool layer, memory layer, orchestrator/planner, and observability/safety — and can articulate why each is required rather than optional.

---

## Answer

### Concept
An agent requires **four supporting components** beyond the LLM reasoning core: a **tool layer** (the actuators), a **memory layer** (state persistence), an **orchestrator** (control flow and budget enforcement), and an **observability/safety layer** (tracing, guardrails, and human-in-the-loop). Omitting any one of these turns a demo into a production liability.

### Mechanism

#### 1. Tool Layer (Actuators)
The LLM can only generate text — tools are what give it real-world effect. Each tool is exposed to the LLM as a **JSON schema**: name, description, parameter types, and return type. The description field is the most critical part; poor descriptions cause the model to select the wrong tool or hallucinate arguments.

Common tool categories:
| Type | Examples |
|------|---------|
| Knowledge retrieval | `search_knowledge_base(query)`, `web_search(query)` |
| Data access | `run_sql(query)`, `get_order(order_id)` |
| Action / write | `create_ticket(details)`, `send_email(to, body)` |
| Code execution | `run_python(code)` — sandboxed (E2B, Modal, Docker) |
| External APIs | `stripe_charge(amount)`, `calendar_create_event(...)` |

**Tool execution is the orchestrator's responsibility** — the LLM only selects a tool and arguments; the orchestrator actually calls it.

#### 2. Memory Layer (State Persistence)
Four types of agent memory, each serving a distinct purpose:

| Memory type | Storage | Content | Example tool |
|-------------|---------|---------|--------------|
| Working | Context window (in-flight) | Current task state, tool results, conversation | Token budget; flush old turns |
| Episodic | Vector store (external) | Past interactions, retrieved by similarity | Pinecone, Qdrant |
| Semantic | KV store / structured DB | User preferences, learned facts | Redis, PostgreSQL |
| Procedural | System prompt / fine-tune | Learned skills and behavioral patterns | System prompt injection |

Working memory is free but bounded by the context window. Episodic memory scales cheaply but requires embedding + retrieval infrastructure. Semantic memory provides exact-match recall that embeddings miss.

#### 3. Orchestrator / Planner (Control Flow)
The orchestrator is the program that drives the agent loop:

```
while not done and turns < MAX_TURNS:
    action = llm.decide(context, tool_schemas)
    if action.type == "tool_call":
        result = tool_layer.execute(action.tool, action.args)  # with timeout, retry
        context.append(result)
    elif action.type == "final_answer":
        return action.content
turns_exceeded → fallback response
```

The orchestrator owns:
- **Turn budget / token budget** — hard caps to prevent runaway loops
- **Retry logic** — tool failures with exponential backoff, idempotency keys
- **Human-in-the-loop triggers** — interrupt before irreversible actions
- **Routing** — whether to call sub-agents, escalate, or terminate
- **State checkpointing** — persist intermediate state for long-running tasks (LangGraph's `StateGraph`, Temporal)

#### 4. Observability & Safety Layer
Without this layer, agents fail silently and catastrophically in production:

- **Tracing** — every reasoning step, tool call, and tool result captured (LangSmith, Arize, OpenTelemetry spans). Essential for debugging non-deterministic multi-step failures.
- **Input/output guardrails** — content filtering before tool execution and before returning to user (NeMo Guardrails, LlamaGuard, custom NLI classifiers)
- **PII scrubbing** — Presidio or regex-based redaction before any data reaches the LLM or external tools
- **Action allowlist / denylist** — policy middleware that rejects out-of-scope tool calls before execution; prevents prompt-injection attacks from triggering destructive tools
- **Alerting** — token budget exhaustion, loop depth exceeded, tool error rate spikes (Datadog / PagerDuty)

### Example / Tradeoff
**LangGraph support agent (production stack):**
- **LLM:** GPT-4o (reasoning), GPT-4o-mini (simple tool selection to save cost)
- **Tools:** `search_kb(query)`, `lookup_order(id)`, `create_ticket(details)`, `escalate(reason)` — each schema has rich description + typed params
- **Memory:** Working context (last 10 turns), Pinecone episodic store (similar past tickets), Redis user-preference store
- **Orchestrator:** LangGraph `StateGraph` with `interrupt_before` on `escalate` tool — human confirms before escalation; max 8 turns, $0.05 cost cap per session
- **Observability:** LangSmith traces every node; Presidio scrubs PII before `lookup_order`; Datadog alerts if p95 turns > 6

**Tradeoff — what happens when components are missing:**
| Missing component | Failure mode |
|-------------------|--------------|
| No tool schemas | LLM hallucinates tool arguments or picks wrong tool |
| No turn budget | Infinite loop; $100+ cost per session |
| No memory | Agent re-asks for context the user already provided; poor UX |
| No guardrails | Prompt injection → destructive tool call (e.g., bulk delete) |
| No tracing | Debugging multi-step failures takes hours; impossible to reproduce |

---

## Verbal script

**Opening (30s):**
"Beyond the LLM itself, I think of a production agent as requiring four non-negotiable components: the tool layer, a memory layer, an orchestrator that owns the control loop, and an observability and safety layer. If any of these is missing, the agent isn't production-ready — it's a demo."

**Core explanation (2–3 min):**
"Let me walk through each. First, the tool layer: the LLM can only generate text, so tools are the actuators that give it real-world effect. Each tool is exposed as a JSON schema — name, description, typed parameters. That description field is crucial; a bad description causes the model to pick the wrong tool. Common categories are knowledge retrieval, data reads, write actions, code execution, and external APIs. The orchestrator, not the LLM, actually executes the tools.

Second, memory. I think of four types. Working memory is just the context window — in-flight state for the current task. Episodic memory is a vector store like Pinecone or Qdrant that retrieves similar past interactions. Semantic memory is a KV store or structured DB for exact facts like user preferences. And procedural memory lives in the system prompt or fine-tuned weights — learned behaviors. Most production agents only implement working plus one of the external types; the others are added as pain points emerge.

Third, the orchestrator. This is the program driving the agent loop: call LLM, parse its action, execute the tool, append the result, repeat. But critically, the orchestrator also owns the turn budget and token budget — hard caps to prevent infinite loops — plus retry logic for tool failures, human-in-the-loop triggers before irreversible actions, and state checkpointing for long-running tasks. LangGraph's StateGraph is a good pattern here.

Fourth, observability and safety. You need full traces of every reasoning step and tool call — LangSmith is the go-to, or OpenTelemetry spans. You need input/output guardrails — NeMo Guardrails or LlamaGuard — and PII scrubbing via Presidio before any data reaches the model or tools. And you need an action allowlist that rejects out-of-scope tool calls before execution, which is your main defense against prompt injection."

**Tradeoff / production angle (1 min):**
"The most common mistake I see is shipping an agent with a tool layer and no orchestrator budget, no guardrails, and no tracing. You get runaway loops when the LLM gets confused, silent failures when tools time out, and no way to debug why the agent took an unexpected action. The observability layer feels like overhead until your first production incident — then it's the difference between a 10-minute fix and a 10-hour investigation. My rule: if I can't replay an agent's decision trace in LangSmith, it's not ready to ship."

**Wrap-up (30s):**
"So: tool layer for real-world actions, memory for state persistence, orchestrator for control flow and budget enforcement, and observability/safety for tracing and guardrails. The LLM is just the reasoning core — the other four are what make it an agent versus an expensive chat widget. Happy to go deeper on any of them, especially memory architecture or the orchestration patterns."

---

## Pitfalls

- **Mistake:** Saying "an agent needs tools and memory" and stopping there, without mentioning the orchestrator's budget enforcement or observability — **Better:** Name all four non-LLM components and explain why the orchestrator's turn budget and the tracing layer are non-negotiable for production; omitting them is the root cause of the most common production agent failures (infinite loops, silent failures).
- **Mistake:** Treating memory as a single concept ("the agent has memory") without distinguishing working/episodic/semantic/procedural — **Better:** Break memory into types, explain what storage backend each requires (context window vs. vector store vs. KV store), and note that most teams start with working + episodic and add semantic only when exact-match failures appear.
- **Mistake:** Describing the tool layer only by examples ("web search, code interpreter") without mentioning that tool schema quality (especially the description field) directly determines LLM tool-selection accuracy — **Better:** Emphasize that the JSON schema description is the LLM's interface to the tool; a vague description causes wrong tool selection or hallucinated arguments, making schema design a first-class engineering concern.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q1: What is an AI agent and its role in a broader system?](03-001-what-is-an-ai-agent-and-its-role-in-a-broader-system.md) | Prerequisite — defines the agent concept; this question is the deeper architectural dive |
| [Q8: Walk through a production-ready agent architecture.](03-008-walk-through-a-production-ready-agent-architecture.md) | Direct follow-up — applies these components to a concrete production design |
| [Q22: Tool schemas that reduce hallucinated actions?](03-022-tool-schemas-that-reduce-hallucinated-actions.md) | Deep dive into tool layer schema design — the highest-leverage component detail |

---

## One-liner recall

> Beyond the LLM, a production agent requires four components: a **tool layer** (JSON-schemed actuators the orchestrator executes), a **memory layer** (working context + episodic vector store + semantic KV store), an **orchestrator** (the loop driver with turn budget, retry logic, and HITL triggers), and an **observability/safety layer** (LangSmith traces, Presidio PII scrubbing, action allowlist, and guardrails) — omitting any one turns a demo into a production liability.
