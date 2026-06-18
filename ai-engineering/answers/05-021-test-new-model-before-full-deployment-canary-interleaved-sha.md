# Test new model before full deployment — canary, interleaved, shadow?

**Category:** 05-evaluation-metrics
**Question #:** 021
**Source section:** §5 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
Interviewers are probing whether you understand that shipping a new LLM (or prompt change) is a risk-management problem, not just a deployment problem. Weak candidates swap models globally and watch production metrics afterward; strong candidates have a staged rollout with automatic rollback triggers, measurable success criteria, and a protocol for each phase.

### Trigger phrases
- "How would you test a new model before rolling it out?"
- "What's your deployment strategy for a new LLM version?"
- "How do you validate a model change doesn't regress production?"
- "Canary, shadow, interleaved — when would you use each?"

### What it tests
Whether the candidate can design a safe, data-driven model deployment pipeline with offline gates, production shadowing, and progressive traffic rollout — not just "deploy and monitor."

---

## Answer

### Concept
Deploying a new LLM into production requires three sequential validation phases: **offline evaluation** (golden-dataset gates before any traffic), **shadow mode** (parallel inference on live traffic with no user impact), and **canary/interleaved rollout** (progressive live traffic exposure with automatic rollback). Each phase has explicit pass/fail criteria; failure at any phase halts promotion to the next.

### Mechanism

**Phase 0 — Offline gate (pre-deployment)**
- Run new model on the category's 150–300 sample golden dataset.
- Must meet or exceed baseline on: Faithfulness ≥ 0.85, Answer Relevancy ≥ 0.80, Recall@5 ≥ 0.70 (for RAG pipelines), and task-specific regression benchmarks.
- Gate is enforced in CI (GitHub Actions / Buildkite). Red gate = no promotion.

**Phase 1 — Shadow mode (0% live traffic)**
- New model runs on every real request *in parallel* with the production model.
- New model responses are **logged but never shown to users**.
- Metrics collected: latency (p50/p95/p99), cost per query, RAGAS Faithfulness (async sidecar), hallucination rate.
- Duration: 24–72 hours, ≥10K requests.
- Pass criteria: p95 latency ≤ baseline + 20%, cost ≤ baseline × 1.15, Faithfulness ≥ 0.85.

**Phase 2 — Interleaved / canary (1% → 10% → 50% → 100%)**
- Traffic splitting via a feature flag or load-balancer weight (e.g. LaunchDarkly, nginx upstream, AWS ALB weighted target groups).
- **Interleaved** means the same user may receive responses from either model on different turns, which controls for temporal novelty effects and user cohort skew.
- At each traffic tier, hold for ≥48 hours and monitor:
  - Business KPIs: deflection rate, CSAT/thumbs-up, ticket escalation rate.
  - Technical SLOs: p95 latency < 800ms, error rate < 0.5%, cost-per-query.
  - RAGAS Faithfulness ≥ 0.85 on sampled async sidecar.
- **Auto-rollback trigger**: if any SLO breaches by > 10% relative for > 15 minutes, feature flag flips back to 0% automatically (PagerDuty + Grafana alerting rule).

**Phase 3 — Full rollout (100%)**
- Promote after all canary tiers pass.
- Keep prior model artifact available for 7-day hot rollback.

### Example / Tradeoff

At a customer-support RAG system (1M queries/day):
- **Shadow mode** caught a 35% p95 latency regression when moving from GPT-4o-mini to a self-hosted Llama 3 70B — avoided a production incident.
- **Interleaved at 5%** (50K req/day) is statistically sufficient to detect a 2pp deflection-rate drop at 95% power within 48 hours (using an online MDE calculator).
- **Tradeoff**: shadow mode doubles inference cost during the shadow period (two models run per request). Mitigate by sampling shadow on 10–20% of traffic rather than 100% if cost is a hard constraint.

