# How decompose high-level goals into executable steps?

**Category:** 03-agents-tool-use
**Question #:** 012
**Source section:** §3 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
The interviewer is probing whether you understand task planning as an engineering discipline, not just a prompt trick. Strong candidates know the failure modes of naive "ask the LLM to plan everything" approaches and can articulate when to use hierarchical decomposition, when to involve human checkpoints, and how to keep plans verifiable and executable.

### Trigger phrases
- "How would your agent break down a complex task?"
- "Walk me through how an agent plans before acting."
- "How do you prevent an agent from going off-track on a long task?"

### What it tests
Ability to design a structured, observable planning layer that translates vague user intent into verifiable, bounded sub-tasks.

---

## Answer

### Concept
Goal decomposition is the process of converting a high-level objective (e.g., "generate a quarterly business review") into a directed acyclic graph (DAG) of atomic, verifiable sub-tasks that each map to one or a small number of tool calls. The core insight is that decomposition is an **orchestration responsibility** — not something left entirely to the LLM at runtime — because unbounded LLM planning is hard to debug, cost-control, or audit.

### Mechanism
**Step 1 — Plan-and-Execute separation.** A planner LLM call (ideally o1/Claude-thinking or a frontier model with extended reasoning) receives the goal and produces a structured plan: an ordered or partially-ordered list of named steps, each with inputs, expected outputs, and a success criterion. The executor loop processes one step at a time, treating the plan as a queue.

**Step 2 — Hierarchical task decomposition.** Complex goals are broken into levels:
- **Level 1 (Goal):** "Produce Q3 business review report"
- **Level 2 (Sub-goals):** Gather metrics / Analyze trends / Draft sections / Compile PDF
- **Level 3 (Actions):** `query_analytics_db(date_range=Q3)`, `call_llm(summarize_metrics)`, `write_file(section_draft)`, `pdf_tool(compile)`

Each Level 3 action corresponds to exactly one tool call with typed inputs and outputs.

**Step 3 — Success criteria per step.** Each step carries a verifiable exit condition (e.g., "metrics_df has >0 rows", "draft_word_count > 300"). The orchestrator evaluates these before advancing; if a step fails its condition, it retries or triggers HITL.

**Step 4 — Re-planning on failure.** If a step fails after retries, the planner is re-invoked with the failure context to produce a revised plan — a controlled reflection loop rather than unconstrained agent wandering.

**Common patterns:**
- **ReAct (Reason + Act):** interleaved thought/action/observation — good for exploratory tasks, but no upfront plan, so hard to bound.
- **Plan-and-Execute (LangGraph):** explicit plan graph, executor processes one node at a time — better debuggability and cost control.
- **Tree of Thoughts (ToT):** branching plan candidates, scored and pruned — used when the right decomposition itself is uncertain (e.g., math olympiad problems, research planning).

### Example / Tradeoff
A **code-review agent** at a fintech company used Plan-and-Execute with LangGraph:
1. Planner call (a frontier model, ~2K tokens): produces 6-step plan as JSON with success criteria.
2. Executor loop: each step calls one tool (GitHub API read, linter, security scanner, a small fast model summarizer).
3. Each step logged with LangSmith; plan node marked `passed`/`failed` with structured output.
4. On failure (e.g., rate limit from GitHub API): orchestrator retries with exponential backoff up to 3×, then re-plans.

**Tradeoff table:**

| Approach | Upfront plan? | Debuggability | Flexibility | Best for |
|----------|--------------|--------------|-------------|----------|
| ReAct | No | Low | High | Exploratory, open-ended |
| Plan-and-Execute | Yes | High | Medium | Structured, auditable tasks |
| Tree of Thoughts | Branching | Medium | Very High | Uncertain decomposition space |
| Hardcoded DAG | Full | Very High | Low | Regulated / deterministic workflows |

**Failure mode:** Planner LLM produces steps that are too coarse (a single step = "research the topic") causing the executor to recurse infinitely or call tools hundreds of times. Fix: add a step-granularity constraint to the planner prompt ("each step must map to ≤2 tool calls and complete in <30s") and a max_depth guard in the orchestrator.

