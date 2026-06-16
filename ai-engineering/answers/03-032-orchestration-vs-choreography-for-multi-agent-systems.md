# Orchestration vs choreography for multi-agent systems?

**Category:** 03-agents-tool-use
**Question #:** 032
**Source section:** §3 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
Interviewers want to know whether you understand the two canonical patterns for coordinating multiple agents and can reason about their production tradeoffs — reliability, debuggability, coupling, and scalability. It probes architectural maturity beyond single-agent loops.

### Trigger phrases
- "How do multiple agents communicate and coordinate?"
- "Would you use a supervisor agent or event-driven agents for this?"
- "How do you design a multi-agent system without a single point of failure?"
- "Walk me through orchestration vs choreography in the context of agents."

### What it tests
Ability to choose and justify a multi-agent coordination pattern based on reliability, latency, debuggability, and coupling requirements.

---

## Answer

### Concept
**Orchestration** uses a central supervisor agent (or orchestrator) that explicitly directs specialist sub-agents — it tells each one what to do and when. **Choreography** removes the central coordinator: agents react to events (messages on a queue or topic) and self-coordinate by publishing results that trigger the next agent downstream. The key distinction is *who decides the next step*: a single brain (orchestration) vs. the agents themselves reacting to shared state (choreography).

### Mechanism

**Orchestration (centralized control):**
```
User Request
     │
     ▼
Supervisor Agent (LLM planner)
  ├─→ spawns ResearchAgent → result returned to supervisor
  ├─→ spawns WriterAgent(research_result) → draft returned
  └─→ spawns CriticAgent(draft) → feedback, loop or finalize
     │
     ▼
Final response
```
- Supervisor holds the global plan; sub-agents are stateless workers.
- Easy to trace: one call graph rooted at the supervisor.
- Single point of failure: supervisor crash or hallucination derails everything.
- Framework: LangGraph with a supervisor node, CrewAI orchestrator pattern, AutoGen GroupChat manager.

**Choreography (event-driven, decentralized):**
```
User Request → Event Bus (Kafka / AWS SNS)
     │
     ├─→ ResearchAgent subscribes to "task.created" → publishes "research.done"
     ├─→ WriterAgent subscribes to "research.done" → publishes "draft.ready"
     └─→ CriticAgent subscribes to "draft.ready" → publishes "review.done" or "draft.revised"
     │
     ▼
FinalDispatcher subscribes to "review.done" → delivers response
```
- No agent knows the full pipeline; each knows only its upstream trigger and downstream event.
- High resilience: agent failure → dead-letter queue → retry without restarting the whole pipeline.
- Harder to trace end-to-end; requires distributed tracing (OpenTelemetry + correlation IDs).
- Framework: Kafka topics, AWS EventBridge, Temporal workflows (choreography with visibility), Celery chains.

### Example / Tradeoff

| Dimension | Orchestration | Choreography |
|-----------|--------------|--------------|
| Coupling | Supervisor knows all agents | Agents know only their event contract |
| Debuggability | Easy — one call tree | Hard — distributed traces needed (OTel) |
| Resilience | SPOF at supervisor | Individual agent failure is isolated |
| Adaptability | Supervisor must be updated for new agents | Add agent by subscribing to an event |
| Latency | Sequential by default (unless supervisor fans out) | Natural fan-out, parallel processing |
| Cost predictability | Easy to budget per supervisor call | Harder — fan-out can multiply unexpectedly |
| Best for | Research assistants, complex multi-step planning, regulated flows needing HITL | Data pipelines, high-volume parallel document processing, loosely-coupled microservice-style AI workflows |

**Concrete example:** A research report generator with 3 agents (researcher, writer, critic) is a natural orchestration fit — the supervisor coordinates tight feedback loops and can insert HITL before finalizing. A document-ingestion pipeline processing 10K PDFs/hour with OCR → extraction → embedding → indexing agents is a natural choreography fit — each agent scales independently, Kafka provides replay on failure, and there's no need for a central planner to monitor every document.

**Hybrid pattern:** Use orchestration at the high-level workflow (supervisor plans which pipeline to invoke) and choreography internally within each pipeline stage for parallelism and resilience. LangGraph supports this: a supervisor node emits tasks to a Kafka-backed worker pool, then collects results.

