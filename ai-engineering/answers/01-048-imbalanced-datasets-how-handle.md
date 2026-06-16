# Imbalanced datasets — how handle?

**Category:** 01-llm-fundamentals
**Question #:** 048
**Source section:** §1 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
Interviewers probe whether the candidate knows what breaks when class distributions are skewed (accuracy becomes meaningless), and whether they can select the right mitigation layer — data-level vs algorithm-level vs threshold-level — matching the business cost of each error type. In AI/LLM contexts, the question surfaces during content-moderation classifiers, fraud detection, anomaly detection in embedding spaces, and fine-tuning on scarce rare-class examples.

### Trigger phrases
- "Our fraud dataset is 99% legitimate — how do you train on that?"
- "How would you handle class imbalance in a medical classifier?"
- "The minority class only has 200 examples — what do you do?"
- "Accuracy is 99% but the model never flags a positive — what's wrong?"

### What it tests
Whether the candidate can diagnose why accuracy fails on imbalanced data and select from a toolkit of data-level (oversample/undersample/SMOTE), algorithm-level (class weights, focal loss), and threshold-level (precision-recall operating point) mitigations matched to business cost.

---

## Answer

### Concept
Imbalanced datasets occur when one class vastly outnumbers another (e.g., 99:1 fraud ratio). Standard accuracy becomes a misleading metric — a model predicting "not fraud" every time achieves 99% accuracy while being useless. The fix requires matching the mitigation to where the imbalance manifests: data distribution, loss function, or decision threshold.

### Mechanism
Three layers of mitigation, applied in order of cost:

**1. Metric fix (always first)**
- Replace accuracy with **precision, recall, F1, ROC-AUC, or PR-AUC**.
- For high-cost false negatives (fraud, cancer) → optimize recall; for high-cost false positives (spam) → optimize precision.
- **PR-AUC** is more informative than ROC-AUC when positive class is rare (ROC-AUC can be optimistically inflated by the large negative class).

**2. Algorithm-level (low cost, try first)**
- **Class weights**: `class_weight='balanced'` in sklearn, or manually set `weight_pos = N_neg / N_pos` in PyTorch `BCEWithLogitsLoss(pos_weight=...)`. The loss for minority-class errors is scaled up, nudging the model without touching the data.
- **Focal loss** (Lin et al., RetinaNet 2017): `FL(p) = -(1-p)^γ · log(p)` — down-weights easy negatives dynamically, useful when the majority class is also easy to classify.

**3. Data-level (more expensive, try if above insufficient)**
- **Random oversampling** (minority): replicate existing samples — fast but risks overfitting on duplicates.
- **Random undersampling** (majority): discard majority samples — fast but discards information.
- **SMOTE** (Synthetic Minority Oversampling Technique): interpolate between k-nearest minority neighbors in feature space, generating synthetic samples. Works well for tabular; harder to apply to text embeddings without careful validation.
- **ADASYN**: SMOTE variant that generates more synthetic samples in difficult-to-learn regions.

**4. Threshold tuning (decision calibration)**
- Default classifier threshold is 0.5, but optimal threshold depends on business cost ratio.
- Plot the **precision-recall curve**, pick the operating point that satisfies the business SLO (e.g., recall ≥ 0.95 for fraud).
- Use **Platt scaling** or **temperature scaling** to calibrate raw logits into calibrated probabilities first, then tune threshold on a held-out validation set.

**In LLM fine-tuning contexts**
- For rare-class instruction following (e.g., only 50 examples of a specific refusal pattern), use **LoRA with higher rank** on those layers + **data augmentation** (paraphrase with GPT-4, back-translation).
- **Few-shot prompting** or **retrieval-augmented classification** can outperform fine-tuning entirely when minority class examples number fewer than ~100.

### Example / Tradeoff
**Fraud detection at Stripe/PayPal scale**: ~0.1% positive rate. Workflow:
1. Replace accuracy with PR-AUC as primary metric.
2. Set `pos_weight=999` in PyTorch BCEWithLogitsLoss (ratio of negatives to positives).
3. If PR-AUC still unsatisfactory, apply SMOTE on transaction feature vectors to 10:1 ratio.
4. Tune threshold on validation set: find the recall=0.95 operating point on the PR curve.
5. Monitor in production: track precision/recall separately on a rolling 7-day window — imbalance ratio shifts with fraud patterns.

**Tradeoff**: SMOTE can introduce artifacts in high-dimensional spaces; interpolating between two minority embeddings doesn't necessarily produce a realistic data point. For text classifiers (e.g., toxic content), paraphrase augmentation via an LLM is more semantically faithful than SMOTE on embedding vectors.

