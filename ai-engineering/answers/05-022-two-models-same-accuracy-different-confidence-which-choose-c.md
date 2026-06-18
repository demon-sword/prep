# Two models, same accuracy, different confidence — which choose? Calibration?

**Category:** 05-evaluation-metrics
**Question #:** 022
**Source section:** §5 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
Interviewers probe whether you understand that accuracy alone is insufficient for production systems — especially in high-stakes domains (medical, financial, content moderation) where a model's expressed confidence determines downstream actions like thresholds, routing, and HITL triggers. A well-calibrated model is one you can trust: when it says 90% confidence, it's right 90% of the time.

### Trigger phrases
- "Two models with the same accuracy — how do you choose between them?"
- "What is calibration and why does it matter?"
- "How do you set decision thresholds in production?"
- "Your model is overconfident — how do you fix it?"

### What it tests
Whether the candidate understands model calibration (reliability diagrams, ECE), can reason about threshold tuning from confidence scores, and knows practical recalibration techniques (Platt scaling, temperature scaling).

---

## Answer

### Concept
**Calibration** measures the alignment between a model's predicted confidence (probability) and its empirical accuracy. A perfectly calibrated model produces confidence scores that match real-world outcomes: among all predictions where the model says 80% confidence, exactly 80% should be correct. Two models with identical accuracy can differ dramatically in calibration — and the better-calibrated model is almost always more useful in production.

### Mechanism

**Step 1 — Measure calibration with ECE (Expected Calibration Error):**
- Bin predictions by confidence (e.g., 10 buckets: 0–0.1, 0.1–0.2, …, 0.9–1.0).
- For each bucket, compute |avg_confidence − accuracy|.
- ECE = weighted average of bucket errors. Lower is better (0 = perfect calibration).
- Plot a **reliability diagram**: confidence on x-axis, accuracy on y-axis. A perfectly calibrated model falls on the diagonal.

**Step 2 — Identify the calibration failure mode:**
- **Overconfident** (above diagonal): model outputs 95% confidence when it's right only 80% of the time → false certainty, dangerous in medical/fraud settings.
- **Underconfident** (below diagonal): model says 60% when it's right 85% of the time → too much HITL escalation, wasted human review cycles.

**Step 3 — Recalibrate if needed:**
- **Platt scaling** (logistic regression on softmax outputs): fits a sigmoid on a held-out calibration set. Works well for binary classifiers.
- **Temperature scaling**: single scalar T applied to logits before softmax — `softmax(logits / T)`. T > 1 flattens distribution (fixes overconfidence); T < 1 sharpens it. State-of-the-art default for neural nets (Guo et al. 2017).
- **Isotonic regression**: non-parametric, fits a monotone mapping from confidence to accuracy. More flexible, needs more calibration data (≥1K samples).

**Step 4 — Choose by decision use case:**

| Use case | Prefer |
|----------|--------|
| Binary threshold (fraud, spam) | Better-calibrated model; tune threshold on PR curve |
| Ranking / top-k retrieval | Accuracy/AUC sufficient; calibration less critical |
| HITL trigger (confidence < θ) | Calibrated model essential — miscalibration drowns HITL with false alarms |
| Multi-class routing | ECE per class; ensure minority class isn't systematically overconfident |

### Example / Tradeoff

In a **content moderation classifier** (same-day accuracy: both 87%), Model A has ECE 0.03 (well-calibrated), Model B has ECE 0.14 (overconfident: outputs 0.92 avg confidence on wrong predictions). Using a 0.85 confidence threshold for auto-approve:

- **Model A**: HITL queue captures the right borderline cases; human reviewers confirm ~85% of escalated items are genuine edge cases.
- **Model B**: many policy violations auto-approved with false 0.92 confidence; HITL queue flooded by cases the model is confidently wrong about.

→ Choose Model A despite identical accuracy. Apply temperature scaling (T ≈ 1.4) if a model is overconfident but otherwise superior on AUC — then re-validate ECE on a held-out set before deploying.

