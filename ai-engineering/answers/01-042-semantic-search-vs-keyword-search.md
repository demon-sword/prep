# Semantic search vs keyword search?

**Category:** 01-llm-fundamentals
**Question #:** 042
**Source section:** §1 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
Interviewers probe whether you understand retrieval at a systems level, not just surface definitions. In RAG pipelines, choosing the wrong retrieval method is the single most common cause of poor answer quality. This question surfaces whether you can reason about the failure modes of each approach and know when to combine them (hybrid search).

### Trigger phrases
- "When would you use semantic search over keyword search?"
- "Your RAG pipeline isn't finding relevant docs — walk me through how you'd debug retrieval."
- "Compare vector search and BM25."
- "What is hybrid search and when do you need it?"

### What it tests
Whether you can reason about retrieval tradeoffs — vocabulary mismatch vs semantic drift — and know that production systems almost always need hybrid search combining both.

---

## Answer

### Concept
Keyword search (BM25/TF-IDF) matches documents by exact or near-exact term overlap — it's fast, interpretable, and excels on precise terminology, product codes, and domain jargon. Semantic search (dense vector retrieval) matches by embedding-space proximity — it captures paraphrasing and conceptual similarity but can miss exact terms. Neither alone is sufficient for production RAG; hybrid search that scores both and fuses the rankings (Reciprocal Rank Fusion or learned reranker) is the standard answer.

### Mechanism

**Keyword search (BM25)**
- Builds an inverted index: term → (document IDs, TF-IDF-like weights)
- At query time, tokenizes the query, looks up each term in the index, scores documents by BM25 (term frequency, inverse document frequency, document length normalization)
- Returns top-k sorted by score
- Tools: Elasticsearch, OpenSearch, Lucene, Weaviate BM25 module

**Semantic search (dense retrieval)**
- Embed every document chunk with a bi-encoder (e.g., `text-embedding-3-large`, `BAAI/bge-large-en-v1.5`) at index time → store vectors in Pinecone, Qdrant, Weaviate, or FAISS with an HNSW index
- At query time, embed the query, run approximate nearest-neighbor (ANN) search via HNSW
- Returns top-k by cosine similarity
- Re-rank with a cross-encoder (e.g., `cross-encoder/ms-marco-MiniLM-L-12-v2`) for precision

**Hybrid search**
1. Run BM25 retrieval → get ranked list A (top-K, e.g., 50)
2. Run dense ANN retrieval → get ranked list B (top-K)
3. Fuse with Reciprocal Rank Fusion (RRF): `score = Σ 1/(k + rank_i)` where k=60
4. Optionally re-rank fused top-N with a cross-encoder
5. Feed top-5 to the LLM

### Example / Tradeoff

| Scenario | Use |
|----------|-----|
| "CPT code 99213" in a medical billing doc | BM25 wins — exact code must match |
| "What are the side effects of the blood thinner?" | Dense wins — "warfarin", "anticoagulant", "Coumadin" are synonyms |
| "Cancel policy 8675309 per section 12.3(b)" | Hybrid — exact policy number + section context |
| Low-latency requirement <50ms | BM25 alone or dense-only with quantized HNSW |
| RAGAS context_recall < 0.6 on exact-term queries | Add BM25 to fix vocabulary mismatch |

**Concrete failure modes:**
- **Dense-only failure:** Query "HTTP 429 error" → embedding model maps it near "rate limiting" semantically, but misses docs that literally say "429" because the number tokenizes poorly. BM25 finds it instantly.
- **BM25-only failure:** Query "plans for ending one's life" vs documents containing "suicide prevention resources" — zero term overlap, BM25 score = 0. Dense search retrieves it by meaning.
- **Negation failure (both):** "models that do NOT support streaming" — embeddings of negated queries are barely different from positive queries in embedding space; BM25 ignores the NOT. This is a hard problem that requires metadata filtering or structured queries.

---

## Verbal script

**Opening (30s):**
"Great question — this is one of the most important practical decisions in RAG system design. The short answer is: keyword search is exact-match and interpretable, semantic search is paraphrase-aware but can miss precise terms, and in production you almost always want hybrid. Let me walk through each and the tradeoffs."

