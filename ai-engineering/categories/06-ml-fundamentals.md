# 06. ML Fundamentals — AI Engineering Interview Category

Classical machine learning knowledge that still appears in ~20–30% of AI engineer interviews, covering data pipelines, model diagnostics, algorithms, and statistical foundations.

---

## Interview signals

| You hear… | This category |
|-----------|---------------|
| "walk me through how you'd handle imbalanced data" | Class imbalance / metrics |
| "what's the bias-variance tradeoff in your model?" | Overfitting / regularization |
| "compare X and Y" (RNN vs LSTM, L1 vs L2, precision vs recall) | Algorithm / technique comparison |
| "how would you debug a model that isn't learning?" | Model diagnostics |
| "explain gradient descent" | Optimization foundations |
| "why not use a neural network for this tabular problem?" | Algorithm selection |

---

## Mental model

Strong candidates treat classical ML as a *diagnostic toolkit*, not a historical relic. They know when gradient boosting (XGBoost/LightGBM) beats a neural net on tabular data, how to read a precision-recall curve to set a business-relevant threshold, and how bias-variance decomposition explains both overfitting in fine-tuned LLMs and underfitting in shallow tree models. They can implement cosine similarity in NumPy without hesitation, explain why L1 produces sparse weights while L2 doesn't, and connect statistical foundations (distributions, Bayes, hypothesis testing) directly to production AI decisions — such as why a well-calibrated fraud detector uses a threshold of 0.23 rather than 0.50. Weak candidates treat these questions as trivia and answer from textbook definitions with no production grounding.

---

## Sub-topics

### 1. Data foundations and preprocessing
**When:** "How do you prepare data for an ML model?" or "walk me through feature engineering"
**What:** The pipeline from raw data to model-ready features — cleaning, encoding, scaling, and handling imbalance — that determines whether a model can learn at all.
**Key questions:**
- [Q1: Data pre-processing and feature engineering?](../answers/06-001-data-pre-processing-and-feature-engineering.md)
- [Q2: SQL vs NoSQL for AI workloads?](../answers/06-002-sql-vs-nosql-for-ai-workloads.md)
- [Q11: Imbalanced datasets in real projects?](../answers/06-011-imbalanced-datasets-in-real-projects.md)
- [Q17: Feature scaling — normalization vs standardization?](../answers/06-017-feature-scaling-normalization-vs-standardization.md)

