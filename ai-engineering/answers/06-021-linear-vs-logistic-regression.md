# Linear vs logistic regression?

**Category:** 06-ml-fundamentals
**Question #:** 021
**Source section:** §6 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
This is a near-universal screening question that separates candidates who understand statistical learning fundamentals from those who only know sklearn API calls. Interviewers probe whether you understand the output space, loss function, and use-case boundary of each model — not just "one is for regression, one is for classification."

### Trigger phrases
- "When would you use linear vs logistic regression?"
- "Walk me through how logistic regression works."
- "What's the difference between linear and logistic regression?"
- "Why can't you use linear regression for a classification problem?"

### What it tests
Understanding of statistical model assumptions, loss functions, and the ability to choose the right tool for continuous vs. binary/categorical outputs.

---

## Answer

### Concept
**Linear regression** models a continuous output as a linear combination of input features: ŷ = wᵀx + b, optimized by minimizing mean squared error (MSE). **Logistic regression** models the *probability* of a binary outcome by passing the linear combination through a sigmoid: P(y=1|x) = σ(wᵀx + b) = 1/(1 + e^{−wᵀx−b}), optimized by minimizing binary cross-entropy (log loss). The key difference: linear regression produces unbounded real-valued outputs; logistic regression constrains output to (0, 1) via the sigmoid, making it interpretable as a probability.

### Mechanism

**Linear Regression:**
- Model: ŷ = wᵀx + b
- Loss: MSE = (1/n) Σ(yᵢ − ŷᵢ)²
- Optimization: closed-form Normal Equation (X^T X)^{-1} X^T y or gradient descent
- Assumptions: linearity, homoscedasticity, no multicollinearity, normally distributed residuals
- Output: any real number (−∞, +∞)

**Logistic Regression:**
- Model: logit(p) = wᵀx + b → p = σ(wᵀx + b)
- Loss: Binary Cross-Entropy = −(1/n) Σ [yᵢ log(p̂ᵢ) + (1−yᵢ) log(1−p̂ᵢ)]
- Optimization: gradient descent (no closed form due to sigmoid); convex loss → global minimum guaranteed
- Coefficient interpretation: log-odds (each unit increase in xⱼ multiplies the odds by e^{wⱼ})
- Output: probability ∈ (0, 1); class assignment via threshold (default 0.5, tunable)

**Why linear regression breaks for classification:**
If you apply linear regression to a {0,1} target, predictions can exceed [0,1] (e.g. ŷ = 1.7 or −0.3), which is nonsensical as a probability. MSE penalizes confident correct predictions (ŷ=0.99 when y=1 contributes loss), which distorts the decision boundary. Log loss instead rewards calibrated confidence.

**Extension — multi-class:**
Logistic regression extends to multi-class via softmax: P(y=k|x) = e^{wₖᵀx} / Σⱼ e^{wⱼᵀx}, with categorical cross-entropy loss.

### Example / Tradeoff

| Criterion | Linear Regression | Logistic Regression |
|-----------|------------------|---------------------|
| Output type | Continuous (price, latency) | Binary/multi-class probability |
| Loss | MSE | Binary cross-entropy |
| Optimization | Closed-form or GD | GD only (convex) |
| Assumptions | Gaussian residuals | Sigmoid-transformed linear relationship |
| Interpretability | Coefficients = direct effect on ŷ | Coefficients = log-odds ratios |
| Calibration | Not a probability | Probabilistic output (may need Platt scaling for calibration) |

**Concrete examples:**
- **Linear:** Predict query latency from prompt-token count and rerank candidate count in a RAG pipeline.
- **Logistic:** Predict whether a support ticket will be escalated (binary), or whether a user query is out-of-scope for a chatbot.
- **sklearn snippet:**
  ```python
  from sklearn.linear_model import LogisticRegression
  from sklearn.preprocessing import StandardScaler
  from sklearn.pipeline import Pipeline

  pipe = Pipeline([
      ('scaler', StandardScaler()),          # required for gradient convergence
      ('clf', LogisticRegression(C=1.0,      # C = 1/λ (regularization strength)
                                 max_iter=1000,
                                 class_weight='balanced'))  # handles imbalance
  ])
  pipe.fit(X_train, y_train)
  proba = pipe.predict_proba(X_test)[:, 1]  # use probabilities, not hard labels
  ```

