# F1 score, ROC curve?

**Category:** 06-ml-fundamentals
**Question #:** 020
**Source section:** §6 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
The interviewer is testing whether you understand classification evaluation beyond raw accuracy — a critical gap that surfaces when working on imbalanced datasets (fraud, medical, spam) that are common in AI/ML roles. They want to see you articulate when each metric is appropriate, not just recite the formula.

### Trigger phrases
- "How do you evaluate a classifier?"
- "What's the difference between F1 and AUC-ROC?"
- "How would you pick a threshold for your model?"
- "Accuracy is 99% — is that good?"

### What it tests
Ability to choose evaluation metrics that align with business goals and handle class imbalance correctly.

---

## Answer

### Concept
**F1 score** is the harmonic mean of precision and recall — `2·P·R/(P+R)` — giving equal weight to false positives and false negatives. The **ROC curve** plots True Positive Rate vs False Positive Rate across all decision thresholds, and AUC-ROC summarises it as a single number (probability that the model ranks a random positive above a random negative).

### Mechanism

**F1 score mechanics:**
- Precision = TP / (TP + FP) — of everything we predicted positive, how many were correct?
- Recall = TP / (TP + FN) — of all actual positives, how many did we catch?
- F1 = 2·P·R / (P+R) — harmonic mean penalises extremes (a model with P=1, R=0 gets F1=0)
- **F-beta**: `(1+β²)·P·R / (β²·P + R)` — β>1 weights recall more (e.g. β=2 for medical diagnosis where missing a case is worse than a false alarm); β<1 weights precision more (e.g. β=0.5 for spam where false positives annoy users)

**ROC curve mechanics:**
- At each decision threshold θ, compute TPR = TP/(TP+FN) and FPR = FP/(FP+TN)
- Plot all (FPR, TPR) pairs → the curve
- AUC-ROC = area under that curve; random classifier = 0.5, perfect = 1.0
- AUC is **threshold-independent** — it measures rank ordering quality across all operating points

**PR curve and PR-AUC:**
- For highly imbalanced datasets (e.g. fraud: 0.1% positive rate), ROC looks optimistic because TN is huge → FPR stays low even with many false alarms
- Precision-Recall curve is more informative: plots Precision vs Recall directly
- PR-AUC (average precision) is the preferred summary metric when positives are rare

### Example / Tradeoff

**Fraud detection (1% positive rate):**
- A model predicting "no fraud" on everything gets 99% accuracy but F1 ≈ 0 and catches 0 fraud
- Use **PR-AUC** as primary metric, not AUC-ROC (which would still be ~0.5)
- Business cost asymmetry: missing a $10K fraud (FN) >> blocking a legitimate transaction (FP)
- Set β=2 or higher; tune threshold on PR curve to hit the fraud team's FP/FN dollar-loss budget
- In sklearn: `classification_report`, `roc_auc_score`, `average_precision_score` (PR-AUC)

**Spam filter (balanced concern):**
- False positives (legitimate email in spam) annoy users → weight precision
- F-beta with β=0.5, or explicit precision floor at 99% then maximise recall

**Multi-class extension:**
- Macro F1: average per-class F1 equally (penalises poor performance on rare classes)
- Weighted F1: average by class support (tracks overall production performance)
- Use micro-average when class imbalance doesn't matter for your task

---

## Verbal script

**Opening (30s):**
"F1 and ROC address a fundamental limitation of accuracy — when your classes are imbalanced, accuracy is misleading. I'd frame my answer around which metric to pick given the business cost of false positives vs false negatives, and whether you're choosing a threshold or comparing models rank-wise."

**Core explanation (2–3 min):**
"F1 is the harmonic mean of precision and recall. Precision measures 'of what I flagged, how much was right?' Recall measures 'of all actual positives, how many did I catch?' F1 penalises extremes — a model that catches everything but spams users with false alarms, or vice versa, scores low.

For asymmetric costs, I'd use F-beta. If missing a cancer diagnosis is five times worse than a false biopsy, I'd set β=2 to weight recall more heavily.

The ROC curve is different — it plots TPR against FPR across every possible threshold. The AUC summarises rank ordering: 'what's the probability my model scores a real positive above a random negative?' AUC is threshold-independent, which makes it great for comparing two models before you've picked a deployment threshold.

But here's the key production insight: for imbalanced datasets — fraud, medical, anomaly detection — ROC AUC is optimistic. Because the negative class is huge, FPR stays low even with many false positives. That's why I always plot the Precision-Recall curve and report PR-AUC (average precision) as the primary metric for these use cases. sklearn's `average_precision_score` gives you this directly."

**Tradeoff / production angle (1 min):**
"In production, I separate 'model selection' from 'threshold selection.' I use AUC-ROC or PR-AUC to pick between model candidates — that's a threshold-free comparison. Once I've chosen a model, I tune the threshold on the PR curve against the business cost function: `cost = FP_rate × FP_cost + FN_rate × FN_cost`. For fraud, FN cost is the dollar value of missed fraud; FP cost is chargeback ops time plus customer friction.

One thing I also watch: in multi-class settings, macro F1 is fairer to minority classes — it treats all classes equally. Weighted F1 tracks overall production volume. I report both."

**Wrap-up (30s):**
"To summarise: F1 for imbalanced threshold-fixed evaluation, F-beta when costs are asymmetric, AUC-ROC for rank-comparison of model candidates, and PR-AUC when positives are very rare. Happy to go deeper on threshold calibration or multi-class variants."

---

## Pitfalls

- **Mistake:** Reporting only accuracy on an imbalanced dataset and calling it good — **Better:** immediately flag class imbalance, switch to PR-AUC or weighted F1, and show the confusion matrix; a 99%-accurate fraud model that catches zero fraud is worthless.
- **Mistake:** Treating AUC-ROC as the universal go-to metric regardless of class distribution — **Better:** for rare-positive datasets (fraud, medical, anomaly), prefer PR-AUC because ROC is optimistic when TN >> TP; explain that FPR denominator includes huge TN pool.
- **Mistake:** Forgetting that F1 requires a fixed threshold, while AUC is threshold-free — **Better:** explain that AUC is used to *select* models, then threshold is *tuned* on the PR curve against business cost; conflating the two signals you don't know when to use each.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q19: Precision vs recall — fraud detection](06-019-precision-vs-recall-fraud-detection.md) | Prerequisite — precision/recall fundamentals that F1 combines |
| [Q11: Imbalanced datasets in real projects](06-011-imbalanced-datasets-in-real-projects.md) | Same context — imbalance is why accuracy fails and F1/PR-AUC matters |
| [Q5: Evaluation metrics — success metrics for an ML model](05-019-success-metrics-for-an-ml-model.md) | Follow-up — how F1/AUC fit into a broader business metric framework |

---

## One-liner recall

> F1 is the harmonic mean of precision and recall (use F-beta for asymmetric costs); AUC-ROC is threshold-free rank quality (use PR-AUC instead when positives are rare); always separate model selection (AUC) from threshold tuning (PR curve + cost function).
