# Real-time vs batch processing for data updates?

**Category:** 06-ml-fundamentals
**Question #:** 007
**Source section:** §6 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
The interviewer wants to see whether you can map a data-freshness SLA to the right processing architecture — a core applied-ML skill. In AI/LLM systems this surfaces constantly: RAG index freshness, feature store updates, embedding recomputation, and model-monitoring pipelines all demand an explicit latency vs cost tradeoff. Weak candidates treat this as a generic software question; strong candidates tie latency requirements to business impact and quantify the cost delta.

### Trigger phrases
- "How would you keep your RAG index up to date?"
- "What's your approach to real-time vs batch for data updates?"
- "How would you handle feature freshness for a recommendation system?"
- "Our embeddings are going stale — how do you fix that?"

### What it tests
Ability to match data-freshness requirements to the appropriate pipeline architecture (streaming vs micro-batch vs bulk batch) and articulate the latency/cost/complexity tradeoffs for each.

---

## Answer

### Concept
Real-time processing updates data as events arrive (sub-second to seconds latency); batch processing accumulates data over a window and processes it in bulk (minutes to hours latency). The right choice depends entirely on how stale data is tolerable before it harms the user or model quality. In AI systems, stale knowledge bases break RAG, stale features drift from training distribution, and stale embeddings cause retrieval failures.

### Mechanism

**Decision axis: acceptable staleness**

| Staleness SLA | Architecture | Typical tooling |
|---------------|-------------|-----------------|
| < 1 second | Streaming (event-by-event) | Kafka + Flink / Spark Structured Streaming |
| 1–60 seconds | Micro-batch streaming | Kafka + Flink micro-batch, AWS Kinesis Data Streams |
| 1–60 minutes | Scheduled micro-batch | Airflow DAG, dbt incremental models |
| Hours / overnight | Full batch | Spark batch job, BigQuery scheduled query, Airflow |

**Real-time (streaming) pipeline:**
1. Source system emits a change event → Kafka topic.
2. Stream processor (Flink/Spark SS) consumes, transforms, and writes to sink within milliseconds.
3. Downstream consumer (vector DB, feature store, model) sees the update immediately.
4. Complexity: exactly-once semantics, backpressure handling, schema evolution, stateful joins.

**Batch pipeline:**
1. Scheduled job reads a full or incremental snapshot from source.
2. Transforms the data (dedup, normalize, embed).
3. Writes bulk upsert to sink.
4. Simple, cheap, easy to re-run; latency is window size + job duration.

**Hybrid (Lambda / Kappa) — common in production AI:**
- **Lambda:** batch layer for correctness + serving layer fed by streaming for recency. Complexity: two code paths.
- **Kappa:** streaming only, replay from Kafka log for re-processing. Simpler, but streaming code must handle bulk replay efficiently.

**RAG-specific pattern:** CDC (Change Data Capture) via Debezium watches the source DB → Kafka topic → embedding worker (containerized, async) → upsert into Pinecone/Qdrant with `doc_id` key. Nightly full-sync as safety net catches missed deletes. Monitoring: `index_lag_seconds` alert > 120s.

### Example / Tradeoff

**Customer support knowledge base (real project pattern):**
- Articles edited in Confluence trigger webhooks → Kafka → async embed worker → Pinecone upsert. Latency: ~30s end-to-end.
- Cost: embedding worker runs continuously (~$80/month for t3.medium), plus Kafka cluster.
- Alternative (nightly batch): job costs ~$5/run but articles published during the day cause hallucinations until 2am.
- Decision: streaming is justified when stale answers have a measurable support-ticket cost > streaming infra cost.

**Feature store for recommendation model:**
- User click events → Kafka → Flink → Redis online store (sub-second reads for inference).
- Historical features (user 90-day aggregates) → overnight Spark job → Parquet → offline store.
- Classic Lambda pattern: online store for recency, offline store for training.

**Key tradeoffs:**

| Dimension | Streaming | Batch |
|-----------|-----------|-------|
| Latency | Sub-second to seconds | Minutes to hours |
| Cost | Continuous infra ($$$) | Pay-per-run ($) |
| Complexity | High (exactly-once, schema, backpressure) | Low (scheduled job) |
| Fault recovery | Offset replay | Re-run job |
| Right for | Real-time RAG, live features, fraud detection | Model training data, overnight reports, bulk re-embedding |

