# What is self-attention? How does it differ from multi-head attention?

**Category:** 01-llm-fundamentals
**Question #:** 022
**Source section:** §1 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
This is a frequent technical screening question — asked to separate candidates who have genuinely understood the transformer architecture from those who have only used it. Interviewers probe whether you can explain the Q/K/V mechanism, the dot-product scoring formula, the role of the scaling factor, and what multi-head adds beyond single-head attention. Strong candidates connect the math to production implications (GQA, FlashAttention, KV cache size).

### Trigger phrases
- "What is self-attention and how does it work?"
- "Walk me through the attention mechanism in a transformer."
- "What's the difference between single-head and multi-head attention?"
- "Why do we use multiple attention heads?"
- "How does the model know which tokens to focus on?"

### What it tests
Deep understanding of the transformer's core mechanism: how Q/K/V projections implement dynamic, content-based token aggregation, and how multi-head attention enables the model to capture multiple relationship types simultaneously.

---

## Answer

### Concept
**Self-attention** is a mechanism that lets each token in a sequence compute a weighted combination of all other tokens, where the weights are determined by how relevant each pair of tokens is to each other. Unlike RNNs that pass information sequentially, or CNNs that use fixed local windows, self-attention operates over the entire sequence in parallel — every token attends to every other token in a single operation.

**Multi-head attention (MHA)** runs H independent self-attention operations in parallel (each on a lower-dimensional subspace), then concatenates and projects their outputs. This allows different heads to specialize in different relationship patterns — one head might capture syntactic dependencies, another semantic similarity, another positional proximity.

### Mechanism

**Single-head self-attention — step by step:**

1. **Linear projections:** For input matrix `X` (shape `[seq_len, d_model]`), compute three matrices via learned weight matrices:
   - `Q = X · W_Q` — queries (what does this token want to know?)
   - `K = X · W_K` — keys (what does this token offer?)
   - `V = X · W_V` — values (what information does this token carry?)
   - Each of Q, K, V has shape `[seq_len, d_k]`

2. **Attention scores:** `Scores = Q · K^T / √d_k`
   - Shape: `[seq_len, seq_len]` — a similarity score between every pair of tokens
   - Dividing by `√d_k` prevents dot products from growing so large that softmax saturates (vanishing gradients)

3. **Softmax:** `A = softmax(Scores)` — normalize scores to sum to 1 per row
   - For **causal (decoder) attention**: apply mask to zero out positions j > i so token i cannot attend to future tokens

4. **Output:** `Z = A · V` — weighted average of value vectors, shape `[seq_len, d_model]`

Putting it together: `Attention(Q, K, V) = softmax(QK^T / √d_k) · V`

**Multi-head attention — what changes:**

Instead of one set of Q/K/V projections at dimension `d_model`, run H heads each projecting to dimension `d_k = d_model / H`:

```
head_i = Attention(X·W_Q_i, X·W_K_i, X·W_V_i)   # shape [seq_len, d_k]

MultiHead(Q, K, V) = Concat(head_1, ..., head_H) · W_O  # shape [seq_len, d_model]
```

- Each head has its own `W_Q_i`, `W_K_i`, `W_V_i` weight matrices — separate learned projections
- `W_O` is a final projection that blends the concatenated head outputs back to `d_model`
- Total parameter count: roughly the same as a single large head, because each head is `d_model/H` wide

**Why multiple heads help:** Each head can learn a different type of relationship. In practice, heads in BERT were shown (Voita et al., 2019) to specialize in: syntactic structure (subject-verb agreement), co-reference (pronoun resolution), positional proximity, and rare token detection. A single head with all parameters pooled together cannot specialize this way.

### Example / Tradeoff

**Concrete example — LLaMA-3-8B:**
- `d_model = 4096`, `H = 32` heads, so `d_k = 128` per head
- **GQA variant:** 8 KV heads shared across 32 query heads — each group of 4 query heads shares one K/V head
- This reduces the KV cache by 4× (from 32 K/V pairs to 8), critical for serving long contexts

**Tradeoff — attention is O(n²) in sequence length:**
The attention score matrix is `[seq_len, seq_len]` — at 128K tokens, that's 16 billion cells per layer. Solutions:
- **FlashAttention:** Tiled computation on-chip that avoids materializing the full matrix; O(n) memory instead of O(n²)
- **Sparse/local attention:** Restrict each token to a sliding window of nearby tokens (used in Longformer, BigBird) — trades recall on long-range dependencies for feasibility
- **GQA / MQA:** Reduce KV head count to shrink KV cache, not the score matrix

