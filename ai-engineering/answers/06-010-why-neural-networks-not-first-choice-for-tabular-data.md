# Why neural networks not first choice for tabular data?

**Category:** 06-ml-fundamentals
**Question #:** 010
**Source section:** §6 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
Interviewers use this question to separate engineers who reach for deep learning by default from those who reason about the right tool for the job. It probes algorithm-selection discipline, understanding of inductive biases, and practical ML experience with tabular datasets — the most common real-world data format.

### Trigger phrases
- "Would you use a neural network or gradient-boosted trees for this?"
- "Why not just use a neural network for everything?"
- "When would you prefer XGBoost over a deep learning model?"

### What it tests
The ability to reason about inductive biases, training data requirements, and the practical sample-efficiency advantages of tree-based ensembles on structured data.

---

## Answer

### Concept
Neural networks are general-purpose function approximators that learn representations from scratch, but tabular data rarely benefits from this flexibility — the features are already hand-engineered, heterogeneous (mix of numeric, categorical, ordinal), and often scarce. Gradient-boosted trees (XGBoost, LightGBM, CatBoost) are the empirical first choice because they encode inductive biases that match the structure of most tabular problems.

### Mechanism
Several properties make NNs a poor default for tabular data:

1. **Sample efficiency** — Gradient boosted trees (GBTs) reach strong performance with hundreds to low thousands of rows. NNs typically need 50K+ samples to learn competitive representations without heavy regularization. Most enterprise tabular datasets (churn, fraud, pricing) are in the 10K–500K range.

2. **Heterogeneous feature handling** — Tabular data mixes continuous, ordinal, categorical-high-cardinality, and binary features. Trees split on each feature independently and handle missing values natively (LightGBM). NNs require careful encoding (embedding layers for categoricals), imputation, and scaling — all of which introduce failure modes.

3. **No spatial/sequential structure to exploit** — CNNs exploit spatial locality; RNNs exploit sequences; transformers exploit pairwise token interactions. Raw tabular features have none of these structures, so deep architectures offer no architectural advantage over shallow split-based models.

4. **Regularization complexity** — GBTs regularize via early stopping + tree depth + min_samples_leaf with few hyperparameters. NNs require weight decay, dropout, batch normalization, learning-rate scheduling, and careful initialization — a much larger search space.

5. **Interpretability** — SHAP values on XGBoost are exact Shapley computations (TreeSHAP, O(TLD) time). SHAP on NNs is approximate (DeepLIFT, Integrated Gradients) and slower — critical for regulated domains (credit, insurance, healthcare).

**When NNs win on tabular data:**
- Very large datasets (millions of rows) where learned embeddings can compress high-cardinality categoricals (e.g. entity embeddings in DeepFM/TabNet)
- Datasets with rich semi-structured text/image columns that mix with tabular features (multimodal fusion models)
- When joint optimization with an embedding space or shared representation is needed (e.g. two-tower retrieval systems)

### Example / Tradeoff
**Benchmark evidence:** The Grinsztajn et al. 2022 paper ("Why tree-based models still outperform deep learning on tabular data", NeurIPS 2022) benchmarked 45 tabular datasets. XGBoost/Random Forest outperformed tabular DL models (TabNet, NODE, FT-Transformer) on 60%+ of datasets, especially those with ≤10K rows or high feature heterogeneity.

**Production example — credit-risk scoring:** A 6-month churn prediction model at a fintech. Dataset: 80K rows, 120 features (transaction counts, days-since-last-login, plan tier, geography). XGBoost trained in 3 min on a MacBook (early stopping, ~600 trees), AUC 0.87. A 5-layer MLP trained in 45 min on GPU, AUC 0.84, required learning-rate warmup, dropout tuning, and still underfit on the minority churn class. SHAP values on XGBoost fed directly into the compliance report; the MLP required post-hoc LIME approximations.

**Tabular transformers (FT-Transformer, TabPFN):** The latest generation narrows the gap, but still lags GBTs on most <100K-row datasets and costs 10–100× more compute. Use them only when you have millions of rows, need embedding-space sharing with other models, or are running AutoML tournaments where compute is not constrained.

