# How do transformers work?

**Category:** 01-llm-fundamentals
**Question #:** 002
**Source section:** §1 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
This is the #3 most-asked question in LLM screening rounds (see Top 15 list). Interviewers want to confirm you can explain the transformer architecture clearly — not just that you've "used" LLMs, but that you understand the mechanism that makes them work. They're probing for: knowledge of self-attention, multi-head attention, the encoder/decoder distinction, and why transformers scaled better than RNNs. Strong candidates tie the architecture to production properties (parallelism, context limits, memory).

### Trigger phrases
- "How do transformers work?"
- "Walk me through the transformer architecture."
- "What's self-attention and how does it fit into the transformer?"
- "Why did transformers replace RNNs for NLP?"
- "How does a language model actually process a prompt?"

### What it tests
Depth of understanding of the core architecture: self-attention mechanism, positional encoding, feedforward sublayers, and how they compose into a stack that enables parallel training and long-range dependency modeling.

---

## Answer

### Concept
The transformer is a neural network architecture built entirely on attention mechanisms (no recurrence, no convolutions). It processes an entire input sequence in parallel, computing attention-weighted representations for each token by allowing every token to "attend" to every other token simultaneously. This parallelism enables efficient training at scale and the ability to capture long-range dependencies that RNNs struggled with.

### Mechanism
A transformer has two variants: **encoder** (BERT-style, bidirectional), **decoder** (GPT-style, causal/unidirectional), or **encoder-decoder** (T5, original "Attention Is All You Need"). Modern LLMs are decoder-only. Here's the decoder stack:

**1. Input processing:**
- Text → tokens (BPE tokenization)
- Token IDs → embedding vectors (shape: `[seq_len, d_model]`, e.g., 4096)
- Positional encodings added — original paper used sinusoidal; modern models use RoPE (Rotary Position Embeddings) which generalizes better to longer sequences

**2. Transformer block (repeated N times, e.g., 32–96 layers in production models):**

**(a) Causal Self-Attention:**
- For each token, compute Query (Q), Key (K), Value (V) projections via learned weight matrices: `Q = XW_Q`, `K = XW_K`, `V = XW_V`
- Attention scores: `A = softmax(QK^T / √d_k)` — scaled dot-product attention. The scaling by `√d_k` prevents vanishing gradients from large dot products
- For decoder-only (causal) attention: a mask zeros out future positions so token i only attends to tokens ≤ i
- Output: `Attention(Q,K,V) = A·V` — a weighted average of value vectors

**(b) Multi-Head Attention (MHA):**
- Run H parallel attention heads, each with smaller d_k = d_model/H (e.g., 128 dims per head in a 4096-dim model with 32 heads)
- Each head learns different relationship patterns (syntactic, semantic, positional)
- Concatenate head outputs → project back to d_model via W_O
- Modern optimization: **Grouped Query Attention (GQA)** — multiple query heads share one K/V head, reducing KV cache size 4–8×

**(c) Feed-Forward Network (FFN):**
- Two linear projections with a non-linearity: `FFN(x) = W_2 · GELU(W_1 · x)`
- Intermediate dimension is 4× d_model (e.g., 16384 for a 4096-dim model)
- Applied independently per token — this is where token-specific "computation" happens
- Modern variants use SwiGLU (Llama, Mistral) instead of ReLU for better training stability

**(d) Residual connections + Layer Norm:**
- Each sublayer wrapped with: `x = LayerNorm(x + Sublayer(x))`
- Pre-norm (norm before sublayer) is now standard; more stable at scale

**3. Output:**
- Final hidden states → linear projection to vocabulary size (e.g., 128K) → softmax → probability distribution over next token

**Why transformers beat RNNs:**
- **Parallelism:** RNNs process tokens sequentially; transformers process the full sequence at once → faster training on GPUs
- **Long-range dependencies:** RNNs suffer from vanishing gradients over long sequences; attention directly connects any two tokens in O(1) hops
- **Scalability:** transformer performance scales predictably with data and compute (Chinchilla scaling laws); RNNs didn't

### Example / Tradeoff
**Concrete example — Llama-3-8B architecture:**
- 32 transformer layers, d_model = 4096, 32 attention heads
- GQA: 8 KV heads (4 query heads share each KV head) → 4× KV cache reduction vs MHA
- FFN: SwiGLU with intermediate dim 14336
- RoPE positional encoding, context length 128K
- Total: ~8B parameters

