# Real bottleneck in LLM serving throughput? PagedAttention?

**Category:** 07-cost-latency
**Question #:** 016
**Source section:** §9 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
This is a senior serving-infrastructure question probing whether you understand *why* GPU throughput in LLM serving is limited — not vaguely ("the GPU is busy") but mechanically. Interviewers at companies running self-hosted models (Anthropic, Mistral, any team with >$50K/month GPU spend) want to know you can distinguish compute-bound from memory-bound bottlenecks, explain KV cache fragmentation as the concrete throughput killer, and articulate exactly what PagedAttention does to fix it.

### Trigger phrases
- "What's the real bottleneck in LLM serving throughput?"
- "Why does PagedAttention improve throughput?"
- "How does vLLM's memory management work?"
- "We're running out of GPU memory before we hit compute limits — why?"
- "KV cache fragmentation — what is it and why does it matter?"

### What it tests
Understanding of the memory-bandwidth bottleneck in autoregressive decode, KV cache memory fragmentation as the primary throughput ceiling in practice, and how PagedAttention's OS-paging analogy solves it to enable higher batch concurrency.

---

## Answer

### Concept
The **real throughput bottleneck** in LLM serving is not compute — it is **GPU HBM memory**, specifically the KV cache. During autoregressive decode every in-flight request holds a growing KV tensor in GPU memory (one key and value vector per attention head per token generated so far). With naive memory management, this causes two problems: (1) **fragmentation** — memory is allocated in contiguous chunks per request and freed only when the request finishes, leaving unusable gaps; and (2) **over-reservation** — systems must pre-allocate worst-case sequence length per request, wasting memory for requests that finish early. Both reduce the number of concurrent requests (batch size) that fit in GPU memory, which directly caps throughput.

**PagedAttention** (introduced in the vLLM paper, Kwon et al. 2023) solves this by storing the KV cache in fixed-size, non-contiguous *pages* — analogous to OS virtual memory paging — eliminating fragmentation and enabling near-zero memory waste. The result: vLLM achieves 2–24× higher throughput than Hugging Face TGI and FasterTransformer on the same hardware, primarily because it can fit more concurrent requests in GPU memory.

### Mechanism

**Why the KV cache is the bottleneck**

During prefill (processing the prompt), attention keys and values for each layer are computed and stored in HBM. During each decode step (generating one new token), those stored KV tensors are read back for the attention computation. As the sequence grows, the KV tensor grows linearly: one KV entry per token, per layer, per head.

Memory footprint of KV cache per request:
```
KV bytes = 2 × num_layers × num_heads × head_dim × seq_len × dtype_bytes
         = 2 × 32 × 32 × 128 × 2048 × 2   ← Llama 3 8B, BF16, 2048-token seq
         ≈ 1.07 GB per request
```
An A100 80GB with a Llama 3 8B model loaded (~16 GB weights) has ~64 GB free for KV cache — supporting only ~60 concurrent requests at max seq_len. More realistic usage: 15–20 requests when accounting for fragmentation with naive allocation.

**The fragmentation problem (before PagedAttention)**

Traditional serving systems allocate a contiguous HBM block per request at the start, sized to the *maximum possible* output length (e.g., `max_tokens=2048`). Problems:
1. **Internal fragmentation:** a 500-token response uses only 25% of its 2048-token allocation; the rest is wasted.
2. **External fragmentation:** finished requests free their blocks, but the gaps are rarely perfectly sized for new requests.
3. **Head-of-line blocking:** a long request occupying a large contiguous block prevents shorter requests from starting even if enough total memory is free.

The result: GPU HBM utilization for KV cache is typically only 20–40% efficient with naive allocation.

**PagedAttention: the fix**

PagedAttention divides KV cache memory into fixed-size *blocks* (e.g., 16 tokens per block). Each request's KV cache is stored across a list of non-contiguous blocks, mapped by a per-request block table (analogous to a virtual-memory page table). Key properties:

| Property | Traditional | PagedAttention |
|----------|------------|----------------|
| Allocation unit | Contiguous chunk (max_seq_len) | Fixed block (16 tokens) |
| Internal fragmentation | Up to (max_seq_len − actual_len) tokens | At most (block_size − 1) tokens |
| External fragmentation | High (varied block sizes) | Zero (all blocks identical size) |
| Memory sharing | Not possible | Blocks shared across requests (e.g. prefix caching) |
| GPU memory utilization | 20–40% effective | >95% effective |

