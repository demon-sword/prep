# What metrics for benchmarking LLM performance?

**Category:** 05-evaluation-metrics
**Question #:** 001
**Source section:** §5 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
Interviewers use this as a calibration question at the start of an eval discussion. They want to see whether you understand the *layers* of measurement — academic benchmarks, task-specific offline metrics, and production business metrics — and whether you can articulate why standard benchmarks are often insufficient for real deployed systems. It probes breadth of eval knowledge and production maturity.

### Trigger phrases
- "What metrics do you use to evaluate an LLM?"
- "How do you benchmark model quality?"
- "Walk me through your evaluation framework."

### What it tests
Ability to distinguish academic benchmarks from production-relevant metrics, and to select the right measurement layer for the deployment context.

---

## Answer

### Concept
LLM benchmarking operates across three distinct layers: **academic benchmarks** (standardised tasks measuring general capability), **task-specific offline metrics** (golden-dataset eval measuring quality on your actual use case), and **production business metrics** (real-world signals — deflection rate, cost/query, p95 latency, thumbs-down). Strong candidates know which layer to reach for and why each has failure modes.

### Mechanism

**Layer 1 — Academic / capability benchmarks**

| Benchmark | What it measures | Saturation risk |
|-----------|-----------------|-----------------|
| MMLU | 57-subject factual MC (undergrad–grad level) | a frontier model class models hit 85–90%; nearly saturated |
| HumanEval / MBPP | Python function synthesis, pass@1 | Increasingly saturated on frontier models |
| BIG-Bench Hard | 23 hard reasoning tasks | More headroom; harder to game |
| MATH / GSM8K | Mathematical reasoning, chain-of-thought | MATH still discriminates at frontier |
| MT-Bench | Multi-turn chat quality via a frontier model judge | Good for instruction-following; judge model bias |

**Layer 2 — Task-specific offline metrics**

For generative tasks (QA, summarization, RAG):
- **RAGAS Faithfulness** — does the answer follow from the retrieved context? (threshold: ≥ 0.85)
- **RAGAS Answer Relevancy** — does the answer address the question?
- **RAGAS Context Recall** — did retrieval surface the right chunks?
- **LLM-judge** (a frontier model as judge) — pairwise or rubric-scored quality; use on 5–10% sample due to cost
- **ROUGE-L / BLEU** — n-gram overlap; only meaningful for extractive tasks; do NOT treat as a primary signal for open-ended generation

For classification/extraction:
- **Accuracy, F1, Precision/Recall** — standard; watch class imbalance
- **ECE (Expected Calibration Error)** — confidence reliability

**Layer 3 — Production / business metrics**

| Metric | What it catches |
|--------|----------------|
| Deflection rate | Chatbot resolving tickets without human handoff |
| CSAT / thumbs-down rate | User satisfaction; leading indicator of quality drop |
| p95 latency | SLO compliance; TTFT for streaming UX |
| Cost per query | Operational budget; tracks prompt bloat or model upgrades |
| Hallucination rate | Sampled faithfulness audit at scale |

### Example / Tradeoff
A company deploys a customer-support RAG chatbot. MMLU is irrelevant — it doesn't test whether the model correctly cites their return policy. Instead: golden dataset of 200 Q&A pairs from real tickets (RAGAS faithfulness ≥ 0.85 and Recall@5 ≥ 0.70 to gate deployment), then production monitoring with deflection rate and thumbs-down as weekly SLOs. BLEU is never touched. When faithfulness drops from 0.88 → 0.79 in week 6, they investigate retrieval quality first (cosine score distribution, embedding drift) before touching the model.

**Key tradeoff:** Academic benchmarks are comparable across models but measure general capability, not task fit. Golden datasets measure task fit but are expensive to build and can go stale. Production metrics catch real failures but lag behind issues by hours or days.

---

## Verbal script

**Opening (30s):**
"I think about LLM metrics in three layers, because each layer catches a different class of problem. Let me walk through them from model capability to production impact."

**Core explanation (2–3 min):**
"The first layer is academic benchmarks — things like MMLU for factual knowledge breadth, HumanEval for code synthesis, MATH and GSM8K for reasoning. These are useful when selecting a base model or comparing two models at a high level, but most frontier models are close to saturating them. More importantly, they don't tell you whether the model performs well on *your* task.

The second layer is task-specific offline evaluation. For a RAG or generative QA system, I reach for RAGAS — specifically faithfulness, which checks whether the answer is grounded in the retrieved context, and context recall, which checks whether retrieval surfaced the right chunks. I also use a golden dataset — a curated set of real representative queries with expected answers — and gate deployment on those metrics: faithfulness ≥ 0.85, Recall@5 ≥ 0.70. BLEU and ROUGE show up here sometimes, but they measure n-gram overlap, not correctness, so I treat them as secondary at best. For classification tasks I use F1 and calibration error.

The third layer is production metrics. Once shipped, the metrics that matter most are: deflection rate — are users getting resolved without escalation?; thumbs-down rate — a leading indicator of quality drops; p95 latency — SLO compliance; and cost per query — tracks prompt drift or unexpected model calls."

**Tradeoff / production angle (1 min):**
"The failure mode I see most often is teams running offline evals and calling it done. A model can pass a golden-set gate and still fail in production because the input distribution shifted — new product names, different phrasing, or stale documents in the index. That's why I always run all three layers in parallel, not sequentially."

**Wrap-up (30s):**
"So in summary: academic benchmarks for model selection, task-specific RAGAS + golden-dataset for deployment gating, and production SLOs for ongoing health. Happy to go deeper on any of these — RAGAS internals, calibration, or how to build a golden dataset."

---

## Pitfalls

- **Mistake:** Citing only BLEU/ROUGE as quality metrics — **Better:** Explain that n-gram overlap measures surface similarity, not factual correctness or helpfulness; use RAGAS faithfulness + LLM-judge for generative tasks; BLEU/ROUGE only make sense for extractive summarization where the reference is exact.
- **Mistake:** Treating academic benchmarks (MMLU, HumanEval) as sufficient for production evaluation — **Better:** Academic benchmarks measure general capability on standardised tasks; they don't measure task fit, domain accuracy, or how the model behaves on your retrieval pipeline; always pair with a task-specific golden dataset.
- **Mistake:** Ignoring production metrics and only doing offline eval — **Better:** Production metrics like deflection rate, thumbs-down, and p95 latency catch distribution shift and silent regressions that golden datasets can't anticipate; offline and production eval must run together.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q2: How evaluate a chatbot?](05-002-how-evaluate-a-chatbot.md) | Applies these metrics to the specific chatbot context |
| [Q9: Perplexity, ROUGE, BLEU — pitfalls of n-gram metrics?](05-009-perplexity-rouge-bleu-pitfalls-of-n-gram-metrics.md) | Deep dive on why n-gram metrics fail for generative systems |
| [Q17: Golden dataset for evaluation and regression testing?](05-017-golden-dataset-for-evaluation-and-regression-testing.md) | How to build and use the offline golden set referenced here |

---

## One-liner recall

> LLM benchmarking has three layers — academic benchmarks (MMLU/HumanEval) for model selection, task-specific golden-dataset metrics (RAGAS faithfulness, Recall@5) for deployment gating, and production SLOs (deflection rate, thumbs-down, p95 latency) for ongoing health — and you need all three running simultaneously.
