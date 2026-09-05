# Evaluate and monitor model in production, not just offline?

**Category:** 05-evaluation-metrics
**Question #:** 013
**Source section:** §5 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
Offline eval on a golden dataset tells you what your model *can* do in a controlled setting — it doesn't tell you what it *is doing* for real users with real, messy queries. Interviewers ask this to probe whether you understand data distribution drift, silent regressions, and the feedback loops needed to keep a production AI system healthy over time.

### Trigger phrases
- "How do you know your model is still working well after launch?"
- "Walk me through your production monitoring strategy for an LLM."
- "How do you catch regressions in a GenAI system?"
- "How do you evaluate and monitor a model in production, not just offline?"

### What it tests
Whether you can architect a continuous quality loop — offline eval + live signals + alerting + regression gating — rather than treating model deployment as a one-time event.

---

## Answer

### Concept
Production evaluation closes the gap between offline benchmarks and real-world behaviour by combining asynchronous metric computation on live traffic, business KPI tracking, and automated regression alerts. Offline eval tells you the model *should* work; production monitoring tells you it *does* work and catches the moment it stops.

### Mechanism

**Layer 1 — Async metric pipeline (100% coverage)**
- Log every request/response pair to a message queue (Kafka, Kinesis).
- An async sidecar computes lightweight, cheap metrics without blocking the serving path:
  - RAGAS **Faithfulness** (context entailment score) and **Answer Relevancy** (query alignment)
  - Retrieval cosine score distribution (p50/p95) — leading indicator of index freshness
  - Response latency (TTFT, total) per model version
- Emit metrics to a time-series store (Prometheus + Grafana / Datadog).

**Layer 2 — LLM-as-judge sampling (1–5% of traffic)**
- A frontier-class model as judge evaluates conversation quality on a random sample: helpfulness, groundedness, tone.
- Results flow into the same Grafana dashboard as async metrics.
- Cost budget: 1M queries/day × 1% sample × ~$0.005/judge call ≈ **$50/day**.

**Layer 3 — Golden dataset regression (nightly)**
- A curated set of ~200–500 query-context-answer triples with expected outputs, covering your highest-risk topics.
- Nightly CI job runs the current prod model against the golden set; computes Faithfulness, Answer Relevancy, and BERTScore F1.
- If any metric drops >3 points from the prior passing run, a PagerDuty alert fires and a GitHub Action blocks the next deployment.
- This is the safety net: it catches silent regressions caused by prompt changes, model updates, or index drift before users notice.

**Layer 4 — Business / user signals (continuous)**
- **Deflection rate** — fraction of queries resolved without human escalation.
- **CSAT / thumbs-down rate** — direct user signal; thumbs-down are routed to a human review queue for label harvesting.
- **Cost-per-query** — tracked per model version and tier; alerts on >15% spike.
- These lag async metrics by hours/days but are ground truth for whether the system is delivering value.

**Alerting thresholds (example SLOs)**
| Metric | Warning | Page |
|--------|---------|------|
| RAGAS Faithfulness (p50) | < 0.90 | < 0.85 |
| Retrieval cosine score (p50) | < 0.72 | < 0.68 |
| p95 latency | > 1.5s | > 3.0s |
| Thumbs-down rate | > 4% | > 8% |

### Example / Tradeoff

At a customer support deployment (a small fast model, Pinecone, 200K queries/day):
- Async RAGAS pipeline added ~40ms latency overhead (async, non-blocking).
- Nightly golden-set regression caught a prompt-rewrite that dropped Faithfulness from 0.93 → 0.81 before it hit prod — blocker in the deployment gate.
- Thumbs-down spikes (> 6%) were the first signal that the chunking strategy had drifted after a Confluence re-indexing; retrieval cosine scores confirmed it 30 min later.

**Key tradeoff — sync vs async eval:**  
Running RAGAS synchronously in the request path adds ~200–400ms latency; running it async means you catch hallucinations retrospectively, not in real time. For most applications async is acceptable; for high-stakes domains (medical, legal) consider a synchronous NLI entailment gate (DeBERTa, ~50ms) on the hot path and async RAGAS for broader monitoring.