**Enabling prefix caching (bonus throughput win)**

Because blocks are addressable units, blocks corresponding to a shared prompt prefix (e.g., a common system prompt) can be *shared across requests* rather than duplicated. vLLM's prefix caching (`--enable-prefix-caching`) maps the same physical blocks to multiple requests' block tables. On a RAG chatbot where all requests share a long system prompt, this can eliminate 30–50% of KV memory usage, directly increasing concurrency.

**Continuous batching — the scheduling complement**

PagedAttention solves memory management; continuous batching (iteration-level scheduling) solves scheduling. At each decode step, vLLM checks if any sequence has finished and immediately admits a new request to fill that slot, rather than waiting for the whole static batch to drain. Together, these two techniques are why vLLM achieves dramatically higher throughput than naive serving systems.

**Full throughput bottleneck stack (priority order)**

```
1. KV cache memory fragmentation (solved by PagedAttention)
   → Increases effective batch size from ~15 to ~60+ concurrent requests

2. Memory bandwidth (structural; partially mitigated by GQA, KV quantization)
   → Decode is ~2 FLOPs/byte at batch=1; larger batches raise arithmetic intensity

3. Static batching waste (solved by continuous batching)
   → Prevents short requests from being blocked by long ones

4. Prefill compute (for long contexts, prefill is compute-bound)
   → Chunked prefill interleaves prefill with decode to avoid decode stalls
```

### Example / Tradeoff

**vLLM vs HuggingFace TGI on LLaMA-13B (Kwon et al. 2023):**

| System | KV cache efficiency | Throughput (req/s) | vs baseline |
|--------|--------------------|--------------------|-------------|
| HuggingFace TGI | ~20–40% HBM utilization | 1× | — |
| FasterTransformer | ~30–50% | 1.4× | +40% |
| vLLM (PagedAttention) | >95% | 2–24× | up to 24× |

The 24× figure occurs at high request concurrency where fragmentation is worst. At low concurrency, the gain is smaller (2–4×) because fragmentation matters less.

**Practical config for maximizing throughput on a single A100 80GB with Llama 3 8B:**
```bash
vllm serve meta-llama/Meta-Llama-3-8B-Instruct \
  --max-num-seqs 256 \           # high concurrency — PagedAttention handles KV memory
  --max-num-batched-tokens 32768 \  # large batch token budget
  --enable-prefix-caching \      # share system-prompt KV blocks
  --kv-cache-dtype fp8 \         # 2× KV memory compression, ~1% quality loss
  --max-model-len 4096            # avoid allocating blocks for unused long seqs
```
Result: ~1,800 tokens/second sustained throughput vs ~150 tokens/second with naively batched TGI at the same concurrency level.

**Tradeoff:** PagedAttention's block table introduces a small per-step memory lookup overhead (~2–5 μs per decode step). Negligible vs the HBM bandwidth transfer time (~1–2 ms per decode step), so the overhead is always worth it. The only case where it doesn't help is single-request latency-optimized serving (batch size = 1), where fragmentation is moot — but even there, prefix caching still reduces KV compute.

---

## Verbal script

**Opening (30s):**
"The real throughput bottleneck in LLM serving isn't compute — it's GPU HBM memory, specifically the KV cache. And within KV cache memory, the problem is fragmentation. PagedAttention is vLLM's solution to that fragmentation problem, borrowed directly from how operating systems manage virtual memory. Let me walk through why fragmentation is so damaging and exactly what PagedAttention does to fix it."

**Core explanation (2–3 min):**
"During autoregressive decode, every in-flight request holds a KV tensor in GPU memory — one key and value per attention head per layer per token generated so far. For a Llama 3 8B model in BF16, that's about 1 GB of KV memory per request at 2048 tokens. An A100 80GB with the model loaded has roughly 64 GB left for KV cache — theoretically 60 concurrent requests. But with naive memory allocation, you almost never get that.

The problem is fragmentation. Traditional systems allocate a contiguous HBM block per request sized to the maximum possible output length — say 2048 tokens — at request arrival. A request that finishes in 300 tokens wastes 85% of its allocation until it's done and freed. Those freed blocks are often the wrong size for new incoming requests. In practice, you get 20–40% effective KV memory utilization, which means you're serving maybe 15–20 concurrent requests on hardware capable of 60.

