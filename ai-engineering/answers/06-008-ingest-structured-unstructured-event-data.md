# Ingest structured, unstructured, event data?

**Category:** 06-ml-fundamentals
**Question #:** 008
**Source section:** §6 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
Interviewers probe whether you can architect a heterogeneous data pipeline that feeds an ML system — not just a single-source ETL. In 2025–2026 AI apps, models ingest CSVs, PDFs, Slack threads, and Kafka streams simultaneously. The interviewer wants to see that you understand **source-specific extraction**, **schema harmonisation**, **latency tiers** (batch vs stream), and **quality gating** before data reaches the model or feature store.

### Trigger phrases
- "How would you ingest data from multiple sources into your AI system?"
- "Our data comes from databases, PDFs, and a Kafka event stream — how do you unify that?"
- "Walk me through a data pipeline for an AI application at scale."

### What it tests
Ability to design a production-grade, multi-modal ingestion architecture with appropriate tooling, latency SLAs, and quality controls for each data class.

---

## Answer

### Concept
AI systems consume three fundamentally different data classes — **structured** (rows, schema, SQL), **unstructured** (text, PDFs, images, audio — no fixed schema), and **event/streaming** (real-time signals: clickstreams, logs, sensor readings) — each requiring different extraction, transformation, and routing strategies before reaching a feature store, vector index, or training dataset.

### Mechanism

**1. Structured data (databases, CSVs, data warehouses)**
- Source: PostgreSQL, MySQL, Snowflake, BigQuery, S3 Parquet.
- Ingest pattern: full-load for small tables; CDC (Change Data Capture) via **Debezium** + **Kafka** for live OLTP tables.
- Transform: normalise types, fill nulls, encode categoricals; land in feature store (Feast/Tecton) for online serving or Parquet in S3 for offline training.
- Key concern: **train/serve feature skew** — the same transformation code must run at training time and serving time.

**2. Unstructured data (documents, PDFs, images, audio)**
- Source: S3, SharePoint, Google Drive, email, web crawl.
- Extract: **PyMuPDF** / **pdfplumber** for native PDFs; **AWS Textract** / **Azure Form Recognizer** for scanned docs (OCR confidence threshold ≥ 0.85); **Whisper** for audio transcription; **GPT-4o vision** for charts/figures.
- Transform: structure-aware chunking (parent-child: 1024-token parent, 256-token child); strip boilerplate; add metadata (source, doc_id, page, timestamp).
- Route: embed via **text-embedding-3-large** or **BGE-M3**; index in **Pinecone/Qdrant** for semantic search; store raw in S3.
- Key concern: document heterogeneity — tables need row-to-Markdown conversion; headers/footers must be stripped.

**3. Event/streaming data (clickstreams, logs, IoT, user actions)**
- Source: **Apache Kafka**, **AWS Kinesis**, **Pub/Sub**.
- Process: **Apache Flink** or **Spark Structured Streaming** for windowed aggregations (e.g., clicks-per-session in last 5 min); **Kafka Streams** for lightweight transformations.
- Sink: real-time features → Redis (online feature store, sub-10ms reads); historical aggregations → Parquet/BigQuery for training; alerts → PagerDuty.
- Key concern: **late-arriving events** — use watermarking (Flink: `.withIdleness(5 minutes)`) to handle out-of-order data without indefinite state.

**Unified quality gates (all three classes)**
- Schema validation: **Great Expectations** / Pydantic checks at ingestion.
- PII scrubbing: **Presidio** detect-and-redact before any LLM or storage write.
- Deduplication: MinHash for documents; idempotency keys (SHA-256 hash of content) for events.
- Observability: row-count / null-rate / latency metrics published to Grafana; alert on anomalies.

### Example / Tradeoff

**Enterprise knowledge-base RAG system (concrete stack):**
| Data class | Source | Ingest tool | Sink |
|------------|--------|-------------|------|
| Structured | PostgreSQL (product metadata) | Debezium CDC → Kafka | Feast feature store + Pinecone metadata filter |
| Unstructured | Confluence PDFs | PyMuPDF + Textract (scanned) | Pinecone (vector) + S3 (raw) |
| Events | User search queries (Kafka) | Flink 5-min window → Redis | Real-time ranking features |

**Latency tradeoff:**  
Streaming (Kafka+Flink) gives <1s freshness but adds operational complexity (state management, watermarking, exactly-once semantics). Batch (Airflow DAG, hourly) is far simpler and sufficient when hour-old data is acceptable — e.g., nightly document re-indexing. Always ask: **"What's the staleness SLA?"** before reaching for streaming.

