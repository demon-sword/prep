# Version and roll back agent behavior?

**Category:** 03-agents-tool-use
**Question #:** 019
**Source section:** §3 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
This tests whether the candidate treats agent behavior as production software — with the same deployment rigor as APIs or models. Interviewers probe for GitOps fluency, feature-flag discipline, canary/shadow deployment patterns, and rollback SLAs. Weak candidates talk only about model versioning and miss that agent behavior lives in prompts, tool schemas, orchestration logic, and memory structures — all of which must be independently versioned and rolled back.

### Trigger phrases
- "How would you safely deploy a prompt change to a production agent?"
- "Agent behavior regressed in production — how do you roll back?"
- "How do you version your agent?"
- "What's your deployment strategy for agentic systems?"

### What it tests
Ability to apply production deployment discipline (versioning, canary, rollback, observability) to all three layers of agent behavior — prompts, tools, and orchestration logic.

---

## Answer

### Concept
Agent behavior is a composite of at least four independently mutable layers: system prompts, tool schemas, orchestration logic (graph/loop code), and model weights. Versioning and rollback means tracking changes across all four layers and having a path to restore any of them to a known-good state without full redeployment.

### Mechanism
**Layer 1 — Prompts (highest change velocity)**
- Store prompts in a versioned artifact store (LangSmith prompt hub, Promptflow, or Git-backed config). Each prompt has a `version_id` (e.g. `support-agent-v1.4.2`).
- At agent startup, the orchestrator loads prompts by version tag. Production uses `stable`; staging uses `canary`.
- Rollback: update `stable` tag to point to previous version — no code deploy required. Change propagates in <1 min via config reload.

**Layer 2 — Tool schemas**
- Tool definitions (JSON schema + function signature) are versioned in the same config store. Tool version is pinned in the agent config: `{"tool": "search_kb", "version": "v2"}`.
- Breaking schema changes (parameter rename, type change) require a new tool version; old version stays registered until all agents drain.

**Layer 3 — Orchestration logic (graph/loop code)**
- Agent graph (LangGraph DAG, ReAct loop) is versioned via Git tags and deployed as a Docker image with a semantic version.
- Use a blue-green deployment: route 5% of traffic to the new image, observe metrics (success rate, avg turns, cost/query) for 30 min, then flip 100% or roll back to the previous image.

**Layer 4 — Model**
- Pin `model_version` in agent config (e.g. `claude-sonnet-5-2024-11-20`). When a provider releases a new snapshot, run golden-dataset regression before promoting to production. If regression fails, keep the pinned old snapshot.

**Canary / shadow deployment flow:**
1. Tag new agent config version → deploy to `canary` slot (5% traffic).
2. Route real queries to both canary and prod (shadow mode for irreversible tools).
3. Compare metrics: turn count, tool-call distribution, success signal rate, error rate, cost/query.
4. If p95 latency or success rate regresses by >5% vs baseline → auto-rollback: flip `stable` tag back; alert on-call.
5. If metrics hold for 30 min (or N=500 queries) → promote canary to stable.

**Rollback SLA targets:**
- Prompt/config change: <2 min (config reload, no redeploy)
- Tool schema change: <5 min (config reload + drain window)
- Orchestration code change: <10 min (blue-green image swap)
- Model version change: <15 min (model snapshot rollback + cache clear)

### Example / Tradeoff
At a real support-agent rollout: prompt v1.5 increased avg turns from 3.2 to 5.8 (cost doubled) on canary. Auto-rollback fired after 200 queries when turn-count SLO breached. The `stable` tag was reverted in 90 seconds with zero user-facing disruption. The culprit was an ambiguous tool-use instruction that caused the agent to call `lookup_order` twice — fixed with an explicit idempotency instruction in the prompt before re-promoting.

**Key tradeoff:** Separate prompt versioning from code versioning dramatically reduces time-to-rollback for the highest-change-velocity layer (prompts), but adds configuration management complexity. At small scale (1–2 agents), a single Git repo for prompts + code is fine. At scale (10+ agents, multiple teams), a dedicated prompt registry (LangSmith / Promptflow) pays for itself.

