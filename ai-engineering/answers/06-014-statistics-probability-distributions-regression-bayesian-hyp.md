# Statistics: probability, distributions, regression, Bayesian, hypothesis testing

**Category:** 06-ml-fundamentals
**Question #:** 014
**Source section:** §6 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
Statistics is the mathematical backbone of every ML model. Interviewers ask this at screening to verify foundational literacy: can the candidate reason about uncertainty, interpret model outputs, and diagnose failures using statistical language? For senior roles it probes whether you can design experiments (A/B tests, hypothesis tests) and communicate results to non-technical stakeholders.

### Trigger phrases
- "Walk me through the statistical concepts you'd use to evaluate a model."
- "How do you test whether two models are statistically different?"
- "What's a p-value and how would you explain it to a PM?"
- "How does Bayesian reasoning apply to ML?"

### What it tests
Breadth of statistical literacy — probability foundations, distribution choice, regression intuition, Bayesian vs frequentist reasoning, and experimental design via hypothesis testing.

---

## Answer

### Concept
Statistics provides the language for quantifying uncertainty in ML: **probability theory** models randomness; **distributions** describe data-generating processes; **regression** fits relationships between variables; **Bayesian inference** updates beliefs with evidence; **hypothesis testing** decides whether observed differences are real or noise.

### Mechanism

**1. Probability foundations**
- **Probability rules:** P(A∩B) = P(A)·P(B|A); P(A∪B) = P(A)+P(B)−P(A∩B)
- **Bayes' theorem:** P(H|D) = P(D|H)·P(H) / P(D) — posterior = likelihood × prior / evidence
- **Expectation & variance:** E[X], Var[X] = E[X²]−(E[X])²; law of total expectation useful for multi-stage ML pipelines

**2. Key distributions**
| Distribution | When | Parameter intuition |
|---|---|---|
| Normal (Gaussian) | Residuals, gradient noise, log-odds | μ (location), σ² (spread) |
| Bernoulli / Binomial | Binary classification, A/B success | p (success prob), n (trials) |
| Categorical / Multinomial | Softmax output, class priors | k-category prob vector |
| Poisson | Count data (clicks/hour, errors/day) | λ = rate |
| Beta | Prior over probabilities (CTR, accuracy) | α, β shape parameters |
| Exponential | Time-to-event (latency tail, TTF) | λ = rate |

**3. Regression**
- **Linear regression** — OLS minimises MSE; closed-form β = (XᵀX)⁻¹Xᵀy; assumptions: linearity, homoscedasticity, independence, normality of residuals
- **Logistic regression** — models log-odds; cross-entropy loss; output is calibrated probability (good for fraud, CTR)
- **Regularisation** — Ridge (L2) shrinks all coefficients; Lasso (L1) zeros irrelevant ones (feature selection)
- **Diagnostics:** R² / adjusted R², residual plots, VIF for multicollinearity, Cook's distance for leverage points

**4. Bayesian inference**
- **Frequentist:** parameters are fixed, data is random; confidence intervals express long-run coverage
- **Bayesian:** parameters are distributions; posterior P(θ|data) combines prior P(θ) with likelihood P(data|θ)
- **Applied to ML:** Bayesian hyperparameter optimisation (Optuna/Ax), uncertainty quantification, Thompson sampling for multi-armed bandits, Bayesian A/B testing (no fixed sample size required)
- **Conjugate priors:** Beta-Binomial for CTR (prior = historical rate → posterior after N impressions), Gaussian-Gaussian for means

**5. Hypothesis testing**
- **Framework:** H₀ (null), H₁ (alternative), significance level α (typically 0.05), p-value = P(data ≥ observed | H₀)
- **Common tests:**
  - **t-test** — compare means of two groups (independent samples), assumes normality (or n ≥ 30 by CLT)
  - **Chi-squared test** — categorical counts (click vs no-click by cohort), goodness-of-fit
  - **Mann-Whitney U** — non-parametric alternative to t-test for skewed distributions (latency data!)
  - **ANOVA** — compare >2 group means; followed by Tukey HSD post-hoc for pairwise comparisons
- **Power analysis:** determine sample size before running experiment; power = P(reject H₀ | H₁ true), typically ≥ 0.80
- **Multiple testing correction:** Bonferroni or Benjamini-Hochberg FDR when testing many metrics/segments

### Example / Tradeoff

