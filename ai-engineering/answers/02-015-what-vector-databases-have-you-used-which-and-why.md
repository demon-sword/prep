# What vector databases have you used? Which and why?

**Category:** 02-rag-systems
**Question #:** 015
**Source section:** §2 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
The interviewer is probing hands-on production experience with vector storage, not textbook knowledge. They want to see whether you can justify a technology choice based on real constraints — managed vs self-hosted, latency SLOs, scale, filtering needs, cost — and whether you understand the architectural tradeoffs each database makes.

### Trigger phrases
- "What vector databases have you worked with?"
- "Which vector DB would you pick for this system, and why?"
- "Have you used Pinecone / Qdrant / Weaviate / FAISS — what's your take?"
- "How did you choose your vector store?"

### What it tests
Ability to select and justify a vector database based on production constraints (scale, latency, cost, filtering, managed vs self-hosted) rather than just naming tools.

---

## Answer

### Concept
A vector database stores high-dimensional embeddings and supports approximate nearest-neighbor (ANN) search — typically HNSW or IVF-based — often combined with metadata filtering. The right choice depends on five axes: managed vs self-hosted, scale (number of vectors), filtering complexity, latency SLO, and cost.

### Mechanism
**Key databases and their positioning:**

| DB | Index | Hosting | Sweet spot | Weakness |
|----|-------|---------|-----------|----------|
| **Pinecone** | HNSW (proprietary) | Fully managed SaaS | Fast MVP, no ops burden, reliable p99 | Costly at high QPS; no self-host |
| **Qdrant** | HNSW + payload indexing | Self-host or cloud | Rich filtering, Rust performance, open-source | You own the ops |
| **Weaviate** | HNSW + BM25 hybrid | Self-host or cloud | Built-in hybrid search, GraphQL API | Memory-heavy HNSW for large corpora |
| **pgvector** | IVF-Flat / HNSW | Any Postgres host | Existing Postgres stack, <5M vectors | Recall drops without tuning; not sharded natively |
| **FAISS** | IVF-PQ, HNSW, Flat | Library (no server) | Offline batch search, R&D, custom infra | No filtering, no persistence, no multi-tenancy |
| **Chroma** | HNSW (hnswlib) | Embedded or server | Local dev / small apps | Not production-grade at scale |
| **Milvus** | IVF-PQ, HNSW, DiskANN | Self-host (k8s) | 100M+ vectors, GPU acceleration | Operational complexity |

**Selection decision tree:**
```
Need managed, zero-ops?
  → Pinecone (or Weaviate Cloud)

Have Postgres already + <10M vectors?
  → pgvector with HNSW index

Need rich payload filtering + self-host?
  → Qdrant (best filtering performance per benchmark)

Need built-in hybrid search (dense + BM25)?
  → Weaviate or Qdrant (with BM25 plugin)

>100M vectors + GPU budget?
  → Milvus or Weaviate with DiskANN

Research / offline batch only?
  → FAISS (IVF-PQ for memory efficiency)
```

**ANN index nuances:**
- **HNSW** — high recall (>95%), fast query, high memory (O(n·d·4 bytes)); sweet spot <50M vectors
- **IVF-PQ** — quantized centroids reduce memory 4–16×; recall ~85–92%; good for 50M–1B vectors
- **DiskANN** — SSD-resident graph; near-HNSW recall with fraction of RAM; Milvus and Weaviate support it

**Filtering:** Pre-filtering (index per segment) vs post-filtering (ANN then filter) tradeoff. Qdrant's payload indexes support pre-filtering without recall collapse — critical for multi-tenant RAG with ACL filters.

### Example / Tradeoff
In a production customer-support RAG system (~2M product chunks): started with **Pinecone** for speed of launch — pod-based s1 tier, cosine similarity, p99 query ~25ms. As metadata filter complexity grew (tenant × product-line × date range), migrated to **Qdrant** (self-hosted on k8s) because Pinecone's metadata filtering degraded recall and added cost. Qdrant's payload indexing kept recall@5 above 90% with compound filters at <30ms p99.

For dev/local testing: **Chroma** embedded mode for zero-infrastructure iteration, swapped for production store at deploy.

**Cost comparison (rough at 5M vectors, 1K QPS):**
- Pinecone p2.x2 pod: ~$700/mo
- Qdrant self-hosted (3-node, 16GB RAM each): ~$300/mo cloud compute + ops overhead
- pgvector on RDS r7g.2xlarge: ~$400/mo — only viable if Postgres already in stack