---

## Verbal script

**Opening (30s):**
"Great question — this comes up constantly in production AI. The root issue is that standard accuracy becomes meaningless when one class dominates: a model predicting 'not fraud' 100% of the time achieves 99.9% accuracy on a 0.1% fraud dataset. So I think about this in three layers: fix the metric first, then try algorithm-level adjustments, then data-level resampling."

**Core explanation (2–3 min):**
"The first thing I always do is swap accuracy for precision, recall, and PR-AUC — not ROC-AUC, because ROC-AUC can look great even when you have no real signal on the minority class. PR-AUC is much more sensitive to minority-class performance.

Next layer is algorithm-level. If I'm using PyTorch, I'll set `pos_weight` in `BCEWithLogitsLoss` to the ratio of negatives to positives — that's essentially free and often gets you 70% of the way there. In sklearn classifiers, `class_weight='balanced'` does the same thing. If the minority class is not just rare but also intrinsically hard (lots of overlap with the majority), focal loss can help by down-weighting easy negative examples dynamically.

If algorithm-level isn't enough, I'll go to data-level. Random oversampling is fastest but risks overfitting. SMOTE synthesizes new minority-class points by interpolating between k-nearest neighbors in feature space — it's the standard for tabular data. For text, I'd rather use LLM-based paraphrase augmentation than SMOTE on embeddings, because interpolating embeddings doesn't always yield a coherent sentence.

Finally, threshold tuning. The default 0.5 cutoff is rarely optimal. I'll calibrate probabilities first — Platt scaling or temperature scaling — then sweep the threshold on a validation set to find the operating point that hits the business constraint, say recall ≥ 0.95 for fraud detection."

**Tradeoff / production angle (1 min):**
"The key production gotcha is that imbalance ratios shift over time. A fraud model trained at 0.1% positive rate might face 0.5% during a fraud spike, which moves your optimal threshold. So I monitor precision and recall separately on a rolling window in production — not just overall accuracy — and retrigger threshold recalibration automatically when the ratio drifts more than 2× from baseline.

In LLM fine-tuning, if I have fewer than ~100 examples of a rare behavior, fine-tuning is often not the right tool — I'd use few-shot prompting or RAG-based classification instead."

**Wrap-up (30s):**
"So the playbook is: metric → algorithm-level (class weights, focal loss) → data-level (SMOTE, augmentation) → threshold tuning. And in production, treat imbalance ratio as a live metric, not a fixed property of your training set. Happy to dig into any of those layers."

---

## Pitfalls

- **Mistake:** Saying "I'd use SMOTE" as the first and only answer — **Better:** Start with metric fix (PR-AUC over accuracy) and class weights, since those are free; only reach for SMOTE when algorithm-level adjustments are insufficient, and caveat that SMOTE on embeddings can produce incoherent points for text tasks.
- **Mistake:** Reporting accuracy as the primary metric on an imbalanced test set — **Better:** Report precision, recall, F1, and PR-AUC; explain why PR-AUC is preferred over ROC-AUC when the positive class is rare (the ROC curve's true-negative-rate axis is dominated by the majority class).
- **Mistake:** Setting a fixed 0.5 threshold after training without tuning — **Better:** Plot the precision-recall curve and choose the threshold that satisfies the business cost constraint (e.g., recall ≥ 0.95 for fraud), and recalibrate probabilities first so the threshold is meaningful.
- **Mistake:** Applying SMOTE to raw text embeddings without validation — **Better:** For NLP tasks, use LLM-based paraphrase augmentation or back-translation to generate minority-class examples that are semantically coherent; evaluate augmented data quality with human review before training.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q46: Bias-variance tradeoff](01-046-bias-variance-tradeoff.md) | Foundational ML concept: imbalance causes high bias toward majority class |
| [Q47: Overfitting — how prevent it?](01-047-overfitting-how-prevent-it.md) | Oversampling and SMOTE can introduce overfitting on duplicated minority examples |
| [Q5: Evaluate and monitor model in production](05-011-evaluate-and-monitor-model-in-production.md) | Production monitoring: tracking precision/recall drift when imbalance ratio shifts |

---

## One-liner recall

> Handle imbalanced datasets in order: fix metrics first (PR-AUC over accuracy), then class weights / focal loss, then SMOTE or augmentation, then threshold tuning on a held-out validation set — and monitor precision/recall separately in production because imbalance ratios drift.