---

## Verbal script

**Opening (30s):**
"The core question is: how stale can your data be before it hurts the user? Everything else — architecture, tooling, cost — follows from that SLA. I'll walk through the decision framework, then give a concrete example from a RAG context."

**Core explanation (2–3 min):**
"Real-time streaming processes events as they arrive — think Kafka plus Flink. You get sub-second to low-second latency but you're running infra continuously and you have to handle exactly-once semantics, schema evolution, and backpressure. That complexity is worth it when stale data has a direct business cost: a support chatbot giving yesterday's pricing, a fraud model missing a transaction pattern.

Batch processing accumulates data over a window — maybe hourly, maybe overnight — and runs a bulk job. Much simpler, much cheaper per run, but the staleness is the window size plus job duration. For training data pipelines, model monitoring roll-ups, or content where freshness is nice-to-have, batch wins.

In practice, production AI systems often use a hybrid pattern. For a RAG system I'd set up CDC with Debezium watching the source database, events flowing through Kafka, an async embedding worker doing upserts into Pinecone with the document ID as the upsert key, and a nightly full-sync as a safety net for missed deletes. I'd monitor an `index_lag_seconds` metric and alert at 120 seconds.

For a feature store, I'd typically run a Lambda architecture: online features from Kafka→Flink→Redis for sub-second inference reads, and offline features from a nightly Spark job into Parquet for training."

**Tradeoff / production angle (1 min):**
"The main thing that bites teams is treating streaming as the default just because it sounds modern. Streaming infra — Kafka cluster, Flink jobs, exactly-once configuration — costs real money and engineering time. If your knowledge base gets 50 edits per day and freshness within an hour is fine, an Airflow DAG running every 30 minutes is strictly better. I always ask: what's the dollar cost of a stale answer? If it's $0.50 in extra support tickets, that doesn't justify $3K/month of streaming infra."

**Wrap-up (30s):**
"So the decision tree is: sub-second SLA → streaming; minutes-to-hour SLA → micro-batch or scheduled; overnight fine → batch. And for production AI systems, a CDC + Kafka + async embed worker pattern covers most RAG freshness needs without full Flink complexity. Happy to go deeper on any layer."

---

## Pitfalls

- **Mistake:** Recommending Kafka + Flink for every data update scenario without asking about staleness tolerance — **Better:** Start with "what's the acceptable lag?" and justify streaming only when the business cost of stale data exceeds the infra cost; most RAG use cases tolerate 1–5 minute lag, which a scheduled Airflow job handles fine.
- **Mistake:** Forgetting deletes when describing CDC/streaming updates — **Better:** Explain that inserts and updates are easy but soft-delete patterns (marking rows as deleted) and nightly full-sync sweeps are needed to purge stale chunks from the vector index, otherwise ghost documents pollute retrieval.
- **Mistake:** Conflating Lambda and Kappa architectures as equivalent — **Better:** Explain Lambda has two code paths (batch correctness + streaming recency) while Kappa uses streaming only with Kafka log replay for reprocessing; Lambda is more common in practice because exact same outputs from batch and stream is hard to guarantee.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q8: Ingest structured, unstructured, event data?](06-008-ingest-structured-unstructured-event-data.md) | Follow-up — how to ingest the data once the pipeline architecture is chosen |
| [Q2: SQL vs NoSQL for AI workloads?](06-002-sql-vs-nosql-for-ai-workloads.md) | Prerequisite — storage layer that feeds streaming or batch pipelines |
| [Q33: Stale indexes, embedding drift](../answers/02-033-stale-indexes-embedding-drift.md) | Same concept applied specifically to RAG vector index freshness |

---

## One-liner recall

> Choose streaming (Kafka+Flink) when stale data has a measurable dollar cost that exceeds continuous infra cost; otherwise a scheduled micro-batch or Airflow DAG is simpler, cheaper, and correct — and always handle deletes via CDC soft-delete or nightly full-sync.
