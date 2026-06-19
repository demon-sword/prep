# Classification algorithms?

**Category:** 06-ml-fundamentals
**Question #:** 023
**Source section:** §6 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
Interviewers use this as a breadth-and-depth scan: can you enumerate the main families, articulate when each wins, and reason about tradeoffs (accuracy vs interpretability, sample size vs speed, linear vs non-linear boundaries)? Applied AI roles care especially about which classifier to reach for first and how to explain the choice to a non-technical stakeholder.

### Trigger phrases
- "Walk me through the classification algorithms you know."
- "How would you pick a classifier for this problem?"
- "What's the difference between logistic regression and a decision tree?"

### What it tests
Breadth of classical ML knowledge and ability to map algorithmic properties to practical constraints (data size, latency, interpretability, class imbalance).

---

## Answer

### Concept
Classification algorithms learn a decision boundary (or probability distribution) that maps input features to discrete class labels. They differ in the form of that boundary (linear vs non-linear), how they handle uncertainty (calibrated probabilities vs hard labels), computational complexity, and interpretability.

### Mechanism
The main families, with key properties:

| Algorithm | Decision boundary | Sample efficiency | Interpretability | Key strength |
|-----------|------------------|------------------|-----------------|--------------|
| **Logistic Regression** | Linear | High (100s of rows) | High (log-odds coefficients) | Baseline; calibrated probabilities; L1 for feature selection |
| **Decision Tree** | Axis-aligned splits | Medium | Very high (SHAP/viz) | Categorical features; no scaling needed |
| **Random Forest** | Non-linear ensemble | Medium (1K+) | Medium (feature importance) | Low variance; handles missing values; tabular default |
| **Gradient Boosted Trees** (XGBoost/LightGBM/CatBoost) | Non-linear ensemble | Medium | Medium (SHAP) | Best-in-class accuracy on tabular; native categoricals in CatBoost |
| **Support Vector Machine (SVM)** | Max-margin hyperplane (+ RBF kernel for non-linear) | Low–medium | Low | High-dimensional sparse text features; margin guarantee |
| **k-Nearest Neighbors (kNN)** | Instance-based, no explicit boundary | Any | Very high | No training phase; degrades O(N) at inference |
| **Naive Bayes** | Linear (Gaussian NB) / conditional independence assumption | Very high (10s of rows) | High | Real-time spam/text classification; very sparse inputs |
| **Neural Networks / Fine-tuned LLMs** | Arbitrary non-linear | Needs 10K+ (or pre-training) | Low | Unstructured inputs (text, images, audio) |

**Decision tree for algorithm selection:**
```
Do you have unstructured inputs (text/images)?
  → Yes: Fine-tuned transformer (BERT/DistilBERT) or CNN
  → No (tabular):
      < 1K rows or need interpretability?
        → Yes: Logistic Regression (or Decision Tree for non-linear)
        → No:
            Need calibrated probabilities for business decision?
              → Yes: Logistic Regression + Platt scaling OR Random Forest with isotonic calibration
              → No: XGBoost/LightGBM (highest accuracy on tabular; tune with Optuna)
      High-dimensional sparse text (TF-IDF features, <100K docs)?
        → SVM with linear kernel or Naive Bayes (fast, strong baseline)
```

### Example / Tradeoff
**Fraud detection pipeline:** Start with Logistic Regression to set a calibrated baseline and verify features (fast, interpretable, PR-AUC of ~0.72). Graduate to XGBoost once the feature set is validated — it consistently outperforms on tabular fraud data (+6–10 pts PR-AUC) and natively handles missing values (card not present vs POS). Use TreeSHAP for regulatory explainability. LightGBM is preferred when training on 50M+ rows due to histogram-based binning (3–5× faster than XGBoost default). For real-time scoring at <10ms latency, serve XGBoost via ONNX Runtime (avoids Python overhead) or Triton Inference Server.

**Class imbalance impact:** GBTs handle mild imbalance well via `scale_pos_weight`; severe imbalance (1:1000) still needs SMOTE oversampling or focal loss on top.

---

## Verbal script

