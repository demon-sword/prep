# How define and enforce agent autonomy boundaries?

**Category:** 03-agents-tool-use
**Question #:** 005
**Source section:** §3 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
Interviewers probe whether you understand that unbounded autonomy is a production liability, not a feature. The question tests whether you've thought about *who decides* what an agent is allowed to do, how that decision is encoded in the system (not just the prompt), and how violations are caught before they cause harm — financial, reputational, or security. Senior engineers are expected to have concrete mechanisms, not vague assurances.

### Trigger phrases
- "How would you prevent an agent from doing something dangerous?"
- "How do you control what actions an agent can take?"
- "What guardrails do you put on autonomous agents?"
- "How do you define the scope of what an agent is allowed to do?"

### What it tests
The ability to translate a vague "give the agent guardrails" requirement into concrete architectural patterns: allowlists, capability scoping, HITL triggers, and runtime policy enforcement.

---

## Answer

### Concept
Agent autonomy boundaries are the explicit constraints on what actions an agent can initiate, what resources it can touch, and under what conditions it must pause for human review. Boundaries are defined at design time (capability scoping, tool allowlists) and enforced at runtime (policy checks, budget limits, HITL triggers) — never just described in a system prompt, which the LLM can ignore or reason around.

### Mechanism

**1. Capability scoping (design time)**
- Give the agent only the tools it needs — no omnibus tool set. A customer support agent gets `search_knowledge_base`, `update_ticket_status`, `send_email_to_customer` — not `delete_account`, `run_sql_query`, or `call_external_api`.
- Each tool schema carries its own permission level (read-only vs write, low-stakes vs high-stakes). LangChain StructuredTool and OpenAI function definitions enforce the schema; the orchestrator enforces which tools are loaded.

