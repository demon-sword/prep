# What is Multi-Head Latent Attention (MLA)? How does it shrink the KV cache?

**Category:** 01-llm-fundamentals
**Question #:** 049
**Source section:** §1 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
GQA is the standard answer to "how do you shrink the KV cache" — but DeepSeek-V2/V3 showed a second, more aggressive axis: compress the cache instead of sharing it. Interviewers ask about MLA to probe whether the candidate knows the state of the art beyond GQA, understands low-rank compression of K/V, and can articulate *why* positional encoding had to be decoupled for the compression to work. It separates candidates who track architecture literature from those who stopped at Llama-2-era GQA.

### Trigger phrases
- "How does DeepSeek keep its KV cache so small?"
- "What is Multi-Head Latent Attention?"
- "Beyond GQA, what else reduces KV cache memory?"
- "Why does MLA use decoupled RoPE?"

### What it tests
Understanding of KV cache anatomy (what is stored per token), low-rank compression as an alternative to head-sharing, and the interaction between positional encoding and compressed representations.

---

## Answer

### Concept
Multi-Head Latent Attention (MLA, DeepSeek-V2 — Liu et al., 2024; retained in V3) replaces the per-head K and V tensors in the KV cache with a single low-rank **latent vector** per token. Instead of caching `2 × n_heads × d_head` elements per layer, MLA caches a compressed latent `c_KV` of dimension `d_c` (512) plus a small shared rotary key (64 dims) — roughly **57× fewer elements** than MHA at DeepSeek-V2 scale. Per-head distinctness is preserved because each head reconstructs its own K/V from the latent through learned up-projections.

### Mechanism
**Compress (down-projection, cached):**
```
c_t^KV = h_t · W^DKV        # W^DKV: [d_model, d_c], d_c = 512 — cached per token
k_t^R  = RoPE(h_t · W^KR)   # decoupled rotary key, d_r = 64, shared across heads — cached
```
**Expand (up-projection, never cached):** each head `i` reconstructs its own keys/values on the fly:
```
k_t^i = c_t^KV · W^UK_i
v_t^i = c_t^KV · W^UV_i
q_t^i = c_t^Q  · W^UQ_i     # queries are likewise compressed (c^Q, dim 1536) then expanded
```

**The absorption trick (why inference stays cheap):** expanding K/V per step would just move the cost from memory to compute — so MLA never materializes them. The content attention score factors as `q·kᵀ = c^Q (W^UQ · W^UKᵀ) c^KVᵀ`, and the bracketed matrix product is **precomputed once** after training. Likewise `W^UV` is absorbed into the output projection `W^O`. At decode time the GPU reads only the latent from cache and multiplies by fused matrices — full-size K/V tensors never exist.

**Decoupled RoPE (the math that makes compression legal):** a rotary rotation does not commute with the learned up-projection — applying RoPE to the compressed latent and then expanding would scramble the relative-position structure, because the rotation would be mixed through the compression basis instead of acting per-head. So position takes a separate path: each head carries its own rotary query `q^{i,R}` (dim 64) scored against one **shared** rotary key `k^R`:
```
score^i(t,j) = (q_content^i · k_content^i) / √d  +  (q_t^{i,R} · k_j^R) / √d_r
```
Content flows through the absorbed latent path; position is explicit, tiny, and shared — costing just 64 cached elements per token.

### Example / Tradeoff
**Size example — DeepSeek-V2 dims** (60 layers, 128 heads, `d_c`=512, `d_r`=64, BF16):
- MLA per token per layer: `512 + 64 = 576` elements ≈ **1.1 KB** → full model ≈ 67.5 KB/token → **128K context ≈ 8.4 GB**.
- Same-shape MHA: `2 × 128 × 128 = 32,768` elements ≈ 64 KB/token/layer → 128K context ≈ **~490 GB** (infeasible).
- Same-shape GQA-8: `2 × 8 × 128 = 2,048` elements — MLA is still **~3.6× smaller** while keeping all 128 distinct query heads.

**Sharing versus compressing (the articulation):** GQA/MQA *share* — fewer K/V vectors, each full-dimensional, in discrete steps (`H/G`), and every query in a group sees identical keys (head diversity collapses). MLA *compresses* — one latent per token with per-head diversity restored by learned up-projections, a continuous knob (`d_c`), and strictly more expressive power per cached byte. Sharing asks "how many lockers"; compressing asks "how small can one locker be while every head still gets its own key cut from it."

**Tradeoffs:** the latent is an information bottleneck (`d_c` must be wide enough — V2 uses 4× head dim); training carries extra projections and absorption bookkeeping; the 64-dim RoPE path cannot be absorbed; and ecosystem support (vLLM kernels, quantization tooling) matured later than GQA's.

