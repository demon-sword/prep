# What are embeddings, and how are they used in RAG?

**Category:** 01-llm-fundamentals
**Question #:** 041
**Source section:** §1 (Beginner staples) in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
The interviewer is checking whether the candidate understands the foundational data structure that makes semantic search (and therefore RAG) work — and whether they can explain it at a production level: model choice, similarity metrics, ANN indexing, and where embeddings break down.

### Trigger phrases
- "What are embeddings, and how are they used in RAG?"
- "How does vector search work under the hood?"
- "Why do we need a vector database for RAG?"

### What it tests
Whether the candidate can explain dense vector representations end-to-end — from encoder output through ANN indexing to retrieval — and knows the failure modes in a real RAG pipeline.

---

## Answer

### Concept
An embedding is a dense, fixed-length floating-point vector (typically 768–3072 dimensions) produced by an encoder model that maps a piece of text into a geometric space where semantic similarity corresponds to vector proximity. Unlike sparse term-frequency vectors (TF-IDF, BM25), embeddings capture meaning: "car" and "automobile" land near each other even though they share no tokens.

### Mechanism
**Embedding generation:**
1. Text (query or document chunk) is tokenized and passed through an encoder — e.g., `text-embedding-3-large` (OpenAI), `all-MiniLM-L6-v2` (sentence-transformers), `bge-large-en-v1.5` (BAAI), or `jina-embeddings-v3`.
2. The encoder's final-layer representation (mean-pooled or CLS-token) is L2-normalized to produce a unit vector.
3. Cosine similarity (= dot product of unit vectors) is the standard similarity metric; dot product is faster and equivalent when vectors are normalized.

**Indexing:**
- Vectors are stored in a vector database (Pinecone, Weaviate, Qdrant, pgvector, FAISS) using an Approximate Nearest Neighbor (ANN) index — typically HNSW (Hierarchical Navigable Small World) for sub-10ms recall@10 searches on millions of vectors.
- HNSW builds a multi-layer proximity graph; query traverses the graph to find neighbors without scanning every vector (O(log N) typical path length).

**RAG retrieval loop:**
1. User query → same embedding model → query vector.
2. ANN search returns top-K chunks (k=5–20) by cosine similarity.
3. Optional re-rank step (cross-encoder, e.g., `ms-marco-MiniLM-L-12-v2`) re-scores top-K with richer context.
4. Selected chunks are injected into the LLM prompt as context ("documents").

### Example / Tradeoff
**Production setup:** A legal-document assistant uses `text-embedding-3-large` (3072-d, $0.13/M tokens), chunks at 512 tokens with 10% overlap, indexes into Pinecone serverless. Hybrid search — dense HNSW plus BM25 — improves recall@5 from 61% to 74% on the golden test set because BM25 catches exact statute citations that dense embeddings miss.

**Key tradeoffs:**
| Dimension | Dense (embedding) | Sparse (BM25) |
|-----------|-------------------|---------------|
| Semantic recall | High | Low |
| Exact-match / keyword | Low | High |
| Domain OOV | Fails on rare terms | Robust |
| Latency | ~5–10ms ANN | ~2–5ms |
| Best for | Conversational queries | Legal/medical citations |

**Failure modes:**
- **Negation:** "no side effects" and "side effects" may embed close together — models don't reliably encode logical negation.
- **Temporal reasoning:** "latest policy" vs "previous policy" — embeddings capture topic, not time.
- **Precision requirements:** exact IDs, codes, or numbers (e.g., ICD-10 "J45.901") fail; use BM25 or metadata filters instead.
- **Embedding drift:** if you update the embedding model, all stored vectors must be re-indexed — a silent recall regression otherwise.

---

## Verbal script

**Opening (30s):**
"Embeddings are the core data structure that makes semantic retrieval possible in RAG. I'd describe them as dense numeric fingerprints of meaning — a fixed-size vector where documents with similar meaning end up geometrically close, so you can find relevant context with a distance search rather than keyword matching."

**Core explanation (2–3 min):**
"Here's how the RAG pipeline actually uses them. At index time, you split your documents into chunks — say 512 tokens with overlap — and pass each chunk through an encoder model like `text-embedding-3-large` or `bge-large-en-v1.5`. The encoder outputs a vector, typically 768 to 3072 floats, which you L2-normalize and store in a vector database like Pinecone or Qdrant. The index is usually HNSW — a proximity graph structure that lets you find approximate nearest neighbors in sub-10 milliseconds even over millions of vectors.

At query time, you embed the user's question with the *same* model — this is important, you can't mix embedding models — get a query vector, and run an ANN search to retrieve the top-K most similar chunks. Those chunks go into the LLM's context window. Often I add a cross-encoder re-ranking step after ANN retrieval to re-score the top-20 with richer pairwise context, then send top-5 to the LLM."

**Tradeoff / production angle (1 min):**
"The key production failure I've seen is relying on dense embeddings alone. Dense search is excellent for semantic similarity but breaks on exact-match queries — things like statute citations, model numbers, or ICD-10 codes. BM25 sparse retrieval handles those well. So in production I'd almost always use hybrid search: dense + BM25 combined with RRF (Reciprocal Rank Fusion), which typically lifts recall@5 by 10–15 points on heterogeneous corpora. Another gotcha is embedding drift: if you switch embedding models mid-deployment, your existing index silently returns bad results because the vector spaces don't align. You need to re-embed everything and run your golden-set eval before swapping."

**Wrap-up (30s):**
"So in short: embeddings map meaning to geometry, HNSW indexes make the search fast, and hybrid search with re-ranking is how you make it reliable in production. Happy to go deeper on any of those layers — the ANN index internals, re-ranking architectures, or failure mode debugging."

---

## Pitfalls

- **Mistake:** Describing embeddings as just "a way to represent text as numbers" without explaining the geometric property (similarity = proximity) or how that enables retrieval — **Better:** Explain that the encoder is trained so semantically similar texts land near each other, which is the entire basis for ANN search; cosine/dot-product similarity is the operational measure.
- **Mistake:** Saying "just embed the query and do a vector search" without mentioning ANN indexing (HNSW/IVF) — implying a brute-force scan — **Better:** Name the index structure, explain why exact search doesn't scale past ~100K vectors, and mention Pinecone/Qdrant/pgvector as production-grade options.
- **Mistake:** Ignoring embedding model choice and assuming one-size-fits-all — **Better:** Mention that model choice (general vs. domain-specific), output dimension, and max sequence length all affect recall; benchmark on your task's golden set before committing.
- **Mistake:** Not mentioning failure modes (negation, exact-match, temporal) — **Better:** Proactively flag where dense embeddings fail and why hybrid search (dense + BM25) is the production-standard fix.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q13: What are embeddings?](01-013-what-are-embeddings.md) | Core concept (this Q is the RAG-specific version; Q13 is the general definition) |
| [Q14: How does chunking happen?](01-014-how-does-chunking-happen.md) | Prerequisite — chunks are what get embedded |
| [Q42: Semantic search vs keyword search?](01-042-semantic-search-vs-keyword-search.md) | Direct follow-up — when dense embeddings beat BM25 and vice versa |

---

## One-liner recall

> Embeddings are dense vectors where semantic similarity = geometric proximity; RAG uses an encoder to embed query and chunks, HNSW ANN search to retrieve top-K candidates, and (optionally) a cross-encoder re-ranker before injecting context into the LLM — with hybrid BM25+dense search covering exact-match failure modes.
