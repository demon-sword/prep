# How does ANN search work? HNSW indexing?

**Category:** 02-rag-systems
**Question #:** 023
**Source section:** §2 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
ANN (Approximate Nearest Neighbor) search is the core engine powering every vector database used in RAG. Interviewers ask this to verify you understand *why* brute-force cosine search doesn't scale, what HNSW actually does structurally, and how to tune it — because bad index parameters directly cause retrieval failures and latency spikes in production.

### Trigger phrases
- "How does the vector search actually work under the hood?"
- "How does HNSW indexing work?"
- "How do you find similar embeddings at scale?"
- "What's the tradeoff between exact search and approximate search?"

### What it tests
Understanding of ANN data structures (graph vs tree vs quantization), HNSW mechanics (layered skip-graph navigation), and production parameter tuning (`ef_construction`, `M`, `ef_search`) — not just "it finds nearest neighbors fast."

---

## Answer

### Concept
ANN search finds vectors that are *approximately* nearest (within a small error margin) to a query vector in sub-linear time, sacrificing a bounded amount of recall for dramatic speed gains. HNSW (Hierarchical Navigable Small World) is the dominant ANN algorithm in production: it builds a multi-layer graph where each layer is a sparser skip-list, allowing logarithmic-time greedy traversal to find nearest neighbors.

### Mechanism

**Why brute force doesn't scale:**
For 10M 1536-dim vectors (OpenAI ada-002), exact cosine search requires 10M dot products × 1536 floats ≈ 15.36B multiply-accumulate ops per query. At a GPU throughput of ~10 TFLOPS, that's ~1.5ms per query — but in practice with memory bandwidth constraints it exceeds 100ms, and it scales linearly with corpus size.

**HNSW structure:**

```
Layer 2 (very sparse):  [A] ——————————————— [G]
Layer 1 (sparser):      [A] —— [C] —— [E] — [G]
Layer 0 (full graph):   [A]-[B]-[C]-[D]-[E]-[F]-[G]  (max M neighbors each)
```

1. **Graph construction:** Each inserted vector is assigned a random max layer (exponential decay probability). At each layer, the algorithm connects the new node to its `M` nearest neighbors (found by greedy search starting from the entry point). The bottom layer (layer 0) stores all nodes with up to `2M` connections.

2. **Query (search):** Enter at the top layer with the entry point. Greedily navigate to the nearest neighbor at that layer. Descend to the next layer and repeat, using the current closest node as the new entry point. At layer 0, expand the candidate set to `ef_search` nodes and return the top-k.

**Key hyperparameters:**
| Parameter | Default | Effect |
|-----------|---------|--------|
| `M` | 16 | Max connections per node; higher → better recall, more memory (O(M × N) edges) |
| `ef_construction` | 200 | Candidate list size at build time; higher → better graph quality, slower indexing |
| `ef_search` | 50–200 | Candidate list at query time; higher → better recall, higher latency |

**Recall vs latency:**  
Pinecone's benchmarks (ANN-benchmarks): HNSW at `ef_search=100` achieves ~99% Recall@10 at ~2–5ms p99 on 1M vectors. Brute force achieves 100% recall at ~50–200ms.

### Example / Tradeoff

**FAISS:** `IndexHNSWFlat` — stores raw vectors + HNSW graph, no compression. Fast for research, high memory.  
**FAISS:** `IndexIVFPQ` — inverted file index + product quantization, 4-32× memory compression, ~2–5% recall drop.  
**Pinecone / Qdrant / Weaviate:** All default to HNSW under the hood; Pinecone adds horizontal sharding across replicas.

**Production tradeoff:**
- **Recall vs latency dial:** Raise `ef_search` for recall-critical search (legal, medical), lower for high-throughput chat (50ms budget).
- **Memory pressure:** Each HNSW node uses ~M × 4 bytes of pointers. At 10M vectors with M=16, that's ~640 MB overhead on top of vector storage.
- **IVF alternative:** IVF (Inverted File Index) clusters vectors into Voronoi cells (k-means); at query time probes `nprobe` cells. Faster build, lower memory, worse recall at high QPS — good for batch pipelines, not real-time RAG.
- **Hybrid scenario:** Qdrant supports filtered HNSW with payload indexes — pre-filter by metadata (e.g., `department=engineering`) before ANN, avoiding post-filter recall collapse on skewed distributions.

