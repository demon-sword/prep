# A/B testing for prompt variations?

**Category:** 05-evaluation-metrics
**Question #:** 020
**Source section:** §5 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
Interviewers ask this to probe whether you treat prompt engineering as a disciplined engineering practice rather than ad-hoc intuition. Strong candidates know how to set up statistically-valid experiments, choose the right metrics, handle non-determinism, and gate rollout — skills that directly transfer to production prompt governance.

### Trigger phrases
- "How do you know if your new prompt is actually better?"
- "Walk me through how you'd compare two prompt variants in production."
- "How do you safely roll out a prompt change to users?"

### What it tests
Ability to apply rigorous experimentation discipline (hypothesis, metric, statistical validity, guardrails) to the non-deterministic, hard-to-measure output space of LLM prompts.

---

## Answer

### Concept
A/B testing for prompt variations is the practice of routing live traffic (or a golden offline dataset) to two or more prompt variants simultaneously, collecting metric data for each, and using statistical tests to determine whether observed differences are significant before rolling out the winning variant. The core challenge is that LLM outputs are non-deterministic and require proxy metrics (LLM-as-judge, task-pass-rate, thumbs-up rate) rather than ground-truth labels.

### Mechanism

**Step 1 — Formulate a hypothesis and choose a primary metric**

Before running any experiment, decide what you're optimising and how you'll measure it:

| Goal | Primary metric | Secondary guardrails |
|------|----------------|----------------------|
| Improve answer quality | LLM-as-judge score (1–5) on 5% sample | Faithfulness ≥ 0.85, latency p95 |
| Reduce hallucinations | RAGAS Faithfulness on golden dataset | Deflection rate, CSAT |
| Improve conciseness | Token count reduction | Answer Relevancy, thumbs-up rate |
| Increase task completion | Pass@1 on golden task set | Cost-per-query, error rate |

