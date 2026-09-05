# How does self-attention work in a transformer?

**Category:** 01-llm-fundamentals
**Question #:** 038
**Source section:** §1 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
This is the single most common LLM technical screen opener. Interviewers use it to quickly sort candidates: those who understand *why* the mechanism exists (permutation-invariance, long-range dependencies) from those who memorised a formula without insight. A strong answer demonstrates that you can build up from first principles, not just recite Q/K/V.

### Trigger phrases
- "Walk me through how self-attention works."
- "Can you explain the transformer architecture?"
- "How does an LLM actually process a sequence of tokens?"
- "What is attention and why does it matter?"

### What it tests
Depth of understanding of the core transformer building block — whether the candidate can explain it mechanically, intuitively, and connect it to real scaling decisions.

---

## Answer

### Concept
Self-attention lets every token in a sequence directly attend to every other token in a single layer, producing context-aware representations. Unlike RNNs, which process tokens sequentially, self-attention is parallel and has O(1) path length between any two positions — making it far better at capturing long-range dependencies.

### Mechanism
For an input sequence of *n* tokens, each token embedding **x** is linearly projected into three vectors:

- **Query (Q)** — "what am I looking for?"
- **Key (K)** — "what do I contain / advertise?"
- **Value (V)** — "what information do I carry?"

The attention score between token *i* and token *j* is:

```
score(i, j) = (Q_i · K_j) / √d_k
```

Dividing by √d_k (the key dimension) prevents vanishing gradients when d_k is large. Scores are passed through **softmax** to produce a probability distribution over all positions, then used to take a weighted sum of values:

```
Attention(Q, K, V) = softmax(QKᵀ / √d_k) · V
```

This produces a new representation for each token that is a blend of all other tokens' values, weighted by relevance.

**Causal (decoder) masking:** For autoregressive generation, positions cannot attend to future tokens. A triangular mask sets future scores to −∞ before softmax, zeroing those weights.

**Multi-head attention** runs *H* independent attention heads in parallel, each with its own W_Q, W_K, W_V projections, then concatenates and projects down:

```
MultiHead(Q, K, V) = Concat(head_1, ..., head_H) · W_O
```

Different heads specialise — one may track syntactic dependencies, another coreference, another positional patterns. This diversity is empirically critical to model quality.

**Complexity:** O(n² · d) in time and O(n²) in memory, where n is sequence length. At n = 1M tokens — the current frontier context length — the attention matrix is the primary memory bottleneck — why FlashAttention (IO-aware tiling) and GQA (sharing K/V heads) exist.

### Example / Tradeoff
In a frontier model (96 heads, d_model = 12 288), each head has d_k = 128. With a 32k context, the raw attention matrix per head is 32k × 32k = 1B float16 values (~2 GB) — before activations. FlashAttention rewrites this as tiled SRAM ops to avoid materialising that matrix in HBM, cutting memory ~5× at the cost of recomputation during the backward pass (training only).

For serving, GQA (grouped-query attention) reduces the number of distinct K and V heads (e.g., 8 groups instead of 96 heads in a 70B-class open-weight model), shrinking the KV cache proportionally — critical when batching many concurrent users.

---

## Verbal script

**Opening (30s):**
"Self-attention is the core operation that makes transformers work, and I think the best way to explain it is to start with the problem it solves. Before transformers, RNNs had to pass information through a sequential bottleneck — if two relevant tokens were 500 positions apart, you had to thread that information through 500 hidden states. Self-attention eliminates that: every token can directly attend to every other token in one shot."

**Core explanation (2–3 min):**
"Here's how it works mechanically. For each token, we learn three linear projections: a Query, a Key, and a Value. You can think of it like a soft database lookup — the Query is what I'm searching for, the Key is the index that other tokens expose, and the Value is the content I'd retrieve. We compute dot products between each query and all keys, scale by the square root of the key dimension to keep gradients stable, apply softmax to get attention weights, then take a weighted sum of the values. The output for each token is now a blend of every other token's information, weighted by how relevant they are. For decoder-only models like GPT, we add a causal mask — tokens can only attend backwards, not to future positions. Multi-head attention just runs this independently H times with different learned projections, then concatenates. Different heads tend to specialise: I've seen heads that clearly track subject-verb agreement and others that track coreference chains."

**Tradeoff / production angle (1 min):**
"The main cost is quadratic: both time and memory scale as O(n²) in sequence length. At 32k tokens, the attention matrix per head is enormous — that's why FlashAttention was such a breakthrough. It avoids materialising that matrix in GPU HBM by computing attention in tiles that fit in fast SRAM, getting a 3–4× memory reduction with no accuracy loss. On the KV cache side, GQA — used in a modern open-weight model, Mistral, Gemma — reduces the number of distinct K/V heads, sometimes by 8–12×, which directly cuts the per-request memory footprint during serving."

**Wrap-up (30s):**
"So in summary: self-attention computes pairwise relevance across all positions via Q/K/V projections, multi-head attention runs it H times in parallel for richer representations, and the quadratic cost is managed in production with FlashAttention and GQA. Happy to go deeper on any part — the math, the masking, or how this interacts with the KV cache at inference."

---

## Pitfalls

- **Mistake:** Describing self-attention as "the model learns which words are important" without explaining the Q/K/V projection mechanism or the scaled dot-product formula — **Better:** Walk through the Q/K/V roles and the softmax(QKᵀ/√d_k)·V formula explicitly; show you can reconstruct the math, not just the intuition.
- **Mistake:** Treating multi-head attention as just "doing attention multiple times" without explaining *why* multiple heads help — **Better:** Explain that different heads learn different relationship types (syntactic, semantic, positional), and that this diversity is empirically necessary for strong performance.
- **Mistake:** Not mentioning the O(n²) complexity or any mitigation — **Better:** Name the bottleneck and at least one production solution (FlashAttention for training/long-context, GQA for KV cache reduction during serving).

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q22: What is self-attention? How does it differ from multi-head attention?](01-022-what-is-self-attention-how-does-it-differ-from-multi-head-at.md) | Deeper version of this question — go here after nailing the basics |
| [Q23: What is grouped query attention (GQA)?](01-023-what-is-grouped-query-attention-gqa-how-does-it-differ-from.md) | Follow-up: how to reduce KV cache cost in production |
| [Q33: What is FlashAttention and how does it work?](01-033-what-is-flashattention-and-how-does-it-work.md) | Follow-up: IO-aware attention for long contexts and training efficiency |

---

## One-liner recall

> Self-attention computes pairwise relevance via scaled dot-products of Q/K/V projections (softmax(QKᵀ/√d_k)·V), runs H times in parallel as multi-head attention, and scales O(n²) — managed in production with FlashAttention and GQA.