---

## Verbal script

**Opening (30s):**
"This is a classic distributed systems question applied to agents. The two patterns are orchestration — where a central supervisor directs all the agents — and choreography — where agents are event-driven and self-coordinate. The right choice depends on how tightly coupled your workflow is, how much resilience you need, and how many agents you're coordinating."

**Core explanation (2–3 min):**
"In orchestration, I have a supervisor agent — often an LLM planner — that explicitly delegates tasks to specialist sub-agents. The supervisor calls ResearchAgent, gets the result, calls WriterAgent with that result, then passes the draft to CriticAgent. It's like a manager calling employees one at a time. The advantage is that the call graph is simple: one root, easy to trace with LangSmith, easy to insert HITL before any step. LangGraph's supervisor pattern and CrewAI both implement this.

The downside is the supervisor is a single point of failure. If it hallucinates a bad plan, everything downstream is wrong. It also tends to be sequential unless the supervisor explicitly fans out.

In choreography, I remove the central coordinator entirely. Agents subscribe to events on a bus — say Kafka. ResearchAgent listens for 'task.created', does its work, and publishes 'research.done'. WriterAgent listens for 'research.done', does its work, publishes 'draft.ready'. No agent knows the full pipeline. This is highly resilient — if WriterAgent crashes, the message sits in Kafka and gets retried once it recovers. New agents can be added by subscribing to existing events without changing anything else.

The cost is observability: I need distributed tracing — OpenTelemetry with correlation IDs — to reconstruct what happened across agents. Choreography also makes it harder to enforce HITL mid-pipeline."

**Tradeoff / production angle (1 min):**
"For a research-assistant product with 3–5 agents doing tight feedback loops — research, draft, critique, revision — I'd use orchestration via LangGraph. The call structure is predictable, I can add HITL before the final output, and debugging is straightforward.

For a document-ingestion pipeline processing tens of thousands of PDFs daily, I'd use choreography with Kafka: OCR → extraction → embedding → indexing agents all scale independently, failed messages are retried from the queue, and adding a new enrichment step doesn't require touching the orchestrator.

The hybrid pattern I often reach for in production is orchestration at the workflow level with choreography inside high-volume pipeline stages."

**Wrap-up (30s):**
"So the decision comes down to: tightly coupled, inspection-heavy workflows → orchestration; loosely coupled, high-volume, resilience-first pipelines → choreography. Happy to go deeper on how HITL fits into each pattern or how Temporal bridges the two."

---

## Pitfalls

- **Mistake:** Defining orchestration as "using a tool like LangChain" and choreography as "not using a framework" — **Better:** Frame it as *who decides the next step*: a central coordinator (orchestration) vs. agents reacting to events (choreography); both can be implemented with or without frameworks.
- **Mistake:** Saying choreography is "always better because it's more scalable" without acknowledging the observability and HITL challenges — **Better:** Call out that choreography requires distributed tracing (OTel + correlation IDs) and makes mid-pipeline HITL gates significantly harder to implement.
- **Mistake:** Ignoring the hybrid pattern — **Better:** In production, most non-trivial systems combine both: orchestration at the workflow planning level and choreography internally for parallel, high-volume stages.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q8: Walk through a production-ready agent architecture](03-008-walk-through-a-production-ready-agent-architecture.md) | Orchestration is the default single-agent architecture; this extends it to multi-agent |
| [Q20: Architect an agent system: loop, tools, memory, orchestration, safety](03-020-architect-an-agent-system-loop-tools-memory-orchestration-sa.md) | Full architecture view including orchestration layer |
| [Q30: Monitor autonomous agent behavior in production](03-030-monitor-autonomous-agent-behavior-in-production.md) | Choreography makes observability harder — distributed tracing is the key mitigation |

---

## One-liner recall

> Orchestration centralizes control in a supervisor (easy to trace, SPOF), while choreography uses event-driven agents reacting to a shared bus (resilient, scalable, but harder to observe) — choose orchestration for tight coupled workflows, choreography for high-volume parallel pipelines, and combine both in production.
