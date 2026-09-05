# Evaluate agent performance — tool selection, action advancement, context adherence

**Category:** 03-agents-tool-use
**Question #:** 034
**Source section:** §3 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
Agents are notoriously hard to evaluate: they produce long, multi-step trajectories rather than single outputs, and the "correctness" of an intermediate step depends on context. Interviewers ask this to probe whether you have a systematic eval framework — not vibes — and whether you understand the three distinct failure modes: the agent chose the wrong tool, the agent didn't make forward progress, or the agent drifted away from the user's original intent.

### Trigger phrases
- "How do you measure whether your agent is actually doing the right thing?"
- "Is there an eval framework for your agent, or is it vibes-based?"
- "How do you evaluate tool selection accuracy and task completion in production?"
- "Walk me through how you'd benchmark an agentic system."

### What it tests
Ability to design a rigorous, multi-dimensional eval framework for non-deterministic multi-step systems — covering offline golden-trajectory benchmarking, production trajectory monitoring, and business-outcome metrics.

---

## Answer

### Concept
Agent evaluation requires three complementary lenses: **tool selection accuracy** (did the agent choose the right tool at each step?), **action advancement** (is the agent making forward progress toward the goal?), and **context adherence** (is the agent staying on task relative to the original goal and conversation context?). These correspond to the three distinct failure modes — wrong action, stuck agent, and goal-drifted agent — and each requires a different measurement technique.

### Mechanism

**1. Tool selection accuracy (offline + online)**

*Offline — golden trajectory benchmarks:*
- Build a golden dataset of 50–200 representative tasks with annotated correct tool calls at each step: `{task, expected_tool, expected_args_schema}`.
- Metrics:
  - **Tool selection accuracy** = fraction of steps where the agent called the correct tool (exact match or fuzzy schema match).
  - **Argument hallucination rate** = fraction of tool calls where required args were fabricated rather than grounded in context.
- Tools: LangSmith datasets, PromptFoo, AgentBench, or custom pytest fixtures that mock tool outputs and assert on the call log.

*Online — production telemetry:*
- Instrument every tool call with structured logs: `{run_id, step, tool_name, args_summary, result_status, latency_ms}`.
- Track **tool error rate** (schema validation failures, 400s, tool timeouts) per tool per day.
- Alert when tool error rate for a specific tool exceeds baseline by 2σ — often signals a schema mismatch after a tool update.

**2. Action advancement (is the agent making progress?)**

An agent that loops, re-queries the same tool with the same args, or emits only "thought" steps without tool calls is stuck. Measure:
- **Steps-to-completion** on the golden dataset: compare agent trajectory length to the expert annotated trajectory length. A ratio > 2× signals over-planning or loops.
- **No-progress rate**: fraction of production runs where ≥2 consecutive steps have identical action fingerprints (same tool + same args hash). This is the production analog of loop detection.
- **Task completion rate (TCR)**: fraction of runs that reach a structured FINAL_ANSWER within the budget (`max_iterations`, `max_tokens`, `wall_clock`). For the support-ticket agent, TCR should be >90% within 5 turns.

Compute TCR against the golden task set offline, and track it in production via orchestrator-emitted run-outcome events.

**3. Context adherence (goal drift)**

Goal drift is the hardest failure to detect because the agent appears to make progress but toward the wrong objective.

- **Offline** — goal-adherence score: after each completed trajectory, use an LLM judge (a frontier model with a rubric) to score `[0–1]` whether the final output satisfies the original task description. Include the full trajectory in the judge prompt so it can detect intermediate drift.
- **Online** — cosine drift tracking: embed the user's original goal at turn 0; embed each agent step summary. If the cosine similarity between the step embedding and the original goal embedding drops below a threshold (e.g., 0.65) for two consecutive steps, fire a goal-drift alert.
- **Context precision on retrieved knowledge**: if the agent uses RAG internally, measure RAGAS `context_precision` — low precision means retrieved docs are off-topic, which is a leading indicator of hallucinated tool args.

**Full eval matrix:**

| Dimension | Offline metric | Production metric | Threshold |
|-----------|---------------|-------------------|-----------|
| Tool selection | Selection accuracy @step | Tool error rate | >85% acc; <5% error |
| Arg quality | Arg hallucination rate | Schema validation failure rate | <5% hallucination |
| Progress | Steps-to-completion ratio | No-progress rate | ratio <2×; <3% stuck runs |
| Completion | Task completion rate (TCR) | TCR per run cohort | >90% |
| Goal adherence | LLM-judge score | Cosine drift alert | >0.80 judge; >0.65 cosine |
| Business | — (offline only) | Deflection rate, CSAT, cost/run | Org-specific SLOs |

### Example / Tradeoff

**Support-ticket agent (LangSmith + custom eval):** A 5-step agent that fetches ticket context, queries CRM, drafts a response, and submits. Golden dataset: 150 tickets with annotated correct tool call per step.

- Baseline tool selection accuracy: 78% (wrong tool called 22% of steps — mostly confusing `fetch_ticket` vs `search_kb`).
- Fix: improved tool descriptions with explicit DO-NOT-use conditions.
- After fix: 94% accuracy, arg hallucination rate dropped from 18% → 3%.
- TCR in production: 91% within 5 turns, 7% reach the turn cap (escalated to human), 2% crash.