**Multi-head vs single-head benchmark:** Removing multi-head attention (using a single full-width head) in BERT-base degrades performance on GLUE by ~2 points; ablations show heads specialize and removing them selectively degrades specific tasks.

---

## Verbal script

**Opening (30s):**
"Self-attention is the core building block of transformers — it's the mechanism that lets every token directly aggregate information from every other token in a single parallel operation. Multi-head attention is the production version that runs several of these attention operations in parallel subspaces, so the model can learn multiple types of relationships simultaneously. Let me walk through the math and then the why."

**Core explanation (2–3 min):**
"I'd start with single-head self-attention. Given an input sequence of token embeddings, we compute three linear projections for every token: a Query, a Key, and a Value. Intuitively, the Query is 'what am I looking for?', the Key is 'what do I offer?', and the Value is 'what information do I contain?'

The attention score between token i and token j is the dot product of i's query and j's key, scaled by the square root of the key dimension to prevent the dot products from blowing up and saturating the softmax. We softmax those scores to get weights, then take a weighted sum of all the value vectors. So the output for token i is: how much of every other token's value should I absorb?

For decoder-only models like GPT, we apply a causal mask — token i can only attend to tokens 1 through i. This is how autoregressive generation works: the model can't peek at future tokens.

Now, multi-head attention: instead of one big Q/K/V projection at d_model = 4096, we run H parallel attention heads, each at d_k = d_model/H (say, 128 for 32 heads). Each head has its own learned projection matrices, so they can specialize. Research has shown heads specialize naturally — some track syntactic structure, some track coreference, some track positional proximity. We concatenate all head outputs and project back to d_model via W_O.

The parameter count is roughly equivalent to a single large head, but you get the specialization benefit."

**Tradeoff / production angle (1 min):**
"The key production concern is that self-attention is O(n²) in sequence length — the score matrix is seq_len × seq_len per layer. At 128K tokens, that's infeasible without optimizations. FlashAttention tiles the computation on-chip and avoids materializing the full matrix, cutting memory to O(n). And Grouped Query Attention (GQA) — which LLaMA-3 and Mistral use — reduces the number of K/V heads while keeping more Q heads, shrinking the KV cache 4–8× at the cost of slight model quality reduction."

**Wrap-up (30s):**
"So: self-attention = dynamic content-based aggregation via QK^T/√d_k applied to V vectors. Multi-head = run H independent attention operations in parallel, let each specialize, then blend. The key production constraints are O(n²) attention cost — addressed by FlashAttention — and KV cache size — addressed by GQA. Happy to go deeper on any piece."

---

## Pitfalls

- **Mistake:** Describing self-attention as "the model pays attention to important words" without explaining how scores are computed — **Better:** State the formula `Attention(Q,K,V) = softmax(QK^T / √d_k) · V` and explain each term: Q/K used for scoring, V is what's aggregated, √d_k scaling prevents softmax saturation. Without the formula you've only described the intent, not the mechanism.
- **Mistake:** Saying multi-head attention "uses multiple layers" or "runs the model multiple times" — **Better:** MHA runs H attention heads in parallel within a single layer, each on a lower-dimensional projection (d_k = d_model/H). It's a width split within one operation, not depth or repetition.
- **Mistake:** Not knowing why we scale by `√d_k` — answering "to normalize" without explaining the vanishing gradient risk — **Better:** With large d_k, dot products grow in magnitude, pushing softmax into saturation regions with near-zero gradients. Dividing by `√d_k` keeps the variance stable (if Q and K have unit variance, QK^T has variance d_k; dividing returns it to ~1).

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q2: How do transformers work?](01-002-how-do-transformers-work.md) | Broader transformer architecture context for this mechanism |
| [Q23: What is grouped query attention (GQA)?](01-023-what-is-grouped-query-attention-gqa-how-does-it-differ-from.md) | GQA is a direct production optimization of multi-head attention |
| [Q33: What is FlashAttention and how does it work?](01-033-what-is-flashattention-and-how-does-it-work.md) | FlashAttention addresses the O(n²) cost of self-attention |

---

## One-liner recall

> Self-attention computes `softmax(QK^T / √d_k) · V` — scoring every token pair by query-key dot product, then aggregating values by those weights; multi-head attention runs H independent projections in parallel (d_k = d_model/H each) so different heads can specialize in syntax, semantics, or position, then blends outputs via W_O.
