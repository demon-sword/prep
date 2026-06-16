# What is grouped query attention (GQA)? How does it differ from standard multi-head attention?

**Category:** 01-llm-fundamentals
**Question #:** 023
**Source section:** §1 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
This question probes whether you understand the memory bottleneck in LLM inference and know the architectural innovations used to address it in production models. Interviewers at companies running inference at scale (Anthropic, OpenAI, Google, any team deploying Llama/Mistral) want to see that you can reason about GPU memory bandwidth, KV cache footprint, and throughput — not just explain attention conceptually.

### Trigger phrases
- "How does Llama 3 / Mistral / Gemma differ from GPT architectures?"
- "What is GQA and why do modern models use it?"
- "How do you reduce KV cache memory without sacrificing quality?"
- "Walk me through multi-head vs multi-query vs grouped-query attention."

### What it tests
Understanding of the memory-bandwidth bottleneck in autoregressive inference and the engineering tradeoffs between KV cache size, model quality, and throughput.

---

## Answer

### Concept
Grouped Query Attention (GQA) is an attention variant that shares Key and Value projection weights across groups of Query heads, reducing KV cache memory and memory-bandwidth pressure during inference without meaningfully degrading model quality compared to full Multi-Head Attention (MHA).

It sits on a spectrum:
- **MHA (Multi-Head Attention):** H query heads, H key heads, H value heads — each head has its own K/V projections. KV cache scales as `2 × H × d_head × seq_len × batch`.
- **MQA (Multi-Query Attention):** H query heads share a single K head and single V head. Maximum memory savings but quality loss on complex tasks.
- **GQA (Grouped-Query Attention):** H query heads divided into G groups (G < H); each group shares one K head and one V head. G=1 collapses to MQA; G=H collapses to MHA. GQA with G≈4–8 matches MHA quality while approaching MQA memory efficiency.

### Mechanism
**Standard MHA:**
```
Q = X·Wq  shape: [B, seq, H, d_head]
K = X·Wk  shape: [B, seq, H, d_head]
V = X·Wv  shape: [B, seq, H, d_head]
Attn(Q,K,V) per head → concat → project
```
Each of H heads maintains its own K/V in the KV cache. For Llama-2-70B with H=64 heads, d_head=128, batch=32, seq=4096: KV cache ≈ 2 × 64 × 128 × 4096 × 32 × 2 bytes ≈ **68 GB**.

**GQA with G groups:**
```
Q heads: H (e.g. 32)
K/V heads: G (e.g. 8)  — each K/V head serves H/G = 4 query heads
KV cache: 2 × G × d_head × seq_len × batch
```
For Llama-2-70B with GQA (G=8): KV cache shrinks 8× to ~**8.5 GB** — the difference between fitting in GPU VRAM or not.

**How queries access grouped K/V at inference:**
Each query head selects its group's K and V tensors. The attention computation is otherwise identical — just fewer unique K/V projections to store and load from memory.

**Why it matters for throughput:** LLM decoding is memory-bandwidth-bound (not compute-bound). Each decode step loads all KV tensors from HBM. Fewer K/V heads = fewer bytes read = faster decode = higher tokens/sec.

### Example / Tradeoff
- **Llama 3 (8B, 70B):** GQA with 8 KV heads (vs 32 or 64 query heads).
- **Mistral 7B:** GQA with 8 KV heads — fits on a single 24 GB GPU for long contexts.
- **Gemma 2:** Uses GQA across all sizes.
- **GPT-4 / earlier GPT-3:** MHA (pre-GQA era).

**Quality tradeoff:** Ainslie et al. (2023, Google Research) showed GQA with G=H/4 to H/8 matches MHA perplexity within ~0.1–0.3 PPL on language modeling tasks, while MQA (G=1) degrades 0.5–2 PPL depending on task. GQA is the dominant choice in models released 2023–2026.

**Conversion from MHA checkpoint:** Models pre-trained with MHA can be converted to GQA by mean-pooling K/V heads within each group and fine-tuning briefly (~5% of original training compute) to recover quality — used in the Llama-2 → 3 transition.

