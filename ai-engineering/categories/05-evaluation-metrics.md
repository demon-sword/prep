# 05. Evaluation & Metrics — AI Engineering Interview Category

Covers how to measure, debug, and continuously improve LLM and RAG systems in production — the most under-prepped high-signal topic in AI engineering interviews.

---

## Interview signals

| You hear… | This category |
|-----------|---------------|
| "how do you know your model is working?" | evaluation framework |
| "what metrics do you use for your chatbot / RAG pipeline?" | metrics & measurement |
| "your accuracy dropped from 95% to 80% — what do you do?" | production debugging |
| "how do you detect hallucinations at scale?" | hallucination measurement |
| "vibes-based vs formal eval?" | golden datasets & regression |
| "how do you A/B test prompt changes?" | deployment & experimentation |

---

## Mental model

Strong candidates understand that evaluation is not a one-time checkpoint but a continuous production discipline with three distinct layers: **offline eval** (golden datasets measuring task accuracy before deployment), **online eval** (production metrics — deflection rate, p95 latency, cost/query, thumbs-down rate — measuring real-world effectiveness), and **model-level diagnostics** (RAGAS faithfulness/context recall, hallucination rate, calibration) that bridge the gap. Weak candidates treat evaluation as "run BLEU/ROUGE on a test set and ship it" — missing that n-gram metrics are nearly useless for generative systems, that hallucination rate must be measured separately from task accuracy, and that a model can pass offline eval while failing silently in production due to distribution shift, prompt injection, or embedding drift.

---

## Sub-topics

### 1. Offline Evaluation: Golden Datasets & Regression Testing
**When:** "how do you evaluate before deploying?" / "what's your eval framework?" / "vibes-based or formal?"
**What:** A curated labeled dataset used to measure quality pre-deployment and catch regressions when prompts, models, or retrieval change.
**Key questions:**
- [Q17: Golden dataset for evaluation and regression testing?](../answers/05-017-golden-dataset-for-evaluation-and-regression-testing.md)
- [Q16: "Vibes-based" eval vs formal eval framework?](../answers/05-016-vibes-based-eval-vs-formal-eval-framework.md)
- [Q20: A/B testing for prompt variations?](../answers/05-020-ab-testing-for-prompt-variations.md)

### 2. Hallucination Detection & Mitigation
**When:** "how do you reduce / measure / detect hallucinations?" / "LLM is confidently wrong — why?" / "medical chatbot factual accuracy?"
**What:** Hallucination is the gap between what the model asserts and what the retrieved context (or ground truth) supports — measured via RAGAS faithfulness, NLI entailment, and production thumbs-down rate.
**Key questions:**
- [Q3: Detect and mitigate hallucinations in production?](../answers/05-003-detect-and-mitigate-hallucinations-in-production.md)
- [Q8: Measure hallucination rate in production?](../answers/05-008-measure-hallucination-rate-in-production.md)
- [Q6: LLM confidently wrong — debug RAG giving confident wrong answers?](../answers/05-006-llm-confidently-wrong-debug-rag-giving-confident-wrong-answe.md)

### 3. Production Monitoring & Business Metrics
**When:** "how do you monitor in production?" / "what operational metrics matter?" / "accuracy dropped — diagnose it?"
**What:** Production eval tracks business SLOs (deflection rate, CSAT, cost/query, p95 latency) and model-level signals (cosine score distribution, latency per stage, thumbs-down rate) to catch regressions before users notice.
**Key questions:**
- [Q13: Evaluate and monitor model in production, not just offline?](../answers/05-013-evaluate-and-monitor-model-in-production-not-just-offline.md)
- [Q12: Operational/business metrics: win rate, deflection rate, p95 latency?](../answers/05-012-operationalbusiness-metrics-win-rate-deflection-rate-p95-lat.md)
- [Q23: Chatbot accuracy dropped 95% → 80% in six weeks — diagnose before retraining?](../answers/05-023-chatbot-accuracy-dropped-95-80-in-six-weeks-diagnose-before.md)

### 4. Deployment Experimentation & Model Selection
**When:** "how do you safely roll out a new model?" / "how do you compare two models?" / "canary vs shadow testing?"
**What:** Safe model deployment uses staged rollout strategies (shadow, canary, interleaved) with automatic rollback triggers, and calibration analysis to choose between models with similar accuracy.
**Key questions:**
- [Q21: Test new model before full deployment — canary, interleaved, shadow?](../answers/05-021-test-new-model-before-full-deployment-canary-interleaved-sha.md)
- [Q22: Two models, same accuracy, different confidence — which choose? Calibration?](../answers/05-022-two-models-same-accuracy-different-confidence-which-choose-c.md)
- [Q18: Feedback and reinforcement loops — system gets better over time?](../answers/05-018-feedback-and-reinforcement-loops-system-gets-better-over-tim.md)

---

## Decision framework

