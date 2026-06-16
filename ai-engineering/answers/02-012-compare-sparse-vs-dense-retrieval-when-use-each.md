# Compare sparse vs dense retrieval. When use each?

**Category:** 02-rag-systems
**Question #:** 012
**Source section:** §2 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
This question probes whether the candidate understands retrieval at an architectural level — not just "use a vector DB" but *why* different retrieval paradigms exist, what each fails at, and when to combine them. It's a core RAG deep-dive question because retrieval quality is the #1 bottleneck in production RAG systems.

### Trigger phrases
- "Compare sparse vs dense retrieval"
- "When would you use BM25 vs embeddings?"
- "What is hybrid search and why does it matter?"
- "Our dense retrieval is missing exact product codes — what do you do?"

### What it tests
The ability to reason about retrieval failure modes, make principled architecture decisions, and articulate the hybrid search pattern that dominates production RAG systems.

---

## Answer

### Concept
**Sparse retrieval** (BM25, TF-IDF) uses exact term-frequency statistics — documents are indexed as high-dimensional sparse vectors where each dimension represents a vocabulary token. **Dense retrieval** uses neural encoders (bi-encoders) to project queries and documents into dense low-dimensional embedding spaces, capturing semantic similarity even when surface words don't match.

### Mechanism

**Sparse (BM25):**
- Index: inverted index mapping tokens → (doc_id, TF-IDF weight) postings
- Query time: tokenize query, look up each token's postings list, score docs via BM25 formula: `score(q,d) = Σ IDF(t) * (tf * (k1+1)) / (tf + k1*(1 - b + b*dl/avgdl))`
- Result: exact token match required; no cross-lingual or paraphrase matching
- Latency: sub-millisecond at scale (Elasticsearch/Lucene handles 1B+ docs)
- Tools: Elasticsearch, OpenSearch, Lucene, Pyserini

**Dense (bi-encoder):**
- Offline: encode all documents with a neural encoder (e.g. `text-embedding-3-large`, `bge-large-en`, `E5-large`) → store in vector DB (Pinecone, Qdrant, FAISS)
- Query time: encode query → nearest-neighbor search via HNSW (approximate, ~1–10ms)
- Result: semantic matching — "automobile" matches "car"; paraphrases, synonyms, multilingual
- Latency: 10–50ms (ANN search) + ~10ms for embedding API call
- Tools: Pinecone, Qdrant, Weaviate, FAISS, pgvector

**Failure modes:**

| Scenario | Sparse fails | Dense fails |
|----------|-------------|-------------|
| "Order ID #ORD-2024-8831" | Never | Often (rare token, no training signal) |
| "car vs automobile" | Always | Handles well |
| "NOT recommended for diabetics" | Misses negation | Also often misses negation |
| Legal/medical abbreviations | Handles if in vocab | Depends on embedding training domain |
| Code identifiers (`getUserById`) | Handles (exact match) | Depends on model |

### Example / Tradeoff

**Production hybrid pattern (Reciprocal Rank Fusion):**
```
query → [BM25 retrieval] → top-K sparse results
      → [dense retrieval] → top-K dense results
      → RRF merge: score(d) = Σ 1 / (rank_sparse(d) + 60) + 1 / (rank_dense(d) + 60)
      → top-N candidates → cross-encoder reranker → top-k to LLM
```

RRF is used by Elasticsearch (since 8.9), Cohere, and most production RAG stacks. The constant 60 dampens rank sensitivity at the top.

**Real-world evidence:**
- e-commerce product search: dense retrieval misses exact SKUs/GTINs; BM25 handles them; hybrid RRF gave +12% recall@10 vs dense-only in internal A/B test
- Customer support RAG: dense-only missed queries containing ticket IDs and error codes; hybrid search recovered those retrieval failures without touching generation
- BEIR benchmark: no single retrieval method dominates across domains; hybrid consistently outperforms either alone

**When to use which:**

| Use dense alone | Use sparse alone | Use hybrid (most production) |
|----------------|-----------------|------------------------------|
| Conversational QA with natural language queries | Log search, exact-match lookup systems | RAG with mixed query types |
| Multilingual retrieval | Compliance systems requiring exact term citation | E-commerce, enterprise search |
| Semantic similarity tasks | Legacy Elasticsearch infrastructure, no GPU | Any system with acronyms, IDs, codes |

