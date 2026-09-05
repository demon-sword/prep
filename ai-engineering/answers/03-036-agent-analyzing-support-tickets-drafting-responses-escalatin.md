# Agent analyzing support tickets, drafting responses, escalating

**Category:** 03-agents-tool-use
**Question #:** 036
**Source section:** §3 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
This is a design question disguised as a scenario prompt. The interviewer wants to see whether you can translate a realistic business workflow — support ticket triage — into a concrete agentic architecture with tool definitions, memory, escalation logic, and cost/safety controls. It tests whether you think about the happy path only or also about failure modes, human-in-the-loop triggers, latency SLOs, and eval.

### Trigger phrases
- "Design an agent that handles customer support tickets end-to-end."
- "How would an agent triage, respond to, and escalate support requests?"
- "Walk me through a real-world agentic workflow for customer service automation."

### What it tests
Ability to decompose a multi-stage business workflow into an agentic architecture with clear tool schemas, HITL triggers, memory strategy, and production quality controls.

---

## Answer

### Concept
A support-ticket agent sits in a ReAct or Plan-and-Execute loop: it reads an incoming ticket, retrieves relevant knowledge (RAG over docs + ticket history), classifies intent and urgency, drafts a response, and either sends it automatically or escalates to a human agent — governed by confidence thresholds and risk rules rather than hard-coded routing.

### Mechanism

**Pipeline stages:**

```
Ticket arrives (webhook / queue)
  → [classify_ticket] — intent, urgency, customer tier (a small fast model, T=0)
  → [retrieve_context] — RAG: KB docs + similar resolved tickets (Pinecone + BM25 hybrid)
  → [draft_response]  — a small fast model with grounding prompt, citation requirement
  → [score_confidence] — RAGAS faithfulness + self-assessed confidence field
  → decision gate ──┬── confidence ≥ 0.85 AND urgency ≠ "critical" → [send_response]
                    └── else → [escalate_to_human] with draft pre-filled
  → [update_ticket_state] — log action, tag resolution path, write episodic memory
```

**Tool schemas (simplified):**
```json
classify_ticket(ticket_id, text) → {intent, urgency: low|medium|high|critical, customer_tier}
retrieve_context(query, filters) → [{chunk, source, score}]
draft_response(ticket, context, tone) → {response_text, citations, confidence}
send_response(ticket_id, response_text) → {status, sent_at}
escalate_to_human(ticket_id, draft, reason) → {queue, agent_assigned}
update_ticket_state(ticket_id, action, metadata) → {ok}
```

**Memory strategy:**
- **Working memory:** current ticket + retrieved context in-context window
- **Episodic memory:** resolved ticket summaries in Redis (TTL 90 days) — retrieved for similar-ticket lookup
- **Semantic memory:** KB product docs in Pinecone — shared across all agent runs
- **Procedural memory:** escalation rules and tone guidelines in system prompt (updated weekly)

**Escalation triggers (in orchestrator code, not prompts):**
1. Urgency = `critical` (always sync HITL)
2. Agent confidence < 0.85
3. Sentiment classifier detects extreme negativity / threat
4. Customer tier = enterprise AND intent = billing dispute
5. Agent used >4 tool calls without convergence (loop detection)

**Observability:** LangSmith traces per ticket; dashboards for deflection rate, CSAT, draft-acceptance rate, p95 latency per stage.

### Example / Tradeoff

**Concrete stack:** LangGraph for the agent loop, a small fast model for classification + drafting, Pinecone (hybrid BM25+dense) for KB retrieval, Cohere Rerank for top-5 context selection, Zendesk API for ticket read/write, Redis for episodic session state, LangSmith for tracing.

**Cost math (1M tickets/day):**
- Classification + draft: ~800 tokens avg → a small fast model: ~$0.12/1K → ~$100/day
- RAG retrieval (Pinecone): ~$40/day at that volume
- ~20% escalations skip generation cost savings
- vs. human agents at $0.50–2.00/ticket: automation saves ~$400K–1.9M/day at 1M volume

**Key tradeoff:** Confidence threshold controls the deflection vs escalation rate. Too high (0.95) → most tickets escalate → low ROI. Too low (0.70) → hallucinated responses go out → CSAT/churn damage. Tune on a golden set of 200–500 labeled tickets; track by intent cluster.

