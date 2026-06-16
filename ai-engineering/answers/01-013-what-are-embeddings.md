# What are embeddings?

**Category:** 01-llm-fundamentals
**Question #:** 013
**Source section:** §1 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
Embeddings are the foundational primitive behind RAG, semantic search, recommendation, and clustering — virtually every AI application a candidate might build. The interviewer is probing whether the candidate understands what embeddings encode (semantic meaning, not surface form), how they're produced (encoder forward pass), and their practical constraints (dimensionality, cosine vs dot product, embedding drift, cost of re-embedding).

### Trigger phrases
- "What are embeddings and how do you use them?"
- "How does semantic search work under the hood?"
- "Walk me through how you'd build a similarity search system."
- "What's the difference between sparse and dense vectors?"

### What it tests
Whether the candidate can translate the mathematical concept of high-dimensional vector representations into production engineering decisions: model choice, indexing strategy, distance metric, and failure modes.

---

## Answer

### Concept
Embeddings are dense, fixed-size vectors of floating-point numbers that encode the *semantic meaning* of a piece of text (or image, audio, etc.) such that similar meanings map to geometrically nearby points in that vector space. A 1,536-dimensional vector from `text-embedding-3-small` or a 768-dimensional vector from `bge-large-en-v1.5` captures enough latent structure that "automobile" and "car" land close together even though they share no characters.

### Mechanism
1. **Encoding:** The input text is tokenized and passed through a transformer encoder (e.g., BERT-style) or the encoder portion of a larger model. The final layer's representation — typically the `[CLS]` token or a mean-pool of all token vectors — is extracted as the embedding.
2. **Similarity:** Vectors are compared using **cosine similarity** (angle, normalized) or **dot product** (magnitude-sensitive, faster with int8). For retrieval, cosine is default; for max-inner-product search (MIPS) tasks like recommendation, dot product is standard.
3. **Indexing:** Billions of vectors can't be brute-force searched in <100ms. Approximate nearest neighbor (ANN) indexes — **HNSW** (Hierarchical Navigable Small World, used in Pinecone/Weaviate/pgvector) or **IVF** (inverted file, used in FAISS) — trade a small recall loss (~1–2%) for 10–100× speed gain.
4. **Storage:** Pinecone, Weaviate, Qdrant, and Chroma store vectors + metadata + namespace filters. pgvector adds embeddings directly to Postgres; FAISS is an in-memory library without persistence.

### Example / Tradeoff
**Production example:** At OpenAI's recommended tier, `text-embedding-3-large` (3,072 dims) costs $0.00013/1K tokens. For 10M product descriptions at avg 50 tokens each, that's ~$65 for the initial embed pass — cheap. But re-embedding when the model changes costs the same again, so **embedding drift** matters: if you swap the embedding model (e.g., from `ada-002` to `3-large`), all stored vectors become stale and must be re-embedded in batch before serving.

**Tradeoff table:**

| Dimension | Small (256–512) | Large (1536–3072) |
|-----------|-----------------|-------------------|
| Memory/vector | 1 KB | 6–12 KB |
| Search latency | Faster ANN | Slower unless quantized |
| Retrieval recall | Lower for subtle queries | Higher |
| Cost to store 10M | ~5 GB | ~30–60 GB |

**When embeddings fail:** Negation ("not profitable" and "profitable" are close), exact-match requirements ("invoice #A-9912"), temporal precision ("2024 Q3 report" vs "2023 Q3 report"), and highly specialized domain vocabulary (e.g., chemical formula strings) — hybrid search (dense + BM25) patches most of these.

---

## Verbal script

**Opening (30s):**
"Embeddings are the representation layer that makes semantic search possible. The core idea is simple: take any text, pass it through an encoder model, and get back a dense vector — typically 768 to 3,072 floating-point numbers — where the geometry of that space reflects semantic meaning. 'Dog' and 'puppy' land close together; 'dog' and 'CPU' land far apart."

**Core explanation (2–3 min):**
"Here's how it works mechanically. You tokenize your text — say a chunk from a PDF — pass it through a transformer encoder like `bge-large-en-v1.5` or OpenAI's `text-embedding-3-small`. The model's final hidden state, typically mean-pooled across tokens, becomes your embedding vector.

Once you have embeddings, you compare them using cosine similarity: normalize each vector to unit length, then take the dot product. Vectors that point in the same direction — same semantic content — score near 1.0; orthogonal vectors score near 0.

But brute-force comparison at scale doesn't work. If you have 10 million documents, checking each one takes hundreds of milliseconds. That's where ANN indexes come in — HNSW builds a hierarchical graph structure so you can navigate from coarse-grained clusters down to exact neighbors in O(log n) hops. Pinecone and Weaviate use HNSW under the hood; FAISS supports both HNSW and IVF and is what you'd use if you're self-hosting."

**Tradeoff / production angle (1 min):**
"The biggest production gotcha I flag is **embedding drift**. If you swap your embedding model — say you go from `ada-002` to `text-embedding-3-large` because recall improved — every vector in your index is now in a different space. They're literally incompatible. You have to re-embed your entire corpus and rebuild the index. For a 10M document corpus this might cost $65 and 2 hours of batch processing — manageable — but you need a plan for the cutover: dual-index serving during migration, or a maintenance window.

The other failure mode is that embeddings don't handle negation, exact-match needs, or very domain-specific jargon well. That's why in production I usually pair dense embeddings with BM25 sparse retrieval — hybrid search — and let a cross-encoder reranker pick the final top-k."

**Wrap-up (30s):**
"So: embeddings = compressed semantic representations produced by encoder models, compared with cosine similarity, indexed with HNSW or IVF for sub-100ms ANN search, stored in a vector DB. The key engineering decisions are model choice, dimensionality vs cost tradeoff, distance metric, and your re-embedding migration plan. Happy to go deeper on any of those — especially how they slot into a RAG pipeline."

---

## Pitfalls

- **Mistake:** Describing embeddings as "word2vec or one-hot encodings" — **Better:** Clarify that modern embeddings come from transformer encoders (BERT-style or LLM-based), capture full-sentence context (not just token-level), and the vector space encodes semantic similarity rather than word co-occurrence statistics.
- **Mistake:** Saying "we compare embeddings with Euclidean distance" without qualification — **Better:** Explain that **cosine similarity is standard** for text (normalizes magnitude), dot product is used when magnitude encodes relevance (recommendation), and L2/Euclidean is correct for quantized vectors or image embeddings where magnitude matters; choosing the wrong metric quietly destroys retrieval recall.
- **Mistake:** Treating embedding models as interchangeable/plug-and-play — **Better:** Flag that **switching embedding models invalidates all stored indexes** (incompatible vector spaces), so model choice is a schema-level architectural commitment; always benchmark on your domain before committing.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q41: What are embeddings, and how are they used in RAG?](01-041-what-are-embeddings-and-how-are-they-used-in-rag.md) | Application-layer follow-up — same concept applied to retrieval pipeline |
| [Q42: Semantic search vs keyword search?](01-042-semantic-search-vs-keyword-search.md) | Natural follow-up — when dense embeddings win vs BM25 |
| [Q14: How does chunking happen?](01-014-how-does-chunking-happen.md) | Prerequisite — what gets embedded and how chunk size affects embedding quality |

---

## One-liner recall

> Embeddings are fixed-size dense vectors produced by transformer encoders that encode semantic meaning as geometry — similar text lands nearby — enabling ANN search via HNSW/IVF indexes in systems like Pinecone or FAISS, with the key engineering gotcha that switching embedding models invalidates every stored vector.