---

## Verbal script

**Opening (30s):**
"GQA shrinks the KV cache by sharing — MLA, from DeepSeek-V2, shrinks it by compressing. Instead of caching per-head keys and values, it caches one low-rank latent vector per token plus a tiny shared rotary key, about 57× smaller than MHA. I'd walk through the compress-expand mechanism, the absorption trick that keeps inference cheap, and why RoPE had to be decoupled."

**Core explanation (2–3 min):**
"Each token's hidden state is down-projected into a 512-dimensional latent, and that latent is all that gets cached — plus a 64-dim rotary key I'll come back to. Each attention head reconstructs its own K and V from the latent via learned up-projections, so unlike MQA, heads don't collapse onto identical keys — diversity is preserved.

The obvious objection is that reconstructing K/V every step just trades memory for compute. The answer is absorption: the attention score factors so that the up-projection matrices can be multiplied into the query and output projections offline, once, after training. At decode time the GPU reads only the latent and multiplies by fused matrices — full-size K and V never exist anywhere.

Then there's the RoPE problem. Rotary embeddings apply a position-dependent rotation that doesn't commute with the up-projection — you can't rotate the compressed latent and expand it and expect correct relative positions. So DeepSeek decouples position into a separate path: each head has its own 64-dim rotary query scored against a single shared rotary key. The attention score is a content term from the latent plus a position term from this path.

On DeepSeek-V2 dimensions the cache is 576 elements per token per layer versus 32,768 for MHA — about 1.1 KB versus 64 KB. A 128K context fits in ~8 GB instead of ~490 GB. And against GQA with 8 KV heads, MLA is still 3.6× smaller while keeping all 128 heads distinct."

**Tradeoff / production angle (1 min):**
"The compression rank is the knob — too narrow a latent bottlenecks quality. And in production, MLA support in serving stacks lagged GQA: you need kernels that implement the absorbed path, otherwise you pay the recomputation cost the paper designed away. But the direction is clear — sharing and compressing stack, and MLA shows compression has more headroom per byte."

**Wrap-up (30s):**
"So MLA compresses rather than shares: one latent per token, per-head keys cut from it by up-projection, absorption keeping inference cheap, and decoupled RoPE keeping positions correct. Happy to go deeper on the absorption math or the sharing-versus-compressing tradeoff."

---

## Pitfalls

- **Mistake:** Describing MLA as "sharing KV across heads like GQA/MQA" — **Better:** State the contrast explicitly: GQA shares full-dimensional K/V across head groups (diversity collapses); MLA caches one latent and each head expands its *own* K/V via up-projection (diversity preserved). Sharing reduces the number of vectors; compressing reduces the dimension of what is stored.
- **Mistake:** Saying RoPE is applied to the latent vector — **Better:** Explain that this is exactly what decoupling avoids: the rotary rotation does not commute with the up-projection, so position travels a separate explicit path (per-head rotary queries against one shared rotary key) added to the content score.
- **Mistake:** Claiming MLA only saves memory capacity — **Better:** Connect it to bandwidth: decode is memory-bandwidth-bound, so loading ~57× fewer bytes per step raises throughput directly — and the absorption trick means the compute side stays flat because full K/V are never materialized.
- **Mistake:** Citing MLA without numbers — saying "much smaller cache" without the 576-vs-32768 arithmetic — **Better:** Memorize the V2 dims (d_c=512, d_r=64, 128 heads × 128 dim) and the ~1.1 KB/token/layer figure; the size example is what makes the answer credible.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q9: What is KV cache? How does it help in LLM inference?](01-009-what-is-kv-cache-how-does-it-help-in-llm-inference.md) | Prerequisite — MLA compresses exactly the K/V tensors the KV cache stores |
| [Q23: What is grouped query attention (GQA)?](01-023-what-is-grouped-query-attention-gqa-how-does-it-differ-from.md) | Contrast — GQA shrinks cache by head sharing; MLA by low-rank compression |
| [Q27: What is positional encoding and why is it needed?](01-027-what-is-positional-encoding-and-why-is-it-needed.md) | Prerequisite — MLA's decoupled RoPE path assumes RoPE mechanics |
| [Q34: Why is LLM inference memory-bounded?](01-034-why-is-llm-inference-memory-bounded.md) | Follow-up — MLA cuts the bytes loaded per decode step, the memory-bound bottleneck |

---

## One-liner recall

> MLA caches one low-rank latent (512-dim) plus a shared 64-dim rotary key per token instead of per-head K/V — ~57× smaller than MHA — with per-head up-projections (absorbed into Q/O at inference) restoring head diversity and decoupled RoPE keeping positions correct: compressing beats sharing per cached byte.
