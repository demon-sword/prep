# Bias/fairness tradeoffs — example?

**Category:** 05-evaluation-metrics
**Question #:** 014
**Source section:** §5 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
Interviewers want to know whether you treat fairness as a box to check or as a genuine engineering constraint with real tradeoffs. They probe whether you can name a concrete fairness metric, explain why optimizing for it conflicts with another objective (accuracy, recall, business KPI), and describe what you did about it in a real system.

### Trigger phrases
- "How do you handle bias in ML models?"
- "Give me an example of a bias/fairness tradeoff you faced."
- "What fairness metrics have you used and how did they affect accuracy?"
- "How do you audit an AI system for discriminatory outputs?"

### What it tests
Ability to reason concretely about group fairness metrics, explain why they conflict with each other and with aggregate accuracy, and apply that reasoning to a real or realistic production scenario.

---

## Answer

### Concept
Fairness in ML is not a single metric — it's a family of competing criteria (demographic parity, equalized odds, calibration) that are mathematically incompatible with each other and often in tension with aggregate accuracy. Choosing one is a business and ethical decision, not just a technical one. The key insight is that optimizing for one fairness definition can degrade another, so the tradeoff must be named and justified explicitly.

### Mechanism

**The three primary fairness definitions:**

| Definition | Formula | What it requires | When to prefer |
|------------|---------|------------------|----------------|
| **Demographic parity** | P(Ŷ=1\|A=0) = P(Ŷ=1\|A=1) | Equal positive prediction rate across groups | Hiring/lending where base rates may reflect historical bias |
| **Equalized odds** | P(Ŷ=1\|Y=y, A=0) = P(Ŷ=1\|Y=y, A=1) for y∈{0,1} | Equal TPR and FPR across groups | High-stakes decisions where both false positives and false negatives matter (e.g., bail, medical screening) |
| **Calibration** | P(Y=1\|Ŷ=p, A=a) = p for all groups | Predicted probabilities reflect actual frequency | Risk scoring, credit underwriting where scores are used as probabilities |

**The impossibility theorem (Chouldechova 2017):** When base rates differ between groups, you cannot simultaneously achieve equalized odds AND calibration. Pick one.

