# Measure hallucination rate in production?

**Category:** 05-evaluation-metrics
**Question #:** 008
**Source section:** §5 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
Interviewers probe whether you distinguish *offline* hallucination benchmarks from the messier reality of continuous production measurement. Strong candidates demonstrate familiarity with async scoring pipelines, calibrated SLOs, and the cost/latency tradeoffs of different detection methods (NLI entailment vs LLM-judge vs RAGAS). Weak candidates describe a one-time eval or conflate "low confidence" with "hallucination."

### Trigger phrases
- "How do you know your model is hallucinating in production?"
- "What's your hallucination rate — how did you measure it?"
- "How do you set a hallucination SLO and track it over time?"

### What it tests
Ability to operationalize hallucination as a production metric with a concrete measurement pipeline, not just offline awareness.

---

## Answer

### Concept
Hallucination rate in production is the fraction of LLM responses that assert facts not grounded in the retrieved context or the source of truth — measured continuously, not just at release time. It requires an async scoring pipeline because synchronous entailment checking adds 200–800 ms per call, which is often unacceptable for user-facing latency SLOs.

### Mechanism
**1. Define hallucination operationally** — choose a measurable proxy:
- *Faithfulness* (RAGAS): score ∈ [0, 1]; response claims are verified against retrieved chunks. Threshold < 0.80 → hallucination.
- *NLI entailment* (DeBERTa-large-mnli or `cross-encoder/nli-deberta-v3-base`): each sentence in the response is classified as ENTAILED / NEUTRAL / CONTRADICTION against the context. Rate = fraction labeled NEUTRAL or CONTRADICTION.
- *LLM-judge* (GPT-4o-mini with a grading rubric): samples 5–10% of traffic; cheaper than NLI on long responses, but biased by the judge model.

**2. Async scoring pipeline** — at generation time, log `{run_id, query, context_chunks, response}` to a Kafka topic. An offline consumer runs NLI or RAGAS faithfulness scoring and emits scores to a metrics store (Datadog / Prometheus). p99 scoring lag < 5 min.

**3. Sample for LLM-judge** — NLI is cheap enough to run on 100% of traffic; LLM-judge is too expensive ($0.002–$0.01/call). Route 5–10% of samples to GPT-4o-mini judge for a richer "hallucinated claim" explanation useful for root-cause analysis.

**4. Define SLO and alert** — e.g., `faithfulness_score_p50 ≥ 0.92` and `hallucination_rate_7d_rolling ≤ 3%`. Alert PagerDuty if rate exceeds threshold for > 15 min.

**5. Segment by failure mode** — break down by retrieval cosine score (low score → retrieval failure vs generation failure), query category, and model version. This identifies whether hallucination spikes are from retrieval degradation or model drift.

### Example / Tradeoff
At a customer-support RAG system with 200K queries/day:
- **NLI pipeline (100% coverage):** DeBERTa `cross-encoder/nli-deberta-v3-base` scoring ~30 ms/response on a 2× A10 sidecar → ~$120/day compute, < 2 min lag. Hallucination rate baseline: 2.1%.
- **LLM-judge (10% sample):** GPT-4o-mini at $0.003/call → $60/day for 20K samples. Provides root-cause explanations for failed cases.
- **RAGAS faithfulness (nightly golden set of 500 Q&A pairs):** catches model-version regressions; gates deployment pipeline.

Tradeoff: NLI gives breadth (100% coverage, low cost) but misses multi-sentence compositional hallucinations. LLM-judge catches richer failure modes but at 10× cost and with judge bias. Combining both is the production sweet spot.

---

## Verbal script

**Opening (30s):**
"Measuring hallucination in production is fundamentally different from offline benchmarking — you can't block every user response to run a slow entailment check. I'd set up an async scoring pipeline that gives continuous signal without adding latency to the user path."

**Core explanation (2–3 min):**
"The first step is defining what 'hallucination' means operationally. I use RAGAS faithfulness as the primary metric — it scores each response claim against the retrieved chunks, returning a value from 0 to 1. A score below 0.80 I treat as a hallucination. For finer-grained analysis I also run NLI entailment using a DeBERTa cross-encoder: it classifies each sentence as ENTAILED, NEUTRAL, or CONTRADICTION. The hallucination rate becomes the fraction of sentences that are NEUTRAL or CONTRADICTION.

To make this work in production, I log every request — query, retrieved chunks, response — to a Kafka topic at generation time. An async consumer picks these up and runs the scoring pipeline, emitting metrics to Datadog with a lag of under 5 minutes. For 200K queries per day, NLI on a small GPU sidecar costs around $120 per day and covers 100% of traffic.

On top of that, I route 5–10% of traffic to a GPT-4o-mini LLM-judge which gives richer explanations for failed cases — useful for root-cause analysis — but I don't run it on everything because it's 10× the cost.

Finally, I define an SLO: faithfulness p50 ≥ 0.92, rolling 7-day hallucination rate ≤ 3%. I alert PagerDuty if either threshold is breached for more than 15 minutes."

**Tradeoff / production angle (1 min):**
"The key tension is cost vs coverage vs explainability. NLI is cheap and fast but misses complex multi-sentence compositional hallucinations. LLM-judge is richer but expensive and biased by the judge model. RAGAS works well for RAG pipelines where context chunks are explicit, but it doesn't help for free-form generation without a context. In that case I fall back to LLM-judge sampling plus user thumbs-down feedback as a weak signal — not perfect, but it catches meaningful regressions."

**Wrap-up (30s):**
"So the architecture is: log everything → async NLI for 100% breadth → LLM-judge sample for depth → golden set nightly for regression gates → SLO alert in Datadog. Happy to go deeper on the NLI scoring setup or the SLO thresholds."

---

## Pitfalls

- **Mistake:** Describing hallucination measurement as "run RAGAS on a golden dataset once before deployment" — **Better:** Explain *continuous* async production measurement with a Kafka pipeline, percentage-sampled LLM-judge, and SLO alerting, emphasizing that offline golden sets only catch regressions at deploy time, not drift during production.
- **Mistake:** Proposing synchronous NLI entailment blocking the user response path — **Better:** Clarify that NLI adds 200–800 ms, so it must run async; log the {query, context, response} tuple at generation time and score offline with < 5 min lag.
- **Mistake:** Treating hallucination rate as a single global number — **Better:** Segment by retrieval cosine score band (low score → retrieval failure), query category, and model version to distinguish generation-side from retrieval-side root causes.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q3: Detect and mitigate hallucinations in production](05-003-detect-and-mitigate-hallucinations-in-production.md) | Companion — mitigation stack; this note focuses on measurement |
| [Q6: LLM confidently wrong — debug RAG giving confident wrong answers](05-006-llm-confidently-wrong-debug-rag-giving-confident-wrong-answe.md) | Overlapping — debugging root cause from measured hallucination signal |
| [Q13: Evaluate and monitor model in production, not just offline](05-013-evaluate-and-monitor-model-in-production-not-just-offline.md) | Broader monitoring context — hallucination rate is one of several production metrics |

---

## One-liner recall

> Measure hallucination in production by logging every {query, context, response} tuple to a Kafka stream, running async NLI entailment (DeBERTa) or RAGAS faithfulness on 100% of traffic, routing 5–10% to a GPT-4o-mini LLM-judge for root-cause explanations, and alerting on a rolling SLO breach — never block the user path with synchronous scoring.
