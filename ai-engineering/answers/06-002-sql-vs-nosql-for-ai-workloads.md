# SQL vs NoSQL for AI workloads?

**Category:** 06-ml-fundamentals
**Question #:** 002
**Source section:** §6 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
Interviewers want to see whether you can match storage technology to the read/write patterns, data shapes, and consistency requirements that arise in AI systems — vector stores, feature stores, metadata indexes, training data lakes, and serving caches all have different profiles. Weak candidates treat the choice as SQL = old, NoSQL = new.

### Trigger phrases
- "What storage would you use for embeddings / features / training logs?"
- "SQL vs NoSQL for AI workloads?"
- "Why did you choose Postgres/Cassandra/DynamoDB over alternatives?"

### What it tests
Ability to match storage access patterns, consistency needs, and data shapes to the right database technology in the context of real AI system components.

---

## Answer

### Concept
SQL (relational) databases enforce a schema, provide ACID transactions, and excel at structured queries with joins; NoSQL databases trade strict consistency and schema rigidity for horizontal scalability, flexible data models, and optimised access patterns (key-value, document, wide-column, graph, or vector). For AI workloads, the choice is driven by the specific component — there is rarely a single "right" answer for the whole system.

### Mechanism
Map each AI system component to its dominant access pattern, then choose:

| Component | Access pattern | Preferred storage |
|-----------|---------------|-------------------|
| Feature store (online serving) | Point lookups by entity ID, <10 ms SLO | Redis (in-memory key-value) or DynamoDB |
| Feature store (offline training) | Batch reads of entire feature tables by time range | Parquet on S3 / Delta Lake + Spark |
| Metadata (experiments, model registry) | Rich queries, joins, audit trail | PostgreSQL / SQLite (MLflow backend) |
| Vector index (ANN retrieval) | Approximate nearest-neighbour by embedding | Pinecone, Qdrant, Weaviate, pgvector |
| Training logs / event telemetry | Append-only, time-series, high ingest | ClickHouse, BigQuery, Kafka → S3 |
| Session / conversation state | TTL-keyed per session, hot reads | Redis with TTL |
| Document metadata sidecar (RAG) | Filter by category/date, join on doc_id | PostgreSQL or Elasticsearch |
| User profile / preferences | Sparse attributes, schema evolves | DynamoDB or MongoDB |

**Decision heuristics:**
1. **Need ACID joins or audit trail?** → PostgreSQL
2. **Sub-millisecond point lookups at high QPS?** → Redis or DynamoDB
3. **ANN search over millions of embeddings?** → Pinecone / Qdrant / FAISS (pgvector for <1 M rows)
4. **Petabyte-scale append-only analytics?** → BigQuery / ClickHouse / Parquet on S3
5. **Flexible document schema that changes often?** → MongoDB / Firestore
6. **Graph traversal (GraphRAG)?** → Neo4j / Kuzu

### Example / Tradeoff
A production RAG pipeline for a customer support chatbot might use:
- **Pinecone** for the vector index (ANN retrieval, managed HNSW, metadata pre-filtering)
- **PostgreSQL** for chunk metadata, ACL groups, and conversation audit logs (joins, ACID)
- **Redis** for semantic response cache (cosine-similarity lookup, TTL=1h, 30% hit rate → saves ~$3K/day at 1M queries)
- **S3 + Parquet** for raw document storage and the offline RAGAS golden-dataset

The common trap is storing embeddings in PostgreSQL via pgvector for the whole system — pgvector is excellent up to ~1M rows but scan degrades past that without IVFFlat indexes, and it still shares IOPS with transactional traffic.

---

## Verbal script

**Opening (30s):**
"For AI workloads I'd answer this component-by-component rather than picking one technology for the whole system. The key insight is that different AI components have completely different access patterns — a feature store, a vector index, an experiment tracker, and a training data lake each need different storage."

**Core explanation (2–3 min):**
"I'd break a typical AI system into layers. First, **metadata and audit** — experiment tracking, model registry, chunk metadata — these benefit from relational storage. PostgreSQL with ACID transactions gives you joins, audit trails, and rich filtering. MLflow, for example, uses Postgres as its backend by default.

Second, **vector retrieval** — this is where purpose-built vector databases shine. Pinecone and Qdrant use HNSW indexes optimised for approximate nearest-neighbour search. pgvector is a reasonable choice for small corpora under about a million vectors, but beyond that you want a dedicated vector store.

Third, **online feature serving** — if you're serving user or item features to a model at inference time, you need sub-10ms reads. Redis is the standard answer: in-memory key-value, optional TTL, trivially horizontally scalable.

Fourth, **offline training data and analytics** — for petabyte-scale event logs and training corpora you want columnar storage: Parquet on S3 read by Spark or BigQuery. These are optimised for full-column scans, not point lookups.

And fifth, **session state and caching** — Redis again with TTL keys, plus semantic caching layers like GPTCache sitting in front of the LLM."

**Tradeoff / production angle (1 min):**
"The major tradeoff I've seen teams get wrong is over-centralising on one database. A team that puts everything in Postgres will eventually hit IOPS contention between transactional metadata writes and large vector scans. Conversely, a team that uses only DynamoDB loses the ability to do complex analytics or joins on experiment results. The right answer is usually a polyglot architecture — Postgres for relational metadata, a vector DB for embeddings, Redis for caching, and a data lake for offline workloads."

**Wrap-up (30s):**
"So my decision framework: relational for metadata and audit, vector DB for embeddings, Redis for online feature serving and caching, columnar storage for offline analytics. Happy to go deeper on any specific component — the vector DB selection tradeoffs or the feature store architecture are each a rich topic."

---

## Pitfalls

- **Mistake:** Saying "NoSQL is better for AI because it's more scalable" without specifying which component — **Better:** Map each component to its access pattern; SQL is often the right choice for metadata, audit logs, and experiment tracking.
- **Mistake:** Recommending pgvector for all vector workloads without mentioning its scaling limits — **Better:** State that pgvector is excellent for <1M vectors but HNSW scan degrades at scale; purpose-built vector DBs (Pinecone, Qdrant) are needed for production RAG at millions of chunks.
- **Mistake:** Ignoring caching layers entirely and focusing only on primary storage — **Better:** Mention Redis semantic cache (GPTCache) as a cost/latency lever; at 1M queries/day a 30% cache hit rate saves meaningful compute spend.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q1: Data pre-processing and feature engineering](06-001-data-pre-processing-and-feature-engineering.md) | Feature store is a downstream consumer of cleaned, engineered features |
| [Q8: Ingest structured, unstructured, event data](06-008-ingest-structured-unstructured-event-data.md) | Ingestion architecture determines which storage tier data lands in |
| [Q2: Design a RAG system for a customer support chatbot](../answers/02-001-design-a-rag-system-for-a-customer-support-chatbot.md) | RAG system design requires the full polyglot storage stack described here |

---

## One-liner recall

> Match each AI system component to its access pattern: PostgreSQL for metadata/audit, a purpose-built vector DB (Pinecone/Qdrant) for embeddings, Redis for online feature serving and caching, and columnar storage (Parquet/BigQuery) for offline training data — never one database for everything.
