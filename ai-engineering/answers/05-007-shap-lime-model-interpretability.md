# SHAP, LIME, model interpretability?

**Category:** 05-evaluation-metrics
**Question #:** 007
**Source section:** §5 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
The interviewer is probing whether you understand that LLM/ML systems deployed in production are not black boxes you can ignore — especially in regulated industries (credit, healthcare, HR). They want to know if you can explain *why* a model made a specific prediction, debug unexpected outputs, and communicate model behaviour to stakeholders. For senior roles this also tests architectural awareness: when to add an interpretability layer, and what its limits are.

### Trigger phrases
- "How would you explain your model's predictions to a non-technical stakeholder?"
- "A model flags a loan application as high-risk — how do you explain that decision to the applicant?"
- "Walk me through SHAP / LIME."
- "How do you debug a model that's performing well on average but failing on a specific subgroup?"

### What it tests
Ability to apply local and global interpretability tools to ML/LLM systems, and to identify when black-box explanations are insufficient for production or compliance.

---

## Answer

### Concept
**SHAP** (SHapley Additive exPlanations) and **LIME** (Local Interpretable Model-agnostic Explanations) are post-hoc interpretability techniques that attribute a model's prediction to its input features. SHAP uses cooperative game theory (Shapley values) to fairly allocate credit across all features; LIME fits a simple surrogate model locally around a specific input instance. Both answer the question: "which features drove *this* prediction, and by how much?"

### Mechanism

**SHAP:**
1. For a prediction on input **x**, compute the marginal contribution of each feature *i* by averaging over all possible feature orderings (Shapley value).
2. `φᵢ = Σ_{S ⊆ F\{i}} [|S|! (|F|−|S|−1)! / |F|!] × [f(S∪{i}) − f(S)]`
3. TreeSHAP (for tree models: XGBoost, LightGBM, sklearn) is exact and runs in polynomial time. KernelSHAP (model-agnostic) samples coalitions for approximation.
4. Properties: **local accuracy** (SHAP values sum to the prediction), **consistency** (higher-impact features always get higher values), **missingness** (absent features get zero contribution).

**LIME:**
1. Sample perturbed versions of **x** (with some features masked/replaced).
2. Query the black-box model on each perturbed sample to get predictions.
3. Fit a simple linear model (locally weighted) on the perturbed samples.
4. The linear model coefficients become the feature importance scores for that instance.
5. Fast but less stable — different runs with different random seeds can produce different explanations (high variance).

**Global interpretability:**
- Aggregate SHAP values across many samples to get **feature importance plots** (SHAP summary plot) and **dependence plots** showing interaction effects.
- Partial Dependence Plots (PDP) and ICE curves for non-SHAP global analysis.

**For LLMs / NLP:**
- SHAP's `Explainer` with `masker=Text()` does token-level perturbation — shows which tokens drove a sentiment or classification score.
- Attention weights are a common proxy but are *not* reliable explanations (Jain & Wallace 2019 showed attention ≠ importance).
- BERTViz for attention visualization; transformer-interpret library wraps Integrated Gradients for token attribution.

### Example / Tradeoff

**Credit-risk model (XGBoost):** Using TreeSHAP, you find that `debt_to_income_ratio` has the highest mean |SHAP| across the test set. For a specific denied applicant, SHAP shows `debt_to_income_ratio = +0.23`, `missed_payments = +0.18`, `credit_age = −0.07` — the first two pushed the score toward "deny," the last one partially offset it. This explanation is auditable and satisfies EU AI Act Article 13 (transparency) and FCRA adverse-action notice requirements.

**LLM sentiment classifier (DistilBERT):** SHAP `Text` masker reveals that the word "not" contributes *positively* (toward positive sentiment) on the phrase "not bad" — confirming the model has learned negation correctly. If instead "not" had near-zero SHAP value, you'd know the model is likely ignoring negation.

**Tradeoffs:**
| Method | Speed | Stability | Consistency | Best for |
|--------|-------|-----------|-------------|----------|
| TreeSHAP | Fast (polynomial) | High | Guaranteed | Tree models (XGBoost, LightGBM, RF) |
| KernelSHAP | Slow (sampling) | Medium | Approximate | Any model, model-agnostic |
| LIME | Fast | Low (high variance) | No formal guarantee | Quick local debug, prototypes |
| Integrated Gradients | Medium | High | Gradient-exact | Neural nets, transformers |