**A/B test on a RAG chatbot (concrete example):**
- Baseline vs new re-ranking strategy; primary metric = CSAT score (1–5, non-normal)
- Used Mann-Whitney U (not t-test — ordinal skewed data)
- Power analysis: MDE = 0.2 CSAT points, power = 0.80, α = 0.05 → n = 3,400 per arm
- Result: p = 0.031 < 0.05, Cohen's d = 0.18 → statistically significant, but small practical effect; PM decided not to ship given infra cost

**Bayesian A/B alternative:** Beta-Bernoulli model on conversion; no fixed sample size; stop when P(variant > control) > 0.95 — reduces test duration by ~40% at cost of more complex interpretation

**Distribution mismatch risk:** log-normal latency distributions (p99 ≫ mean) are mis-characterised by normal assumptions; always plot the CDF / use non-parametric tests for latency data

---

## Verbal script

**Opening (30s):**
"I'd organise my answer into five areas that tend to come up together: probability foundations, key distributions, regression, Bayesian inference, and hypothesis testing. These form a chain — probability defines distributions, distributions underpin regression models and priors, and hypothesis testing is how we make decisions from data."

**Core explanation (2–3 min):**
"Starting with probability: Bayes' theorem P(H|D) ∝ P(D|H)·P(H) is the single most important formula — it shows up in Bayesian classifiers, RLHF reward estimation, and Thompson sampling. For distributions, I always think about *what process generated the data*: binary outcomes → Bernoulli; counts → Poisson; continuous residuals → Normal; time-to-event → Exponential. Getting the distribution wrong biases every downstream estimate.

On regression: linear regression minimises squared error and gives interpretable coefficients, but the key assumptions are linearity and homoscedasticity — I always check residual plots. Logistic regression extends this to probability outputs via the sigmoid link; it's my default for calibrated binary classifiers before reaching for gradient boosting.

Bayesian vs frequentist: the practical difference is that Bayesian inference lets you incorporate prior knowledge and gives you a full posterior, which is useful for small samples and when you want to say 'there's a 92% probability the new model is better' rather than just 'p < 0.05'. I've used it for Bayesian hyperparameter optimisation via Optuna and for adaptive A/B tests that stop early.

For hypothesis testing: I start with the right test for the data type — t-test for normally distributed means, Mann-Whitney for skewed/ordinal, chi-squared for categorical counts. I always do a power analysis *before* running the test to avoid underpowered experiments that miss real effects."

**Tradeoff / production angle (1 min):**
"The biggest practical pitfall is multiple testing: if you track 20 metrics in an A/B test with α=0.05, you expect one false positive by chance. I apply Benjamini-Hochberg FDR correction and pre-register primary metrics. Latency data is almost always log-normal so normal-theory tests understate variance — I use Mann-Whitney or bootstrap confidence intervals there. And Bayesian A/B testing reduces wall-clock time but requires careful prior specification; a poorly chosen prior can bias the outcome, so I document prior assumptions explicitly."

**Wrap-up (30s):**
"The common thread across all of statistics is quantifying uncertainty honestly. Whether it's a regression residual, a posterior distribution, or a p-value, the goal is to know how much to trust a result — and to communicate that trust clearly to stakeholders. Happy to go deeper on any of the five areas."

---

## Pitfalls

- **Mistake:** Defining p-value as "the probability the null hypothesis is true" — **Better:** p-value is P(observing data this extreme or more | H₀ is true); it says nothing directly about P(H₀)
- **Mistake:** Treating all continuous data as normally distributed and using t-tests for latency or revenue data — **Better:** check the distribution shape first (plot histogram/CDF); use Mann-Whitney or bootstrap CIs for skewed/heavy-tailed data
- **Mistake:** Skipping power analysis and declaring "no effect" from an underpowered experiment — **Better:** pre-compute required sample size for target MDE and power (≥0.80) before starting the test; interpret non-significant results in terms of confidence intervals, not just p > 0.05

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q9: Bias-variance tradeoff](06-009-bias-variance-tradeoff.md) | Bias-variance decomposition uses expectation/variance concepts from probability theory |
| [Q19: Precision vs recall — fraud detection](06-019-precision-vs-recall-fraud-detection.md) | Precision/recall are derived from conditional probability; threshold choice is a hypothesis-testing decision |
| [Q20: F1 score, ROC curve](06-020-f1-score-roc-curve.md) | AUC is a probabilistic interpretation of classifier ranking quality |

---

## One-liner recall

> Statistics for ML = probability/Bayes' theorem → distribution selection by data type → regression with residual diagnostics → Bayesian posteriors for uncertainty → hypothesis tests with pre-registered primary metrics, power analysis, and multiple-testing correction.
