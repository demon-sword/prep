# What is hybrid search? When combine vector + BM25?

**Category:** 02-rag-systems
**Question #:** 017
**Source section:** §2 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
This is a depth probe on RAG retrieval architecture. The interviewer wants to know whether you understand *why* neither pure dense nor pure sparse retrieval is sufficient in production — and whether you've actually debugged the failure modes that make hybrid necessary. It tests practical experience over textbook knowledge.

### Trigger phrases
- "How would you improve retrieval quality in your RAG system?"
- "When would you combine vector search with BM25?"
- "Walk me through your retrieval strategy."
- "What is hybrid search and why does it matter?"

### What it tests
Whether the candidate understands the complementary failure modes of dense and sparse retrieval and can articulate when and how to fuse them in production.

---

## Answer

### Concept
Hybrid search combines **sparse retrieval** (BM25 / keyword-based inverted index) with **dense retrieval** (bi-encoder embeddings + ANN index like HNSW) into a single ranked list. The key insight is that each approach has orthogonal failure modes: dense search misses exact keywords and product codes; sparse search misses paraphrase and semantic equivalence. Combining them covers the union of both signal types.

### Mechanism
1. **Two parallel retrieval legs:**
   - **Sparse (BM25):** Elasticsearch/OpenSearch inverted index scores documents by TF-IDF term overlap. Excellent for exact strings: product SKUs (`B08N5M7S6K`), legal citations (`42 U.S.C. § 1983`), medical codes (`ICD-10: J18.9`).
   - **Dense (bi-encoder):** Query and document embeddings (e.g. `text-embedding-3-small`, `bge-large-en`) retrieved via HNSW index (Pinecone, Qdrant, Weaviate). Excellent for paraphrase, synonymy, and conceptual similarity.

2. **Fusion — Reciprocal Rank Fusion (RRF):**
   - Each leg returns top-K results with their rank positions.
   - RRF score: `score(d) = Σ 1 / (k + rank_i(d))` where k=60 by default.
   - Documents appearing in both lists are promoted; outliers from either list are preserved.
   - RRF is rank-based (no score normalization needed) — avoids the apples-to-oranges problem of merging BM25 raw scores with cosine similarities.

3. **Optional reranking:** After RRF produces a top-20–50 merged list, a cross-encoder reranker (Cohere Rerank, `bge-reranker-large`) re-scores with full query-document attention, producing the final top-5–10 for generation.

4. **Production implementations:**
   - **Elasticsearch 8.9+** has native `knn` + `match` hybrid query with RRF built-in.
   - **Qdrant** supports sparse+dense hybrid natively via `sparse_vectors` field.
   - **LangChain `EnsembleRetriever`** orchestrates BM25 + Chroma/Pinecone with configurable weights.

### Example / Tradeoff
**Before hybrid:** A product search RAG using dense-only retrieval returned semantically similar products but missed exact SKU lookups — users searching "B08N5M7S6K" got wrong items. Recall@5 was 61%.

**After hybrid (BM25 + dense + RRF + Cohere rerank):** SKU lookups resolved exactly via BM25; semantic queries still handled by dense. Recall@5 jumped to 79%, NDCG@5 from 0.58 to 0.74.

**Cost tradeoff:** Hybrid adds ~5–10ms latency for the BM25 leg. Cross-encoder reranking on top-50 adds 50–150ms. At 1M queries/day, the reranker cost (Cohere Rerank ~$1/1K calls → ~$1K/day) is the main budget line; limit reranking to queries where the fusion score spread is narrow.

---

## Verbal script

**Opening (30s):**
"Hybrid search is one of my go-to architectural defaults for RAG retrieval. The core insight is that dense and sparse retrieval have complementary failure modes — dense alone misses exact keywords, sparse alone misses paraphrase — so combining them gives you the union of both signal types. Let me walk through how it works and when I'd reach for it."

**Core explanation (2–3 min):**
"I run two retrieval legs in parallel. The sparse leg uses BM25 — an inverted index in Elasticsearch or OpenSearch — which excels at exact string matching: product codes, legal citations, medical abbreviations like 'ICD-10 J18.9'. The dense leg uses a bi-encoder like `bge-large-en` or OpenAI's `text-embedding-3-small` with an HNSW index in Pinecone or Qdrant — great for paraphrase and conceptual queries.

To merge the two ranked lists I use Reciprocal Rank Fusion. RRF scores each document as the sum of `1/(k + rank)` across all lists, where k is typically 60. The key advantage of RRF over weighted score fusion is that it's rank-based — I don't have to normalize BM25 scores against cosine similarities, which would be apples and oranges. Documents appearing in both lists get a natural boost.

After RRF I've got a merged top-30 or so. For high-stakes queries, I'll add a cross-encoder reranker — Cohere Rerank or `bge-reranker-large` — which reads the full query and each document together and re-scores with much higher accuracy. That final list of top-5 or top-10 goes to the LLM."

**Tradeoff / production angle (1 min):**
"The main cost is latency — BM25 adds 5–10ms, reranking adds 50–150ms per query. At scale, I'll limit reranking to queries where the RRF score spread is tight (the retrieval is uncertain), and skip it when one document dominates. Elasticsearch 8.9+ has native hybrid query with RRF built-in, so in practice it's not that much extra plumbing. The bigger gotcha is that BM25 and dense indexes need to stay in sync — if one index goes stale, the fusion degrades silently. I'd set up CDC-driven updates for both in tandem."

**Wrap-up (30s):**
"So the short answer: use hybrid search as your default for production RAG. Pure dense is wrong for anything with exact keywords; pure sparse is wrong for semantic queries. RRF fusion is cheap, rank-normalization-free, and battle-tested. Happy to go deeper on reranking or the HNSW internals."

---

## Pitfalls

- **Mistake:** Describing hybrid search as "just averaging the scores from BM25 and cosine similarity" — **Better:** Explain that raw score scales are incompatible (BM25 can be 0–20+, cosine is 0–1) and that RRF is the standard fusion because it operates on ranks, eliminating normalization entirely.
- **Mistake:** Saying "I'd use hybrid search always" without naming the concrete failure mode it solves — **Better:** Lead with the failure mode: "Dense-only fails on exact keywords like SKUs and codes; sparse-only fails on paraphrase — hybrid covers both" then explain the mechanism.
- **Mistake:** Forgetting that both indexes must stay in sync — **Better:** Mention that embedding drift or stale BM25 indexes silently degrade fusion quality; both pipelines need the same CDC-driven update trigger.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q12: Compare sparse vs dense retrieval. When use each?](02-012-compare-sparse-vs-dense-retrieval-when-use-each.md) | Prerequisite — explains the individual failure modes that make hybrid necessary |
| [Q18: What is re-ranking? Cross-encoder vs bi-encoder?](02-018-what-is-re-ranking-cross-encoder-vs-bi-encoder.md) | Natural follow-up — reranking is the layer applied after hybrid fusion |
| [Q13: Common RAG failure points — how debug them?](02-013-common-rag-failure-points-how-debug-them.md) | Same domain — vocabulary mismatch is one of the 6 failure modes hybrid search directly fixes |

---

## One-liner recall

> Hybrid search fuses BM25 (exact keyword recall) + dense bi-encoder (semantic recall) via Reciprocal Rank Fusion, then optionally reranks the merged top-K with a cross-encoder — covering the complementary failure modes of each retrieval method alone.
