# Chain-of-thought vs tree-of-thought vs graph planning?

**Category:** 03-agents-tool-use
**Question #:** 013
**Source section:** §3 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
The interviewer is probing whether you understand the spectrum of LLM reasoning strategies and can articulate *when each one is appropriate*. This is a senior-level question because it requires knowing not just what each technique is, but how to operationalize them in production agents — including cost, latency, and reliability tradeoffs. It often follows "how do you decompose high-level goals?" and signals a shift toward architecture depth.

### Trigger phrases
- "How does chain-of-thought differ from tree-of-thought?"
- "When would you use graph-based planning in an agent?"
- "Compare CoT, ToT, and graph planning — which do you pick?"
- "How do you approach multi-step reasoning in your agents?"

### What it tests
Ability to map reasoning strategy to task complexity and production constraints — not just define the acronyms.

---

## Answer

### Concept
**Chain-of-thought (CoT)**, **tree-of-thought (ToT)**, and **graph planning** are three progressively more powerful (and expensive) strategies for getting an LLM to reason through complex tasks. CoT serializes reasoning into a linear scratchpad; ToT branches into parallel candidate plans and scores them; graph planning builds an explicit DAG of sub-goals with dependency edges, enabling parallelism and cycle detection. In production agents, most problems are solved with CoT or a hybrid CoT+DAG — ToT and full graph planning are reserved for search-heavy tasks where exploring alternatives is worth the cost.

### Mechanism

**Chain-of-Thought (CoT)**
- Prompt technique: `"Let's think step by step"` or few-shot examples with interleaved reasoning
- LLM produces a scratchpad of intermediate steps before the final answer
- Variants: **Zero-shot CoT** (single prompt), **few-shot CoT** (exemplar demonstrations), **Self-Consistency CoT** (sample N completions at temperature 0.7, majority-vote the answer)
- Used in: ReAct (Thought → Action → Observation loop), Plan-and-Execute first-pass planning
- Limitations: single-path — if the first reasoning chain goes wrong, there is no backtracking; hallucinations compound

