# Stale indexes, embedding drift

**Category:** 02-rag-systems
**Question #:** 033
**Source section:** §2 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
This question probes production RAG operational maturity — most candidates design the happy-path pipeline but ignore what happens over time: source documents change, new content is added, and the embedding model itself may be swapped. Weak candidates treat the vector index as a write-once artifact; strong candidates treat it as a live data product with freshness SLOs and migration playbooks.

### Trigger phrases
- "What happens to your RAG system when documents are updated or deleted?"
- "How do you keep your vector index fresh as your knowledge base changes?"
- "What is embedding drift and how do you handle it?"
- "How would you migrate to a new embedding model without downtime?"

### What it tests
Operational depth: ability to design index lifecycle management — incremental updates, deletion handling, drift detection, and zero-downtime model migrations.

---

## Answer

### Concept
**Stale indexes** occur when the vector store falls out of sync with the source of truth: documents are updated, deleted, or added but the index isn't refreshed, causing the LLM to generate answers from outdated or irrelevant chunks. **Embedding drift** is a related problem: when you retrain or swap the embedding model, existing vectors are no longer comparable to new query embeddings encoded by the updated model, silently degrading retrieval quality.

### Mechanism

**Staleness — four root causes and fixes:**

| Root cause | Symptom | Fix |
|------------|---------|-----|
| New docs not indexed | Recall gaps on recent content | CDC pipeline (Debezium/Kafka) triggers re-ingestion on source writes |
| Updated docs with old chunks | LLM returns outdated information | Chunk-level content hash → detect delta → delete old chunks, insert new |
| Deleted docs still indexed | Ghost answers from removed content | Soft-delete flag + nightly purge job; use doc_id metadata filter |
| Embedding model swapped mid-index | Cosine similarity breaks (query vs. index encoded by different models) | Blue-green index migration — build full new index in parallel, cutover atomically |

**Incremental update pattern (production):**
1. Source-of-truth systems emit events: Confluence webhook, S3 event, Postgres CDC (Debezium → Kafka topic).
2. Consumer computes SHA-256 hash of each document at ingest. On update, compare hash — skip if unchanged.
3. On delta: delete all chunks for `doc_id` from vector store (Pinecone `delete(filter={"doc_id": "..."})`, Qdrant `delete_points`), re-chunk and re-embed, upsert new chunks with updated `updated_at` metadata.
4. Monitor `index_lag_seconds` = now − max(`indexed_at`) per data source. Alert if lag > SLO (e.g., 15 min for real-time, 24 h for batch knowledge bases).

**Embedding drift detection and migration:**
1. Maintain a golden retrieval eval set (200–500 queries with expected doc_ids).
2. After any embedding model change, run eval against old index — track Recall@5 regression.
3. Zero-downtime migration: build new index in parallel (shadow index), route 5% of traffic via A/B shadow queries, measure Recall@5 and latency. When new index is ≥ baseline: atomic DNS/client cutover. Keep old index for 48 h rollback window.
4. Never mix encoders: all chunks in a live index must use the same model version. Tag chunks with `embedding_model` metadata field.

### Example / Tradeoff

**Concrete incident pattern:** A legal-tech RAG system embedded 50K contracts using `text-embedding-ada-002`. Six months later they upgraded to `text-embedding-3-large` for 15% better Recall@5 on their golden set. Team swapped the query encoder without migrating the index. Cosine similarity between new query vectors and old ada-002 chunk vectors became meaningless — top-k results were near-random, deflection rate collapsed from 72% → 31% overnight. Fix: rebuild full index with `text-embedding-3-large` over a weekend, shadow-test, then cutover.

**Cost of full rebuild vs. incremental:**
- Full rebuild: simple but expensive — 50K contracts × 10 chunks × 1536 dims × $0.00002/1K tokens ≈ $40; fine for a weekend migration.
- Incremental CDC: ~$0/day ongoing but requires operational complexity (Kafka, hash tracking, deletion logic). Worth it for large corpora (>1M docs) or high-update-frequency sources.

---

## Verbal script

