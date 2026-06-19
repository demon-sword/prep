# Diagnose performance bugs in a model?

**Category:** 06-ml-fundamentals
**Question #:** 003
**Source section:** §6 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
Interviewers want to see systematic debugging instinct — not guesswork. Strong candidates follow a structured diagnostic ladder from data → training loop → architecture → evaluation, rather than immediately jumping to "retrain with more data." This is heavily probed in mid-to-senior ML interviews because poor debuggers waste GPU-months.

### Trigger phrases
- "Your model's validation loss is stagnating — how do you debug it?"
- "A model that was working dropped 10 points of accuracy in production — where do you start?"
- "Diagnose performance bugs in a model?"

### What it tests
Ability to isolate root cause across the full ML pipeline — data quality, training dynamics, architecture, and evaluation — using structured hypotheses rather than trial-and-error.

---

## Answer

### Concept
Model performance bugs fall into five root-cause buckets: **data issues** (leakage, distribution shift, label noise), **training dynamics issues** (wrong learning rate, vanishing/exploding gradients, underfitting/overfitting), **architecture mismatches** (wrong inductive bias for the task), **evaluation bugs** (metric doesn't match business goal, test set contamination), and **production drift** (train/serve feature skew). Diagnosing systematically means ruling out each layer before touching the next.

### Mechanism
**5-step diagnostic ladder:**

1. **Validate the eval metric first.** Check if validation loss and the business metric are aligned. A classification model with `accuracy` as the metric on an imbalanced dataset will appear 98% accurate while being useless — swap to PR-AUC or F1 immediately.

2. **Check the data.** Run a data audit:
   - Label noise: sample 200 random examples and manually inspect labels.
   - Train/test leakage: verify timestamps, shuffle seeds, feature construction pipelines.
   - Distribution shift: compare `train_X.describe()` vs `val_X.describe()` / production feature distributions.
   - Class imbalance: `value_counts()` on target; if >10:1 imbalance, accuracy is misleading.

3. **Sanity-check the training loop.** Overfit a single mini-batch (32 examples) on purpose — if the model can't reach near-zero training loss on 32 examples with high learning rate, the architecture or loss function is broken. Common bugs:
   - Gradient not flowing: check `requires_grad`, detached tensors, frozen layers not intended to be frozen.
   - Dimension mismatch causing silent broadcasting: print `tensor.shape` at every layer; use `assert` guards.
   - Loss is NaN: learning rate too high, log(0), inf in features — add gradient clipping (`clip_grad_norm_(1.0)`).
   - Wrong loss function: using CrossEntropyLoss with sigmoid output (expects raw logits) or BCELoss with multi-class.

4. **Plot learning curves.** Compare train loss vs val loss over epochs:
   - Both high → **underfitting** (model capacity too low, learning rate too low, not enough epochs)
   - Train low, val high → **overfitting** (add dropout/L2, reduce model size, get more data)
   - Val loss decreasing then spiking → **learning rate too high or batch norm issue**
   - Val loss never decreases → data/label bug or architectural mismatch

5. **Profile inference vs training for production bugs.** If accuracy was fine offline but degraded in production, check:
   - Feature skew: production features computed differently than training (different time windows, imputation logic).
   - Model/data staleness: embedding models updated but downstream classifier not retrained.
   - Batch norm inference mode: `model.eval()` not called, so batch statistics differ.

### Example / Tradeoff
**Concrete incident:** A fine-tuned BERT classifier for intent detection dropped from 91% to 79% accuracy after a data pipeline update. Diagnosis ladder:
1. Metric aligned (accuracy fine for balanced 10-class problem) ✓
2. Data audit: the pipeline started lowercasing text at ingestion — but the fine-tuned BERT tokenizer was case-sensitive (bert-base-cased). Token-ID mismatch caused OOV on proper nouns.
3. Fix: unified preprocessing contract in the feature pipeline, pinned the tokenizer type in metadata.
4. Result: accuracy recovered to 90% after reprocessing — no retraining needed.

**Tool stack for PyTorch debugging:** `torch.autograd.set_detect_anomaly(True)` for NaN gradient location, `torchinfo` for shape tracing, TensorBoard or W&B for loss curves, `torch.testing.assert_close` for numerical precision checks.

---

## Verbal script

**Opening (30s):**
"I approach model debugging with a five-layer diagnostic ladder — I never start by retraining, because the bug could be in evaluation, data, or the training loop itself. Let me walk through how I'd systematically rule out each layer."

**Core explanation (2–3 min):**
"First, I validate the evaluation metric. If I'm looking at accuracy on an imbalanced dataset, I might be measuring the wrong thing entirely — I'd switch to PR-AUC or F1 before drawing any conclusions.

Second, I audit the data: sample 200 examples to inspect label quality, check for train/test leakage (wrong shuffling, timestamp issues), and compare feature distributions between train and validation to catch any preprocessing bugs.

Third, I run a single mini-batch overfit test — force the model to memorize 32 examples with a high learning rate. If it can't reach near-zero loss on 32 samples, something is architecturally broken: a detached tensor, wrong loss function, or dimension broadcasting issue. In PyTorch I'd use `set_detect_anomaly(True)` and print tensor shapes at each layer.

Fourth, I plot training curves. High train and val loss → underfitting. Low train, high val → overfitting. Val loss spiking after decreasing → learning rate or batch norm issue. The shape of those curves tells me exactly which lever to pull.

Fifth, for production degradation specifically, I check for feature skew — the production pipeline computing features differently than training — and make sure `model.eval()` is called so batch norm uses population statistics, not mini-batch statistics."

**Tradeoff / production angle (1 min):**
"The key tradeoff is time: the mini-batch overfit test is fast (under a minute) and rules out training-loop bugs before burning GPU-hours on a full rerun. The place candidates get stuck is skipping the data audit because it's 'boring' — but label noise or train/test leakage is often the root cause, and no amount of architecture tuning will fix it. In production, feature skew between serving and training is the single most common silent killer of deployed models."

**Wrap-up (30s):**
"So in summary: validate the metric → audit data → sanity-check the training loop → read the learning curves → check train/serve skew for production bugs. Happy to go deeper on any specific layer — gradient debugging, data leakage detection patterns, or overfitting diagnostics."

---

## Pitfalls

- **Mistake:** Immediately retraining with more data or tweaking the architecture when accuracy drops — **Better:** First check if the eval metric is correct and run a data audit; the bug is often in preprocessing or label noise, not model capacity.
- **Mistake:** Ignoring the difference between training loss and validation loss curves and only reporting final accuracy — **Better:** Plot both curves over epochs; the shape reveals underfitting vs overfitting vs a learning rate issue, each with a different fix.
- **Mistake:** Assuming a production accuracy drop means the model degraded — **Better:** Check for feature skew (production features computed differently) and confirm `model.eval()` is called; these are more common causes than actual model rot.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q9: Bias-variance tradeoff?](06-009-bias-variance-tradeoff.md) | Underfitting vs overfitting is the core diagnostic axis from learning curves |
| [Q13: Debug model that runs but doesn't learn — broadcasting, dimension mismatches?](06-013-debug-model-that-runs-but-doesnt-learn-broadcasting-dimensio.md) | Deeper dive on training-loop-specific bugs |
| [Q1: Data pre-processing and feature engineering?](06-001-data-pre-processing-and-feature-engineering.md) | Data audit and leakage detection are the first two diagnostic steps |

---

## One-liner recall

> Diagnose in order: validate the metric → audit data for leakage/noise/shift → mini-batch overfit test to catch training-loop bugs → read learning curves for under/overfitting → check train/serve feature skew for production drops.
