# How efficiently generate and store embeddings for products and queries?

**Category:** 02-rag-systems
**Question #:** 007
**Source section:** §2 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
This probes production-scale embedding pipeline design — a core RAG engineering task that separates candidates who've built real systems from those who've only run notebooks. Interviewers want to see that you understand batching, cost-efficiency, storage architecture, query-time versus index-time asymmetry, and incremental update patterns.

### Trigger phrases
- "How would you generate and store embeddings for a product catalog of 5M items?"
- "We have 10M documents — how do you build the embedding pipeline efficiently?"
- "How do you handle incremental updates to your vector index?"

### What it tests
Ability to design a scalable, cost-efficient embedding pipeline covering batch generation, storage architecture (vector DB + metadata DB), and real-time query embedding — including incremental update and embedding model migration strategies.

---

## Answer

### Concept
Embedding generation for a large corpus is a batch-processing engineering problem: you need to run millions of items through a model (OpenAI `text-embedding-3-small`, `ada-002`, or a self-hosted `sentence-transformers` model) and persist the resulting dense vectors in a vector database (Pinecone, Qdrant, Weaviate, or FAISS + object store) so they can be searched at query time. Query-time embeddings are generated on-demand, usually in < 50 ms, so they need a different optimization path than index-time embeddings.

### Mechanism

**Index-time (offline) pipeline:**

