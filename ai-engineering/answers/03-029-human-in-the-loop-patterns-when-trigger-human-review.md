# Human-in-the-loop patterns — when trigger human review?

**Category:** 03-agents-tool-use
**Question #:** 029
**Source section:** §3 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
Interviewers probe whether you understand that fully autonomous agents are not always appropriate — and that the ability to design principled HITL checkpoints is what separates production-grade agent systems from demos. They want to see concrete trigger criteria, not hand-waving about "when it seems risky."

### Trigger phrases
- "How do you decide when to pause an agent and ask a human?"
- "What are your HITL patterns for agentic workflows?"
- "How do you keep humans in the loop without breaking automation?"
- "When should an agent escalate vs proceed autonomously?"

### What it tests
Ability to design safe, auditable agent systems with principled escalation criteria — production experience with real failure modes rather than theoretical safety awareness.

---

## Answer

### Concept
Human-in-the-loop (HITL) in agentic systems means inserting a mandatory human approval or review checkpoint before the agent proceeds to an action the system cannot safely reverse or whose consequences exceed an acceptable risk threshold. The goal is to capture the efficiency of automation while keeping human judgment at the decision boundaries that matter most.

### Mechanism

**Four trigger categories — implement as orchestrator-side rules, not LLM-side prompts:**

| Trigger category | Examples | Pattern |
|-----------------|----------|---------|
| **Irreversibility** | Delete files, send emails, execute payments, deploy to prod | `interrupt_before` on any write/send/delete tool call |
| **Confidence below threshold** | LLM uncertainty signal, tool output cosine sim < 0.6, ambiguous user intent | Structured `CLARIFY` action type in schema; agent emits it and pauses |
| **High-stakes domain** | Medical advice, legal contract generation, financial transactions > $X | Static allowlist of tool + context combinations requiring approval |
| **Budget / anomaly** | Token spend > 2× baseline, turn count > max_turns × 0.8, tool call loop detected | Orchestrator circuit-breaker: pause + alert Slack/PagerDuty |

**Implementation with LangGraph:**
```python
from langgraph.graph import StateGraph
from langgraph.checkpoint.postgres import PostgresSaver

# interrupt_before makes the graph pause before executing the node
graph = StateGraph(...)
graph.add_node("send_email", send_email_tool)
graph.compile(
    checkpointer=PostgresSaver(conn),
    interrupt_before=["send_email", "delete_record", "execute_payment"]
)

# Resume after human approval
graph.invoke(None, config={"thread_id": thread_id})  # resumes from checkpoint
```

**Async approval queue pattern (for regulated domains):**
1. Agent emits a `PendingApproval` event → writes to Postgres `approvals` table
2. Notification pushed to reviewer (Slack/email) with agent state snapshot
3. Reviewer approves/rejects/edits via UI → writes decision
4. Orchestrator polls or listens via webhook → resumes or aborts the thread

**Tiered autonomy by action class:**
```
Low risk (read-only queries, drafts, analysis):
  → fully autonomous, log only

Medium risk (outbound communication drafts, API writes with undo):
  → shadow review: proceed, flag for async human audit within 24h

High risk (irreversible writes, external payments, PII access beyond scope):
  → synchronous human approval before proceeding

Critical (medical triage, legal filings, security changes):
  → mandatory dual approval + structured audit trail
```

### Example / Tradeoff
A support-ticket agent (LangGraph + GPT-4o) uses `interrupt_before=["send_reply", "issue_refund"]`. For standard replies (confidence > 0.85, no refund), it runs fully autonomously — 80% of tickets resolved without human touch. For anything triggering the interrupt (15% of tickets), a reviewer approves in the UI within 2 minutes. The remaining 5% (escalations, angry customers flagged by sentiment classifier) go directly to human agents.

**Latency vs safety tradeoff:** Synchronous HITL adds 2–10 min median wait to high-risk actions. Async shadow review adds zero latency but catches issues after the fact. The choice depends on reversibility: async is acceptable for outbound drafts (can be recalled), synchronous is required for payments or deletions.

