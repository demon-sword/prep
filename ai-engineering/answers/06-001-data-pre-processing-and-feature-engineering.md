# Data pre-processing and feature engineering?

**Category:** 06-ml-fundamentals
**Question #:** 001
**Source section:** §6 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
Interviewers want to see that you treat data quality as a first-class engineering problem, not an afterthought. Most real-world ML failures trace back to dirty data or poorly engineered features, not model choice. This question probes your end-to-end pipeline thinking and your practical experience with the messy realities of raw data.

### Trigger phrases
- "Walk me through how you'd prepare a dataset for training."
- "What data pre-processing steps would you apply before feeding data to a model?"
- "How do you handle missing values / categorical variables / skewed distributions?"

### What it tests
Practical ML pipeline fluency — knowing the full spectrum from raw data ingestion to model-ready feature tensors, with awareness of data leakage pitfalls and the cost of getting this wrong.

---

## Answer

### Concept
Data pre-processing transforms raw, messy inputs into clean, model-ready tensors. Feature engineering extracts or constructs informative signals from those cleaned inputs. Together they are typically the highest-leverage lever in a traditional ML pipeline: better features routinely outperform fancier models on the same data.

### Mechanism

**Pre-processing pipeline (in order):**

1. **Ingest & audit** — profile the dataset: row counts, null rates per column, cardinality of categoricals, distribution shape (skewness, outliers). Tools: `pandas-profiling` / `ydata-profiling`, Great Expectations for schema validation.

2. **Handle missing values:**
   - Numerical: mean/median imputation for MCAR (missing completely at random); model-based imputation (KNN, IterativeImputer) for MAR.
   - Categorical: mode imputation or dedicated `"MISSING"` category; never silently drop rows without justification.
   - Time-series: forward-fill (LOCF) or interpolation respecting temporal order.

3. **Outlier treatment:** IQR clipping or Winsorisation for regression targets; log/Box-Cox transforms for heavy right skew (e.g. transaction amounts, ad spend). For anomaly-detection tasks, outliers are the signal — leave them.

4. **Encode categoricals:**
   - Low cardinality (≤15 levels): one-hot encoding.
   - High cardinality (e.g. zip codes, product IDs): target encoding (with out-of-fold estimation to prevent leakage), frequency encoding, or entity embeddings.
   - Ordinal: integer mapping preserving order.

5. **Scale numerical features:**
   - StandardScaler (zero mean, unit variance) — for models sensitive to feature magnitude: logistic regression, SVM, PCA, k-NN, neural nets.
   - MinMaxScaler — when bounded [0,1] range matters (e.g. image pixels, sigmoid output features).
   - Tree-based models (XGBoost, Random Forest) are scale-invariant — skip scaling.
   - **Critical:** fit scalers on training data only, apply to val/test. Fitting on full dataset = data leakage.

6. **Handle class imbalance** (if applicable): oversample minority (SMOTE), undersample majority, or use `class_weight='balanced'` — but always evaluate on PR-AUC not accuracy.

**Feature engineering:**

- **Domain-derived features:** for a transaction fraud model, derive `txn_velocity_24h`, `amount_deviation_from_user_median`, `merchant_category_risk_score`.
- **Interaction terms:** multiply or concatenate correlated features where domain knowledge suggests interaction (e.g. `price × discount_rate`).
- **Temporal features:** extract `hour_of_day`, `day_of_week`, `days_since_last_purchase` from timestamps.
- **Text:** TF-IDF or embeddings (all-MiniLM-L6-v2) for free-form strings; n-gram features for structured codes.
- **Embeddings as features:** for tabular + entity data, pre-trained embeddings (product or user IDs) fed as dense feature vectors to gradient boosting or a shallow MLP.
- **Dimensionality reduction:** PCA or UMAP when feature count >> sample count; interpret variance-explained threshold (≥95%).

**Leakage prevention checklist:**
- All transforms fitted within cross-validation folds, not on full data.
- No future-facing features in time-series (e.g. using next-day sales to predict today).
- No target-derived features computed before train-test split.
- Use `Pipeline` + `ColumnTransformer` in scikit-learn to enforce this mechanically.

### Example / Tradeoff