**Tradeoff — LLM judge cost vs. proxy metrics:** LLM-judge evaluation at scale costs ~$0.02/run with a frontier model (150 tokens input + 50 output). At 10K runs/day that's $200/day. Use LLM judge on a sampled 5% of production runs and 100% of golden-dataset regression runs; use cheaper proxy metrics (cosine drift, TCR, tool error rate) for the other 95%.

---

## Verbal script

**Opening (30s):**
"Evaluating an agent is much harder than evaluating a single LLM call because you're assessing a multi-step trajectory rather than a single output. I break it into three dimensions: did the agent choose the right tools, did it make forward progress, and did it stay focused on the original goal? Each has different measurement techniques for offline benchmarking versus production monitoring."

**Core explanation (2–3 min):**
"Starting with tool selection accuracy — I'd build a golden dataset of representative tasks with annotated correct tool calls at each step. I'd compute two metrics: selection accuracy, which is the fraction of steps where the agent chose the right tool, and argument hallucination rate, which is how often required args were fabricated rather than grounded in context. In LangSmith, you can log every tool call with run_id and step index and replay those against the golden annotations. In production I'd track tool error rate — schema validation failures and 400s — per tool per day, because a sudden spike usually means a schema broke after a tool update.

For action advancement, I'd measure steps-to-completion relative to the expert trajectory. If the agent takes twice as many steps as the golden trajectory on average, it's over-planning or looping. In production I'd compute a no-progress rate: the fraction of runs where two consecutive steps have identical action fingerprints — same tool, same args. That's a dead giveaway for an infinite loop. Task completion rate — how often the agent reaches a FINAL_ANSWER within its turn budget — is the headline metric for production reporting.

Goal drift is the sneakiest failure. The agent appears busy but is answering the wrong question. Offline, I'd use an LLM judge with a rubric that gets the full trajectory and scores whether the final output satisfies the original goal. In production I'd embed the user's goal at turn zero and embed each step summary, then alert when cosine similarity drops below 0.65 for two consecutive steps — that's a reliable leading indicator before the user gets a useless response."

**Tradeoff / production angle (1 min):**
"The main practical tradeoff is LLM-judge eval cost versus proxy metric coverage. Running a frontier model as a judge on every production run costs $200/day at 10K runs. I'd run the judge on a 5% sample plus 100% of golden-dataset regression runs, and use cheaper signals — cosine drift, TCR, tool error rate — for everything else. The risk is the proxies miss subtle goal-drift cases that the judge would catch; I'd calibrate the proxy thresholds against the judge on a quarterly basis.

The other important operational note: connect eval to deployment gates. If tool selection accuracy on the golden dataset drops below 85% after a prompt or tool-schema change, that should block the release — same way test coverage gates block a code deploy."

**Wrap-up (30s):**
"So the framework is: three dimensions, two regimes. Offline golden-trajectory benchmarks for tool accuracy and TCR before deployment, LLM-judge scoring on sampled production runs for goal adherence, and lightweight proxy metrics — no-progress rate, cosine drift, tool error rate — for real-time alerting. Happy to go deeper on the LangSmith dataset setup or the LLM-judge rubric design."

---

## Pitfalls

- **Mistake:** Treating task completion rate as the only metric ("the agent either finishes or it doesn't") — **Better:** Distinguish TCR (did it finish?) from goal adherence (did the final output satisfy the original intent?), tool selection accuracy (were intermediate steps correct?), and action advancement (was there unnecessary looping?). An agent can complete a task via a wrong but accidentally correct path, or complete while drifting from the user's actual goal.
- **Mistake:** Saying "I'd watch the logs" without describing structured telemetry — **Better:** Specify the exact events emitted per step (`run_id`, `step`, `tool_name`, `args_summary`, `result_status`), the aggregated dashboards (tool error rate, no-progress rate, TCR), and the alerting thresholds (2σ above baseline tool error rate triggers PagerDuty).
- **Mistake:** Proposing LLM-judge evaluation on 100% of production runs without mentioning cost — **Better:** Design a tiered approach: LLM judge on a 5% production sample + 100% golden regressions + cheaper proxy metrics (cosine drift, TCR) for everything else, with quarterly calibration of proxy thresholds against the judge.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q30: Monitor autonomous agent behavior in production](03-030-monitor-autonomous-agent-behavior-in-production.md) | Complementary — monitoring is the operational layer; this question focuses on the eval metrics and benchmarking framework |
| [Q17: Planning failures hardest to detect in production](03-017-planning-failures-hardest-to-detect-in-production.md) | Goal drift and sycophantic loops are covered here from an eval angle; Q17 covers detection mechanisms |
| [Q8: How evaluate a RAG pipeline? What metrics?](02-021-how-evaluate-a-rag-pipeline.md) | RAGAS metrics for RAG-using agents; context_precision is a leading indicator of tool-arg hallucination |

---

## One-liner recall

> Evaluate agents across three dimensions — tool selection accuracy (golden-dataset step annotations), action advancement (steps-to-completion ratio + no-progress rate), and context/goal adherence (LLM-judge on sampled runs + cosine drift monitoring) — and gate deployments on the offline golden-dataset benchmarks.