---

## Verbal script

**Opening (30s):**
"ANN search is the retrieval engine inside every vector database. The naive approach — comparing the query embedding against all stored vectors — is exact but scales linearly. At 10M vectors that's too slow for real-time RAG. HNSW is the algorithm most production systems use to get approximate nearest neighbors in log time. Let me walk through how it works and the tradeoffs that matter in practice."

**Core explanation (2–3 min):**
"HNSW builds a multi-layer graph — think of it like a skip list extended into high-dimensional space. At the bottom layer, every vector is a node connected to its M nearest neighbors. Higher layers are progressively sparser; vectors are randomly promoted to higher layers with exponential decay probability. At insert time, the algorithm does a greedy graph search at each layer to find the best M neighbors to connect to.

At query time, you enter the graph at the top layer via a single entry point and greedily hop to whichever neighbor is closest to your query vector. You descend layer by layer, using your current best candidate as the start point for the next layer. At layer 0, you expand to `ef_search` candidates and return the top-k. This greedy descent takes O(log N) hops at the upper layers and O(ef_search) work at the bottom.

The two parameters that matter most in production are `M` — the number of edges per node, which controls graph connectivity and memory use — and `ef_search`, which is a runtime knob: higher values find more candidates and improve recall but increase latency. For a customer support RAG, I'd typically set `ef_search` around 100–150 for ~99% Recall@10 at under 5ms p99."

**Tradeoff / production angle (1 min):**
"The key production tradeoffs are: HNSW consumes significant memory for the graph edges — at 10M vectors with M=16 that's roughly 640 MB of pointer overhead on top of 60 GB of vector storage for 1536-dim float32. If memory is tight, I'd switch to IVF+PQ (product quantization) which gives 8–16× compression with ~2–5% recall loss — acceptable for most chat applications, not for high-stakes retrieval. A second issue is filtered search: if you need metadata filters (e.g., only search documents owned by this user), you need a vector DB that supports pre-filtering at the index layer like Qdrant or Weaviate — otherwise post-filtering collapses recall when the filter is restrictive."

**Wrap-up (30s):**
"In summary: HNSW achieves sub-linear ANN search via a layered navigable graph, with `M` and `ef_search` as the main levers for the recall-latency-memory tradeoff. For production RAG I default to HNSW (Pinecone or Qdrant) with ef_search tuned to hit target recall, and add metadata pre-filtering for ACL-restricted corpora. Happy to go deeper on IVF-PQ or the filtered HNSW implementation if useful."

---

## Pitfalls

- **Mistake:** Saying "ANN is just approximate cosine similarity" without explaining *how* it achieves sub-linear complexity — **Better:** Explain the graph structure: greedy multi-layer navigation reduces candidate evaluation from O(N) to O(log N) hops before the dense bottom-layer scan.
- **Mistake:** Treating `ef_search` as a build-time constant and not mentioning it's a per-query runtime knob — **Better:** Emphasize that `ef_search` can be tuned per query or per SLO tier: lower for high-QPS chat, higher for precision-critical legal/medical retrieval.
- **Mistake:** Ignoring filtered search and its recall collapse — **Better:** Note that post-filter ANN (filter after retrieving top-K) collapses recall when filters are selective; Qdrant's and Weaviate's payload-indexed pre-filtering avoids this, and this is a real production failure mode.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q12: Compare sparse vs dense retrieval. When use each?](02-012-compare-sparse-vs-dense-retrieval-when-use-each.md) | Dense retrieval uses HNSW ANN under the hood — prerequisite |
| [Q15: What vector databases have you used? Which and why?](02-015-what-vector-databases-have-you-used-which-and-why.md) | Vector DBs are essentially HNSW + storage + serving layer — same concept |
| [Q19: Scale RAG to 10M+ articles — sharding, caching, retrieval optimization](02-019-scale-rag-to-10m-articles-sharding-caching-retrieval-optimiz.md) | HNSW sharding and `ef_search` tuning are the retrieval levers at scale |

---

## One-liner recall

> HNSW builds a multi-layer skip-graph where query traversal descends greedily from sparse upper layers to the dense bottom layer — achieving O(log N) approximate nearest-neighbor search, with `M` (graph connectivity) and `ef_search` (candidate list size) as the recall-latency-memory knobs.