**Calibrating thresholds:** Start conservative (interrupt on all writes), then use production data to identify which interrupts are always approved → promote to async review → eventually fully autonomous with logging. This "trust escalation" pattern avoids both over-automation and under-automation.

---

## Verbal script

**Opening (30s):**
"HITL is one of those things every agent system needs but many demos skip. The key insight I'd lead with is that HITL triggers should live in the orchestrator as deterministic rules — not in the LLM's prompt — because you can't rely on the model to correctly assess when it needs help. Let me walk through the trigger categories I use and how to implement them."

**Core explanation (2–3 min):**
"I think of HITL triggers across four categories. First is irreversibility — any action the system cannot undo. Sending an email, executing a payment, deleting a record: these get an `interrupt_before` gate in LangGraph, so the graph pauses and writes a checkpoint to Postgres before the tool is ever called. A reviewer sees the pending action in a UI, approves or edits it, and the graph resumes.

Second is confidence below threshold — when the agent's own structured output includes a low-confidence signal or when the retrieved context similarity is below, say, 0.6. I implement this as a CLARIFY action type in the tool schema: instead of calling a tool, the agent emits a clarification request, which surfaces to the user or reviewer.

Third is high-stakes domain — medical, legal, financial. Here I use a static allowlist: certain tool+context combinations always require approval regardless of confidence. This is a policy decision, not a model decision.

Fourth is budget or anomaly — if the agent is spending 2× the expected tokens, or is on turn 18 of a 20-turn max, I treat that as a circuit-breaker signal. The orchestrator pauses and pages the on-call engineer."

**Tradeoff / production angle (1 min):**
"The key tradeoff is latency vs safety. Synchronous HITL adds 2–10 minutes of wait time, which is fine for high-stakes actions but kills UX for routine ones. So I use tiered autonomy: fully autonomous for low-risk reads and drafts, async shadow review for medium-risk writes where there's an undo path, and synchronous approval for truly irreversible or high-stakes actions. Over time, I track which synchronous interrupts are 100% approved in production and promote them to async — so the system gets progressively more autonomous as trust is established."

**Wrap-up (30s):**
"The core principle: HITL triggers are orchestrator-level deterministic policy — irreversibility, confidence threshold, domain class, anomaly budget — not prompts asking the model to ask for help. Happy to go deeper on the LangGraph checkpoint/resume implementation or the async approval queue pattern."

---

## Pitfalls

- **Mistake:** "I put a line in the prompt saying 'ask the human when you're unsure'" — **Better:** Implement HITL as orchestrator-side code using `interrupt_before` on specific tool nodes or a confidence-threshold circuit breaker; LLM-side instructions are unreliable for safety-critical decisions.
- **Mistake:** "HITL everywhere to be safe" without considering latency impact — **Better:** Use tiered autonomy — synchronous approval only for irreversible/high-stakes actions, async shadow review for medium-risk, fully autonomous for low-risk — and track approval rates to progressively reduce unnecessary interrupts.
- **Mistake:** Not persisting agent state before the interrupt, so approval restarts the full workflow — **Better:** Use a checkpointing mechanism (LangGraph `PostgresSaver`, Redis snapshot) so the graph resumes from the exact point of interruption after human approval.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q10: Design a safe and debuggable agent loop](03-010-design-a-safe-and-debuggable-agent-loop.md) | prerequisite — loop design determines where HITL checkpoints are inserted |
| [Q5: How define and enforce agent autonomy boundaries](03-005-how-define-and-enforce-agent-autonomy-boundaries.md) | companion — autonomy boundaries define the HITL trigger policy |
| [Q31: Agents in regulated domains (financial, healthcare)](03-031-agents-in-regulated-domains-financial-healthcare.md) | follow-up — regulated domains require mandatory HITL for specific action classes |

---

## One-liner recall

> HITL triggers belong in orchestrator code as deterministic rules (irreversibility, confidence threshold, domain class, anomaly budget) — not in LLM prompts — implemented via `interrupt_before` checkpoints with tiered autonomy (sync for irreversible, async shadow for medium-risk, fully autonomous for low-risk).