PagedAttention fixes this by dividing KV memory into fixed-size blocks — say 16 tokens each — and giving each request a block table that points to wherever its blocks happen to live in memory. No contiguous allocation required. When a request needs one more block, it grabs any free block. When it finishes, those blocks return to the free pool immediately. Internal fragmentation drops from potentially thousands of tokens wasted per request to at most 15 tokens (one block minus one). External fragmentation drops to zero because all blocks are identical size.

The result is over 95% effective KV memory utilization, which directly translates to fitting far more concurrent requests in GPU memory. Higher concurrency means larger effective batch size, which means better amortization of weight transfers from HBM, which is the memory-bandwidth bottleneck for decode. So PagedAttention improves throughput by attacking the memory capacity constraint that limits batch size, not the bandwidth constraint itself — but those two constraints are linked.

The vLLM paper showed 2–24× throughput improvement over Hugging Face TGI on LLaMA-13B, purely from this memory management improvement — same hardware, same model, same request distribution."

**Tradeoff / production angle (1 min):**
"There are a couple of things to layer on top. First, prefix caching: because KV blocks are addressable units, blocks for a shared system prompt can be shared across all requests simultaneously — the same physical blocks appear in multiple requests' block tables. On a RAG chatbot where every request starts with a long grounding prompt, this eliminates 30–50% of KV memory usage and lets you push concurrency even higher.

Second, KV quantization: by storing keys and values in FP8 instead of BF16, you halve KV memory consumption with about 1% quality loss, which again directly multiplies the concurrent-request capacity. And GQA — grouped query attention in Llama 3 and Mistral — reduces the number of KV heads by a factor of 4–8, shrinking KV size proportionally.

The throughput ceiling after PagedAttention shifts from memory fragmentation to actual memory bandwidth. That's the fundamental limit that compute-bound work doesn't hit."

**Wrap-up (30s):**
"So the one-sentence answer is: the real throughput bottleneck before PagedAttention was KV cache fragmentation wasting 60–80% of GPU HBM memory, limiting batch size far below hardware capacity. PagedAttention's fixed-size non-contiguous block allocation brings effective memory utilization above 95%, which enables 2–24× more concurrent requests and proportionally higher throughput — with continuous batching handling the scheduling side. Happy to go deeper on chunked prefill, KV quantization, or the speculative decoding interaction."

---

## Pitfalls

- **Mistake:** Saying the bottleneck is "compute" or "GPU utilization" without distinguishing memory-bandwidth-bound decode from compute-bound prefill — **Better:** Explicitly state that decode is memory-bandwidth-bound (arithmetic intensity ~2 FLOPs/byte at batch=1, far below A100's 156-FLOPs/byte roofline), so the throughput limit is how many concurrent requests fit in HBM memory, not how fast the GPU can compute.
- **Mistake:** Describing PagedAttention as just "KV cache paging" without explaining *why fragmentation matters* — "it's more memory efficient" — **Better:** Quantify the fragmentation problem: traditional systems achieve only 20–40% effective HBM utilization for KV cache because of fixed contiguous allocation; PagedAttention raises this to >95%, directly multiplying the sustainable batch size by 2–5× on the same hardware.
- **Mistake:** Crediting continuous batching (not PagedAttention) as the source of vLLM's throughput gains — **Better:** Distinguish the two: continuous batching solves *scheduling* waste (short requests blocked behind long ones in static batches); PagedAttention solves *memory allocation* waste (fragmentation limiting how many requests fit at all). Both are required; PagedAttention is the larger gain at high concurrency.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q14: Latency vs throughput for LLM serving?](07-014-latency-vs-throughput-for-llm-serving.md) | Prerequisite — establishes the latency/throughput curve and why batch size matters |
| [Q3: How reduce latency in GenAI applications?](07-003-how-reduce-latency-in-genai-applications.md) | Application-level latency levers (streaming, caching, tiering) that complement serving-layer optimization |
| [Q6: Quantization and model distillation for inference?](07-006-quantization-and-model-distillation-for-inference.md) | KV quantization (FP8/INT8 keys/values) directly reduces KV cache memory pressure and extends PagedAttention's concurrency gains |

---

## One-liner recall

> The real LLM serving throughput bottleneck is KV cache memory fragmentation: traditional contiguous-allocation schemes waste 60–80% of GPU HBM (achieving only 20–40% effective utilization), capping batch concurrency far below hardware capacity; PagedAttention borrows OS virtual-memory paging to store KV tensors in fixed-size non-contiguous blocks (>95% HBM utilization, 2–24× throughput gain in the vLLM paper), with prefix caching and KV quantization (FP8) providing further concurrency multipliers.