---

## Verbal script

**Opening (30s):**
"The short answer is that gradient-boosted trees — XGBoost, LightGBM, CatBoost — are empirically superior on most tabular datasets, and neural networks only close the gap at very large scale. I'll explain the structural reasons, then give a concrete example."

**Core explanation (2–3 min):**
"Tabular data is fundamentally different from images or text. The features are already hand-crafted and heterogeneous — you have a mix of continuous, ordinal, and high-cardinality categorical columns. Trees handle that natively with per-feature splits and native missing-value imputation; a neural network needs explicit encoding layers for each feature type, which introduces more failure modes.

The second issue is sample efficiency. Most enterprise tabular datasets are in the 10K–500K row range. Gradient-boosted trees reach strong performance there; neural networks typically need 50K+ samples just to avoid heavy overfitting, and then you're tuning dropout, weight decay, learning rate, and batch size on top of the model itself.

There's also no inductive bias to exploit. CNNs exploit spatial locality; transformers exploit token-pair interactions. Tabular features don't have spatial or sequential structure, so deep architectures add complexity without providing an architectural advantage.

Finally, interpretability: TreeSHAP gives exact Shapley values for GBTs in milliseconds. SHAP on neural networks is approximate and slow. For anything credit-scoring, insurance-pricing, or medical-risk-related, regulators often require SHAP feature-importance explanations, and GBTs make that tractable."

**Tradeoff / production angle (1 min):**
"Neural networks do win when the dataset is very large — millions of rows — or when you need to jointly embed tabular features with text or images. DeepFM or two-tower models for recommendation systems are a good example, where entity embeddings for high-cardinality user/item IDs compress the space better than one-hot encodings. The Grinsztajn et al. NeurIPS 2022 benchmark formalizes this: GBTs outperformed tabular DL on 60%+ of 45 benchmark datasets, with the gap closing only as row count and cardinality grew."

**Wrap-up (30s):**
"My rule of thumb: start with LightGBM or XGBoost, get a SHAP-explainable baseline, and only reach for tabular neural networks (TabNet, FT-Transformer) when you have millions of rows or a genuine multimodal fusion requirement. Happy to dig into any of those tradeoffs."

---

## Pitfalls

- **Mistake:** Saying "neural networks are more powerful so they'd do better" without addressing sample efficiency or inductive bias — **Better:** Acknowledge that GBTs encode inductive biases (independent per-feature splits, native missing-value handling) that match tabular structure, and cite the sample-efficiency gap at typical enterprise dataset sizes.
- **Mistake:** Claiming NNs are always worse on tabular data — **Better:** Acknowledge the 2022 NeurIPS evidence showing the gap narrows at millions of rows or high-cardinality categoricals, and name specific contexts where tabular DL (TabNet, FT-Transformer, two-tower) wins.
- **Mistake:** Ignoring the interpretability/compliance angle — **Better:** Mention that TreeSHAP (exact Shapley values in O(TLD) time) is a practical requirement for regulated domains and is far more tractable than SHAP on NNs.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q9: Bias-variance tradeoff?](06-009-bias-variance-tradeoff.md) | Random Forest as variance-reduction ensemble; same inductive bias concept |
| [Q23: Classification algorithms?](06-023-classification-algorithms.md) | Broader algorithm selection — GBTs vs NNs vs linear models |
| [Q7: SHAP, LIME, model interpretability](05-007-shap-lime-model-interpretability.md) | TreeSHAP vs approximate SHAP for NNs in regulated domains |

---

## One-liner recall

> GBTs (XGBoost/LightGBM) beat NNs on most tabular data because tabular features are already hand-engineered and heterogeneous (no spatial/sequential structure to exploit), GBTs are far more sample-efficient at typical enterprise dataset sizes (10K–500K rows), and TreeSHAP provides exact interpretability that regulators require — NNs only win at millions of rows or multimodal fusion tasks.