**Exactly-once semantics** in Flink requires idempotent sinks and checkpointing — adds ~10–20% throughput overhead vs at-least-once; worth it only when downstream impact of duplicates is costly (financial transactions, billing events).

---

## Verbal script

**Opening (30s):**
"I'd frame this around three data classes that need different handling — structured relational data, unstructured documents, and real-time event streams — and then a shared quality layer that applies across all three before anything reaches the model."

**Core explanation (2–3 min):**
"For structured data, the main question is freshness vs simplicity. If hour-old data is fine, a nightly Airflow job pulling from Postgres or Snowflake into Parquet works great. If I need near-real-time, I'd use Debezium to capture Postgres WAL events into Kafka, then land them into a feature store like Feast for online serving. The critical thing is making sure the same transformation logic runs at training time and serving time — train/serve skew is a silent accuracy killer.

For unstructured data — PDFs, Word docs, emails — I'd route by MIME type. Native-digital PDFs go through PyMuPDF; scanned docs go through Textract or Azure Form Recognizer with an OCR confidence gate. Tables get converted to Markdown before chunking. I'd use a parent-child chunking strategy — 1024-token parent for context, 256-token child for retrieval precision — and embed with text-embedding-3-large into Pinecone.

For event streams — clickstreams, user actions, logs — I'd use Kafka as the backbone with Flink for windowed aggregations. For example, clicks-per-session in the last five minutes lands in Redis for sub-10ms feature reads at serving time. Historical data goes to BigQuery for training. The main nuance here is late-arriving events — Flink watermarking prevents infinite state accumulation.

Across all three, I'd add shared quality gates: Great Expectations for schema validation, Presidio for PII scrubbing before any LLM sees the data, MinHash dedup for documents, and idempotency keys for events."

**Tradeoff / production angle (1 min):**
"The biggest tradeoff is streaming complexity vs freshness. Streaming infrastructure — Kafka, Flink, exactly-once checkpointing — is operationally expensive. I'd default to batch unless the staleness SLA is under an hour. For a RAG knowledge base, documents can be re-indexed nightly; that's batch. For real-time personalisation ranking features, I need Kafka+Flink. Getting that threshold wrong — streaming everything by default — leads to over-engineered pipelines that are fragile and hard to debug."

**Wrap-up (30s):**
"So the mental model is: classify data by class, match each to the right extraction tool and latency tier, then apply shared quality gates. Happy to go deeper on any layer — the Flink windowing semantics, the chunking strategy for unstructured docs, or the feature store design."

---

## Pitfalls

- **Mistake:** Describing only batch ETL ("we pull from the DB into S3 nightly") without addressing streaming or unstructured sources — **Better:** Segment your answer by data class (structured/unstructured/event) and choose the latency tier appropriate to each; name the staleness SLA before recommending a pattern.
- **Mistake:** Saying "we'd use Kafka for everything" without mentioning the operational complexity of exactly-once semantics, watermarking, or state management — **Better:** Explain that streaming adds complexity (Flink checkpointing, late-event watermarks, ~10–20% throughput overhead for exactly-once), and justify it only when the staleness SLA demands <1s freshness.
- **Mistake:** Forgetting the quality layer — schema validation, PII scrubbing, deduplication — and jumping straight to storage — **Better:** Explicitly call out Great Expectations/Pydantic validation, Presidio PII scrubbing, and MinHash/idempotency-key dedup as gates that apply before any data reaches the model or feature store.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q7: Real-time vs batch processing for data updates](06-007-real-time-vs-batch-processing-for-data-updates.md) | Direct prerequisite — streaming vs batch decision framework |
| [Q1: Data pre-processing and feature engineering](06-001-data-pre-processing-and-feature-engineering.md) | Follow-up — once ingested, how to transform and featurise |
| [Q3: Design a GenAI document-processing pipeline for unstructured data](../answers/02-003-design-a-genai-document-processing-pipeline-for-unstructured.md) | Cross-category deeper dive on unstructured doc ingestion |

---

## One-liner recall

> Segment by data class — structured (Debezium CDC → Feast), unstructured (PyMuPDF/Textract → parent-child chunks → Pinecone), events (Kafka+Flink → Redis feature store) — with shared Presidio PII scrubbing, Great Expectations validation, and dedup gates at every entry point; choose batch vs stream by staleness SLA, not by default.