In a fraud detection project (Stripe-style): raw transaction data had 40% null `merchant_zip`, skewed `amount` (log transform applied), 200+ raw merchant categories (target-encoded using 5-fold out-of-fold), and severe class imbalance (0.1% fraud). Pre-processing stack: Great Expectations for schema contracts → median imputation → log-amount → target encoding within `Pipeline` → `class_weight='balanced'` XGBoost. Result: PR-AUC improved from 0.54 (naive baseline) to 0.81.

**Key tradeoff — automation vs interpretability:** AutoML/FeatureTools can auto-generate hundreds of interaction features, but regulators (FCRA, GDPR Article 22) may require feature-level explanations via SHAP. A smaller, manually engineered feature set is often preferable in regulated domains.

---

## Verbal script

**Opening (30s):**
"I think of data pre-processing and feature engineering as a pipeline with a strict ordering — get the ordering wrong and you introduce leakage, which silently inflates your offline metrics while the model fails in production. Let me walk through the stages I'd apply in practice."

**Core explanation (2–3 min):**
"I'd start with a data audit using ydata-profiling to understand null rates, cardinality, and distribution shape for every column. From there I handle missingness — mean or median imputation for numerical features that are missing completely at random, and a dedicated MISSING category for categoricals so the model can learn from the absence itself. For skewed numericals like transaction amounts I apply a log transform to compress the tail.

For categoricals, I distinguish low-cardinality (one-hot) from high-cardinality like zip codes or product IDs, where I use target encoding with out-of-fold estimation to avoid leakage. Feature scaling — StandardScaler — goes in for linear models and neural nets but I skip it entirely for tree-based models like XGBoost since they're split-point-based and scale-invariant.

Feature engineering is where domain knowledge earns its keep. For fraud detection I'd derive velocity features — transactions in the last 24 hours — and deviation from the user's historical median spend. These are far more informative than raw amount alone.

The single most important mechanical discipline here is wrapping everything in a scikit-learn Pipeline with ColumnTransformer. This guarantees that scalers and encoders are fitted only on the training fold during cross-validation, never on the full dataset, which is the number one source of data leakage I see in real codebases."

**Tradeoff / production angle (1 min):**
"At production scale the tradeoff shifts toward real-time feature serving. Features like 24-hour transaction velocity can't be computed at prediction time from scratch — you need a feature store (Feast, Tecton) that maintains pre-computed aggregates and serves them with sub-10ms latency. The training pipeline reads historical snapshots from the same store to maintain training-serving consistency, which is otherwise a silent source of model degradation."

**Wrap-up (30s):**
"So the core discipline is: audit → clean → encode → scale → engineer domain features → enforce leakage prevention via Pipeline. In production, extend that to a feature store for low-latency serving. Happy to go deeper on any specific stage — leakage patterns, target encoding mechanics, or feature store design."

---

## Pitfalls

- **Mistake:** Fitting scalers or encoders on the full dataset before splitting — **Better:** Always fit inside a `Pipeline` that runs within cross-validation folds; explain that fitting on the test set inflates metrics because the model has seen test-set statistics during "training."
- **Mistake:** Using accuracy as the evaluation metric after applying SMOTE for class imbalance — **Better:** Use PR-AUC or F1 with `average='binary'`; SMOTE changes the class distribution in training but evaluation must reflect the true production distribution.
- **Mistake:** Applying the same pre-processing logic to all model types (e.g. scaling for XGBoost) — **Better:** Tree-based models are scale-invariant; applying StandardScaler to XGBoost features wastes computation and signals surface-level familiarity.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q11: Imbalanced datasets in real projects?](06-011-imbalanced-datasets-in-real-projects.md) | Directly related — imbalance handling is a core pre-processing concern |
| [Q19: Precision vs recall — fraud detection?](06-019-precision-vs-recall-fraud-detection.md) | Evaluation metrics flow directly from pre-processing choices for imbalanced data |
| [Q9: Bias-variance tradeoff?](06-009-bias-variance-tradeoff.md) | Feature engineering richness directly controls variance; regularization interacts with feature count |

---

## One-liner recall

> Data pre-processing is audit → impute → encode → scale (inside a Pipeline to prevent leakage), followed by domain-derived feature engineering; the discipline is fitting all transforms on training data only and matching the same pipeline in a feature store for production serving.