| Variant | KV heads | KV cache size | Quality | Throughput |
|---------|----------|---------------|---------|------------|
| MHA | H (32) | 100% | Best | Baseline |
| GQA (G=8) | 8 | 25% | ≈MHA | ~2–3× MHA |
| MQA (G=1) | 1 | 3% | -0.5–2 PPL | ~4× MHA |

---

## Verbal script

**Opening (30s):**
"GQA is one of my favorite architecture questions because it's directly tied to a real production constraint. The core problem is: standard multi-head attention stores one Key and Value tensor per head in the KV cache, and that cache grows linearly with heads, batch size, and sequence length. At 70B scale with 64 heads and a 4K context, that's tens of gigabytes just for the KV cache. GQA solves this by sharing K/V projections across groups of query heads."

**Core explanation (2–3 min):**
"Let me put it on a spectrum. In full MHA, every query head has its own K and V — so if you have 32 query heads, you have 32 K heads and 32 V heads in the cache. In Multi-Query Attention, the extreme version, all 32 query heads share a single K and single V. That's memory-efficient but hurts quality on complex tasks. GQA splits the difference: 32 query heads are organized into, say, 8 groups, and each group shares one K and one V. So the KV cache is 8× smaller than MHA while quality stays within ~0.1–0.3 perplexity points.

The reason this matters at inference time is that LLM decoding is memory-bandwidth-bound, not compute-bound. Each decode step doesn't do matrix multiplications — it loads K and V from HBM for each token generated. Fewer K/V heads means fewer bytes transferred per decode step, which translates directly to higher tokens-per-second. In practice, Mistral 7B with GQA on a 24 GB GPU can serve much longer contexts at higher throughput than an equivalent MHA model.

A concrete example: Llama 3 uses GQA across all sizes — 8B has 8 KV heads vs 32 query heads, and 70B has 8 KV heads vs 64 query heads. The KV cache savings are what allow Llama 3 70B to be deployed on 2–4 A100s rather than requiring 8."

**Tradeoff / production angle (1 min):**
"The main tradeoff is quality vs memory. GQA is essentially a free lunch at G=H/4 to H/8 — quality loss is negligible. The only case where MHA still dominates is very small models with few heads to begin with, where the grouping doesn't make architectural sense. In production with vLLM, GQA is handled natively — PagedAttention is aware of head grouping, so you get both memory efficiency and good batch scheduling out of the box."

**Wrap-up (30s):**
"So in summary: GQA reduces KV cache footprint by sharing K/V projections across groups of query heads. It's the reason modern frontier models — Llama 3, Mistral, Gemma — can run longer contexts at higher throughput without quality loss. It's become the default architectural choice for any model you'd deploy in production today."

---

## Pitfalls

- **Mistake:** Confusing GQA with MQA — saying "GQA means all heads share one K/V" — **Better:** Clarify the spectrum: MHA (each head independent) → GQA (grouped sharing) → MQA (single shared K/V). GQA is the middle ground with G groups.
- **Mistake:** Describing GQA as a pure training optimization rather than an inference optimization — **Better:** Emphasize that KV cache is the key bottleneck at inference time; GQA reduces bytes loaded from HBM per decode step, which is why it improves throughput and enables longer contexts on fixed VRAM.
- **Mistake:** Not knowing which production models use GQA — **Better:** Cite Llama 3, Mistral 7B, Gemma 2, and mention that vLLM and TGI both support GQA natively; this shows production familiarity beyond textbook knowledge.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q22: What is self-attention? How does it differ from multi-head attention?](01-022-what-is-self-attention-how-does-it-differ-from-multi-head-at.md) | Prerequisite — GQA is a variant of MHA; need MHA mechanics first |
| [Q9: What is KV cache? How does it help in LLM inference?](01-009-what-is-kv-cache-how-does-it-help-in-llm-inference.md) | Core dependency — GQA's primary benefit is reducing KV cache footprint |
| [Q33: What is FlashAttention and how does it work?](01-033-what-is-flashattention-and-how-does-it-work.md) | Complementary optimization — FlashAttention addresses compute/memory IO; GQA addresses cache size; both deployed together in modern serving stacks |

---

## One-liner recall

> GQA groups the H query heads into G clusters (G < H) that share a single K/V projection each, shrinking the KV cache by H/G× and boosting decode throughput without meaningfully degrading quality — the default attention variant in Llama 3, Mistral, and Gemma.