1. **Extract & clean** — pull product records from source DB, normalize text fields (title + description + category + attributes concatenated), strip HTML, handle missing fields.
2. **Batch with parallelism** — chunk corpus into batches of 512–2048 items; run concurrent embedding calls (OpenAI supports 2048 inputs per call). Use async Python (`asyncio` + `httpx`) or a workflow orchestrator (Airflow, Prefect) with parallel workers. For a self-hosted model, use GPU batching with `sentence-transformers` on an A10/A100; set `batch_size=256–512` for throughput.
3. **Cost gate** — for OpenAI `text-embedding-3-small`: $0.02 / 1M tokens. A product record averaging 200 tokens → 5M products = 1B tokens = ~$20 total (one-time). For incremental daily delta, cost is negligible.
4. **Store vectors** — upsert into vector DB with a stable `product_id` as the primary key. Pinecone accepts batches of 100 vectors per upsert; Qdrant supports bulk upsert of 10K+.
5. **Store metadata** — keep all filterable fields (price, category, brand, in_stock) in a metadata sidecar (PostgreSQL or the vector DB's payload store). This avoids bloating vector payloads and enables pre-filter pushdown.
6. **Incremental updates** — listen to change events (CDC from PostgreSQL via Debezium, or a Kafka topic). Re-embed only changed records; upsert by `product_id`. For deletions, call vector DB delete-by-id.

**Query-time (online) pipeline:**

1. User query arrives → normalize (lowercase, strip punctuation).
2. Embed query via the **same model** used at index time (model mismatch = garbage retrieval).
3. Execute ANN search (Pinecone `query()`, Qdrant `search()`) with top-k=20 and metadata filter.
4. Target p95 embedding latency < 20 ms (OpenAI API); for stricter SLOs, cache frequent query embeddings in Redis (TTL 1 h) keyed on `sha256(query_text)`.

**Self-hosted option (cost at scale):**
For > 100M queries/month, OpenAI costs dominate. Deploy `text-embedding-3-small` via vLLM or `sentence-transformers` on a GPU server — throughput ~20K embeddings/s on an A10G. Break-even vs OpenAI API at roughly 500M tokens/month.

### Example / Tradeoff

**Stack used at mid-scale product search (5M SKUs, 500K queries/day):**
- Index pipeline: Airflow DAG → 8 parallel workers → OpenAI `text-embedding-3-small` → Pinecone serverless (us-east-1), 1536-dim vectors.
- Metadata: PostgreSQL; Pinecone payload store holds only `product_id`, `category`, `in_stock`.
- Query: FastAPI service → `httpx` async embed call → Pinecone query with category pre-filter → cross-encoder rerank top-20 → return top-5.
- Incremental: Debezium CDC → Kafka topic `product-changes` → worker re-embeds + upserts within 2 min SLA.

**Key tradeoffs:**
| Decision | Option A | Option B |
|----------|----------|----------|
| Model | OpenAI API (easy, $) | Self-hosted sentence-transformers (complex, cheap at scale) |
| Storage | Pinecone serverless (no ops) | Qdrant on-prem (cheaper at high QPS) |
| Updates | Periodic batch re-index | CDC streaming (lower staleness, higher complexity) |
| Dimension | 1536-dim (high accuracy) | 256-dim MRL (4× cheaper, ~95% quality) |

**Matryoshka Representation Learning (MRL):** models like `text-embedding-3-small` support truncating embeddings to lower dimensions (256, 512) without significant accuracy loss — a powerful cost/storage lever.

---

## Verbal script

**Opening (30s):**
"I'd break this into two distinct paths: the offline batch pipeline for generating and indexing embeddings at scale, and the online path for embedding user queries at low latency. They have very different optimization goals — throughput vs latency — and should be treated separately."

**Core explanation (2–3 min):**
"For offline indexing — say 5M products — I'd run a parallel batch pipeline. Extract text fields from the source DB, concatenate title plus description plus attributes, then fan out to embedding workers. With OpenAI's `text-embedding-3-small`, you can send batches of 2048 inputs per call, and async HTTP lets you saturate the API rate limit. Total cost for 5M products at 200 tokens each is roughly $20 — basically free. The vectors go into Pinecone or Qdrant keyed on `product_id`, with filterable metadata like category and price in a sidecar PostgreSQL table or the vector DB's payload store — you don't want to bloat the vector payload.

For incremental updates, I'd set up CDC via Debezium on the source DB, publish change events to Kafka, and have a consumer worker re-embed and upsert changed records. That keeps the index fresh within a 2-minute SLA without a full re-index.

On the query side, the critical rule is to use the exact same model. A mismatch between index-time and query-time models breaks retrieval entirely. For latency, I target sub-20ms embedding via the API, and cache frequent query embeddings in Redis — e.g. common product search terms don't need re-embedding every time."

**Tradeoff / production angle (1 min):**
"At very high scale — say 100M+ queries/month — OpenAI API costs start to dominate. That's where self-hosting with `sentence-transformers` on an A10G GPU makes sense; you get ~20K embeddings/s. The break-even is roughly 500M tokens/month. Another great lever is MRL — `text-embedding-3-small` supports truncating vectors to 256 dimensions with minimal accuracy loss, which cuts storage and ANN search cost by 6×."

**Wrap-up (30s):**
"So the key architecture is: offline batch pipeline with parallelism and CDC-driven incremental updates, Pinecone or Qdrant for vector storage with metadata in a sidecar, and the same model used for both indexing and queries. Happy to go deeper on the CDC update flow or the self-hosting tradeoff."

---

## Pitfalls

- **Mistake:** Using a different embedding model at query time than at index time (or re-indexing after a model upgrade without re-embedding all documents) — **Better:** Treat embedding model version as part of the index schema; when you change models, trigger a full re-index and A/B test before cutover using RAGAS retrieval metrics.
- **Mistake:** Generating embeddings one-at-a-time in a loop instead of batching — **Better:** Always batch at 512–2048 inputs per API call and parallelize across workers; single-threaded embedding of 5M products at 1 embedding/call would take hours and 5× the cost.
- **Mistake:** Storing all metadata fields inside the vector payload, making the index bloated and slow — **Better:** Keep only filterable fields in the vector DB payload; store full records in PostgreSQL or a document store, joining on `product_id` after retrieval.
- **Mistake:** Ignoring stale embeddings after product catalog changes — **Better:** Architect CDC-driven incremental update from day one; full re-indexes don't scale and create stale retrieval windows.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q13: What are embeddings?](../answers/01-013-what-are-embeddings.md) | Prerequisite — what embeddings are before covering how to generate them at scale |
| [Q23: How does ANN search work? HNSW indexing?](02-023-how-does-ann-search-work-hnsw-indexing.md) | Follow-up — what happens after embeddings are stored: ANN search mechanics |
| [Q33: Stale indexes, embedding drift](02-033-stale-indexes-embedding-drift.md) | Same concept — the incremental update / embedding drift failure mode in detail |

---

## One-liner recall

> Batch-generate embeddings offline (2048/call, async, ~$20 per 5M products), store vectors in Pinecone/Qdrant keyed on stable IDs with metadata in a sidecar, drive incremental updates via CDC, and always use the same model for index and query time.