**Threshold tuning workflow:**
1. Generate PR curve on a calibration hold-out set.
2. Pick operating threshold at target precision (e.g., 95% precision for a high-stakes action).
3. Check ECE; apply temperature scaling if ECE > 0.05.
4. Monitor calibration drift monthly — distribution shift can re-break calibration.

---

## Verbal script

**Opening (30s):**
"This is a question about calibration — the idea that two models can have the same raw accuracy but very different trustworthiness in production. I'd always choose the better-calibrated model for any application where the confidence score drives a downstream decision, like routing to a human reviewer or setting an auto-approve threshold."

**Core explanation (2–3 min):**
"Let me walk through the mechanics. Calibration measures whether predicted confidence matches empirical accuracy. You measure it with Expected Calibration Error: bin predictions by confidence, compute the gap between average confidence and accuracy per bin, and take the weighted average. Perfect calibration means the model is right 80% of the time when it says 80% — it falls on the diagonal of a reliability diagram.

Two failure modes: overconfident models output 95% when they're right 80% of the time — that's dangerous in medical or fraud contexts because the system auto-approves cases it gets wrong. Underconfident models say 60% when they're right 85% — that's less dangerous but drives unnecessary human escalations.

To fix calibration, the go-to is **temperature scaling** — you divide logits by a learned scalar T before softmax. T > 1 flattens the distribution and lowers overconfidence. It's a single parameter fit on a held-out calibration set, computationally free at inference, and doesn't change accuracy. Platt scaling and isotonic regression are alternatives for binary tasks or when you have more calibration data."

**Tradeoff / production angle (1 min):**
"The key production angle: if you're setting any confidence threshold — HITL triggers, auto-approve gates, alerting — calibration is non-negotiable. Miscalibration at ECE 0.14 on a content moderation system means your HITL queue fills up with cases the model is confidently wrong about, burning reviewer capacity on the wrong items. I'd validate ECE on a held-out set, apply temperature scaling if ECE > 0.05, and monitor calibration monthly because distribution shift will re-break it."

**Wrap-up (30s):**
"So in summary: same accuracy, pick the better-calibrated model. Measure ECE, use a reliability diagram, apply temperature scaling to recalibrate if needed, and always monitor calibration drift in production. Happy to go deeper on threshold tuning or the Platt vs temperature scaling tradeoffs."

---

## Pitfalls

- **Mistake:** Saying "I'd just pick whichever has slightly better AUC" — **Better:** Acknowledge that calibration is often more operationally important than a marginal AUC gain if confidence scores drive thresholds or HITL routing; measure ECE explicitly on a held-out calibration set.
- **Mistake:** Treating calibration as a fixed property — **Better:** Explain that calibration drifts under distribution shift (new user cohorts, seasonal topic patterns) and must be monitored continuously, with temperature T re-fit periodically on fresh calibration data.
- **Mistake:** Proposing Platt scaling for neural networks without caveat — **Better:** Note that temperature scaling (Guo et al. 2017) outperforms Platt scaling for deep models because it preserves the full multi-class distribution with a single parameter; Platt scaling is better suited to binary, shallow classifiers.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q19: Success metrics for an ML model?](05-019-success-metrics-for-an-ml-model.md) | Calibration fits within the broader success-metrics framework |
| [Q14: Bias/fairness tradeoffs — example?](05-014-biasfairness-tradeoffs-example.md) | Calibration across subgroups is a key fairness concern (per-group ECE) |
| [Q3: Detect and mitigate hallucinations in production?](05-003-detect-and-mitigate-hallucinations-in-production.md) | LLM confidence scores and calibration connect to hallucination detection thresholds |

---

## One-liner recall

> Choose the better-calibrated model (lower ECE): accuracy alone ignores whether confidence scores are trustworthy for threshold-based decisions, and apply temperature scaling (T > 1 for overconfident models) to fix miscalibration without changing accuracy.