---

## Verbal script

**Opening (30s):**
"Decomposing high-level goals is one of the trickiest parts of agent design, because naïve approaches — just ask the LLM to plan everything dynamically — tend to produce unbounded, unauditable behavior. I'd use a Plan-and-Execute pattern with explicit success criteria per step, which gives you debuggability and cost control."

**Core explanation (2–3 min):**
"I'd start with a dedicated planner call — typically a more capable model like a frontier model or an o-series model with extended reasoning — that takes the goal and produces a structured JSON plan: an ordered list of named sub-tasks, each with typed inputs, expected outputs, and a verifiable success criterion. Think of it as converting a vague intent into a DAG of atomic actions.

The executor loop then processes steps one at a time. Each step maps to one or two tool calls. Before advancing, the orchestrator validates the step's success criterion — for example, 'did the DB query return >0 rows?' If it fails, the orchestrator retries up to three times with exponential backoff, then triggers HITL or re-invokes the planner with the failure context for a revised plan.

Hierarchically, you decompose: the top level is the goal, the second level is sub-goals (gather data, analyze, draft, compile), and the third level is individual tool calls with typed parameters. This prevents the classic failure mode where a step is too coarse — 'research the topic' — and the executor recurses or calls tools hundreds of times.

A concrete example: a code-review agent I'd build would have a frontier model produce a 6-step plan as JSON — fetch PR diff, run linter, run security scanner, summarize findings, draft review comment, post via GitHub API. Each step is logged in LangSmith with its inputs, outputs, and pass/fail status against the success criterion."

**Tradeoff / production angle (1 min):**
"The main tradeoff is flexibility vs. debuggability. ReAct is more flexible — there's no upfront plan, the agent reasons step by step — but it's hard to bound cost or audit after the fact. Plan-and-Execute is more auditable but requires a good planner prompt. For regulated domains or expensive workflows, I'd lean toward hardcoded DAGs with LLM steps only at reasoning nodes, not for control flow. Tree of Thoughts is useful when the decomposition itself is uncertain, but it's expensive — three branches × three depths = nine planner calls before you start executing."

**Wrap-up (30s):**
"So the key principle is: keep decomposition explicit and in the orchestrator layer, not hidden inside a ReAct loop. Structured plans with success criteria per step give you cost bounds, debuggability, and a re-planning hook when things go wrong. Happy to go deeper on re-planning strategies or how to prompt the planner for step granularity."

---

## Pitfalls

- **Mistake:** Treating goal decomposition as just "asking the LLM to plan inside the ReAct loop" and never producing an explicit upfront plan — **Better:** Use Plan-and-Execute: generate a structured JSON plan with named steps and success criteria before execution begins, so you can validate, bound, and debug each step independently.
- **Mistake:** Not constraining step granularity in the planner prompt, leading to steps like "analyze all the data" that map to dozens of tool calls — **Better:** Add explicit constraints to the planner prompt: "each step must map to ≤2 tool calls, have a verifiable binary success criterion, and complete in under 60 seconds"; enforce max_depth in the orchestrator.
- **Mistake:** Re-planning blindly on every failure without passing failure context — **Better:** Pass the failed step's error, retry log, and current state back to the planner so the revised plan avoids the same decomposition mistake; cap re-plan attempts at 2–3 to prevent infinite loops.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q13: Chain-of-thought vs tree-of-thought vs graph planning](03-013-chain-of-thought-vs-tree-of-thought-vs-graph-planning.md) | Planning strategies compared — direct follow-up |
| [Q8: Walk through a production-ready agent architecture](03-008-walk-through-a-production-ready-agent-architecture.md) | Decomposition fits inside the loop controller layer |
| [Q11: Termination conditions in long-running agents](03-011-termination-conditions-in-long-running-agents.md) | Success criteria per step feed directly into termination logic |

---

## One-liner recall

> Use Plan-and-Execute: a dedicated planner LLM call produces a structured JSON DAG of atomic steps with typed inputs and verifiable success criteria; the orchestrator executor processes one step at a time, retrying failures and re-invoking the planner with failure context — never delegating control-flow decisions to the ReAct loop.
