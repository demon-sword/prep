# Imbalanced datasets in real projects?

**Category:** 06-ml-fundamentals
**Question #:** 011
**Source section:** §6 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
The interviewer is probing whether you've dealt with the practical reality that real-world data is almost never balanced — fraud is 0.1% of transactions, cancer is 1% of scans, churn is 5% of users. They want to see that you don't naively optimize accuracy (a model predicting "not fraud" 100% of the time is 99.9% accurate but useless), and that you know the full toolkit: metric selection, algorithm-level fixes, data-level fixes, and threshold tuning — and can pick the right lever for the situation.

### Trigger phrases
- "How have you handled imbalanced datasets in real projects?"
- "Our fraud data is 99% legitimate, 1% fraudulent — how do you approach that?"
- "What do you do when one class is much rarer than the other?"
- "How do you deal with class imbalance in classification?"

### What it tests
Ability to select appropriate metrics and apply the right combination of data-level, algorithm-level, and threshold-level fixes for imbalanced classification — without the naive accuracy trap.

---

## Answer

### Concept
Class imbalance occurs when one class is substantially rarer than others (e.g., 1:100 or 1:1000 ratio), causing standard classifiers to become biased toward the majority class. The core danger is **metric blindness**: accuracy looks great while the minority class (the one you actually care about) is nearly ignored. The solution is a three-layer toolkit: choose the right metric, fix at the algorithm/data level, and tune the decision threshold separately.

### Mechanism

**Layer 1 — Metric: ditch accuracy**
- **PR-AUC (Precision-Recall AUC):** primary metric for severe imbalance (fraud, medical). Measures precision and recall across all thresholds; unaffected by true-negative count.
- **F1 / F-beta score:** harmonic mean of P and R. F-beta (β > 1) when recall matters more (missed cancer worse than false alarm).
- **ROC-AUC:** OK for moderate imbalance, but misleading at 100:1+ ratios because the large TN pool inflates the curve.
- **Avoid:** raw accuracy.

**Layer 2 — Algorithm-level fixes**

| Technique | How it works | When to use |
|-----------|-------------|-------------|
| `class_weight='balanced'` (sklearn) | Re-weights minority class loss by `n_samples / (n_classes × count)` | Any sklearn classifier; zero data overhead; good default |
| Focal loss | Down-weights easy majority examples dynamically via `(1−p_t)^γ` | Neural networks, severe imbalance |
| Threshold-aware ensembles (BalancedRandomForest) | Under-samples majority in each tree's bootstrap | Tree models with extreme imbalance |

