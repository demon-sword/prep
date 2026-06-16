# Vocabulary mismatch (dense-only failing on keywords)

**Category:** 02-rag-systems
**Question #:** 030
**Source section:** §2 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
The interviewer wants to know whether you understand a critical production failure mode in RAG: dense embeddings are trained on semantic similarity but fail on exact-match queries involving product codes, model numbers, medical identifiers, legal citations, or rare proper nouns. This probes your retrieval debugging instinct and your knowledge of hybrid search as the standard fix.

### Trigger phrases
- "Your RAG returns wrong results when users search for a specific SKU / model number / drug name — how do you debug it?"
- "Dense retrieval is missing documents that clearly contain the answer — what's going on?"
- "When would you combine BM25 with vector search?"
- "What are the failure modes of embedding-based retrieval?"

### What it tests
Whether the candidate can diagnose the root cause of dense-only retrieval failures and knows to apply hybrid BM25+dense search with RRF fusion as the production fix.

---

## Answer

### Concept
Vocabulary mismatch occurs when a user's query contains exact tokens (product codes, acronyms, rare names, numerical identifiers) that dense bi-encoders map to semantically *similar* but not *identical* documents, while the exact-match documents containing those tokens rank low or disappear entirely. Dense embeddings trained via contrastive learning on sentence pairs optimise for semantic proximity, not term-level exact match.

### Mechanism
1. **Root cause — embedding space compression:** A bi-encoder like `text-embedding-3-large` represents a 512-token chunk as a single 1536-d vector. When rare tokens like `RTX-4090`, `ibuprofen 800mg`, or `ICD-10 Z87.891` appear infrequently in training data, their contribution to the embedding is dominated by surrounding context. A query for `"RTX-4090 VRAM specs"` may score high cosine similarity against a generic GPU overview doc rather than the chunk that literally says `"RTX 4090: 24 GB GDDR6X"`.

2. **BM25 fills the gap:** BM25 (Best Match 25) is a TF-IDF variant that scores by exact term frequency and inverse document frequency. Rare tokens that appear infrequently across the corpus get *high* IDF weight, so a document containing `RTX-4090` scores heavily when the query also contains that exact token.

3. **Hybrid search with RRF fusion:** The fix is to run both retrievers in parallel and merge ranked lists using Reciprocal Rank Fusion (RRF):
   ```
   RRF_score(d) = Σ_r  1 / (k + rank_r(d))    where k=60
   ```
   Elasticsearch 8.9+ supports this natively via `knn` + `query` clauses with `rrf` rank combiner. Qdrant 1.7+ supports hybrid queries. You can also implement it in application code by running both retrievers and fusing.

4. **Cross-encoder reranking layer:** After RRF fusion, pass the top-20–50 candidates to a cross-encoder (Cohere Rerank, BGE-Reranker) that does full query×document attention, which further corrects ordering.

5. **Metadata filter augmentation:** For structured identifiers (SKUs, IDs), store the token as a structured metadata field and apply an exact-match pre-filter before ANN search, bypassing embedding lookup entirely.

### Example / Tradeoff
**Production incident pattern:** An e-commerce RAG for product specs was returning GPU overviews instead of the exact spec sheet for `RTX-4090` because dense embeddings mapped the query to semantically similar GPU docs. Adding BM25 via Elasticsearch hybrid search with RRF improved Recall@5 from 61% to 79% on a golden dataset of 200 identifier-heavy queries. The BM25 component alone scored Recall@5 of 74% for exact-match queries while scoring only 52% on paraphrase-heavy natural language queries — illustrating complementarity.

**Tradeoff:** Hybrid search adds one Elasticsearch (or BM25 service) query in parallel with the ANN lookup, adding ~10–30ms latency at 99th percentile. This is worth it when >15% of queries contain identifiers. If latency is extremely tight, a query classifier can route exact-match queries to BM25-only and natural-language queries to dense-only, but this adds engineering complexity and a classification failure mode.

---

## Verbal script

**Opening (30s):**
"Vocabulary mismatch is one of the most common production failure modes I've seen in RAG systems. The symptom is that dense-only retrieval returns semantically related documents but completely misses the exact document containing the specific product code, drug name, or legal citation the user asked about. The root cause is that bi-encoders optimise for semantic proximity, not token-level exact match. My go-to fix is hybrid search — running BM25 in parallel with dense retrieval and fusing with RRF."