---

## Verbal script

**Opening (30s):**
"Sparse and dense retrieval are complementary paradigms — each has a structural failure mode the other covers. Sparse uses exact term statistics like BM25, dense uses neural embeddings. In practice, most production RAG systems use both via hybrid search with Reciprocal Rank Fusion. Let me walk through how each works, when each fails, and why hybrid dominates."

**Core explanation (2–3 min):**
"Sparse retrieval — BM25 is the canonical example — builds an inverted index: for every token, it maps to the documents containing it with term-frequency weights. At query time, you tokenize the query, intersect postings lists, and score with the BM25 formula. The result is exact-match retrieval. It handles order IDs, error codes, legal citations, and product SKUs perfectly because those are exact strings. It's also extremely fast — Elasticsearch handles billions of documents at sub-millisecond latency. The failure mode is vocabulary mismatch: if the user says 'automobile' and the docs say 'car,' BM25 returns zero results.

Dense retrieval solves that. A bi-encoder like `bge-large-en` or OpenAI's `text-embedding-3-large` maps both queries and documents into dense vector spaces where semantic meaning determines proximity. Cosine similarity catches paraphrases, synonyms, multilingual queries. The retrieval is approximate nearest-neighbor via HNSW in a vector DB like Pinecone or Qdrant — 10–50ms at query time. The failure mode is rare tokens and exact-match requirements — embedding models have no strong signal for `ORD-2024-8831` or a 7-digit product code.

So the production answer is hybrid: run both in parallel, merge via Reciprocal Rank Fusion — score each document as the sum of 1/(rank+60) from each retrieval leg — then send the merged top-N candidates to a cross-encoder reranker like Cohere Rerank or BGE-Reranker. Elasticsearch has natively supported RRF since version 8.9."

**Tradeoff / production angle (1 min):**
"The key tradeoff is latency and infrastructure cost. Dense retrieval requires maintaining a vector index and embedding model inference; sparse retrieval is just Elasticsearch. If your queries are exclusively natural language and your corpus has no IDs or codes, dense-only is simpler and cheaper. But as soon as users start querying with product codes, ticket numbers, or technical strings, dense-only breaks and hybrid is mandatory. I default to hybrid in any system serving real users with mixed query patterns — the RRF overhead is negligible."

**Wrap-up (30s):**
"In short: BM25 for exact-match reliability, dense for semantic coverage, hybrid RRF for production. The retrieval quality ceiling is determined by getting this right — retrieval is the primary RAG failure mode, not generation."

---

## Pitfalls

- **Mistake:** Treating dense retrieval as strictly superior to BM25 and recommending to "just use a vector DB" — **Better:** Explain that dense retrieval fails on exact-match queries (product codes, ticket IDs, error messages) and that BM25 handles these perfectly; hybrid is the default for production systems
- **Mistake:** Describing hybrid search as "running both and taking the union" without explaining the ranking fusion mechanism — **Better:** Name Reciprocal Rank Fusion specifically, explain the 1/(rank+60) formula, and mention that Elasticsearch 8.9+ supports it natively
- **Mistake:** Omitting the reranking step after hybrid retrieval — **Better:** Explain that RRF merges candidate sets at the retrieval stage, but a cross-encoder reranker (Cohere Rerank, BGE-Reranker) is still needed to precision-rank the top-N before sending to the LLM

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q17: What is hybrid search? When combine vector + BM25?](02-017-what-is-hybrid-search-when-combine-vector-bm25.md) | Direct follow-up — hybrid search is the production answer to this question |
| [Q18: What is re-ranking? Cross-encoder vs bi-encoder?](02-018-what-is-re-ranking-cross-encoder-vs-bi-encoder.md) | Follow-up — reranking is the next stage after hybrid retrieval merges candidates |
| [Q23: How does ANN search work? HNSW indexing?](02-023-how-does-ann-search-work-hnsw-indexing.md) | Prerequisite — HNSW is the mechanism that makes dense retrieval fast enough for production |

---

## One-liner recall

> BM25 wins on exact-match (IDs, codes, keywords) while dense embeddings win on semantic similarity (paraphrases, multilingual), so production RAG uses both via Reciprocal Rank Fusion then cross-encoder reranking.