**Layer 3 — Data-level fixes (when algorithm fixes aren't enough)**

| Technique | Mechanism | Risk |
|-----------|-----------|------|
| **SMOTE** (Synthetic Minority Over-sampling) | Interpolates new minority samples between k-nearest neighbors | Can create unrealistic samples in sparse regions |
| Random under-sampling | Drop majority examples | Discards real signal |
| LLM augmentation (2026) | a frontier model generates synthetic minority examples for NLP tasks | Distribution shift if generations are OOD |

**Layer 4 — Threshold tuning**
The default 0.5 decision threshold is rarely optimal under imbalance. Plot the **PR curve** and find the threshold that maximizes F-beta for your business objective. In fraud detection, you might set threshold at 0.2 to capture 90% recall (few missed frauds) at the cost of more false positives (extra reviews).

### Example / Tradeoff
**Fraud detection project (1% positive rate):**
- Baseline XGBoost with default settings: **accuracy 99.1%, recall 0.18** — model predicts "not fraud" almost always.
- Fix 1: Add `scale_pos_weight=99` (XGBoost's class weight equivalent) → recall jumps to 0.71, PR-AUC 0.81.
- Fix 2: SMOTE minority oversampling to 10:1 ratio → recall 0.78, PR-AUC 0.84.
- Fix 3: Threshold tuned to 0.23 on PR curve to hit recall ≥ 0.90 → operational decision: accept precision 0.42 (58% false positive review queue, acceptable to fraud ops).
- **Monitoring:** deployed with PR-AUC dashboard; alert if recall drops >5% over rolling 7-day window (imbalance can shift if fraud patterns change).

**LLM/AI context:** When fine-tuning a classifier on imbalanced NLP data (e.g., toxicity detection), focal loss in the cross-entropy head outperforms SMOTE because SMOTE doesn't handle high-dimensional text embeddings well. LLM augmentation for minority class examples is effective when the minority class is well-defined (specific violation type), but needs RAGAS-style or human review gating to avoid distribution shift.

---

## Verbal script

**Opening (30s):**
"Imbalanced datasets are the norm in production AI — fraud is 0.1% of transactions, rare disease is 1% of scans. The first mistake most candidates make is optimizing accuracy, which makes the problem invisible. I think of the solution in three layers: fix the metric, fix the algorithm, and tune the threshold. Let me walk through each."

**Core explanation (2–3 min):**
"I'd start with the metric. Accuracy is meaningless when 99% of examples are the majority class — a model predicting 'not fraud' always is 99% accurate. Instead I use PR-AUC as the primary metric for severe imbalance, or F-beta if I know the relative cost of false negatives vs false positives.

On the algorithm side, the cheapest and usually most effective fix is class weighting — `class_weight='balanced'` in sklearn, or `scale_pos_weight` in XGBoost. This re-weights the loss function so each minority example counts proportionally more. For neural networks I use focal loss, which dynamically downweights easy majority examples.

If algorithm fixes aren't enough, I go to data-level remediation. SMOTE synthesizes new minority examples by interpolating between k-nearest minority neighbors — it's effective for tabular data but can create unrealistic samples in sparse regions. For NLP tasks in 2026, I've used a frontier model to generate synthetic minority examples and then filter them with a human or automated quality gate.

The last layer is threshold tuning, which is often overlooked. The default 0.5 threshold is wrong under imbalance. I plot the PR curve and pick the threshold that hits the business SLO — for fraud, that might be 'recall ≥ 0.90' even if it means precision of 0.40 and a larger review queue."

**Tradeoff / production angle (1 min):**
"The tradeoff is cost: SMOTE adds training complexity and can overfit. Class weighting is nearly free. Lowering the threshold increases false positives, which has a real ops cost — more fraud analysts reviewing benign transactions. The right answer depends on the asymmetric cost of each error type. In medical imaging, a missed cancer (false negative) is catastrophic, so I'd bias heavily toward recall; in spam detection, a false positive (legit email flagged) is the bigger UX problem.

One production gotcha: imbalance ratios can shift over time. If the real fraud rate drops from 1% to 0.3% because a fraud ring was caught, your calibrated threshold is now wrong. I monitor recall and PR-AUC on a rolling window and set SLO alerts."

**Wrap-up (30s):**
"So: swap accuracy for PR-AUC as the primary metric, apply class weights as the default first fix, layer in SMOTE or augmentation only if needed, and tune the decision threshold explicitly against the business cost ratio. Happy to go deeper on focal loss, SMOTE internals, or how I'd handle this in the LLM fine-tuning context."

---

## Pitfalls

- **Mistake:** Saying "I'd use SMOTE to fix imbalance" as the first and only answer — **Better:** Lead with metric change (PR-AUC over accuracy) and class weighting, then mention SMOTE as a data-level fallback with its caveats (unrealistic interpolation in sparse regions, not suitable for high-dimensional text).
- **Mistake:** Treating ROC-AUC as the gold standard for imbalanced data — **Better:** Explain that ROC-AUC is inflated by the large true-negative pool at extreme ratios (100:1+); PR-AUC is the correct metric because it ignores true negatives.
- **Mistake:** Using a fixed 0.5 decision threshold after training — **Better:** Tune the threshold on the PR curve to hit the business SLO (e.g., recall ≥ 0.90 for fraud), and monitor it over time as class distributions shift.
- **Mistake:** Conflating "balanced accuracy" with solving the underlying problem — **Better:** Balanced accuracy is a diagnostic metric; the real production fix requires re-weighting, augmentation, or threshold tuning depending on the use case.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q19: Precision vs recall — fraud detection?](06-019-precision-vs-recall-fraud-detection.md) | Direct application — precision/recall tradeoff is the core imbalance metric |
| [Q20: F1 score, ROC curve?](06-020-f1-score-roc-curve.md) | Follow-up — when to use F1 vs ROC-AUC under imbalance |
| [Q1: Data pre-processing and feature engineering?](06-001-data-pre-processing-and-feature-engineering.md) | Prerequisite — data-level fixes (SMOTE, augmentation) sit in the preprocessing pipeline |

---

## One-liner recall

> Imbalanced data: swap accuracy for PR-AUC, apply `class_weight='balanced'` first, add SMOTE for tabular/focal loss for NNs if needed, then tune the decision threshold on the PR curve to match the business cost ratio — and monitor recall drift in production.