---

## Verbal script

**Opening (30s):**
"I've worked with several vector stores across different stages of production — Pinecone for managed simplicity, Qdrant for rich filtering at self-hosted scale, FAISS for offline batch research, and pgvector when we already had Postgres in the stack. My selection framework comes down to five axes: managed vs self-hosted, number of vectors, filtering complexity, latency SLO, and cost."

**Core explanation (2–3 min):**
"Let me walk through the main options.

Pinecone is the default managed choice — zero operational overhead, reliable p99 latency around 20–30ms, and a clean SDK. The tradeoff is cost at high QPS and limited control over the underlying index. I'd pick it when the team is small, we're moving fast, and ops complexity is a risk.

Qdrant is my go-to for self-hosted deployments where metadata filtering is complex — things like per-tenant ACL filters combined with date ranges. Qdrant's payload indexing does pre-filtering without sacrificing HNSW recall, which is a meaningful advantage over post-filtering approaches that can collapse recall to near-zero when filters are tight. It's written in Rust, so the per-query latency is excellent.

Weaviate makes sense when you want built-in hybrid search — it can fuse BM25 and dense retrieval natively without running a separate Elasticsearch instance. That's attractive if you want to reduce infrastructure components.

pgvector is interesting if you already have Postgres. For corpora under about five million vectors, the HNSW extension performs well. Beyond that, you start hitting sharding limits and you lose the memory efficiency you'd get from a purpose-built store.

FAISS I treat as a library, not a database — great for offline batch search or for building custom serving infrastructure, but it doesn't handle persistence, multi-tenancy, or filtering natively."

**Tradeoff / production angle (1 min):**
"The key mistake I see is choosing a vector DB based on brand name rather than the filtering model. HNSW recall degrades badly when you add metadata post-filters — if you're filtering to 5% of the corpus, ANN retrieves from 100% and then discards 95%, so effective recall tanks. Qdrant and Weaviate with native payload indexing solve this by partitioning the graph by filter values. That's the architectural decision that matters most for multi-tenant RAG.

Cost is the other lever: at 1M queries/day, the difference between a managed tier and self-hosted can be $5K–$10K/month. I always model that break-even before committing."

**Wrap-up (30s):**
"So my default stack: Pinecone for rapid iteration or when ops is a constraint, Qdrant for production self-hosted with complex filters, Weaviate when hybrid search is needed built-in, pgvector for Postgres-native shops under five million vectors. Happy to go deeper on any of these or on how ANN index choice — HNSW vs IVF-PQ vs DiskANN — affects the recall/cost tradeoff."

---

## Pitfalls

- **Mistake:** Naming only one tool ("I've used Pinecone") without discussing why or what tradeoffs it made — **Better:** Explain the selection criteria: managed vs self-hosted, filtering model, scale, cost; reference at least one alternative considered and rejected.
- **Mistake:** Treating all vector DBs as equivalent "just store embeddings" stores, ignoring filtering — **Better:** Explicitly discuss pre-filtering vs post-filtering and why compound metadata filters matter for multi-tenant or ACL-controlled RAG pipelines.
- **Mistake:** Recommending FAISS as a production vector database — **Better:** Clarify FAISS is a library with no persistence, filtering, or multi-tenancy; it's for offline batch or custom serving infrastructure only.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q12: Compare sparse vs dense retrieval. When use each?](02-012-compare-sparse-vs-dense-retrieval-when-use-each.md) | Prerequisite — vector DB hosts the dense index; retrieval strategy determines what you store |
| [Q23: How does ANN search work? HNSW indexing?](02-023-how-does-ann-search-work-hnsw-indexing.md) | Deep dive into the index algorithm underlying every vector DB |
| [Q17: What is hybrid search? When combine vector + BM25?](02-017-what-is-hybrid-search-when-combine-vector-bm25.md) | Follow-up — Weaviate/Qdrant built-in hybrid search vs separate Elasticsearch |

---

## One-liner recall

> Choose by five axes — managed vs self-hosted, vector count, filtering complexity, latency SLO, cost — defaulting to Pinecone for zero-ops, Qdrant for rich pre-filtering at self-hosted scale, and pgvector when Postgres is already in the stack under 5M vectors.