**Core explanation (2–3 min):**
"Keyword search, specifically BM25, works by building an inverted index — each term maps to the documents that contain it, weighted by how often the term appears in that doc and how rare it is across all docs. It's extremely fast — milliseconds even at millions of documents — and it's unbeatable when the query uses the exact same words as the document. Think product SKUs, error codes, regulatory section numbers like '12 CFR 1026.4'. The failure mode is vocabulary mismatch: if the user asks 'plans for ending one's life' but your docs say 'suicide prevention', BM25 returns nothing because no terms match.

Semantic search solves that by encoding every document chunk into a dense vector using a bi-encoder — something like `text-embedding-3-large` from OpenAI or `bge-large-en-v1.5` from BAAI — and then doing approximate nearest-neighbor search via HNSW at query time. The query also gets embedded, and we find the closest document vectors by cosine similarity. This handles paraphrasing beautifully. But it has its own failure modes: short exact strings like 'HTTP 429' or 'ICD-10 J06.9' get buried in an embedding space dominated by semantic meaning, and negation is nearly invisible — 'no streaming support' looks almost identical to 'supports streaming' in embedding space.

So in production, the standard pattern is hybrid: run BM25 and dense retrieval in parallel, fuse the rankings using Reciprocal Rank Fusion — which is just `1 / (k + rank)` summed across both lists — and then optionally re-rank the top 20 fused results with a cross-encoder for precision. Elasticsearch and Weaviate both support this natively."

**Tradeoff / production angle (1 min):**
"The main tradeoffs are latency and complexity. BM25 alone is <10ms. Dense ANN with HNSW is maybe 20–50ms. Adding a cross-encoder re-rank adds another 50–200ms depending on the model size. At scale — say 10M documents — you also need to think about HNSW index memory, quantization (scalar or product quantization to shrink vectors), and sharding. Pinecone handles the scaling automatically; self-hosted FAISS requires you to manage it. One thing I always do: run RAGAS metrics — specifically context_recall and context_precision — on a golden test set for both BM25-only and dense-only, then show the hybrid improvement before choosing the architecture."

**Wrap-up (30s):**
"To summarize: BM25 for exact term matching and low latency, dense for semantic paraphrasing, hybrid with RRF for production. The specific failure modes — vocab mismatch for BM25, exact-string misses and negation blindness for dense — are what drive the hybrid decision. Happy to go deeper on the re-ranking layer or how I'd tune the BM25 weight in the fusion if that's useful."

---

## Pitfalls

- **Mistake:** Saying "semantic search is better than keyword search" without qualification — **Better:** Explain that each has distinct failure modes (vocabulary mismatch for BM25, exact-string/negation failures for dense) and that production systems use hybrid; mention BM25's unbeatable latency advantage for exact-match use cases.
- **Mistake:** Describing hybrid search as "running both and picking whichever scores higher" — **Better:** Explain Reciprocal Rank Fusion specifically: `score = 1/(k + rank)` summed across ranked lists, which normalizes incompatible score scales between BM25 (raw BM25 scores) and cosine similarity (0–1).
- **Mistake:** Not mentioning the re-ranking layer when asked about retrieval quality — **Better:** Note that even after hybrid retrieval, a cross-encoder re-ranker (e.g., `ms-marco-MiniLM-L-12-v2`) is standard for precision on the top-N, and that the bi-encoder/cross-encoder distinction matters (bi-encoder is fast but approximate; cross-encoder attends to both query and doc jointly for much higher accuracy at higher latency).

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q14: How does chunking happen?](01-014-how-does-chunking-happen.md) | Upstream: chunk strategy affects what BM25 and dense search can retrieve |
| [Q13: What are embeddings?](01-013-what-are-embeddings.md) | Prerequisite: dense retrieval is built on embeddings |
| [What is re-ranking? Cross-encoder vs bi-encoder?](02-014-what-is-re-ranking-cross-encoder-vs-bi-encoder.md) | Follow-up: re-ranking sits on top of hybrid retrieval to boost precision |

---

## One-liner recall

> Keyword search (BM25) matches exact terms and is unbeatable on jargon/codes; semantic search (dense vectors + HNSW) handles paraphrasing but fails on exact strings and negation; production RAG uses hybrid — RRF-fused BM25 + dense — followed by cross-encoder re-ranking.
