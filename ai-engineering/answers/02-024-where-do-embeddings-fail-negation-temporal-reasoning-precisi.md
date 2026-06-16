# Where do embeddings fail? Negation, temporal reasoning, precision requirements.

**Category:** 02-rag-systems
**Question #:** 024
**Source section:** §2 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
The interviewer is probing whether you understand the fundamental limits of dense vector retrieval — not just how it works when it works, but when it silently fails. This is a production-depth question: weak candidates describe embedding similarity correctly but can't explain why a well-built RAG system still returns the wrong chunks for certain query classes. Strong candidates name specific failure modes, explain the linguistic/geometric root cause, and describe the mitigation (hybrid search, structured filters, re-ranking).

### Trigger phrases
- "Where does semantic search break down?"
- "When would you NOT rely on embedding-based retrieval?"
- "You have a RAG system with good retrieval accuracy overall but certain queries always fail — what's wrong?"
- "Why might a user search for 'no side effects' and get documents about side effects?"

### What it tests
Depth of understanding of dense retrieval failure modes and the ability to prescribe targeted mitigations (BM25 hybrid, metadata filters, cross-encoder reranking) rather than defaulting to "just tune the embedding model."

---

## Answer

### Concept
Embeddings compress an entire passage's meaning into a fixed-length vector by training on co-occurrence patterns — they capture *topic similarity* well but are poor at encoding *logical operators* (negation, conditionals), *exact values* (dates, IDs, amounts), and *temporal ordering*. A query that semantically inverts a document's claim ("no known drug interactions") can retrieve the very document it should exclude, because the embedding space places "drug interactions" and "no drug interactions" near each other.

### Mechanism
**1. Negation failure:** Encoders like `text-embedding-3-large` or `bge-large-en-v1.5` are trained with contrastive objectives on passage pairs; negation is syntactically rare enough in training data that "X" and "not X" end up close in embedding space. Cosine similarity between `"warfarin has no drug interactions"` and `"warfarin has many drug interactions"` is often > 0.85 — the model focuses on the shared noun phrase, ignoring the polarity marker.

**2. Temporal reasoning failure:** Queries like "latest policy as of Q3 2024" or "what changed after the March update" require the model to encode *relative time* semantics. Bi-encoder embeddings have no temporal axis — they represent static semantics. A 2022 policy doc and a 2024 policy doc for the same topic may be more similar to each other (~0.92 cosine) than either is to the query (~0.80), so the wrong version is retrieved.

**3. Precision / exact-match failure:** Part numbers (`SKU-7841-B`), IDs, codes, legal citations (`17 C.F.R. § 240.10b-5`), and proper nouns with rare surface forms are tokenized into fragments by BPE and poorly represented in embedding space. BM25 trivially matches exact strings; HNSW-indexed dense search may rank them below semantically-adjacent but wrong results.

**4. Multi-hop / compositional queries:** "Find contracts signed by Alice that mention exclusivity AND have a renewal clause before 2025" requires three conjunctive conditions. Embeddings collapse all of that into one point — retrieval will return documents satisfying subsets of the conditions, not necessarily the intersection.

### Example / Tradeoff
**Production incident pattern:** An e-commerce RAG built on `text-embedding-ada-002` with Pinecone retrieval showed Recall@5 of 74% overall, but dropped to 31% on product-code queries (e.g., "SKU-4421-X availability"). Root cause: BPE fragments `SKU-4421-X` into `SK`, `U`, `-`, `44`, `21`, `-`, `X` — 7 tokens, each common, so the embedding looks like general retail vocabulary. Fix: **hybrid BM25+dense with RRF** (Elasticsearch 8.9+) — BM25 handles exact SKU match, dense handles semantic intent; Recall@5 on product codes jumped to 78%.

**Negation mitigation:** Add a **cross-encoder re-ranking pass** (Cohere Rerank, `ms-marco-MiniLM-L-12-v2`) over the top-20 dense candidates — cross-encoders read query + document jointly and reliably detect polarity mismatches. Also consider **structured metadata filters**: if "no side effects" can be rewritten as `side_effects_count = 0` from document metadata, apply a pre-filter before dense retrieval.