**Core explanation (2–3 min):**
"Let me break down why this happens. A dense bi-encoder compresses a 512-token chunk into a single fixed-size vector. For common words and concepts, this works great — 'how do I reset my password' maps close to 'forgot password help'. But rare tokens like `RTX-4090`, `ICD-10 Z87.891`, or `invoice #INV-20241107` appear infrequently in the embedding model's training data. Their signal gets diluted in the vector. So when a user searches for `RTX-4090 VRAM specs`, the embedding query vector lands near generic GPU content rather than the specific spec sheet.

BM25 solves this directly. It's an inverted index with TF-IDF weighting. Rare tokens get high IDF weight precisely *because* they're rare — so a document containing `RTX-4090` scores very high when the query also contains that token. The two retrievers are complementary: dense wins on paraphrases and natural language; BM25 wins on exact tokens.

The production fix is to run both in parallel and merge with Reciprocal Rank Fusion. RRF is simple: score each document as the sum of 1/(k + rank) across both ranked lists, where k=60 is a constant. This is now native in Elasticsearch 8.9+ via the `rrf` rank combiner. After fusion, I pipe the top-20–50 candidates through a cross-encoder like Cohere Rerank or BGE-Reranker for final ordering."

**Tradeoff / production angle (1 min):**
"The tradeoff is latency — you're now running two queries instead of one. In practice, since both run in parallel, the overhead is the slower of the two, typically the BM25 query at 10–30ms. That's usually acceptable. If you need to cut that, a query classifier can route identifier-heavy queries (regex or a small classifier detecting alphanumeric codes) to BM25-only, and paraphrase-heavy queries to dense-only. But that adds a classification failure mode, so I'd only do it if latency SLOs are very tight.

For highly structured identifiers like SKUs or IDs, I also store them as structured metadata fields and apply exact-match pre-filtering at the vector DB layer — Pinecone and Qdrant both support metadata filtering — which bypasses the embedding problem entirely for those fields."

**Wrap-up (30s):**
"To summarise: vocabulary mismatch is dense retrieval failing on exact tokens because bi-encoders optimise for semantic proximity. The fix is hybrid search — BM25 + dense in parallel, fused with RRF, optionally followed by cross-encoder reranking. Happy to go deeper on the RRF mechanics, query routing, or how to benchmark this on a golden dataset."

---

## Pitfalls

- **Mistake:** Saying "dense embeddings should handle everything because they capture meaning" without acknowledging that rare proper nouns and identifiers are underrepresented in embedding training data — **Better:** Explain that contrastive training optimises semantic proximity, not token-level exact match, and that rare tokens have weak signal in the embedding space.
- **Mistake:** Recommending only "use a better embedding model" as the fix — **Better:** A better embedding model helps marginally but doesn't solve the fundamental problem; hybrid search with BM25 is the standard production fix because BM25 is immune to vocabulary mismatch by design (it's an exact-match algorithm).
- **Mistake:** Not quantifying the improvement — **Better:** Cite a concrete benchmark: hybrid search typically improves Recall@5 by 15–20 percentage points on identifier-heavy query sets compared to dense-only; use a golden dataset of known exact-match queries to measure this before and after.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q17: What is hybrid search? When combine vector + BM25?](02-017-what-is-hybrid-search-when-combine-vector-bm25.md) | Core mechanism — hybrid search is the fix for vocabulary mismatch |
| [Q13: Common RAG failure points — how debug them?](02-013-common-rag-failure-points-how-debug-them.md) | Parent context — vocabulary mismatch is one of the 6 RAG failure modes |
| [Q24: Where do embeddings fail?](02-024-where-do-embeddings-fail-negation-temporal-reasoning-precisi.md) | Sibling failure mode — negation and temporal reasoning also break dense retrieval |

---

## One-liner recall

> Dense bi-encoders fail on rare tokens (SKUs, drug codes, legal citations) because contrastive training optimises semantic proximity, not exact match — fix with hybrid BM25+dense retrieval fused via RRF, boosting Recall@5 by ~15–20 points on identifier-heavy queries.
