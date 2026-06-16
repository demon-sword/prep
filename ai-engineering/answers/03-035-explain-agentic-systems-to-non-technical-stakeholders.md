# Explain agentic systems to non-technical stakeholders?

**Category:** 03-agents-tool-use
**Question #:** 035
**Source section:** §3 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
Interviewers use this to probe communication skills, business acumen, and whether you can translate technical complexity into outcomes that matter to product managers, executives, or clients. Senior roles in particular require bridging engineering and business — an engineer who can't explain what they built won't get buy-in for resources or trust from stakeholders. In 2026 it's also a proxy for AI literacy: companies worry about stakeholders who misunderstand agents as either magic or dangerous.

### Trigger phrases
- "How would you explain this to a non-technical stakeholder?"
- "How do you get executive buy-in for an agentic feature?"
- "Walk me through how you'd present this system to a PM / legal team / C-suite."
- "How do you set expectations around what the agent can and can't do?"

### What it tests
Ability to translate system design into business outcomes and risk framing without using jargon — a must-have for senior and staff-level AI engineering roles.

---

## Answer

### Concept
An agentic system is an AI assistant that can **take sequences of actions on your behalf** — searching databases, drafting emails, calling APIs, checking calendars — and make decisions about what to do next based on what it observes. Instead of a single question-and-answer, it runs a loop: think → act → check result → think again. The key message for stakeholders: it handles multi-step tasks that used to require a human to coordinate, but it still needs guardrails and oversight for high-stakes steps.

### Mechanism
The communication framework has three layers:

**1. Analogy first — "a very capable junior employee":**
"Think of the agent like a smart junior analyst. You give it a task — 'research competitor pricing and draft a summary email' — and it figures out the steps: search the web, read the results, filter what's relevant, write the draft. It's not magic; it follows a process. But like a junior hire, it can make mistakes, so we put a manager (the human-in-the-loop trigger) in the chain for anything consequential — sending the email, for instance."

**2. Outcomes, not architecture:**
Translate capability into business value without mentioning LangGraph, ReAct, or orchestrators. Focus on:
- **Time saved:** "This replaces a 45-minute manual workflow with a 90-second automated one."
- **Scale:** "It handles 500 support tickets/day; previously that required 3 agents working full time."
- **Consistency:** "It applies the same policy every time — no variance between shifts."

**3. Risk and boundaries — proactively surface limitations:**
Non-technical stakeholders most often mis-set expectations. Address upfront:
- **What it can't do:** "It can't verify facts it wasn't given; it can hallucinate. That's why we gate the send action."
- **When humans stay in the loop:** "For any action that costs money, emails a customer, or modifies a record — a human reviews first."
- **How we measure success:** "We track: tasks completed without human intervention (deflection rate), customer satisfaction score, error rate, and cost per task."

### Example / Tradeoff
**Customer support agent at a SaaS company:**
- **Stakeholder pitch:** "Right now, Tier-1 support handles ~800 tickets/day. 60% are password resets, billing questions, or status checks — all rule-based. We're building an agent that handles those automatically, 24/7, in under 5 seconds. It escalates anything it's uncertain about. Expected outcome: 40% deflection rate, saving ~$180K/year in support costs, with CSAT maintained above 4.2/5."
- **Risk framing:** "The agent never cancels a subscription or issues a refund without a human confirming. The audit trail shows every action it took so we can review any complaint."

**Tradeoff to surface:** Stakeholders often want full automation immediately. The honest answer: "We start with read-only tasks, then add write actions incrementally as we build confidence — this is safer and lets us catch errors early without customer-facing impact."

---

## Verbal script

**Opening (30s):**
"Great question — this is something I've had to do a lot. My approach is to lead with the business outcome, use a concrete analogy, and proactively address the risks before they ask. I find stakeholders get in trouble when they either over-trust agents or dismiss them — so calibration is the job."

**Core explanation (2–3 min):**
"I'd start with an analogy: 'Imagine a very capable junior analyst who can use your company's tools — search internal docs, pull reports, draft emails — and figure out the right sequence of steps to complete a multi-part task. That's essentially what an AI agent is. It's not a chatbot that answers one question; it works through a chain of actions and adjusts based on what it finds.'

Then I'd shift to outcomes. For a support team: 'This agent handles 60% of Tier-1 tickets — the password resets, billing lookups, status checks — without a human touching them. That's 480 tickets a day resolved in under 10 seconds, versus the current 4-minute average. Your team focuses on the 40% that actually need a human.'

Then I'd ground it in metrics they care about: deflection rate, CSAT, cost-per-ticket, time-to-resolution.

Finally, I'd address risk before they bring it up: 'The agent doesn't have unlimited authority. Any action that touches money, sends an external email, or modifies an account triggers a human review. Every step is logged so if something goes wrong, we can audit it.' That framing — outcomes + boundaries + auditability — is what builds trust."

**Tradeoff / production angle (1 min):**
"The hardest part is expectation-setting around edge cases. Stakeholders often see a 90% success rate in the demo and assume 100% in production. I'm explicit: 'It will fail on ~5-10% of tasks in ways we don't fully predict. We design the system so failures are safe — it asks for help rather than guessing.' The other thing that surprises people is cost: at scale, agents can be significantly more expensive than a single LLM call because they make multiple API calls. So I always bring the cost-per-task number and compare it to the human equivalent."

**Wrap-up (30s):**
"The bottom line I leave them with: an agent is a force multiplier, not a replacement. It handles the repeatable, rules-based parts of a workflow at machine speed so your team can focus on judgment calls. And we instrument everything so you always know what it did and why. Happy to go deeper on the safety mechanisms or the evaluation framework."

---

## Pitfalls

- **Mistake:** Using technical jargon ("ReAct loop," "orchestrator," "tool-calling API") with a business audience — **Better:** Anchor on analogy ("junior analyst who uses your tools") and outcomes ("saves 40 hours/week"), then offer to explain the mechanics for those who want depth.
- **Mistake:** Glossing over failure modes and error rates to make the pitch sound cleaner — **Better:** Proactively state what the agent can't do ("it can't verify facts it wasn't given"), what triggers human review, and what the error rate is in testing. This builds more trust than overselling.
- **Mistake:** Skipping the cost conversation — **Better:** Always surface cost-per-task relative to the human alternative. Stakeholders who approve the project without knowing agent costs get surprised at the first billing cycle, which erodes trust.
- **Mistake:** Framing agents as "fully autonomous" in the first conversation — **Better:** Introduce tiered autonomy: read-only first, then write actions after demonstrated accuracy, with HITL gates throughout. This manages expectations and gives a clear roadmap.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q4: When is agentic architecture the wrong solution?](03-004-when-is-agentic-architecture-the-wrong-solution.md) | Anti-patterns to surface when setting stakeholder expectations |
| [Q29: Human-in-the-loop patterns — when trigger human review?](03-029-human-in-the-loop-patterns-when-trigger-human-review.md) | The governance story stakeholders most want to understand |
| [Q26: Control cost explosions from tool calls](03-026-control-cost-explosions-from-tool-calls.md) | Cost framing required for executive buy-in |

---

## One-liner recall

> Explain agents as a junior analyst who sequences tool use autonomously, lead with time-saved and deflection-rate outcomes, surface cost-per-task and HITL gates upfront, and resist the urge to use any jargon until they ask.