**Opening (30s):**
"Classification algorithms are a big family, so I like to organize them by the shape of boundary they learn and what constraints they're optimized for. I'll walk through the main families and then explain my decision framework for choosing between them."

**Core explanation (2–3 min):**
"I think of classifiers in four broad groups. First, linear models — Logistic Regression is my default baseline. It learns log-odds coefficients over features, gives calibrated probabilities out of the box, and works well even with just a few hundred samples. L1 regularization doubles as built-in feature selection. Then tree-based models — Decision Trees are interpretable but high-variance; Random Forests fix that with bagging, averaging out noise across trees. Gradient Boosted Trees — XGBoost, LightGBM, CatBoost — are typically the best single-model approach on tabular data. They build trees sequentially, each one correcting the residuals of the last, and LightGBM's histogram binning makes them fast even on 50 million rows.

The third group is kernel methods — SVMs with an RBF kernel can draw arbitrary non-linear boundaries and they're especially strong on high-dimensional sparse inputs like TF-IDF text vectors, where there's a margin guarantee. But they don't scale to millions of training points. Fourth is neural networks and fine-tuned transformers, which I reach for when the input is unstructured — text, images, audio — or when I have enough data to benefit from pre-trained representations.

For choosing: if the data is tabular and I have thousands of rows, XGBoost or LightGBM will almost always win on raw accuracy. If I need a calibrated probability output for a downstream cost-sensitive decision — like setting a fraud threshold at a specific dollar loss — I'll check calibration with a reliability diagram and apply Platt scaling if needed."

**Tradeoff / production angle (1 min):**
"The most common pitfall I see is skipping straight to a neural network on tabular data. Grinsztajn et al. at NeurIPS 2022 showed that tree-based models still outperform deep nets on most standard tabular benchmarks because GBTs have the right inductive bias — axis-aligned splits that naturally handle heterogeneous feature scales and categorical variables. Neural nets also need more data and are harder to debug. I'll consider a neural net on tabular data only when I have millions of rows, mixed numerical and categorical embeddings, or I need to share representations across tasks."

**Wrap-up (30s):**
"So the short version: Logistic Regression baseline → GBT (XGBoost/LightGBM) for tabular accuracy → SVM for sparse high-dimensional → fine-tuned transformer for unstructured. Happy to go deeper on any of these, or talk through calibration and imbalanced-class handling."

---

## Pitfalls

- **Mistake:** Listing every algorithm name without explaining *when* to use each — **Better:** Lead with the decision framework: linear vs tree vs kernel vs neural, driven by data type, sample size, and interpretability requirements.
- **Mistake:** Saying "random forests are always better than decision trees" without explaining *why* (variance reduction via bagging) — **Better:** Explain the bias-variance decomposition: a single deep tree has low bias but high variance; Random Forest averages N uncorrelated trees to cut variance without increasing bias.
- **Mistake:** Ignoring calibration — treating any classifier's softmax/sigmoid output as a trustworthy probability — **Better:** Always check calibration with a reliability diagram, especially for threshold-sensitive applications (fraud, medical); apply Platt scaling or isotonic regression when the model is overconfident.
- **Mistake:** Recommending neural networks for tabular classification problems as "state of the art" — **Better:** Cite the Grinsztajn NeurIPS 2022 result — GBTs still outperform most tabular deep learning methods; NNs win only when you have millions of rows or need cross-task representation sharing.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q21: Linear vs logistic regression?](06-021-linear-vs-logistic-regression.md) | Prerequisite — logistic regression is the linear classifier baseline |
| [Q19: Precision vs recall — fraud detection?](06-019-precision-vs-recall-fraud-detection.md) | Follow-up — choosing the right eval metric for the chosen classifier |
| [Q9: Bias-variance tradeoff?](06-009-bias-variance-tradeoff.md) | Same concept — explains why ensembles beat single trees |

---

## One-liner recall

> Pick by data type and size: Logistic Regression baseline → XGBoost/LightGBM for tabular accuracy → SVM for sparse high-dimensional → fine-tuned transformer for unstructured; always check calibration before setting thresholds.