**Tree-of-Thought (ToT)** — Yao et al., 2023
- Framework: at each reasoning step, generate *k* candidate continuations ("thoughts"), score them (via LLM self-evaluation or heuristic), and expand the highest-scoring branches via BFS or DFS
- Implements a search over the reasoning tree: `generate → evaluate → prune → recurse`
- Self-consistency becomes a special case (flat, no pruning)
- Tools: guidance from Princeton/Google; implementations in LangGraph via conditional edges sampling multiple next-steps
- Benchmarks: Creative Writing (+74% coherence), Game of 24 (+17% success rate over standard CoT in the original paper
- Limitations: O(k^d) LLM calls (k candidates × d depth); at a frontier model rates, a depth-4 tree with k=3 costs ~12 calls per query; latency 10–30s; not suitable for real-time agent tasks

**Graph Planning (Explicit DAG)**
- Approach: produce a directed acyclic graph of tasks — nodes are atomic sub-goals, edges are dependencies
- The agent or a planner constructs a structured JSON plan (e.g., `{id: "fetch_data", depends_on: [], tool: "search"}`), which an orchestrator executes, potentially in parallel for independent branches
- LangGraph DAG mode, Plan-and-Execute with Pydantic task schemas, or custom orchestrators (Prefect, Temporal)
- Enables: parallelism (independent nodes run concurrently), cycle detection, re-planning on node failure (re-route around failed node)
- Real example: a research agent that simultaneously runs `search_web`, `search_internal_docs`, and `check_citations` in parallel, then merges results in a synthesis node
- Limitations: plan quality depends on the initial decomposition; a wrong dependency edge blocks downstream work; graph construction itself requires a capable planner LLM call

### Example / Tradeoff

| Strategy | Best for | Avg cost/query | Latency | Backtracking |
|----------|----------|----------------|---------|--------------|
| **CoT (zero-shot)** | Structured reasoning, classification, QA | 1 LLM call | ~1–3s | None |
| **Self-Consistency CoT** | High-stakes factual Q&A where majority vote helps | 5–25 LLM calls | ~5–15s | None |
| **ToT** | Open-ended problem solving, creative tasks, puzzles | k^d calls (typically 9–27 for k=3, d=3) | 10–60s | Yes (pruned tree) |
| **Graph (DAG)** | Complex multi-step agents with parallelism | 1 planner call + N parallel tool calls | ~5–20s total with concurrency | On node failure |

**Production default**: ReAct CoT for most agents (cheap, debuggable), with a Plan-and-Execute DAG for tasks ≥5 steps. ToT is reserved for offline batch tasks (automated essay scoring, long-form content planning) where time and cost are secondary.

---

## Verbal script

**Opening (30s):**
"There are three main reasoning strategies I think about when designing agent planning: chain-of-thought, tree-of-thought, and graph planning. They trade off cost and latency against reasoning power and backtracking ability. In production I almost always start with CoT, and the question is really when the complexity of the task justifies the more expensive alternatives."

**Core explanation (2–3 min):**
"Chain-of-thought is the baseline — you prompt the LLM to reason step by step before producing its answer. In a ReAct agent that's the 'Thought' before each 'Action'. It's one LLM call per step, cheap, fast, and debuggable. The failure mode is that it's a single linear path: if the model goes wrong on step two there's no backtracking — the error compounds.

Self-consistency CoT adds a lightweight hedging layer: you sample N reasoning traces at temperature 0.7 and majority-vote the final answer. That's helpful for factual Q&A but still gives you no branching at the reasoning step level.

Tree-of-thought, from Yao et al. 2023, takes it further: at each reasoning step you generate k candidate continuations, score them — either by asking the LLM to self-evaluate or with a heuristic — and expand the best branches via BFS or DFS. It's a beam search over the thought space. The Game of 24 benchmark showed a 17-point improvement over standard CoT. The cost is O(k^d) — a depth-3 tree with 3 candidates means 27 LLM calls — so I'd only use it offline or for tasks where accuracy matters far more than latency, like generating a long-form design document.

Graph planning is what I use for complex agents with parallelism. The planner produces a JSON DAG — nodes are atomic tool calls, edges are dependencies — and the orchestrator executes independent nodes concurrently. A research agent, for example, can fan out to web search, internal docs search, and citation checker in parallel, then synthesize. LangGraph supports this natively. The upside is you get actual parallelism and can re-plan around a failed node. The downside is the initial plan must be correct — a wrong dependency edge blocks everything downstream."

**Tradeoff / production angle (1 min):**
"In practice I default to ReAct CoT for anything ≤5 steps. When the task has ≥5 steps with known structure, I switch to a Plan-and-Execute DAG because parallelism cuts wall-clock time significantly even if total token count is similar. I only reach for ToT when the task is open-ended and offline — something like generating multiple candidate architectures and evaluating them before presenting to the user. The cost is just too high for real-time user-facing agents."

**Wrap-up (30s):**
"So the hierarchy is: CoT for most things, DAG for structured multi-step parallel tasks, and ToT for high-stakes offline search problems. Happy to go deeper on any of these — how ToT self-evaluation works, or the Plan-and-Execute implementation with LangGraph."

---

## Pitfalls

- **Mistake:** Defining all three strategies without ever discussing when to use each or their cost — **Better:** Always anchor to a decision: "CoT is my default; I'd move to graph planning when there's parallelism to exploit, and ToT only offline when accuracy >>> latency"
- **Mistake:** Saying "ToT is always better than CoT because it explores more paths" — **Better:** Quantify the cost: a depth-3, k=3 ToT tree = 27 LLM calls vs 1 for CoT; at a frontier model pricing that's a 27× cost multiplier per query, which is only justified for high-stakes offline tasks
- **Mistake:** Treating graph planning and ToT as interchangeable — **Better:** They are orthogonal: ToT is a search strategy over LLM reasoning steps (no explicit tool calls); graph planning is a DAG of tool-calling sub-tasks executed by an orchestrator — very different runtime models

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q12: How decompose high-level goals into executable steps?](03-012-how-decompose-high-level-goals-into-executable-steps.md) | Prerequisite — Plan-and-Execute is the production form of graph planning |
| [Q7: Prevent agents from over-reasoning or over-planning?](03-007-prevent-agents-from-over-reasoning-or-over-planning.md) | Follow-up — ToT and deep graphs are the primary over-planning risk |
| [Q9: What logic belongs in orchestrator vs LLM?](03-009-what-logic-belongs-in-orchestrator-vs-llm.md) | Same concept — graph planning splits reasoning (LLM) from execution (orchestrator) |

---

## One-liner recall

> CoT is a linear scratchpad (1 LLM call/step, default for agents), ToT is beam search over reasoning steps (k^d calls, offline only), and graph planning is a parallel DAG of tool-calling sub-tasks executed by an orchestrator (best for ≥5-step structured tasks).