**Common tradeoff levers:**
1. **Threshold adjustment** — apply different classification thresholds per group to equalize TPR or FPR (post-processing; works without retraining; can conflict with equal treatment arguments).
2. **Re-weighting / re-sampling** — upsample under-represented groups or apply instance weights during training (in-processing).
3. **Adversarial debiasing** — add a fairness adversary head that predicts group membership from representations; penalize the main model for making it easy (in-processing; computationally expensive).
4. **Fairness constraints as regularization** — add a Lagrange multiplier on demographic parity gap or equalized-odds gap during training (e.g., Google's `tensorflow/fairness`).

**Audit tooling:** Fairlearn (Microsoft), AI Fairness 360 (IBM), What-If Tool (Google), SHAP subgroup analysis.

### Example / Tradeoff

**Resume screening classifier (concrete example):**

A candidate scoring model trained on historical hire data showed 78% overall accuracy but a 23-percentage-point gap in recall between male and female applicants (male recall 85%, female recall 62%). This meant qualified female candidates were rejected at a much higher rate.

Options considered:
- **Demographic parity threshold adjustment** — lowered the score cutoff for the under-represented group. Result: recall gap closed from 23pts to 4pts, but false positive rate for that group rose 8pts (more noise in the pipeline). Business accepted this tradeoff as aligned with EEOC obligations.
- **Re-weighting training data** — assigned 2× sample weight to historical female hires. Closed the gap to 9pts in validation but required retraining every quarter as data distribution shifted.

**Key insight delivered in interview:** "We chose demographic parity over equalized odds because our legal team prioritized opportunity access. But we measured calibration separately so hiring managers' confidence scores remained interpretable. The tradeoff was transparency: we disclosed the threshold difference to stakeholders."

**Metrics tracked post-deployment (Fairlearn):**
- Demographic parity gap: target ≤0.05
- Subgroup recall per protected attribute (gender, race)
- False positive rate by group (to detect over-selection noise)
- Overall AUC (ensuring fairness adjustments didn't crater aggregate quality)

---

## Verbal script

**Opening (30s):**
"Fairness is one of those areas where there isn't a single right answer — there are competing definitions, and choosing between them is as much an ethical and legal decision as a technical one. I'll walk through the main tradeoffs, then give a concrete example of how I navigated this in a real system."

**Core explanation (2–3 min):**
"The three definitions you'll see most often are demographic parity, equalized odds, and calibration. Demographic parity says the positive prediction rate should be the same across groups. Equalized odds requires both true positive rates and false positive rates to match. Calibration says the predicted probability should reflect the actual frequency, regardless of group.

The catch — and this is Chouldechova's impossibility theorem from 2017 — is that when base rates differ between groups, you cannot satisfy equalized odds and calibration simultaneously. So the first thing I do on any fairness project is ask: which definition aligns with our legal obligations and business goals? That determines everything downstream.

In a resume screening model I worked on, we discovered a 23-point recall gap between male and female applicants. The model had 78% overall accuracy — it looked fine in aggregate — but it was disproportionately rejecting qualified female candidates. We used Fairlearn to surface the subgroup metrics.

We had three options: threshold adjustment per group, which is post-processing and fastest to deploy; re-weighting training samples, which is in-processing and more durable; or adversarial debiasing, which is expensive but closes the gap at the representation level. We chose threshold adjustment because we needed a fast fix, then moved to re-weighting in the next training cycle.

We set a demographic parity gap target of ≤0.05 and tracked it weekly in Grafana alongside subgroup recall and FPR. We accepted a slight increase in false positive rate for the affected group because our legal team prioritized opportunity access — EEOC compliance — over perfect calibration."

**Tradeoff / production angle (1 min):**
"The key production tension is that fairness interventions often conflict with aggregate accuracy. Threshold adjustment can look like 'lowering the bar,' which requires careful stakeholder communication. Re-weighting can cause the model to overfit the minority group if the training set is small. And any fairness-aware model needs its own regression tests — you can pass a deployment gate on aggregate AUC and still degrade subgroup recall between releases if you're not tracking it separately. I'd set a Fairlearn subgroup audit as a required CI step, not an ad hoc audit."

**Wrap-up (30s):**
"The short version: fairness is a tradeoff between competing mathematical definitions. Choose the one that aligns with legal/business requirements, instrument subgroup metrics in production, and treat fairness degradation as a deployment blocker the same way you'd treat accuracy regression."

---

## Pitfalls

- **Mistake:** Saying "we measured accuracy by demographic group and made sure it was equal" — **Better:** Name a specific fairness criterion (equalized odds, demographic parity) and explain *why* that one, since equal accuracy per group does not prevent disparate false positive rates that cause real harm.
- **Mistake:** Treating fairness as a one-time audit rather than a continuous monitoring concern — **Better:** Describe how subgroup metrics are tracked in production CI (Fairlearn dashboard, nightly subgroup recall check, deployment gate) and how you'd catch fairness regressions between model versions.
- **Mistake:** Claiming you can satisfy all fairness definitions simultaneously — **Better:** Cite the impossibility result (Chouldechova 2017) and explain that you pick one definition based on the use case, then measure the others as observational signals.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q7: SHAP, LIME, model interpretability?](05-007-shap-lime-model-interpretability.md) | SHAP subgroup attribution is a key tool for diagnosing where bias originates in feature space |
| [Q1: What metrics for benchmarking LLM performance?](05-001-what-metrics-for-benchmarking-llm-performance.md) | Subgroup fairness metrics extend the broader eval framework to protected attributes |
| [Q13: Evaluate and monitor model in production, not just offline?](05-013-evaluate-and-monitor-model-in-production-not-just-offline.md) | Production monitoring must include per-subgroup metric dashboards alongside aggregate KPIs |

---

## One-liner recall

> Fairness definitions (demographic parity, equalized odds, calibration) are mathematically incompatible when base rates differ — pick the one aligned with legal/business requirements, instrument subgroup metrics in CI, and treat fairness regression as a deployment blocker.