---

## Verbal script

**Opening (30s):**
"I think of production monitoring for an LLM system in four layers: an async metric pipeline on 100% of traffic, a lightweight LLM-as-judge sampling pass, a nightly golden-dataset regression job, and business signals like deflection rate and CSAT. Each layer catches a different class of failure at a different cost point."

**Core explanation (2–3 min):**
"The async pipeline is the backbone. Every request-response pair goes into Kafka. A sidecar consumer computes RAGAS Faithfulness and Answer Relevancy, plus retrieval cosine scores and latency, without touching the user-facing serving path. These emit into Grafana, and I set SLO thresholds — say, Faithfulness p50 below 0.90 fires a warning, below 0.85 pages on-call.

For conversation quality — things like tone, helpfulness, nuance — I run a frontier model judge on 1–5% of traffic. That's cheap: at 1M queries/day and 1% sampling, it costs around $50/day. The judge scores come into the same dashboard.

Then nightly, a CI job runs the prod model against a golden dataset of 200–500 hand-annotated query-context-answer triples. If Faithfulness drops more than 3 points from the previous passing run, the next deployment is blocked automatically. This is the safety net that catches silent regressions from prompt changes, model updates, or index drift.

Finally, business signals — deflection rate, thumbs-down rate, cost-per-query — are the ground truth. They lag by hours, but they're what the business actually cares about, and spikes there trigger a full incident investigation."

**Tradeoff / production angle (1 min):**
"The biggest tradeoff is sync versus async eval. Running NLI entailment or RAGAS synchronously catches hallucinations before the user sees them, but adds 200–400ms per request. For most chatbots that's too expensive, so async is the default. For high-stakes domains — a medical chatbot, a legal assistant — I'd add a synchronous DeBERTa NLI gate on the hot path and keep async RAGAS for broader monitoring."

**Wrap-up (30s):**
"The key insight is that offline eval is necessary but not sufficient. Production monitoring closes the loop with real traffic, catches distribution shifts, and gives you the leading indicators — retrieval score drift, Faithfulness decline — before the lagging business metrics like CSAT deteriorate. Happy to go deeper on golden-dataset design or SLO threshold setting."

---

## Pitfalls

- **Mistake:** Treating offline golden-dataset eval as sufficient monitoring — "We ran evals before launch, so we're good." — **Better:** Explain that prod traffic distribution shifts over time (user vocabulary changes, knowledge base updates), so a static golden set is a lagging indicator; you need async metric telemetry on live traffic plus periodic golden-set updates seeded from production failures.
- **Mistake:** Using only user thumbs-down/CSAT as the production quality signal — **Better:** Thumbs-down has high latency (users don't always rate) and low coverage; pair it with async automated metrics (RAGAS Faithfulness, retrieval cosine score) that provide near-real-time 100% coverage and can alert before users notice degradation.
- **Mistake:** Running RAGAS synchronously on every request and blaming latency budgets for dropping eval — **Better:** Run it asynchronously via a Kafka sidecar; reserve synchronous checks for a fast, narrow NLI entailment gate only in high-stakes domains.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q8: Measure hallucination rate in production](05-008-measure-hallucination-rate-in-production.md) | Specific sub-problem of production monitoring — hallucination SLO tracking |
| [Q17: Golden dataset for evaluation and regression testing](05-017-golden-dataset-for-evaluation-and-regression-testing.md) | The offline component that anchors the production monitoring regression gate |
| [Q2: How evaluate a chatbot?](05-002-how-evaluate-a-chatbot.md) | Broader eval framework context this question extends into production |

---

## One-liner recall

> Production monitoring = async RAGAS sidecar on 100% of traffic + 1–5% LLM-judge sampling + nightly golden-set regression gate + business KPIs (deflection rate, CSAT), each catching a different failure class at increasing cost and latency.