Always define a **primary metric** (what you're trying to move), **guardrail metrics** (must not regress), and a **minimum detectable effect (MDE)** before looking at data.

**Step 2 — Choose the experiment surface**

| Surface | When to use | Notes |
|---------|-------------|-------|
| **Offline golden dataset** | Pre-production, fast iteration | Run both variants against 150–300 representative queries; no user exposure |
| **Shadow mode** | High-risk changes (production traffic, no user exposure) | Log variant B responses alongside variant A; compare offline |
| **Canary / live A/B** | After offline validation passes | 5–20% of traffic to variant B; collect real user signals |
| **Interleaved evaluation** | Ranking/search prompts | Same user sees results from both variants in one session (reduces user-level variance) |

**Step 3 — Control for non-determinism**

- Set **temperature = 0** for offline comparisons to eliminate randomness as a confound.
- For production A/B tests (where T > 0 is needed), use **repeated sampling** (e.g., 5 samples/query) and average the metric, or run with fixed seeds via a deterministic sampler.
- Use a **paired test** where both variants respond to the same query, which eliminates query-level variance.

**Step 4 — Statistical validity**

- Run a **power analysis** before launching: typically need MDE of 2–5pp, α = 0.05, power = 0.80 → 300–1,000 observations per variant depending on metric variance.
- Use **paired t-test** (for paired query samples) or **Mann-Whitney U** (for ordinal LLM-judge scores) rather than a simple average comparison.
- Report **confidence intervals**, not just p-values.
- Watch for **multiple comparison inflation** — if testing 5 variants simultaneously, apply Bonferroni correction or use a sequential testing framework (e.g., SPRT).

**Step 5 — Rollout gate**

```
Offline golden dataset:
  Primary metric improves ≥ MDE with p < 0.05?
    AND guardrail metrics (faithfulness, latency, cost) hold?
  → Promote to shadow / canary

Canary (5–10% live traffic, 48–72h):
  Same metrics + real user signals (thumbs-up, escalation rate)?
  → Promote to 100%

Auto-rollback trigger:
  If guardrail metric breaches threshold at any stage → revert instantly
```

**Tooling:** promptfoo (open-source prompt eval/A/B framework), LangSmith experiment runs, RAGAS offline eval suite, custom Grafana dashboards for live canary metrics.

### Example / Tradeoff

**Customer support chatbot prompt test:** Baseline prompt (A): system-role only with general instructions. Variant B: added explicit chain-of-thought instruction + citation format requirement.

- Offline test: 200 golden queries, T=0, LLM-as-judge (a frontier model, 1–5 scale). Variant B: 3.7 vs 3.2 (p < 0.001). RAGAS Faithfulness: 0.91 vs 0.88. Token cost: +22% (more verbose CoT).
- Canary (10% traffic, 72h): Deflection rate +4pp (61% → 65%), CSAT +0.2 (3.9 → 4.1), p95 latency +180ms (token inflation). Guardrails held.
- Decision: roll out B (quality win outweighs latency cost); added LLMLingua post-processing to trim verbose CoT from final response, recovering 140ms.

**Tradeoff:** The biggest risk in prompt A/B testing is **novelty effect** — users engage more with a new format initially, inflating early metrics. Minimum 48–72h canary before concluding, and check day-1 vs day-2 metrics separately.

---

## Verbal script

**Opening (30s):**
"Prompt changes can silently degrade a production system, so I treat them with the same rigour as a code deployment — hypothesis, metric, statistical gate, canary rollout. Let me walk through how I'd structure that."

**Core explanation (2–3 min):**
"First, I define the hypothesis and the primary metric before looking at any data. For example: 'Adding chain-of-thought instructions will improve LLM-judge quality score by at least 0.3 points while keeping faithfulness above 0.85 and latency within 200ms.' The guardrail metrics are as important as the primary metric — a prompt that improves quality but inflates cost by 50% or slows TTFT below acceptable UX is not a win.

Second, I start with an offline golden dataset — 150 to 300 representative queries with expected answers. I run both variants at temperature zero, score with RAGAS and an LLM-as-judge, and use a paired t-test because both variants see the exact same queries. This eliminates query-level variance. If the offline gate passes, I move to shadow mode for high-risk changes, or directly to a 5–10% live canary.

In a live canary, I collect real user signals: thumbs-up rate, escalation rate, deflection rate, and p95 latency. I wait at least 48 to 72 hours to avoid novelty effect — users often engage more with any change on day one. I also set an auto-rollback trigger: if faithfulness drops below 0.80 or latency breaches the SLO at any point, the system reverts automatically without human intervention.

For the stats: I do a power analysis upfront to know how many observations I need. Typically a 2–5 percentage point MDE, alpha 0.05, power 0.80, gives me 300 to 1,000 observations per variant. If I'm testing multiple variants simultaneously, I apply Bonferroni correction to avoid false-positive inflation."

**Tradeoff / production angle (1 min):**
"The hardest tradeoff is that the metrics that are easiest to measure offline — BLEU, ROUGE, even LLM-judge scores — don't always predict business KPIs like deflection rate or revenue. I've seen a prompt score 15% better on LLM-judge but produce no improvement in deflection rate because the quality gain was in a dimension users didn't care about. That's why I always include at least one real user signal in the canary and treat offline metrics as a necessary but not sufficient gate."

**Wrap-up (30s):**
"So in short: define hypothesis and metrics first, validate offline at temperature zero on a golden dataset, then canary with user signals and an auto-rollback trigger. Tools like promptfoo and LangSmith make the offline A/B layer straightforward. Happy to go deeper on the statistical validity piece or how to handle multi-variant tests."

---

## Pitfalls

- **Mistake:** Evaluating prompt variants by eyeballing a few outputs and declaring a winner — **Better:** Run a statistically-powered experiment (paired t-test, 300+ query golden dataset at T=0, explicit MDE and p-value threshold) to distinguish signal from noise; LLM outputs are high-variance and intuition fails.
- **Mistake:** Ignoring guardrail metrics (latency, cost, faithfulness) and optimising only the primary quality score — **Better:** Define guardrail thresholds upfront (e.g., "variant B wins only if it doesn't increase p95 latency by more than 200ms or cost-per-query by more than 10%") and treat guardrail breach as an automatic disqualifier.
- **Mistake:** Running a canary for only 24 hours and concluding from the novelty spike on day one — **Better:** Wait 48–72 hours minimum; check day-1 vs day-2 metric stability; novelty effects reliably inflate early engagement for any change.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q21: Test new model before full deployment — canary, interleaved, shadow](05-021-test-new-model-before-full-deployment-canary-interleaved-sha.md) | Deployment strategy patterns that also apply to prompt rollouts — canary and shadow mode |
| [Q10: Testing strategies for non-deterministic outputs](05-010-testing-strategies-for-non-deterministic-outputs.md) | How to handle non-determinism when constructing the test harness for prompt A/B experiments |
| [Q16: "Vibes-based" eval vs formal eval framework](05-016-vibes-based-eval-vs-formal-eval-framework.md) | Formal eval framework that provides the golden-dataset offline gate used in prompt A/B testing |

---

## One-liner recall

> Prompt A/B testing requires an upfront hypothesis + metric (primary + guardrails), offline validation on a golden dataset at T=0 with a paired statistical test, then a 48–72h live canary with auto-rollback — because eyeballing outputs and ignoring guardrail metrics are the two most common ways teams ship prompt regressions.
