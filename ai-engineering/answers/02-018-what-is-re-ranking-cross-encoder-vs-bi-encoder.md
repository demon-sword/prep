# What is re-ranking? Cross-encoder vs bi-encoder?

**Category:** 02-rag-systems
**Question #:** 018
**Source section:** §2 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
Re-ranking sits at the intersection of retrieval quality and latency/cost tradeoffs — a hallmark senior RAG topic. Interviewers want to know whether you understand *why* a two-stage pipeline outperforms a single retrieval pass, and whether you can articulate the architectural cost of running a cross-encoder at scale versus the cheaper bi-encoder shortcut.

### Trigger phrases
- "How would you improve retrieval precision in your RAG system?"
- "What is re-ranking and why do you need it?"
- "Cross-encoder vs bi-encoder — when use each?"
- "Our top-k results are relevant but the answer is never in position 1 — how do you fix that?"

### What it tests
Knowledge of the two-stage retrieve-then-rerank architecture, the accuracy/latency tradeoff between bi-encoders and cross-encoders, and when to apply each in production.

---

## Answer

### Concept
Re-ranking is a second-pass scoring step that takes the top-N candidates returned by a fast first-stage retriever (bi-encoder or BM25) and re-scores them using a slower but more accurate model (cross-encoder), then reorders before passing the top-k to the LLM. The first stage optimizes for *recall* (don't miss relevant docs); the second stage optimizes for *precision* (surface the best ones first).

### Mechanism

**Stage 1 — Bi-encoder retrieval (fast, approximate):**
- A bi-encoder encodes query and document *independently* into dense vectors: `q = E(query)`, `d = E(doc)`.
- Similarity is computed as cosine or dot product: `score = q · d`.
- Documents are pre-indexed (HNSW in Pinecone, Qdrant, or FAISS); at query time only the query is encoded → O(log N) ANN lookup.
- Weakness: the query and document never attend to each other, so the model cannot reason about their *interaction* — e.g., matching "bank" (financial) to a doc about "river bank."

**Stage 2 — Cross-encoder reranking (slower, accurate):**
- A cross-encoder concatenates query + document and runs them through a single BERT-style encoder together: `score = CE([query; doc])`.
- Full cross-attention over both sequences lets the model capture fine-grained relevance signals: negation, domain jargon, implicit relationships.
- Cannot pre-index (score is query-doc specific) → must run at query time for every candidate → latency is O(N × inference_cost).
- Used *only* on the top-N candidates (typically N=50–200) from stage 1 to bound cost.

**Two-stage pipeline in practice:**
```
Query
  │
  ▼
BM25 / bi-encoder HNSW → top-50 candidates  (fast: ~10–20ms)
  │
  ▼
Cross-encoder re-ranker → top-5 reranked     (slower: ~100–300ms on CPU; 20–50ms GPU)
  │
  ▼
LLM generation with top-5 as context
```

### Example / Tradeoff

**Production tools:**
- **Cohere Rerank** (API): `co.rerank(query=q, documents=top_50, top_n=5)` — no GPU required; ~$1/1K rerank calls.
- **BGE-Reranker-v2** (open-source, BAAI): runs on single GPU; self-hosted latency ~30ms/50 docs.
- **ms-marco-MiniLM-L-6-v2** (sentence-transformers): lightweight cross-encoder for on-prem setups.
- **Jina Reranker v2**: multilingual, 512-token window.

**Concrete metric:** In a customer support RAG system, switching from bi-encoder top-5 → bi-encoder top-50 + cross-encoder top-5 raised RAGAS context_precision from 0.61 to 0.82 (a 34% improvement), at a cost of +80ms p95 latency per query. At 1M queries/day using Cohere Rerank, additional cost ≈ $1,000/day — acceptable when deflection rate improvement saves 3× in support agent costs.

**Tradeoff table:**

| Dimension | Bi-encoder only | Cross-encoder rerank |
|-----------|-----------------|----------------------|
| Latency | ~10–20ms | +80–300ms |
| Accuracy | Moderate (misses interaction) | High (full cross-attention) |
| Scalability | Pre-indexed, scales to billions | Only top-N candidates; N ≤ 200 |
| Cost | Index storage + ANN query | Inference per candidate |
| When to use | First-stage retrieval, real-time | Second-stage rerank, quality-critical |

---

## Verbal script

**Opening (30s):**
"Re-ranking is a classic two-stage design pattern in RAG. The key insight is that the models best suited for *finding* relevant documents are different from the models best suited for *ordering* them precisely. A bi-encoder is fast enough to search millions of docs, but a cross-encoder is more accurate because it can reason about the *interaction* between the query and each document. So we use both — one to recall, one to rank."

**Core explanation (2–3 min):**
"Let me walk through both models. A bi-encoder encodes query and document completely independently into dense vectors. At query time you just encode the query, compute a dot product against pre-indexed document vectors, and do an ANN lookup — that's O(log N), very fast. The downside is the model never *sees* the query and document together, so it misses subtle relevance signals.

A cross-encoder takes the query and document concatenated as a single input and runs full cross-attention over both. This lets it capture things like negation, domain-specific jargon, and implicit relationships. But because the score is query-document specific, you can't pre-compute it — you have to run inference at query time for every candidate, which is expensive.

So the production pattern is: bi-encoder (or BM25) retrieves a cheap, high-recall top-N — say 50 or 100 documents — and then the cross-encoder re-scores just those N documents and reorders them before we pass the top-5 into the LLM context. We pay the cross-encoder cost only on a small candidate set, not the full index.

For tooling: Cohere Rerank is the managed option — you send it query + documents and get back a sorted list. For self-hosted I'd use BGE-Reranker or the ms-marco-MiniLM family from sentence-transformers. On a single GPU, cross-encoding 50 docs takes roughly 20–50ms."

**Tradeoff / production angle (1 min):**
"The tradeoff to call out is latency vs precision. Re-ranking adds 80–300ms depending on candidate count and hardware. At 1M queries/day, Cohere Rerank costs about $1K/day. You have to justify that against the quality improvement — in support chatbot contexts, a 20-point improvement in context precision often translates directly to higher deflection rate, which is measurable in dollars. If latency is the harder constraint, I'd profile first: is the bottleneck in the LLM call or the reranker? Usually it's the LLM, so the reranker cost is already hidden. If not, I'd reduce N (top-50 → top-25) or use a smaller cross-encoder."

**Wrap-up (30s):**
"In short: bi-encoder for recall at scale, cross-encoder for precision on a small candidate set. The two-stage pattern is the industry standard — Cohere, BGE-Reranker, or ms-marco are the go-to tools. Happy to go deeper on hybrid search feeding into re-ranking, or on how you evaluate reranker quality with NDCG."

---

## Pitfalls

- **Mistake:** Saying "re-ranking is just running the embedding model again on the results" — **Better:** Clarify that a cross-encoder is a *different architecture* from a bi-encoder: it takes query + doc as a *single* concatenated input through full cross-attention, which is why it's more accurate but cannot be pre-indexed.
- **Mistake:** Not mentioning the two-stage structure — describing cross-encoders as if they're used to search the full index — **Better:** Explicitly say the cross-encoder only operates on the top-N candidates from a fast first-stage retriever (bi-encoder or BM25); running a cross-encoder against millions of docs would be prohibitively slow.
- **Mistake:** Ignoring latency impact and just saying "use a cross-encoder for better results" — **Better:** Quantify the cost: cross-encoding 50 candidates adds ~80–200ms; name the N tradeoff (50 is common; 200 is the upper bound before latency dominates).

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q17: What is hybrid search? When combine vector + BM25?](02-017-what-is-hybrid-search-when-combine-vector-bm25.md) | Prerequisite — hybrid search is the first-stage retrieval that feeds into re-ranking |
| [Q21: How evaluate a RAG pipeline? NDCG, MRR, precision@k, recall?](02-021-how-evaluate-a-rag-pipeline-ndcg-mrr-precisionk-recall.md) | Follow-up — NDCG and MRR measure the quality gain from re-ranking |
| [Q12: Compare sparse vs dense retrieval. When use each?](02-012-compare-sparse-vs-dense-retrieval-when-use-each.md) | Same concept cluster — bi-encoder is dense retrieval; re-ranking extends it |

---

## One-liner recall

> Re-ranking uses a slow, accurate **cross-encoder** (full cross-attention over query+doc) to re-score the top-N candidates returned by a fast **bi-encoder** ANN retrieval, trading ~80–200ms latency for a 20–30 point precision improvement before passing top-k to the LLM.