**Opening (30s):**
"Stale indexes and embedding drift are the two biggest silent killers in production RAG systems. They don't throw errors — they just make the system give increasingly wrong answers. I think about them as separate problems: staleness is about keeping the index in sync with your source of truth, and drift is about keeping the index consistent when your embedding model changes."

**Core explanation (2–3 min):**
"For staleness, the key is treating document updates as events rather than polling for changes. I'd wire up a CDC pipeline — Debezium on Postgres, or webhooks from Confluence — feeding a Kafka topic that a consumer listens to. The consumer computes a SHA-256 hash of each document at ingest and stores it alongside the chunks. On an update event, it compares the new hash, and if there's a delta: delete all chunks for that doc_id from the vector store, re-chunk, re-embed, and upsert fresh chunks with an updated `indexed_at` timestamp. I also track `index_lag_seconds` — the difference between now and the most recent `indexed_at` per data source — and alert if it exceeds the SLO. For a real-time support KB that's 15 minutes; for a static document archive that's 24 hours.

For deleted documents: if a doc gets removed from the source, the old chunks will keep surfacing ghost answers. I handle this with a soft-delete flag in metadata — mark `deleted=true`, filter it from retrieval immediately, and run a nightly hard-delete purge from the vector store.

For embedding drift: the golden rule is that every chunk in a live index must be encoded by the same model version. I tag every chunk with an `embedding_model` field. When we need to upgrade — say from `text-embedding-ada-002` to `text-embedding-3-large` — I do a blue-green migration: build the new index in parallel, shadow-test 5% of live traffic against it while comparing Recall@5 on a golden eval set. When the new index meets or exceeds baseline, I do an atomic cutover and keep the old index live for 48 hours as a rollback window."

**Tradeoff / production angle (1 min):**
"The main tradeoff is operational complexity vs. cost. Full nightly rebuilds are simple — no CDC plumbing, no deletion logic — but they're expensive and slow for large corpora. Incremental CDC is cheaper per day but needs Kafka, hash tracking, and deletion idempotency. I'd choose incremental for corpora over ~500K docs or sources that update hourly. Below that, a nightly rebuild with blue-green cutover is often simpler and good enough. The critical thing either way is running your golden eval set before and after any change — without that, you won't catch drift until users are complaining."

**Wrap-up (30s):**
"The one-liner: treat your vector index like a live database, not a build artifact — instrument `index_lag`, enforce one-model-version-per-index, and never let a query encoder update outpace an index rebuild. Happy to dig into CDC architectures or zero-downtime migration patterns."

---

## Pitfalls

- **Mistake:** Saying "just rebuild the index nightly" without addressing deletion — old chunks for deleted docs remain in the index and surface ghost answers indefinitely. — **Better:** Explain the soft-delete-then-hard-purge pattern and note that Pinecone's `delete(filter={"doc_id": "..."})` handles this.
- **Mistake:** Describing embedding model upgrades as "just swap the model and re-embed new queries" without mentioning that the existing index was encoded by the old model — this silently breaks cosine similarity for all retrieval. — **Better:** Explain the blue-green index migration: build new index in parallel, shadow-test with A/B queries, atomic cutover with rollback window.
- **Mistake:** Treating index lag as a binary flag ("fresh or stale") rather than a metric with a per-source SLO. — **Better:** Describe monitoring `index_lag_seconds` per data source with source-specific SLO thresholds and alerting.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q7: How efficiently generate and store embeddings for products and queries?](02-007-how-efficiently-generate-and-store-embeddings-for-products-a.md) | Foundation: how the index is built and updated |
| [Q11: How ensure quality of data the LLM interacts with?](02-011-how-ensure-quality-of-data-the-llm-interacts-with.md) | Broader data quality framework that staleness fits inside |
| [Q34: Weak evaluation hiding retrieval failures](02-034-weak-evaluation-hiding-retrieval-failures.md) | Without a golden eval set you can't detect drift-induced regression |

---

## One-liner recall

> Stale indexes are fixed with CDC-driven incremental updates + doc_id deletion; embedding drift is prevented by tagging chunks with model version and doing blue-green parallel rebuilds before any encoder upgrade.
