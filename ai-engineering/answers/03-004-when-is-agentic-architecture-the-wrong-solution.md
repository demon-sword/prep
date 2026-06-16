# When is agentic architecture the wrong solution?

**Category:** 03-agents-tool-use
**Question #:** 004
**Source section:** §3 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
Interviewers ask this to test engineering judgment — specifically whether you default to the shiniest tool or can reason about when simpler approaches win. In 2025–2026, "agent" is heavily hyped; strong candidates push back and articulate concrete failure modes, cost traps, and cases where a chain, a DAG, or a simple prompt is strictly better.

### Trigger phrases
- "When would you NOT use an agent?"
- "What are the downsides of agentic architectures?"
- "How do you decide between an agent and a simpler pipeline?"

### What it tests
Ability to evaluate architectural fit: recognising the real costs (latency, cost, unpredictability, debuggability) of multi-step LLM control flow and knowing which task properties make those costs unjustifiable.

---

## Answer

### Concept
Agentic architecture is the **wrong solution** whenever the added flexibility of LLM-controlled flow doesn't outweigh its costs: higher token spend, non-deterministic execution paths, compounding error rates across steps, and dramatically harder evaluation and debugging. The heuristic: if you can enumerate all valid execution paths at design time, a chain or DAG is almost always the better choice.

### Mechanism
Five concrete situations where agents are the wrong call:

| Situation | Why agents are wrong | Better alternative |
|-----------|----------------------|--------------------|
| **Fixed, enumerable workflow** | Developer already knows the path; LLM control flow adds cost and variance with no benefit | Deterministic chain / LangChain Sequential / DAG |
| **Latency-critical path** (< 500 ms SLO) | Each agent step = 1+ LLM call + tool latency; 3–5 steps easily adds 3–10 s | Single prompt with structured output, or pre-built pipeline |
| **Budget-constrained at scale** (≥1M req/day) | 5-step GPT-4o agent at $0.30/task = $300K/day; a single GPT-4o-mini prompt = ~$2K/day | Prompt-engineered single call or distilled fine-tune |
| **High-stakes, low-tolerance for errors** (financial, medical, legal) | Non-deterministic path makes auditability near-impossible; compounded errors at each step | Deterministic pipeline with HITL gates and explicit audit trail |
| **Simple classification or extraction** | One structured-output LLM call is sufficient; routing + tools add complexity with no benefit | `response_format: json_schema` single call |

**Error compounding** is the most-missed failure mode: if each agent step has 90% success probability, a 5-step agent succeeds only 59% of the time. A single-step pipeline at 95% is far better for reliability.

**Debuggability:** When a 5-step agent fails, you don't know which step failed, what the model "saw" at that step, or why it chose that tool sequence. Traditional software doesn't have this problem. You need full distributed tracing (LangSmith, Arize Phoenix, OpenTelemetry) just to diagnose.

**Evaluation difficulty:** Agents produce non-deterministic paths, so you can't write simple input→expected-output tests. You need trajectory evaluation, tool-selection accuracy, and end-state success metrics — all much harder to maintain.

### Example / Tradeoff
A customer support team evaluating agents for handling routine refund requests (fixed policy: check order age > 30 days → reject; ≤ 30 days → approve). An agent that dynamically decides to call `lookup_order()`, then `check_policy()`, then `issue_refund()` adds 3 LLM calls + latency (~4 s) to something that can be a single SQL query + rule engine (~50 ms). The team shipped the rule engine.

Contrast with a multi-tool **research agent** that searches the web, reads 10 PDFs, synthesises findings, and writes a report — genuinely open-ended; you can't enumerate the path in advance. Here, agency is justified.

---

## Verbal script

**Opening (30s):**
"I'd flip this question around and say: you should default to NOT using an agent, and only reach for one when you've confirmed the task genuinely requires open-ended, LLM-controlled flow. Most things that look like they need an agent don't — they need a well-engineered pipeline."

**Core explanation (2–3 min):**
"The clearest signal that an agent is wrong is when you can enumerate all the valid execution paths at design time. If the sequence is always 'classify → look up → respond,' that's a chain — a deterministic DAG in code, not an LLM-controlled loop. Forcing that into an agent adds 3–5 extra LLM calls, unpredictable path variance, and exponential debugging complexity, with zero upside.

The second red flag is a latency or cost SLO that agents can't meet. A 3-step agent on GPT-4o is realistically 5–8 seconds of wall-clock time and 15–30 cents per task. At 1M requests a day that's $150K–300K/day. A single GPT-4o-mini prompt with structured output handles most extraction and classification tasks in under a second for about $2/thousand.

Third: error compounding. If each step in a 5-step agent has a 10% failure probability, you only succeed 59% of the time overall. A well-engineered single-step pipeline at 95% is more reliable than a 5-step agent where each step is 99% reliable.

High-stakes regulated domains are a fourth no-go. In financial or medical contexts, every decision needs an audit trail. 'The LLM chose to call this tool based on prior observations' is not an audit trail. You need explicit, logged, deterministic logic with HITL gates — an agent's non-deterministic path makes auditability nearly impossible.

Finally, debugging. When your 5-step agent fails, you don't know which step broke. You need distributed tracing — LangSmith, Arize Phoenix — just to diagnose. A chain fails loudly at a specific function call."

**Tradeoff / production angle (1 min):**
"The situations where agents genuinely earn their complexity: truly open-ended tasks where the valid action sequence depends on runtime data you can't predict at design time — multi-step research, dynamic planning, anything where 'what to do next' is a genuine function of the current observation. Even then I'd impose hard limits: max turn budget (e.g. 10 steps), cost ceiling per task, and HITL gates for irreversible actions. The agent is wrong if those constraints can't be met."

**Wrap-up (30s):**
"So my practical rule: if you can write a flowchart for it, write the code for it. Reach for agents only when the flowchart branches depend on data you won't have until runtime and the LLM is the right thing to do that branching. Happy to go into how I'd enforce cost and turn limits when agents are justified."

---

## Pitfalls

- **Mistake:** Saying "agents are always more powerful so they're the right default" — **Better:** Argue the opposite: agents are a last resort when simpler pipelines can't handle the open-endedness. Default to chains; justify agents by listing what a pipeline can't do.
- **Mistake:** Listing "agents are bad because they're non-deterministic" without explaining *why* that matters in practice — **Better:** Quantify: 5-step agent at 90% per-step reliability = 59% end-to-end success; trace the debuggability problem (which step failed? why?); mention the need for LangSmith/Arize Phoenix for observability.
- **Mistake:** Not mentioning cost at scale — **Better:** Give concrete math: 5-step GPT-4o agent at $0.30/task × 1M req/day = $300K/day vs. a single GPT-4o-mini prompt at ~$2/thousand = ~$2K/day.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q3: What makes a system truly agentic? What does NOT qualify?](03-003-what-makes-a-system-truly-agentic-what-does-not-qualify.md) | Prerequisite — defines what counts as agentic before asking when to avoid it |
| [Q2: Agent vs simple LLM chain?](03-002-agent-vs-simple-llm-chain.md) | Same decision axis — chain is almost always the answer when agent is wrong |
| [Q26: Control cost explosions from tool calls](03-026-control-cost-explosions-from-tool-calls.md) | Follow-up — if you do use an agent, how to bound its costs |

---

## One-liner recall

> Agents are wrong when the execution path can be enumerated at design time, latency/cost SLOs can't absorb multiple LLM calls, auditability is required, or error compounding across steps makes the end-to-end reliability worse than a single-step pipeline.
