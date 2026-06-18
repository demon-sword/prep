# Success metrics for an ML model?

**Category:** 05-evaluation-metrics
**Question #:** 019
**Source section:** §5 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
Interviewers use this to test whether you think beyond model accuracy to the full measurement stack: task-appropriate offline metrics, calibration, fairness, and — critically — business outcomes. Weak candidates name a single metric (accuracy, F1) without connecting it to the problem framing or production reality.

### Trigger phrases
- "What metrics would you use to evaluate this model?"
- "How do you define success for your ML system?"
- "Walk me through how you'd measure model performance end-to-end."

### What it tests
The ability to select task-appropriate offline metrics, bridge them to production business KPIs, and recognise when a metric diverges from real-world value.

---

## Answer

### Concept
Success metrics for an ML model span three layers: (1) **task-appropriate offline metrics** that reflect what the model optimises, (2) **calibration and fairness checks** that catch silent failure modes, and (3) **production / business KPIs** that measure whether the model delivers value. A single accuracy number almost never covers all three — and the gap between them is where models fail in production.

### Mechanism

**Layer 1 — Task-appropriate offline metrics**

| Task type | Primary metric | Why / When |
|-----------|---------------|------------|
| Binary classification | PR-AUC, F1 | Class-imbalanced; accuracy misleading (fraud: 0.1% base rate → 99.9% accuracy = useless) |
| Multi-class | Macro-F1, top-k accuracy | Macro-F1 weights rare classes equally; top-k for ranking UX (recommendation) |
| Regression | MAE, RMSE, MAPE | MAE for median error; RMSE penalises large errors; MAPE for proportional cost |
| Ranking / search | NDCG@k, MRR, Precision@k | NDCG rewards highly relevant results at top positions; MRR for single-answer lookup |
| Generative / LLM | RAGAS Faithfulness, Answer Relevancy, BERTScore F1 | BLEU/ROUGE are paraphrase-blind and accuracy-blind |
| Time series | MASE, sMAPE | Scale-independent; compare against naïve seasonal baseline |

**Layer 2 — Calibration and fairness**

- **Calibration:** does `P(y=1|x) = 0.7` mean 70% of those cases are actually positive? Measure with Expected Calibration Error (ECE) or reliability diagrams. Miscalibration is silent: accuracy can look fine while confidence scores mislead downstream decisions.
- **Fairness / subgroup analysis:** overall F1 can mask 20pp gaps across demographic slices. Use Fairlearn or Aequitas; log subgroup AUC to a CI gate.
- **Threshold sensitivity:** for classifiers, report both the default threshold metric and the PR curve — let the business tune recall-precision tradeoff (fraud: high recall; spam: high precision).

**Layer 3 — Production / business KPIs**

| Model type | Business KPI |
|------------|-------------|
| Support chatbot (LLM) | Deflection rate, CSAT, cost/query, p95 latency |
| Fraud model | Dollar loss prevented, false-positive rate (declined legitimate txns) |
| Recommender | Click-through rate, add-to-cart, revenue lift vs A/B control |
| Search / ranking | Click-through rate, NDCG, MRR, session depth |
| Churn prediction | Retention rate lift, campaign ROI in A/B test |

The canonical framework: **offline metric ↔ proxy for ↔ business KPI**. When the proxy drifts from the KPI (model improves NDCG but revenue falls), recalibrate the metric.

### Example / Tradeoff

**Fraud detection (real pattern):** Training on class-weighted cross-entropy with PR-AUC as the offline metric, a model reached PR-AUC = 0.94. But in production the business KPI was *dollar loss prevented per false-positive*, which required setting the threshold at recall = 0.92 (not 0.50), exposing a miscalibration gap — the model's predicted probabilities were systematically low, so the business-optimal threshold was 0.23, not 0.50. Fix: Platt scaling (sigmoid recalibration on a held-out set) brought ECE from 0.12 → 0.03, aligning predicted scores with actual positivity rates.

