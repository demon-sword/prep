# Precision vs recall — fraud detection?

**Category:** 06-ml-fundamentals
**Question #:** 019
**Source section:** §6 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
The interviewer is probing whether you understand that raw accuracy is meaningless for imbalanced classification problems like fraud. They want to see you reason through business consequences of false positives vs false negatives, choose the right metric for the problem, and know how to tune a threshold rather than just accept model defaults.

### Trigger phrases
- "How would you evaluate a fraud detection model?"
- "What metrics matter most for a classifier with class imbalance?"
- "Our model has 99% accuracy on fraud — is that good?"
- "How do you balance catching fraud vs. blocking legitimate transactions?"

### What it tests
Ability to match evaluation metrics to business consequences in imbalanced classification settings.

---

## Answer

### Concept
**Precision** = TP / (TP + FP) — of all transactions flagged as fraud, what fraction are actually fraud (low precision → lots of false alarms, blocking good customers).  
**Recall** (Sensitivity) = TP / (TP + FN) — of all actual fraud, what fraction did the model catch (low recall → missed fraud, dollar losses).  
Accuracy is useless at 0.1% fraud prevalence: a model that flags nothing gets 99.9% accuracy but catches zero fraud.

### Mechanism

**The fundamental tension:**
- High precision, low recall → strict threshold: few false alarms but many missed frauds. Customers happy; fraud team/insurers unhappy.
- High recall, low precision → lenient threshold: most fraud caught but many blocked legitimate transactions. Customers frustrated with declined cards.

**Threshold tuning:**
Most classifiers output a probability score (e.g., XGBoost, LightGBM). The default threshold (0.5) is rarely optimal. The PR curve plots precision vs recall across all thresholds. Select the operating point by business cost:

```
Cost function = (FP × cost_of_blocking_legit_txn) + (FN × cost_of_missed_fraud)
```

At Stripe/PayPal scale: a false positive blocks a $200 purchase (customer friction, churn risk); a false negative on a $5,000 fraudulent wire is a direct loss plus chargeback fees.

**Derived metrics:**
- **F1 score** — harmonic mean of precision and recall. Use when FP and FN costs are roughly symmetric.
- **F-beta score** — `F_β = (1+β²) × P × R / (β²P + R)`. Set β > 1 (e.g., β=2) to weight recall higher when missed fraud (FN) is more costly than false alarms.
- **PR-AUC** — area under the precision-recall curve. Better than ROC-AUC for severely imbalanced data (1:1000 or worse), because PR-AUC does not get inflated by the massive true-negative pool.
- **ROC-AUC** — area under the TPR vs FPR curve. Still useful for comparing classifiers, but can be misleadingly high under extreme imbalance.

**Production metrics beyond offline eval:**
- Dollar loss prevented per day (recall-driven)
- False positive rate among high-value customers (precision-driven, churn-sensitive)
- Chargeback rate (industry SLO: Visa/Mastercard threshold < 1%)

### Example / Tradeoff

**Real-world calibration:** A fraud model at a fintech with 0.05% fraud rate might set threshold at 0.15 (not 0.5) to achieve recall = 0.92, accepting precision = 0.40 (60% false positive rate among flags). The downstream queue is handled by human reviewers — the business chose to catch 92% of fraud and manually triage 2.3× as many flagged transactions as actual frauds.

**Tooling:** scikit-learn's `precision_recall_curve` + `average_precision_score`; LightGBM/XGBoost with `scale_pos_weight` for imbalanced training; `imbalanced-learn` SMOTE for oversampling rare class.

**Threshold tuning in code:**
```python
from sklearn.metrics import precision_recall_curve
precs, recs, thresholds = precision_recall_curve(y_true, y_scores)
# Pick threshold maximising F2 (recall-weighted)
f2 = (5 * precs * recs) / (4 * precs + recs + 1e-9)
best_threshold = thresholds[f2.argmax()]
```

---

## Verbal script

**Opening (30s):**
"Precision and recall address a core problem in fraud detection: the class is so rare that accuracy is useless. I'd frame the answer around the business cost of each error type — a false positive blocks a legitimate customer, a false negative is direct monetary loss — then show how you tune a threshold on the PR curve to minimize that cost."

**Core explanation (2–3 min):**
"Let me start with the formulas. Precision is TP over TP+FP — of everything I flag as fraud, how many are actually fraud. Recall is TP over TP+FN — of all actual fraud, how much do I catch. At 0.1% fraud prevalence, a model that flags nothing gets 99.9% accuracy but zero recall, so accuracy is irrelevant.

The fundamental tension: high precision means few false alarms but more missed fraud; high recall means catching more fraud but also blocking more legitimate transactions. In fraud, missed fraud usually has hard dollar costs — chargebacks, regulatory penalties — while false alarms generate customer friction and churn.

Most production fraud systems use a probability threshold below 0.5. You plot the PR curve — precision vs recall at every threshold — and pick the operating point that minimizes a cost function: false positives times cost-of-blocking-a-good-customer, plus false negatives times average-fraud-loss. If fraud losses are 10× the cost of a false alarm, you weight recall heavily — use F2 score (β=2) rather than F1 to formalize that.

For model comparison I prefer PR-AUC over ROC-AUC at extreme imbalance. ROC-AUC gets inflated because the true-negative pool is huge, so even a bad model can show 0.97 AUC while missing half the fraud."

**Tradeoff / production angle (1 min):**
"In production the story doesn't end at offline metrics. I'd also track dollar loss prevented per day, chargeback rate (Visa/Mastercard enforce a < 1% threshold), and false positive rate among high-value customers separately — a premium account holder being blocked is disproportionately damaging to retention. I'd also set up threshold monitoring: model score distributions shift with fraud pattern changes, so what was a safe threshold at month 1 may have 15% more false negatives by month 6 without recalibration."

**Wrap-up (30s):**
"The key insight is that precision and recall are two levers controlling the same threshold, and the right operating point is determined by business costs, not by maximizing a single metric. Happy to go deeper on PR-AUC vs ROC-AUC, F-beta score choice, or how I'd handle concept drift in the fraud signal over time."

---

## Pitfalls

- **Mistake:** Reporting accuracy on an imbalanced fraud dataset (e.g., "99.9% accuracy") without mentioning precision/recall — **Better:** Immediately flag that accuracy is meaningless at 0.1% fraud prevalence; pivot to PR-AUC, recall@threshold, and dollar-loss metrics.
- **Mistake:** Saying "maximize F1 score" without justifying why FP and FN costs are equal — **Better:** Quantify the asymmetric cost (FN = $X fraud loss, FP = customer churn risk), then choose F-beta or a direct cost function to reflect that asymmetry.
- **Mistake:** Treating 0.5 as the default threshold without discussing threshold tuning on the PR curve — **Better:** Explain that production fraud thresholds are often 0.1–0.3, tuned by plotting the PR curve and finding the point that minimizes total expected cost.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q20: F1 score, ROC curve?](06-020-f1-score-roc-curve.md) | Direct follow-up — derived metrics built on precision/recall |
| [Q11: Imbalanced datasets in real projects?](06-011-imbalanced-datasets-in-real-projects.md) | Same domain — handling class imbalance via sampling, loss weighting |
| [Q19 (eval): Success metrics for an ML model?](../answers/05-019-success-metrics-for-an-ml-model.md) | Broader metric selection framework including business KPIs |

---

## One-liner recall

> In fraud detection, choose recall-weighted metrics (F2, PR-AUC) over accuracy, tune the threshold using a cost function (FN × fraud_loss + FP × churn_cost) on the PR curve, and monitor dollar-loss-prevented and chargeback rate in production.