---

## Verbal script

**Opening (30s):**
"Agent behavior lives in at least four independently mutable layers: system prompts, tool schemas, orchestration logic, and model version. I treat each one like a production microservice dependency — every layer is versioned, changes go through canary or shadow deployment, and rollback SLAs are defined before promoting anything to stable."

**Core explanation (2–3 min):**
"I'd start by separating prompt versioning from code versioning, because prompts change far more often than orchestration code. Prompts live in a versioned artifact store — LangSmith's prompt hub or a Git-backed config — each tagged with a semantic version. The orchestrator loads prompts by tag at startup: production reads from `stable`, canary gets a new tag. Rolling back a prompt means flipping the `stable` tag back to the previous version — that propagates in under two minutes with no code deploy.

Tool schemas get versioned the same way. If I rename a parameter or add a required field, I register it as a new tool version and keep the old one alive until all agents drain. This avoids a situation where a live agent calls a tool with a schema it wasn't trained on.

Orchestration logic — the actual LangGraph DAG or ReAct loop code — is Docker-image-tagged and deployed blue-green. I route 5% of real traffic to the new image, measure turn count, success-signal rate, and cost-per-query, and auto-promote or auto-rollback based on thresholds. If p95 turn count increases by more than 20% on canary, we roll back the image automatically.

Model versions are pinned explicitly in the agent config — `claude-sonnet-5-2024-11-20` — and I run a golden-dataset regression before promoting any model snapshot change. This avoids surprises when OpenAI silently updates a model."

**Tradeoff / production angle (1 min):**
"The main tension is configuration complexity vs rollback speed. A single flat Git repo works for one or two agents, but with ten agents across three teams, you need a dedicated prompt registry and per-agent config namespacing or you get prompt version collisions. The other gotcha is that shadow mode for irreversible tools — like sending emails or calling external APIs — requires mock interceptors in canary, otherwise you shadow-blast customers. That's a runtime safety concern that's easy to forget during deployment."

**Wrap-up (30s):**
"The key insight is that most agent regressions trace back to prompt changes, so investing in fast, prompt-only rollback — under two minutes — gives you 80% of the safety with 20% of the infrastructure overhead. Happy to go deeper on the golden-dataset regression gate or the shadow-mode tool interceptor pattern."

---

## Pitfalls

- **Mistake:** Treating agent versioning as equivalent to model versioning only — saying "we pin the model version and that's it" — **Better:** Explain that prompts, tool schemas, and orchestration logic each change independently and need separate versioning + rollback paths; prompt changes have the highest velocity and the fastest rollback SLA.
- **Mistake:** Claiming blue-green deployment is sufficient without addressing irreversible tool calls in canary — **Better:** Describe shadow-mode interceptors or mock backends for canary traffic so tools like `send_email` or `process_payment` don't execute twice during a shadow test.
- **Mistake:** Skipping rollback SLA definition — just saying "we can roll back" — **Better:** Commit to concrete targets: <2 min for prompt/config, <10 min for orchestration code, and explain how each is achieved (tag flip vs image swap vs model snapshot restore).

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q8: Walk through a production-ready agent architecture](03-008-walk-through-a-production-ready-agent-architecture.md) | Prerequisite — the architecture this versioning strategy operates on |
| [Q9: What logic belongs in orchestrator vs LLM](03-009-what-logic-belongs-in-orchestrator-vs-llm.md) | Related — versioning strategy mirrors the orchestrator/LLM boundary |
| [Q30: Monitor autonomous agent behavior in production](03-030-monitor-autonomous-agent-behavior-in-production.md) | Follow-up — monitoring feeds the rollback trigger signals |

---

## One-liner recall

> Version agents across four independent layers (prompts, tool schemas, orchestration code, model snapshot), deploy changes via canary/shadow with per-layer rollback SLAs — prompt flips in <2 min, image swaps in <10 min — and auto-roll back when turn-count or success-rate SLOs breach.