**LLM chatbot (RAG):** Primary offline metric: RAGAS Faithfulness ≥ 0.85 on a 200-query golden dataset. Secondary: NDCG@5 ≥ 0.72 for retrieval quality. Production KPI: deflection rate ≥ 60%, CSAT ≥ 4.1/5, p95 latency ≤ 2s. Faithfulness and deflection rate initially diverged — faithfulness was fine but deflection was low because answers were technically correct but too verbose (users escalated). Fix: added Answer Relevancy metric (conciseness dimension) to the offline gate.

---

## Verbal script

**Opening (30s):**
"I think about success metrics across three layers: task-appropriate offline metrics, calibration and fairness checks, and production business KPIs. The reason you need all three is that a model can look great on accuracy but completely fail on the business objective — so let me walk through how I'd structure this for a given problem."

**Core explanation (2–3 min):**
"For offline metrics, the choice is driven by the task type. For binary classification, especially on imbalanced data like fraud or medical risk, I'd use PR-AUC rather than accuracy — a model that predicts the majority class always gets 99% accuracy on a 1% positive-rate problem but is useless. For ranking tasks like search or recommendation, NDCG@k captures whether highly-relevant results appear at the top. For generative systems, I avoid BLEU and ROUGE — they're paraphrase-blind — and instead use RAGAS Faithfulness and Answer Relevancy against a golden dataset.

The second layer is calibration. This is where I see a lot of people drop the ball. If I say 'this transaction has a 70% fraud probability,' I want 70% of those transactions to actually be fraud. I measure that with ECE or a reliability diagram on a held-out set. Miscalibrated models cause silent downstream errors — thresholds tuned in dev don't transfer to prod.

Third, I map offline metrics to business KPIs and set up an A/B test or shadow deployment to verify the proxy actually correlates. For a fraud model, the KPI is dollar loss prevented per false-positive — high recall is good, but each false-positive (declined legitimate card) has a real cost too."

**Tradeoff / production angle (1 min):**
"The hardest part is when the offline proxy diverges from the business KPI. I've seen a model's NDCG improve 8% after a reranking change while revenue per session stayed flat — because NDCG was measuring relevance but users actually cared about price, which wasn't in the relevance labels. The fix is to A/B test and use revenue as the north-star metric, not the model metric alone. Offline metrics are necessary but not sufficient — they're guardrails, not the destination."

**Wrap-up (30s):**
"So in short: pick task-appropriate offline metrics, validate calibration, add subgroup fairness checks in CI, then tie model performance to a business KPI through A/B testing. Happy to go deeper on any specific task type or the calibration piece."

---

## Pitfalls

- **Mistake:** Saying "I'd use accuracy" for an imbalanced problem without acknowledging the base rate issue — **Better:** Lead with PR-AUC or F1 for imbalanced tasks and explain why accuracy misleads (a model predicting all-negative on 1% positive-rate data is 99% accurate but catches nothing).
- **Mistake:** Stopping at offline metrics without connecting to a business KPI or A/B test — **Better:** Explain the proxy relationship: "NDCG is my offline proxy for revenue-per-session, and I validate that relationship with an A/B test before deploying."
- **Mistake:** Ignoring calibration — treating confidence scores as probabilities without verification — **Better:** Mention ECE measurement and Platt scaling / isotonic regression as standard recalibration tools, especially when threshold decisions have business cost.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q12: Operational/business metrics — win rate, deflection rate, p95 latency](05-012-operationalbusiness-metrics-win-rate-deflection-rate-p95-lat.md) | Production KPI layer — the business metrics this note's framework maps to |
| [Q14: Bias/fairness tradeoffs — example](05-014-biasfairness-tradeoffs-example.md) | Subgroup fairness analysis as the third calibration/fairness check in this framework |
| [Q1: What metrics for benchmarking LLM performance?](05-001-what-metrics-for-benchmarking-llm-performance.md) | LLM-specific offline metrics — generative task layer of this framework |

---

## One-liner recall

> Choose task-appropriate offline metrics (PR-AUC for imbalanced classification, NDCG for ranking, RAGAS Faithfulness for LLMs), validate calibration (ECE + Platt scaling), add subgroup fairness checks, and tie everything to a production business KPI through A/B testing — because the proxy diverging from the KPI is the most common production failure mode.