---

## Verbal script

**Opening (30s):**
"I'd approach this as a multi-tool ReAct agent with a structured escalation gate. The core loop is: classify the ticket → retrieve KB context → draft a response → score confidence → either send automatically or escalate with the draft pre-filled. Let me walk through each piece."

**Core explanation (2–3 min):**
"The agent has five tools — classify_ticket, retrieve_context, draft_response, send_response, and escalate_to_human — each with a typed JSON schema so the LLM's tool selection is highly constrained and predictable.

For retrieval, I'd use a hybrid RAG setup: Pinecone for dense semantic search over KB articles, BM25 for exact product-name matching, and RRF fusion to merge results, then Cohere Rerank to pick the top 5 chunks. This is important because support tickets often have exact model numbers or error codes that dense-only retrieval misses.

The response is drafted with a small fast model at temperature zero, with a grounding prompt that says 'only use the provided context, cite sources, abstain if unsure.' Then I run a confidence check — either a self-assessed confidence field in the structured output or an async RAGAS faithfulness pass.

The escalation gate lives in the orchestrator code, not in the prompt. If urgency is critical, confidence below 0.85, or it's an enterprise billing dispute, we route to a human queue via the escalate_to_human tool, passing the pre-drafted response so the agent's work still has value even when escalated."

**Tradeoff / production angle (1 min):**
"The key production challenge is calibrating the confidence threshold. I'd tune it on a golden set of 200+ labeled tickets — annotated with 'correct to send' vs 'should escalate' — and plot deflection rate vs CSAT at different thresholds. Separately, I'd monitor draft_acceptance_rate: if human agents are editing >40% of pre-filled drafts, the drafting quality needs improvement. Also, episodic memory is important for recurring customers — pulling their last 3–5 resolved tickets from Redis gives the agent context to not repeat solutions or acknowledge a pattern, which dramatically improves CSAT."

**Wrap-up (30s):**
"So the key design decisions are: typed tool schemas for predictable LLM calls, confidence-gated escalation in orchestrator code, hybrid RAG for support-domain vocabulary, and LangSmith tracing for every ticket to measure deflection rate and spot regressions. Happy to go deeper on the escalation logic or the eval framework."

---

## Pitfalls

- **Mistake:** Describing the agent as "reads the ticket and replies" with no mention of escalation, confidence gating, or HITL triggers — **Better:** Explain the escalation gate explicitly (confidence threshold, urgency classifier, customer tier rules) as orchestrator-enforced logic, not prompt instructions, because an agent that never escalates is a liability in production.
- **Mistake:** Using temperature > 0 for response drafting or omitting a grounding prompt — **Better:** Set T=0 for the draft_response tool call and include an explicit "only use provided context, cite sources, abstain if unsure" instruction; ungrounded responses at scale cause CSAT damage that's hard to recover from.
- **Mistake:** Relying on a single dense vector retrieval without BM25 — **Better:** Support tickets contain product codes, error IDs, and SKUs that dense-only retrieval misses; hybrid BM25+dense with RRF fusion is the production default for support domains.
- **Mistake:** Not mentioning how to evaluate the agent — **Better:** Define draft_acceptance_rate (human edits), deflection_rate (auto-sent), and CSAT delta vs baseline as the three core production SLOs, and tune the confidence threshold on a golden labeled dataset.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q8: Walk through a production-ready agent architecture](03-008-walk-through-a-production-ready-agent-architecture.md) | Foundation architecture this design builds on |
| [Q29: Human-in-the-loop patterns — when trigger human review?](03-029-human-in-the-loop-patterns-when-trigger-human-review.md) | Escalation trigger design — confidence, urgency, domain rules |
| [Q1: Design a RAG system for a customer support chatbot](../answers/02-001-design-a-rag-system-for-a-customer-support-chatbot.md) | RAG layer within this agent — same stack, more detail on retrieval eval |

---

## One-liner recall

> A support-ticket agent runs classify → RAG-retrieve → draft → confidence-gate → auto-send or escalate-with-draft, with typed tool schemas, hybrid BM25+dense retrieval, T=0 grounding, and threshold tuned on a golden labeled set tracked via deflection rate and CSAT.