### 2. Model diagnostics and optimization
**When:** "Your model isn't improving — what do you check?" or "how do you prevent overfitting?"
**What:** Using training/validation gaps, learning curves, and loss analysis to diagnose underfitting, overfitting, and numerical issues; regularization and early stopping as remedies.
**Key questions:**
- [Q3: Diagnose performance bugs in a model?](../answers/06-003-diagnose-performance-bugs-in-a-model.md)
- [Q9: Bias-variance tradeoff?](../answers/06-009-bias-variance-tradeoff.md)
- [Q13: Debug model that runs but doesn't learn?](../answers/06-013-debug-model-that-runs-but-doesnt-learn-broadcasting-dimensio.md)
- [Q16: Regularization — L1, L2, dropout?](../answers/06-016-regularization-l1-l2-dropout.md)

### 3. Algorithms and architecture selection
**When:** "Why would you choose X over Y?" or "compare these two approaches"
**What:** Knowing when to reach for gradient boosted trees vs neural nets vs logistic regression vs CNNs vs LSTMs, and what each architecture is optimized for.
**Key questions:**
- [Q10: Why neural networks not first choice for tabular data?](../answers/06-010-why-neural-networks-not-first-choice-for-tabular-data.md)
- [Q12: RNN vs LSTM?](../answers/06-012-rnn-vs-lstm.md)
- [Q21: Linear vs logistic regression?](../answers/06-021-linear-vs-logistic-regression.md)
- [Q23: Classification algorithms?](../answers/06-023-classification-algorithms.md)

### 4. Evaluation metrics and statistical foundations
**When:** "How do you measure model success?" or "explain precision vs recall in your use case"
**What:** Selecting the right metric for the business problem (PR-AUC for imbalanced, F1 for balanced, NDCG for ranking), supported by statistical grounding in distributions, Bayes, and calibration.
**Key questions:**
- [Q19: Precision vs recall — fraud detection?](../answers/06-019-precision-vs-recall-fraud-detection.md)
- [Q20: F1 score, ROC curve?](../answers/06-020-f1-score-roc-curve.md)
- [Q14: Statistics: probability, distributions, regression, Bayesian, hypothesis testing](../answers/06-014-statistics-probability-distributions-regression-bayesian-hyp.md)

---

## Decision framework

```
Choosing algorithm for a new task:
  If task = image classification / vision:
    → CNN (ResNet/EfficientNet)  because spatial locality + translation invariance
  If task = sequence (NLP, time-series) with long-range dependencies:
    → Transformer  because global attention, parallelizable training
  If task = sequence with limited compute / edge:
    → LSTM  because handles variable-length sequences, smaller than transformer
  If task = tabular structured data:
    → XGBoost / LightGBM first  because less data needed, handles mixed types, no scaling required
    → MLP as alternative if >100K rows and interactions are complex
  If task = binary classification with interpretability requirement:
    → Logistic regression  because coefficients are directly interpretable
  If task = generative / creative:
    → Decoder-only LLM (GPT-family)

Choosing regularization:
  If you need feature selection / sparse weights:
    → L1 (Lasso)  because drives coefficients exactly to 0
  If you want weight shrinkage without sparsity:
    → L2 (Ridge)  because penalizes large weights proportionally
  If model is a neural net and overfitting after epochs:
    → Dropout (training time) + early stopping  because acts as ensemble regularizer
  If fine-tuning an LLM (LoRA):
    → Low rank constraint implicitly regularizes; reduce rank if overfitting

Choosing evaluation metric:
  If classes are balanced:
    → Accuracy or F1
  If classes are imbalanced (fraud, medical):
    → PR-AUC (precision-recall area under curve), not ROC-AUC
  If ranking / retrieval:
    → NDCG, MRR, Recall@k
  If regression:
    → RMSE for outlier-sensitive, MAE for robust
  If probabilistic prediction matters:
    → ECE (expected calibration error) + reliability diagram

Choosing scaling approach:
  If algorithm is distance-based (KNN, SVM, cosine similarity, PCA):
    → Standardization (zero mean, unit variance) — scale-sensitive
  If algorithm is tree-based (XGBoost, Random Forest):
    → No scaling needed — splits are monotone-invariant
  If features have bounded ranges or heavy-tailed distributions:
    → Min-Max normalization [0,1] or RobustScaler (median/IQR)
```

---

## Common mistakes

| Mistake | What to say instead |
|---------|---------------------|
| Defining bias-variance as just "underfitting vs overfitting" without the mathematical decomposition | "Generalization error = Bias² + Variance + Irreducible noise. High bias → model too simple (high train+val error). High variance → model too complex (low train, high val error). I use train-val gap to diagnose which." |
| Saying "accuracy" as the metric for fraud detection or medical diagnosis | "Accuracy is misleading on imbalanced data. I'd use PR-AUC since I care about the precision-recall tradeoff at the operating threshold, not ROC-AUC which treats all thresholds equally." |
| Answering "use a neural network" for tabular data without justification | "XGBoost/LightGBM typically outperform neural nets on tabular data because they handle mixed feature types natively, need less data, and are less sensitive to hyperparameters. Neural nets only win with >100K rows and complex feature interactions." |
| Treating L1 and L2 regularization as interchangeable "to prevent overfitting" | "L1 drives coefficients to exactly zero — useful for feature selection. L2 shrinks all coefficients but keeps them non-zero. In practice I use ElasticNet when I want both properties, or dropout for neural nets." |
| Explaining RNNs without mentioning the vanishing gradient problem | "RNNs suffer from vanishing gradients over long sequences because the gradient is multiplied by the recurrent weight matrix at each step. LSTMs solve this with gated cell state that has additive gradient flow, allowing gradients to survive 100s of timesteps." |
| Saying "just resample" for imbalanced data without discussing the metric implication | "Resampling is a data-level fix, but I'd start with the metric — switch to PR-AUC, use class_weight='balanced' in sklearn, then evaluate whether SMOTE actually improves PR-AUC on a held-out set." |

---

## Question checklist

| # | Question | Difficulty signal | Status |
|---|----------|-------------------|--------|
| 1 | Data pre-processing and feature engineering? | E | `todo` |
| 2 | SQL vs NoSQL for AI workloads? | E | `todo` |
| 3 | Diagnose performance bugs in a model? | M | `todo` |
| 4 | Optimize for latency or throughput? (personal assistant, one request) | M | `todo` |
| 5 | Data parallelism for single-request assistant? | M | `todo` |
| 6 | Transformers — why foundational? ⭐ | E | `todo` |
| 7 | Real-time vs batch processing for data updates? | M | `todo` |
| 8 | Ingest structured, unstructured, event data? | M | `todo` |
| 9 | Bias-variance tradeoff? | E | `todo` |
| 10 | Why neural networks not first choice for tabular data? | M | `todo` |
| 11 | Imbalanced datasets in real projects? | M | `todo` |
| 12 | RNN vs LSTM? | E | `todo` |
| 13 | Debug model that runs but doesn't learn — broadcasting, dimension mismatches? | M | `todo` |
| 14 | Statistics: probability, distributions, regression, Bayesian, hypothesis testing | M | `todo` |
| 15 | Supervised vs unsupervised learning? | E | `todo` |
| 16 | Regularization — L1, L2, dropout? | E | `todo` |
| 17 | Feature scaling — normalization vs standardization? | E | `todo` |
| 18 | Implement cosine similarity in NumPy (Amazon) | E | `todo` |
| 19 | Precision vs recall — fraud detection? | M | `todo` |
| 20 | F1 score, ROC curve? | E | `todo` |
| 21 | Linear vs logistic regression? | E | `todo` |
| 22 | Gradient descent? | E | `todo` |
| 23 | Classification algorithms? | E | `todo` |
| 24 | GANs basic principles? | M | `todo` |
| 25 | CNN architecture? | M | `todo` |
| 26 | BERT architecture? | M | `todo` |

---

## One-page summary

- **Algorithm selection**: XGBoost/LightGBM first for tabular data (handles mixed types, less data, no scaling needed); CNNs for images; LSTMs for short sequences; Transformers for long-range dependencies and NLP; logistic regression for interpretable binary classification.
- **Bias-variance**: Error = Bias² + Variance + Irreducible noise. High bias → model too simple (both train and val error high). High variance → model too complex (low train, high val error). Fix: regularization (L1/L2/dropout), more data, or ensemble methods.
- **Imbalanced data**: Never use accuracy. Use PR-AUC + class_weight='balanced' + threshold tuning via PR curve. SMOTE as last resort — verify it actually improves PR-AUC on held-out set.
- **Regularization**: L1 → feature selection (sparse weights); L2 → weight shrinkage (no sparsity); Dropout → ensemble regularizer for neural nets (50% in FC layers, 10–20% in conv layers). LoRA rank is implicit regularization for LLM fine-tuning.
- **Gradient descent variants**: SGD (noisy, can escape local minima), Adam (adaptive learning rates, best default for neural nets), AdamW (Adam + decoupled weight decay, preferred for transformers). Learning rate and batch size are the two most impactful hyperparameters.