```
Which evaluation approach do I use?

Is the system deployed yet?
  No (pre-deployment):
    → Offline eval with golden dataset
    → Retrieval metrics: Recall@5, NDCG, context_recall (RAGAS)
    → Generation metrics: faithfulness, answer_relevancy (RAGAS)
    → Gate: block deploy if faithfulness < 0.85 or Recall@5 < 0.70

  Yes (in production):
    → Business metrics: deflection rate, CSAT, thumbs-down rate, cost/query
    → Latency SLOs: p95 < 2s, TTFT < 500ms
    → Model diagnostics: cosine score distribution, stage-level latency traces
    → Shadow/canary for new model rollouts

Is the task generative (chat, summarization, QA)?
  → Do NOT use BLEU/ROUGE as primary signal — they correlate poorly with quality
  → Use RAGAS faithfulness + answer_relevancy + LLM-judge on 5-10% sample
  → Supplement with task-specific human eval on 50-100 golden examples

Is hallucination the primary risk?
  → Measure: RAGAS faithfulness < threshold → flag; NLI entailment for regulated domains
  → Separate hallucination SLO from task-accuracy SLO
  → Production proxy: thumbs-down rate + manual audit on low-faithfulness samples

Are you comparing two models or prompt variants?
  Latency-sensitive / cost-constrained:
    → Shadow mode first (zero user risk), then interleaved A/B at 10%
    → Auto-rollback if degradation > 3% on primary metric within 24h
  Same accuracy, different confidence:
    → Prefer better-calibrated model (lower ECE, tighter confidence intervals)
    → Use reliability diagram to verify
```

---

## Common mistakes

| Mistake | What to say instead |
|---------|---------------------|
| "I measure accuracy with BLEU/ROUGE" | "BLEU/ROUGE measure n-gram overlap, not correctness — for generative systems I use RAGAS faithfulness, LLM-judge, and task-specific golden datasets" |
| "I run evals offline and ship if they pass" | "Offline eval catches regressions; production monitoring (deflection rate, thumbs-down, p95 latency) catches distribution shift and silent failures that golden sets miss" |
| "I detect hallucinations by asking GPT-4 to check itself" | "Self-checking is biased toward the model's own style — I use an independent NLI model (DeBERTa) or RAGAS faithfulness with a separate judge model, plus retrieval-gate cosine thresholding" |
| "I'd just compare accuracy scores between the two models" | "Same accuracy with different confidence curves means different calibration — the better-calibrated model is more reliable at threshold decisions; I'd compare ECE and draw a reliability diagram" |
| "To test a new model I'd swap it and see what happens" | "Shadow mode first — run the new model in parallel, log outputs, compare offline. Then 10% canary with auto-rollback trigger. Never cold-swap in production" |
| "Chatbot accuracy dropped — let me retrain" | "Retraining before diagnosis wastes compute; I'd first check for input distribution shift, prompt/template changes, upstream data drift, embedding drift, and retrieval quality degradation before touching model weights" |

---

## Question checklist

| # | Question | Difficulty signal | Status |
|---|----------|-------------------|--------|
| 1 | What metrics for benchmarking LLM performance? | E | `todo` |
| 2 | How evaluate a chatbot? | E | `todo` |
| 3 | Detect and mitigate hallucinations in production? ⭐ | M | `todo` |
| 4 | Prevent factual errors in summarization? | M | `todo` |
| 5 | Reduce hallucinations in a medical chatbot? | M | `todo` |
| 6 | LLM confidently wrong — debug RAG giving confident wrong answers? | M | `todo` |
| 7 | SHAP, LIME, model interpretability? | M | `todo` |
| 8 | Measure hallucination rate in production? | M | `todo` |
| 9 | Perplexity, ROUGE, BLEU — pitfalls of n-gram metrics? | E | `todo` |
| 10 | Testing strategies for non-deterministic outputs? | M | `todo` |
| 11 | Measure accuracy in generative systems? | M | `todo` |
| 12 | Operational/business metrics: win rate, deflection rate, p95 latency? | M | `todo` |
| 13 | Evaluate and monitor model in production, not just offline? | S | `todo` |
| 14 | Bias/fairness tradeoffs — example? | M | `todo` |
| 15 | Time to first token — why matter for UX? | E | `todo` |
| 16 | "Vibes-based" eval vs formal eval framework? | M | `todo` |
| 17 | Golden dataset for evaluation and regression testing? | M | `todo` |
| 18 | Feedback and reinforcement loops — system gets better over time? | S | `todo` |
| 19 | Success metrics for an ML model? | E | `todo` |
| 20 | A/B testing for prompt variations? | M | `todo` |
| 21 | Test new model before full deployment — canary, interleaved, shadow? | S | `todo` |
| 22 | Two models, same accuracy, different confidence — which choose? Calibration? | S | `todo` |
| 23 | Chatbot accuracy dropped 95% → 80% in six weeks — diagnose before retraining? | S | `todo` |

---

## One-page summary

- **Three eval layers:** offline golden dataset (pre-deploy regression gate) → production business metrics (deflection rate, CSAT, cost/query, p95 latency) → model diagnostics (RAGAS faithfulness/context_recall, cosine score distribution, hallucination rate); all three must run together.
- **BLEU/ROUGE are traps:** n-gram metrics penalise synonyms and ignore factual correctness — always prefer RAGAS faithfulness + LLM-judge for generative tasks; use BLEU/ROUGE only when you can explain their limitations.
- **Hallucination has two distinct SLOs:** faithfulness (does the answer match the context?) and accuracy (is the context correct?); RAGAS faithfulness < 0.85 triggers replacement with a canned safe response; production proxy is thumbs-down + manual audit.
- **Deploy strategies:** shadow (zero user risk, full data) → interleaved A/B (split traffic, live comparison) → canary (10% rollout, auto-rollback on >3% metric drop); never cold-swap a new model into 100% of traffic.
- **Diagnose before you retrain:** accuracy drop is usually upstream of the model — check distribution shift, prompt/template changes, data freshness, embedding drift, and retrieval quality degradation first; retraining is the last resort.