**Key tradeoff — attention is O(n²) in sequence length:**
The attention matrix is `[seq_len × seq_len]`, so doubling the context quadruples attention compute and memory. At 128K tokens, the raw attention matrix would be 16B cells — infeasible without optimizations like FlashAttention (tiled computation that avoids materializing the full matrix) and sliding window / sparse attention patterns.

---

## Verbal script

**Opening (30s):**
"The transformer is the architecture at the heart of every modern LLM, and what makes it special is that it replaced sequential processing with parallel attention — every token can directly attend to every other token simultaneously. Let me walk through the architecture layer by layer."

**Core explanation (2–3 min):**
"I'd start with the input: text gets tokenized into subword tokens, each mapped to an embedding vector, and positional encodings are added so the model knows token order. Modern LLMs use RoPE — rotary positional embeddings — which generalize better to long contexts than the original sinusoidal encodings.

Then the input passes through N stacked transformer blocks — in a production model like LLaMA-3-70B, that's 80 layers. Each block has two key components. First, multi-head self-attention: for each token, we compute three projections — Query, Key, and Value. The attention score between token i and token j is the dot product of their Q and K vectors, scaled by √d_k to prevent large values, then softmaxed to get weights. We apply those weights to the V vectors to get the output — essentially 'for each token, which other tokens should I aggregate information from, and how much?' Multi-head means we run this H times in parallel with different projections, each head specializing in different relationship patterns.

For LLMs specifically, we use causal masking — token i can only attend to tokens 1 through i — so the model can't cheat by looking at future tokens during training or generation.

The second component is a per-token feedforward network: two linear layers with a non-linearity (SwiGLU in modern models), with a hidden dimension 4× wider than d_model. This is where a lot of the 'computation' happens — the attention layer aggregates context, the FFN transforms it.

Residual connections and layer norm wrap each sublayer, which are critical for training stability at scale."

**Tradeoff / production angle (1 min):**
"The big architectural tradeoff is attention's quadratic complexity in sequence length. The attention matrix is seq_len × seq_len — doubling context quadruples memory and compute. FlashAttention solves this by computing attention in tiles without materializing the full matrix, cutting memory from O(n²) to O(n). GQA reduces KV cache size by sharing K/V heads across multiple Q heads — Llama-3 uses 8 KV heads for 32 query heads, a 4× reduction that's critical for serving large contexts.

In production, this means you're constantly trading off context length against VRAM and latency. A 70B model with 128K context can eat 20GB just for the KV cache."

**Wrap-up (30s):**
"So a transformer is: embed tokens + positional encoding → N × (causal self-attention + FFN + residual/norm) → project to vocabulary → sample. The magic is attention enabling parallel processing and direct long-range connections, and the scale enabling emergent capability. I can go deeper on any piece — GQA, FlashAttention, RoPE, or encoder vs decoder tradeoffs."

---

## Pitfalls

- **Mistake:** Describing attention as just "the model pays attention to important words" without explaining Q/K/V matrices and the dot-product scoring mechanism — **Better:** Walk through `A = softmax(QK^T / √d_k) · V` and explain that Q and K are used for scoring relevance, V is what's actually aggregated — without this, you haven't explained *how* attention works.
- **Mistake:** Forgetting the FFN sublayer and treating transformers as "just attention" — **Better:** Emphasize that each block has two sublayers: self-attention (for context aggregation) and FFN (per-token transformation); the FFN typically has 4× more parameters than the attention sublayer and is critical for representational power.
- **Mistake:** Not knowing why transformers replaced RNNs — vague answers like "they're better" — **Better:** State the two concrete reasons: parallelism (RNNs are sequential, transformers process all positions at once → training is 10–100× faster on GPUs) and long-range dependencies (attention directly connects any two positions in O(1), no vanishing gradient over distance).

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q1: How do LLMs work?](01-001-how-do-llms-work.md) | Prerequisite overview; this is the architecture deep dive |
| [Q22: What is self-attention? How does it differ from multi-head attention?](01-022-what-is-self-attention-how-does-it-differ-from-multi-head-at.md) | Deep dive specifically on the attention mechanism |
| [Q23: What is grouped query attention (GQA)?](01-023-what-is-grouped-query-attention-gqa-how-does-it-differ-from.md) | KV cache optimization covered in this answer |

---

## One-liner recall

> Transformers stack N blocks of (causal self-attention + FFN + residual/norm), where attention scores are QK^T/√d_k applied to V vectors, enabling parallel training and O(1) long-range connections — at the cost of O(n²) attention complexity addressed by FlashAttention and GQA.
