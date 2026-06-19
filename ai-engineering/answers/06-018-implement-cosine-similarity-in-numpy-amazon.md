# Implement cosine similarity in NumPy (Amazon)

**Category:** 06-ml-fundamentals
**Question #:** 018
**Source section:** §6 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
This is a classic ML coding screen question at Amazon and similar companies. It tests whether you understand the mathematical definition of cosine similarity (not just that it "measures vector closeness"), whether you can translate the formula into correct NumPy without bugs (zero-division, broadcasting, shape issues), and whether you know when cosine similarity is preferred over Euclidean distance or dot product. It's also a signal for how you approach embeddings in RAG/semantic-search contexts.

### Trigger phrases
- "Implement cosine similarity in NumPy from scratch"
- "Without using sklearn, how would you compute cosine similarity between two vectors?"
- "Write a function that computes pairwise cosine similarity between two sets of embeddings"

### What it tests
Ability to translate vector-math into idiomatic, numerically-safe NumPy and articulate why cosine similarity is the right metric for normalized embedding spaces.

---

## Answer

### Concept
Cosine similarity measures the cosine of the angle between two vectors, ignoring magnitude — so two documents with identical word proportions but very different lengths score 1.0. The formula is:

```
cos(A, B) = (A · B) / (||A|| × ||B||)
```

Values range from −1 (opposite) to 1 (identical direction); in embedding spaces with non-negative activations the practical range is [0, 1].

### Mechanism

**Single-pair implementation:**
```python
import numpy as np

def cosine_similarity(a: np.ndarray, b: np.ndarray) -> float:
    """Cosine similarity between two 1-D vectors."""
    dot = np.dot(a, b)
    norm_a = np.linalg.norm(a)
    norm_b = np.linalg.norm(b)
    if norm_a == 0 or norm_b == 0:
        return 0.0          # convention: zero vector has no direction
    return dot / (norm_a * norm_b)
```

**Batch / pairwise implementation (matrix form):**
```python
def cosine_similarity_matrix(A: np.ndarray, B: np.ndarray) -> np.ndarray:
    """
    Compute cosine similarity between every row of A and every row of B.
    A: shape (m, d), B: shape (n, d)
    Returns: shape (m, n)
    """
    # Normalize each row to unit length
    A_norm = A / (np.linalg.norm(A, axis=1, keepdims=True) + 1e-10)
    B_norm = B / (np.linalg.norm(B, axis=1, keepdims=True) + 1e-10)
    return A_norm @ B_norm.T   # (m, d) @ (d, n) → (m, n)
```

Key implementation notes:
- Add `1e-10` (epsilon) to norms instead of an `if` check — vectorised and avoids zero-division without branching.
- Use `axis=1, keepdims=True` for row-wise normalization; without `keepdims=True` broadcasting will silently fail on shape `(m, 1)` vs `(m,)`.
- Once rows are unit-normalized, cosine similarity reduces to the dot product — this is why FAISS's IndexFlatIP (inner product) is equivalent to cosine similarity when you pre-normalize embeddings at ingestion time.

### Example / Tradeoff
In a RAG pipeline using OpenAI `text-embedding-3-small` (1536-d vectors), every document chunk and every query is L2-normalized at ingestion. FAISS IndexFlatIP then retrieves the top-k nearest by inner product, which is mathematically identical to cosine similarity — no per-query norm computation needed at search time. This is 10–20% faster than computing norms on the fly.

**Why cosine over Euclidean?**
Euclidean distance conflates magnitude with direction. A 1-sentence chunk and a 10-page document about the same topic will have very different magnitudes, but similar cosine values. In embedding spaces this bias-toward-length is undesirable.

**Why not always dot product?**
Raw dot product favors high-magnitude vectors, which tends to favor frequent or long texts. Cosine (or pre-normalized dot product) removes that confound.

---

## Verbal script

**Opening (30s):**
"I'd frame this as two sub-questions: implementing the formula correctly in NumPy, and understanding when cosine similarity is the right choice. Let me start with the implementation, then talk about the production angle."

**Core explanation (2–3 min):**
"Cosine similarity is A dot B divided by the product of their L2 norms — it's the cosine of the angle between the two vectors, so it ranges from −1 to 1.

For a single pair, I'd write:

```python
dot = np.dot(a, b)
norm_a = np.linalg.norm(a)
norm_b = np.linalg.norm(b)
return dot / (norm_a * norm_b) if norm_a and norm_b else 0.0
```

For a matrix of queries against a matrix of documents — which is the real production case — I'd normalize each row first and then do a matrix multiply:

```python
A_norm = A / (np.linalg.norm(A, axis=1, keepdims=True) + 1e-10)
B_norm = B / (np.linalg.norm(B, axis=1, keepdims=True) + 1e-10)
return A_norm @ B_norm.T
```

The epsilon avoids zero-division without branching, and once vectors are unit-normalized, cosine similarity is just an inner product — which is why FAISS's IndexFlatIP with pre-normalized vectors is equivalent and faster than computing cosine on the fly."

**Tradeoff / production angle (1 min):**
"Cosine is preferred over Euclidean in embedding spaces because it ignores magnitude — a short and long document about the same topic will have similar cosine scores but very different L2 distances. The tradeoff is that cosine is slightly more expensive to compute for raw vectors, so in production I always pre-normalize at ingestion time and use inner-product indices. The downside of cosine is it fails for zero vectors — convention is to return 0.0."

**Wrap-up (30s):**
"To summarize: implement via dot-product divided by norm-product, handle zero vectors, vectorise with a normalize-then-matmul pattern for batch cases, and in production pre-normalize embeddings so inner-product indices can be used directly. Happy to go deeper on FAISS index types or the broader RAG retrieval stack."

---

## Pitfalls

- **Mistake:** Dividing by norms without guarding against zero vectors, causing `nan` or `ZeroDivisionError` — **Better:** Add a zero-check or epsilon `+ 1e-10` to the denominator so the function handles degenerate inputs gracefully.
- **Mistake:** Using `np.linalg.norm(A, axis=1)` without `keepdims=True` in the batch case, causing a silent shape mismatch `(m,)` vs `(m, d)` that either crashes or broadcasts incorrectly — **Better:** Always use `keepdims=True` for row-wise normalization: `A / np.linalg.norm(A, axis=1, keepdims=True)`.
- **Mistake:** Not explaining *why* cosine over Euclidean — just implementing the formula without context — **Better:** Explicitly note that cosine is magnitude-invariant, making it the right choice for embedding similarity where document length shouldn't dominate the score.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q13: What are embeddings, and how are they used in RAG?](../answers/01-041-what-are-embeddings-and-how-are-they-used-in-rag.md) | Embeddings are the vectors cosine similarity operates on |
| [Q23: How does ANN search work? HNSW indexing?](../answers/02-023-how-does-ann-search-work-hnsw-indexing.md) | FAISS/HNSW use inner-product (equivalent to cosine on normalized vecs) for ANN retrieval |
| [Q17: Feature scaling — normalization vs standardization?](06-017-feature-scaling-normalization-vs-standardization.md) | L2 normalization is the prerequisite for using inner product as cosine similarity |

---

## One-liner recall

> Cosine similarity = dot(A,B) / (||A|| × ||B||); in NumPy, normalize rows with `keepdims=True` then matmul — and in production pre-normalize embeddings at ingestion so FAISS IndexFlatIP is equivalent and free of per-query norm computation.
