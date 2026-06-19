# Feature scaling — normalization vs standardization?

**Category:** 06-ml-fundamentals
**Question #:** 017
**Source section:** §6 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
Tests whether the candidate understands *why* scale matters (distance-based and gradient-based algorithms are sensitive to feature magnitude), can choose the right technique for the distribution at hand, and knows the production gotcha of fitting the scaler on training data only.

### Trigger phrases
- "How would you handle features of very different scales?"
- "When would you use min-max normalization vs z-score standardization?"
- "What preprocessing do you apply before training a neural network / SVM / k-NN?"

### What it tests
Ability to match scaling method to data distribution + algorithm + production requirements, and to avoid data-leakage through the scaler.

---

## Answer

### Concept
Feature scaling brings numeric features onto a comparable range so that algorithms that depend on distances (k-NN, SVM, PCA) or gradient magnitudes (neural networks, logistic regression with gradient descent) are not dominated by large-valued features. The two main methods are **min-max normalization** (rescale to [0, 1]) and **z-score standardization** (rescale to zero mean, unit variance).

### Mechanism

| Method | Formula | Output range | Sensitive to outliers? |
|--------|---------|--------------|------------------------|
| Min-max normalization | `x' = (x − min) / (max − min)` | [0, 1] (bounded) | Yes — outliers shift min/max |
| Z-score standardization | `x' = (x − μ) / σ` | (−∞, +∞) unbounded | Less so — mean/std more robust |
| Robust scaling | `x' = (x − median) / IQR` | Unbounded | No — uses median/IQR |

**Decision rule:**
```
Bounded, known range + no heavy outliers (pixel intensities, ratings)?
  → Min-max normalization (values stay in [0,1], good for sigmoid/tanh activations)

Unknown range or significant outliers + Gaussian-ish data?
  → Z-score standardization (preserves signed distance from mean; standard for SVMs, PCA, LR)

Heavy outliers present?
  → Robust scaling (sklearn.preprocessing.RobustScaler)

Tree-based model (XGBoost, Random Forest, LightGBM)?
  → No scaling needed — splits are rank-invariant
```

**Critical production rule:** Fit the scaler **only on the training set**, then apply `transform()` to validation and test sets. Fitting on the full dataset leaks test-set statistics → inflated metrics.

```python
from sklearn.preprocessing import StandardScaler
from sklearn.pipeline import Pipeline

pipe = Pipeline([
    ('scaler', StandardScaler()),
    ('clf', LogisticRegression()),
])
pipe.fit(X_train, y_train)          # scaler fitted on X_train only
pipe.score(X_test, y_test)          # transform applied to X_test with train params
```

### Example / Tradeoff

**Neural network training (LLM embedding fine-tuning):** When appending tabular features (e.g., user age, tenure) to a model alongside text embeddings, z-score standardization ensures gradient contributions from tabular features are comparable to the embedding dimensions. Without scaling, a feature with range [0, 100k] dominates weight updates and destabilizes training.

**Fraud detection SVM:** SVM maximizes the margin in feature space; a feature with σ=50,000 (transaction amount) would overshadow a feature with σ=1 (browser trust score). Standardization brings both to σ=1, letting the kernel measure distance fairly.

**Tradeoff:** Min-max is bounded, which suits pixel-level CNNs (VGG, ResNet expect [0,1] or [0,255]). But a single outlier (e.g., a fraudulent transaction 100× the max training value) will compress all other values into a tiny range at inference time — StandardScaler degrades more gracefully.

---

## Verbal script

**Opening (30s):**
"Feature scaling matters whenever your algorithm is sensitive to feature magnitudes — distance-based methods like k-NN and SVM, or gradient descent in neural networks. The two main choices are min-max normalization and z-score standardization, and I pick between them based on the data distribution, presence of outliers, and the downstream model."

**Core explanation (2–3 min):**
"Min-max rescales to [0, 1] using the training min and max. It's great when the range is known and bounded — pixel intensities for a CNN, ratings on a 1–5 scale. The downside is that outliers shift the min and max, compressing everything else.

Z-score standardization subtracts the mean and divides by standard deviation, producing unbounded output centered at zero. It's the standard for SVMs, PCA, and logistic regression because it preserves signed distance from the center and degrades gracefully with outliers. If outliers are severe, I'd use RobustScaler from sklearn, which uses median and IQR instead of mean and std.

Tree-based models — XGBoost, LightGBM, Random Forest — don't need scaling at all because splits are rank-invariant.

The production rule I always emphasize: fit the scaler only on training data, then call transform on val and test. Fitting on the full dataset leaks test statistics and gives you optimistically biased evaluation metrics. sklearn Pipelines make this easy — the scaler is part of the pipeline and can't leak."

**Tradeoff / production angle (1 min):**
"A concrete production gotcha: in a fraud detection SVM, transaction amount could have a σ of $50,000 while browser trust score has σ=1. Without standardization, the kernel distance is dominated by transaction amount and the trust score is invisible to the model. After StandardScaler both have σ=1 and the SVM learns both features.

Another angle: at serving time, you serialize the fitted scaler alongside the model and apply the same training-set params to new requests. If your data distribution shifts (embedding drift, seasonality), the scaler params become stale — a signal to retrain."

**Wrap-up (30s):**
"So my rule of thumb: bounded known range → min-max; general continuous features → standardization; heavy outliers → robust scaling; tree models → skip scaling entirely. And always fit on training data only. Happy to go deeper on any of these or discuss how this applies to feature stores in production."

---

## Pitfalls

- **Mistake:** Fitting StandardScaler on the full dataset (train + test) before the train/test split — **Better:** Always fit the scaler inside a Pipeline or after the split, on training data only; explain that test-set leakage inflates eval metrics and produces overconfident models in production.
- **Mistake:** Applying min-max scaling when heavy outliers exist in production data — **Better:** Explain that a single extreme value at inference time compresses all other features into a near-zero range; use StandardScaler or RobustScaler when the feature range is unbounded or outlier-prone.
- **Mistake:** Scaling tree-based model features unnecessarily and calling it a best practice — **Better:** Clarify that XGBoost, LightGBM, and Random Forest are invariant to monotonic feature transformations; scaling adds complexity with no benefit.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q1: Data pre-processing and feature engineering?](06-001-data-pre-processing-and-feature-engineering.md) | Prerequisite — scaling is one step in the preprocessing pipeline |
| [Q9: Bias-variance tradeoff?](06-009-bias-variance-tradeoff.md) | Related — poor scaling can mask underfitting/overfitting signals |
| [Q18: Implement cosine similarity in NumPy (Amazon)](06-018-implement-cosine-similarity-in-numpy-amazon.md) | Follow-up — cosine similarity is scale-invariant by design; contrast with Euclidean distance |

---

## One-liner recall

> Choose min-max for bounded distributions, z-score standardization for general continuous features (degrades gracefully with outliers), robust scaling when outliers are severe, and no scaling for tree models — always fit the scaler on training data only to avoid test-set leakage.