| Phase | Traffic | User Impact | Duration | Rollback Effort |
|-------|---------|-------------|----------|-----------------|
| Offline gate | 0% | None | Minutes (CI) | N/A — never deployed |
| Shadow | 0% user-visible | None | 24–72h | N/A — not live |
| Canary 1% | 1% | Minimal | 48h | Instant flag flip |
| Canary 10% | 10% | Limited | 48h | Instant flag flip |
| Full rollout | 100% | All users | Ongoing | 7-day hot rollback |

---

## Verbal script

**Opening (30s):**
"I think about model deployment in three sequential phases, each with explicit pass/fail gates, so that no regression reaches users without being caught first. The key principle is: fail fast in the cheapest environment, then progressively expose to real traffic."

**Core explanation (2–3 min):**
"Phase zero is an offline gate run in CI. I run the new model against our golden dataset — around 150–300 human-labeled query/answer/chunk triples — and require it to meet or exceed baseline Faithfulness ≥ 0.85, Answer Relevancy ≥ 0.80, and Recall@5 ≥ 0.70. If it fails, it never gets deployed. This costs nothing and catches most regressions.

"Phase one is shadow mode. I deploy the new model behind the existing one, run both on every live request, but only show the old model's response to users. The new model's outputs are logged and run through an async RAGAS sidecar. I'm checking p95 latency, cost per query, and Faithfulness over 24–72 hours and at least 10K requests. If p95 latency is more than 20% higher or Faithfulness drops below 0.85, I don't proceed.

"Phase two is a canary rollout — typically 1% → 10% → 50% → 100% traffic via feature flags or weighted load-balancer rules. I prefer *interleaved* allocation rather than cohort-split, because it controls for novelty effects and user segment skew. At each tier I hold for 48 hours and watch business KPIs: deflection rate, CSAT, p95 latency, and cost. I set up an auto-rollback rule: if any SLO breaches by more than 10% relative for more than 15 minutes, the flag automatically flips to 0%."

**Tradeoff / production angle (1 min):**
"The main cost of shadow mode is that you're running two models simultaneously — doubling inference cost during the shadow window. You can mitigate this by sampling shadow traffic at 10–20% rather than 100%. The other risk is novelty bias in canary: users behave differently when a product is new, so a 48-hour hold at each tier is the minimum to see steady-state metrics. For latency-critical systems, I'd also set a stricter p95 threshold in shadow — say ≤ 10% regression — rather than ≤ 20%."

**Wrap-up (30s):**
"The key insight is that canary alone is not enough — you need the offline gate to catch regressions cheaply, and shadow mode to validate latency and cost before any user sees the new model. I'm happy to go deeper on auto-rollback trigger design or how to size the golden dataset."

---

## Pitfalls

- **Mistake:** "I'd just push to 10% canary and monitor CSAT for a few days" — **Better:** Describe the full three-phase pipeline (offline gate → shadow → canary), name specific SLO thresholds, and explain the auto-rollback trigger; skipping shadow misses latency/cost regressions before any user exposure.
- **Mistake:** Treating canary as a cohort split (all users in segment X get new model) without mentioning novelty-effect bias — **Better:** Explain interleaved allocation (same user may hit either model across turns), specify 48h minimum hold per tier, and reference statistical power / MDE to justify sample size.
- **Mistake:** Not specifying rollback criteria or rollback speed — **Better:** Mention the auto-rollback rule (PagerDuty + Grafana alert: SLO breach > 10% relative for > 15 min → flag flips to 0%), and note the 7-day hot artifact retention for full rollout reversal.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q16: "Vibes-based" eval vs formal eval framework](05-016-vibes-based-eval-vs-formal-eval-framework.md) | Prerequisite — formal eval framework that feeds the offline gate |
| [Q17: Golden dataset for evaluation and regression testing](05-017-golden-dataset-for-evaluation-and-regression-testing.md) | Prerequisite — golden dataset construction used in Phase 0 |
| [Q20: A/B testing for prompt variations](05-020-ab-testing-for-prompt-variations.md) | Same concept — canary/interleaved design applies equally to prompt A/B tests |

---

## One-liner recall

> Safe model deployment uses three phases in sequence: offline golden-dataset CI gate → shadow mode (0% user-visible, latency/cost check) → interleaved canary (1→10→50→100%) with auto-rollback on SLO breach.