**Key tradeoff — when to stop at logistic regression:**
For tabular classification with <500K rows and interpretability requirements (FCRA, HIPAA), logistic regression with L2 regularization is often the right choice over XGBoost or neural nets. It's fast, interpretable (log-odds per feature), and sklearn's `coef_` gives regulatory-grade explanations. Reach for gradient-boosted trees when you need to capture non-linear interactions or when accuracy outweighs interpretability.

---

## Verbal script

**Opening (30s):**
"Great question — this is really about choosing the right model for the output type. I think of it this way: linear regression is for continuous targets, logistic regression is for class probabilities, and the core difference is the loss function and what the model is learning to predict."

**Core explanation (2–3 min):**
"I'd start with linear regression. The model is simply ŷ equals w-transpose-x plus b. You minimize MSE — mean squared error — and you can even solve it in closed form with the normal equation. The output is any real number, which is perfect for predicting something like latency or revenue.

Now, if you try to apply that to a binary label — spam or not-spam — you immediately hit a problem: the model can predict 1.7 or negative 0.3, which makes no sense as a probability, and MSE penalizes confident correct predictions in weird ways.

Logistic regression fixes this by passing the linear combination through a sigmoid function: p equals 1 over 1 plus e to the minus wᵀx. Now the output is always between 0 and 1 — a proper probability. The loss switches to binary cross-entropy, which rewards confident correct predictions and heavily penalizes confident wrong ones. Importantly, because the log loss is convex, gradient descent always finds the global minimum.

One thing I like to highlight for interviewers: the coefficients in logistic regression are log-odds ratios. A coefficient of 0.7 on a feature means that a one-unit increase in that feature multiplies the odds of the positive class by e^0.7 ≈ 2.0. That's critical for regulated domains — FCRA-compliant models need that interpretability."

**Tradeoff / production angle (1 min):**
"In production, logistic regression shines when you need interpretability, fast inference, and a calibrated probability output — like routing support tickets or flagging out-of-scope queries in a chatbot. The default 0.5 threshold is rarely optimal; I always tune it on the PR curve using a cost function that reflects the business asymmetry between false positives and false negatives.

Where it breaks down: when there are non-linear interactions between features. A ticket-escalation model might need to combine 'angry sentiment AND enterprise tier AND billing keyword' — that interaction is hard to capture without feature engineering. At that point I'd move to XGBoost, which handles non-linearities natively without requiring manual feature crosses."

**Wrap-up (30s):**
"So the one-liner: linear regression for continuous outputs with MSE, logistic regression for class probabilities with cross-entropy and a sigmoid — and always tune the classification threshold against a business cost function rather than defaulting to 0.5. Happy to go deeper on multi-class softmax or regularization tradeoffs."

---

## Pitfalls

- **Mistake:** Saying "logistic regression is just linear regression with a different output function" without explaining the loss function change — **Better:** Explicitly state that linear regression uses MSE and logistic uses binary cross-entropy; the loss function drives the optimization behavior and why MSE is inappropriate for classification (penalizes confident correct predictions, unbounded output).
- **Mistake:** Defaulting to threshold 0.5 for classification without mentioning threshold tuning — **Better:** Explain that 0.5 is arbitrary; use the PR curve + cost function (FP cost vs FN cost) to pick the threshold that minimizes expected business loss, especially for imbalanced problems like fraud or escalation.
- **Mistake:** Forgetting to standardize features before logistic regression — **Better:** Logistic regression uses gradient descent, which converges much faster when features are on the same scale; always wrap in a StandardScaler Pipeline in sklearn to prevent convergence issues with max_iter.
- **Mistake:** Treating the logistic regression probability output as perfectly calibrated — **Better:** Logistic regression can be miscalibrated (overconfident or underconfident); check with a reliability diagram and apply Platt scaling or isotonic regression if calibration matters for downstream decisions.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q19: Precision vs recall — fraud detection?](06-019-precision-vs-recall-fraud-detection.md) | Threshold tuning on logistic regression output; PR-AUC vs accuracy |
| [Q20: F1 score, ROC curve?](06-020-f1-score-roc-curve.md) | Evaluation metrics for logistic regression classifiers |
| [Q9: Bias-variance tradeoff?](06-009-bias-variance-tradeoff.md) | L1/L2 regularization of logistic regression controls variance |

---

## One-liner recall

> Linear regression minimizes MSE for continuous outputs (ŷ ∈ ℝ); logistic regression minimizes binary cross-entropy after a sigmoid for class probabilities (p ∈ (0,1)) — always tune the decision threshold using a PR-curve cost function rather than defaulting to 0.5.