**Temporal mitigation:** Store `effective_date` as a metadata field on every chunk; apply a hard date-range filter at retrieval time rather than relying on the embedding to encode recency. For Pinecone, this is a metadata filter: `{"effective_date": {"$gte": "2024-01-01"}}`.

---

## Verbal script

**Opening (30s):**
"Embeddings are powerful but they have well-known blind spots — negation, exact-match precision, and temporal reasoning are the top three that trip up production RAG systems. I'd organize my answer around why each fails at the representation level, then what you do about it."

**Core explanation (2–3 min):**
"Let me take them one at a time. First, **negation**: bi-encoder models like `bge-large` or OpenAI's `text-embedding-3-large` are trained with contrastive objectives that pull semantically related passages together. 'Drug interactions exist' and 'no drug interactions' share all the same keywords, so they end up within high cosine similarity — often above 0.85. The polarity word 'no' is too short and too common to move the embedding meaningfully. In practice, I've seen a medical RAG retrieve the exact wrong section because of this.

Second, **temporal / exact-value precision**: embeddings have no time axis. A query for 'the Q3 2024 pricing policy' retrieves the 2023 version because they're topically identical — high semantic similarity, wrong version. And for part numbers or legal citations — BPE tokenization fragments them into common subword pieces, so the embedding looks like generic text. BM25 trivially handles these; dense retrieval does not.

Third, **multi-hop conjunction**: 'contracts signed by Alice with an exclusivity clause before 2025' requires satisfying three conditions simultaneously. Dense retrieval collapses all of that into one cosine distance and returns documents that partially satisfy the query."

**Tradeoff / production angle (1 min):**
"The mitigations are targeted. For exact-match failures, use hybrid BM25 + dense with RRF — this is table stakes for any production RAG. For negation and semantic mismatch, add a cross-encoder re-ranking pass over the top 20 candidates — cross-encoders read query and document jointly and reliably catch polarity mismatches. For temporal and structural conditions, store structured metadata at ingestion time — `effective_date`, `sku`, `author` — and push those as hard filters *before* dense retrieval hits the ANN index. The key insight is: don't ask the embedding to encode things it was never trained to encode."

**Wrap-up (30s):**
"So embeddings are fantastic for fuzzy semantic recall but fail on polarity, exact values, and time. The fix is layered: hybrid search for recall, metadata filters for structure, and cross-encoder reranking to catch what dense retrieval gets wrong. Happy to go deeper on any of those mitigations."

---

## Pitfalls

- **Mistake:** Saying "embeddings sometimes get confused" without naming specific failure classes (negation, temporal, exact-match) — **Better:** Name the three failure modes with root causes: contrastive training ignores polarity; BPE fragments rare strings; embeddings have no time axis.
- **Mistake:** Proposing "fine-tune the embedding model" as the primary fix — **Better:** Fine-tuning helps domain vocabulary but does NOT fix negation or temporal reasoning at the architectural level; the correct mitigations are hybrid search (BM25), metadata filters, and cross-encoder reranking.
- **Mistake:** Ignoring multi-hop / conjunctive queries as a failure mode — **Better:** Note that embeddings compress all conditions into one vector; conjunctive queries need structured filtering or decomposed retrieval (query decomposition + intersection).

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q12: Compare sparse vs dense retrieval. When use each?](02-012-compare-sparse-vs-dense-retrieval-when-use-each.md) | BM25 as the fix for exact-match embedding failures |
| [Q17: What is hybrid search? When combine vector + BM25?](02-017-what-is-hybrid-search-when-combine-vector-bm25.md) | Hybrid search is the primary mitigation for embedding precision failures |
| [Q18: What is re-ranking? Cross-encoder vs bi-encoder?](02-018-what-is-re-ranking-cross-encoder-vs-bi-encoder.md) | Cross-encoder reranking fixes negation and polarity failures that bi-encoders miss |

---

## One-liner recall

> Embeddings fail on negation (polarity ignored by contrastive training), temporal/exact-match precision (BPE fragments rare strings, no time axis), and conjunctive queries (single vector can't enforce multiple conditions) — fix with BM25 hybrid search, metadata filters, and cross-encoder reranking.