**When SHAP/LIME break down:**
- Very high-dimensional inputs (images, long text) — too many features to attribute meaningfully without further grouping (superpixels for images, sentences for text).
- Correlated features — SHAP handles correlation via Shapley marginal contributions but can distribute importance oddly when features are nearly redundant.
- LLMs: token-level SHAP is expensive (2^N perturbations approximated), and the explanation is at the token level, not at the reasoning-chain level — for chain-of-thought models you need process-level tracing, not just output attribution.

---

## Verbal script

**Opening (30s):**
"Interpretability comes up most in two contexts for me: debugging unexpected model behaviour and meeting compliance requirements in regulated domains. I'd frame the answer around two main tools — SHAP for theory-sound feature attribution, LIME for quick local approximations — and then discuss where they work well versus where they break down."

**Core explanation (2–3 min):**
"SHAP is grounded in cooperative game theory. For a given prediction, it asks: what is the fair marginal contribution of each feature, averaged over all orderings in which you could add that feature? The result is a SHAP value per feature that sums exactly to the difference between the model's prediction and its baseline (mean prediction). For tree models like XGBoost, TreeSHAP computes this exactly in polynomial time — that's the version you'd use in production. For neural networks or LLMs, you'd use KernelSHAP, which approximates by sampling feature coalitions.

LIME takes a different approach: it samples slightly perturbed versions of your input — for a tabular model, that means masking or replacing random feature values; for text, that means dropping tokens — queries the model on those perturbations, then fits a simple local linear model to explain *this one prediction*. The linear coefficients are your importance scores. It's faster and more model-agnostic but less stable — run it twice and you might get meaningfully different coefficients.

A concrete example: on a credit model at my last job, we used TreeSHAP to generate per-application adverse-action explanations — 'your application was denied primarily because your debt-to-income ratio is in the 95th percentile and you have two missed payments in the last 12 months.' That's directly auditable for FCRA compliance. We also built a SHAP summary plot globally to communicate to the product team which features were driving denials overall."

**Tradeoff / production angle (1 min):**
"The important caveat is that attention weights in transformers are *not* the same as SHAP values — Jain & Wallace showed in 2019 that attention and feature importance are often uncorrelated. If you're working with LLMs and need attributions at the token level, Integrated Gradients (available via the `transformer-interpret` library) is more theoretically sound. But even those give you token-level credit, not reasoning-chain credit — for multi-step agentic or CoT systems, process-level tracing with LangSmith is more useful than token attribution.

Also, SHAP explanations can be misleading when features are highly correlated — in that case, the importance is distributed across correlated features in ways that are mathematically correct but practically hard to act on."

**Wrap-up (30s):**
"So my short answer is: use TreeSHAP for tree models in any compliance-sensitive setting, KernelSHAP or Integrated Gradients for neural nets, and be honest that for LLMs the explanations are token-level approximations — useful for debugging but not a complete picture of model reasoning."

---

## Pitfalls

- **Mistake:** Saying "attention weights show what the model focuses on" as if attention = interpretability — **Better:** Cite Jain & Wallace 2019: attention and importance are often uncorrelated; use Integrated Gradients or SHAP Text masker for theoretically-grounded token attribution in transformers.
- **Mistake:** Treating LIME as equally reliable as SHAP without noting its instability — **Better:** Explicitly flag that LIME has no consistency guarantee and can produce different explanations across runs; prefer TreeSHAP when you have tree models, or KernelSHAP when you need model-agnosticism with more stability.
- **Mistake:** Conflating local explanations (why did *this* prediction happen) with global explanations (what does the model do overall) — **Better:** Distinguish the two clearly: SHAP waterfall/force plots are local; SHAP summary plots and PDPs are global; both are needed for full model understanding.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q3: Detect and mitigate hallucinations in production](05-003-detect-and-mitigate-hallucinations-in-production.md) | Both concern diagnosing model failures; interpretability tools surface *why* a model is wrong |
| [Q6: LLM confidently wrong — debug RAG giving confident wrong answers](05-006-llm-confidently-wrong-debug-rag-giving-confident-wrong-answe.md) | Interpretability at the token/attribution level complements retrieval-level debugging |
| [Q14: Bias/fairness tradeoffs — example](05-014-biasfairness-tradeoffs-example.md) | SHAP subgroup analysis is a primary tool for detecting and diagnosing fairness failures |

---

## One-liner recall

> SHAP gives theoretically-sound feature attribution (Shapley values summing to the prediction gap) best used with TreeSHAP for tree models; LIME gives fast but unstable local surrogates; attention ≠ importance in transformers — use Integrated Gradients instead.