**2. Action allowlisting / denylisting (runtime policy)**
- Before any tool call executes, a policy layer evaluates it: Is this tool in the allowed set? Does the argument satisfy constraints (e.g., dollar amount < $500, user's own data only)?
- Implemented as a middleware intercept in the agent loop — not inside the LLM prompt. Tools like LangGraph's `interrupt` or custom `pre_tool_call` hooks enforce this.

**3. Resource and budget limits**
- Turn budget: cap the number of LLM calls or tool invocations per task (e.g., max 10 steps). Prevents runaway loops.
- Cost budget: track cumulative API spend per run; abort if a threshold is crossed.
- Time budget: hard timeout (e.g., 30 seconds) triggers graceful shutdown and HITL escalation.

**4. Human-in-the-loop (HITL) triggers**
- Irreversible actions (delete, send email, charge card) pause the loop and require human approval.
- Confidence threshold: if the agent's planned action has high uncertainty (detected via structured output confidence field or low tool-call consistency across samples), escalate.
- Anomaly triggers: action type not seen in training distribution → pause.

**5. Environment isolation (sandboxing)**
- Code execution happens in a sandboxed container (e.g., E2B, Modal, AWS Fargate with no VPC egress) — the agent cannot reach production databases or external APIs directly.
- Read-only replicas and staging environments for data-touching actions.

**6. Audit trail and post-hoc enforcement**
- Every tool call logged with timestamp, arguments, result, and agent reasoning trace (LangSmith, OpenTelemetry). Enables replay debugging and policy violation detection.
- Anomaly detection on the trace stream: flag runs that invoke high-risk tools above a frequency threshold.

### Example / Tradeoff

A financial reconciliation agent at a fintech startup: tools are `read_ledger(date_range)`, `flag_discrepancy(transaction_id, reason)`, and `create_jira_ticket(summary)`. The tool `write_ledger_correction` is explicitly excluded — any correction requires human approval via a HITL workflow in LangGraph (`interrupt_before=["write_ledger_correction"]`). Turn budget is 20 steps; cost budget is $0.50 per run. All tool calls emit structured logs to Datadog. Result: the agent runs autonomously for ~95% of reconciliation cases, with human review triggered for the remaining 5% involving write actions.

**Tradeoff:** Tight boundaries reduce agent utility — if you allowlist too few tools, the agent can't complete tasks and escalates constantly, frustrating users. If boundaries are too loose, one jailbreak or prompt-injection attack has real consequences. The right calibration is task-specific: start with read-only access, add write tools one at a time with HITL on each new capability, and tighten after observing production behavior.

---

## Verbal script

**Opening (30s):**
"Agent autonomy boundaries are really about two things: defining what the agent *can* do at design time, and enforcing it at runtime so the LLM can't reason its way around the constraint. I'd break this into capability scoping, runtime policy enforcement, HITL triggers, and sandboxing."

**Core explanation (2–3 min):**
"I'd start at the tool layer — the agent only gets the tools it needs for its specific task. A customer support agent gets search and ticket tools, not a raw SQL tool. Each tool's schema defines its own constraints: argument types, value ranges, read vs write. The LLM is never given a tool it shouldn't call.

At runtime, before any tool executes, a policy middleware checks the call — is this tool in the allowed set, does the argument satisfy constraints like dollar limits or scope to the user's own data? This check lives in the orchestrator, not the prompt. In LangGraph I'd use `interrupt_before` on high-stakes tools to require human approval.

I'd also set hard budget limits — max 10 turns per task, max $0.50 in API spend, 30-second timeout. These prevent runaway loops. If any limit is hit, the agent gracefully escalates rather than failing silently.

Finally, sandboxing: if the agent executes code, it runs in an isolated container like E2B or Modal with no VPC egress. It can't reach production databases directly."

**Tradeoff / production angle (1 min):**
"The calibration question is hard — too tight and the agent escalates constantly and users stop trusting it; too loose and one prompt injection has real consequences. My approach is to start with read-only tools only, add write capabilities one at a time with HITL on each new capability, and only remove the HITL requirement after observing stable behavior in production. I also maintain a full audit trail in LangSmith or OpenTelemetry — every tool call logged with arguments and reasoning trace — so I can detect anomalies and replay failures."

**Wrap-up (30s):**
"In summary: scope at the tool level, enforce at the middleware layer with a policy check, set hard budgets, sandbox side-effectful execution, and wire HITL to irreversible actions. Happy to go deeper on any of those layers or talk about how I'd calibrate HITL thresholds for a specific domain."

---

## Pitfalls

- **Mistake:** "I put the constraints in the system prompt — I tell the agent it's not allowed to delete records." — **Better:** The system prompt is advisory; a sufficiently adversarial input or jailbreak can override it. Enforce constraints in the orchestrator's policy layer as code, not prose. The LLM cannot override a `if tool_name in DENIED_TOOLS: raise PolicyViolation` check.
- **Mistake:** Describing autonomy boundaries only in terms of prompt-level instructions without mentioning tooling, sandboxing, or HITL triggers — **Better:** Name the specific enforcement mechanism for each boundary type: allowlist tools in the tool registry, reject calls in a pre-execution policy hook, sandbox code in E2B/Modal, and gate irreversible actions behind `interrupt_before` (LangGraph) or a HITL approval queue.
- **Mistake:** "I'd just monitor the logs and fix issues afterward." — **Better:** Post-hoc monitoring catches violations after damage is done. Pre-execution policy checks are the primary control; monitoring is a secondary anomaly-detection layer.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q4: When is agentic architecture the wrong solution?](03-004-when-is-agentic-architecture-the-wrong-solution.md) | Prerequisite — autonomy risk is a core reason NOT to use agents in regulated/high-stakes contexts |
| [Q10: Design a safe and debuggable agent loop](03-010-design-a-safe-and-debuggable-agent-loop.md) | Follow-up — the agent loop design embodies the boundary enforcement architecture |
| [Q29: Human-in-the-loop patterns — when trigger human review?](03-029-human-in-the-loop-patterns-when-trigger-human-review.md) | Same concept — HITL is the primary runtime boundary enforcement mechanism |

---

## One-liner recall

> Autonomy boundaries = capability scoping at design time (allowlisted tools only) + runtime policy middleware (pre-call enforcement, hard budgets, HITL on irreversible actions) + sandboxed execution — never just a system prompt instruction the LLM can reason around.
