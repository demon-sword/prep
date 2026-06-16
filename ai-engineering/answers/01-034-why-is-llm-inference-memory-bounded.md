# Why is LLM inference memory-bounded?

**Category:** 01-llm-fundamentals
**Question #:** 034
**Source section:** §1 (Architecture deep dives)
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
This question probes whether you understand the *actual* hardware bottleneck in production LLM serving — not the theoretical compute cost, but the practical memory-bandwidth wall that dominates decode latency. Senior candidates are expected to reason about GPU memory bandwidth, arithmetic intensity, and how design decisions like GQA, quantization, and speculative decoding shift the bottleneck.

### Trigger phrases
- "Why doesn't throwing more GPU compute speed up generation?"
- "What's the real bottleneck in LLM serving throughput?"
- "Why is decode so much slower than prefill?"
- "How does PagedAttention / vLLM actually help?"

### What it tests
Understanding of the memory-bandwidth bottleneck in autoregressive decode and how production systems (vLLM, TGI, GQA, quantization) address it.

---

## Answer

### Concept
LLM inference during the **decode phase** is memory-bandwidth-bound, not compute-bound. For each new token generated, the GPU must load all model weights from HBM (high-bandwidth memory) into SRAM — but the actual arithmetic performed on those weights is tiny (just one token's worth of activations). The ratio of compute operations to bytes transferred — called **arithmetic intensity** — is far too low to keep GPU cores busy; the bottleneck is how fast weights can be streamed from memory, not how fast the cores multiply.

### Mechanism

**Two phases of inference:**

| Phase | Behavior | Bottleneck |
|-------|----------|------------|
| **Prefill** | Process all prompt tokens in parallel (one big matrix-matrix multiply) | Compute-bound (high arithmetic intensity) |
| **Decode** | Generate one token at a time (matrix-vector multiply per step) | Memory-bandwidth-bound (low arithmetic intensity) |

**Why decode is memory-bound:**

- A 70B-parameter model in FP16 requires ~140 GB of weight data.
- Each decode step loads all 140 GB of weights from HBM to perform a tiny matrix-vector product (~140 GB × 2 flops/byte = ~280 GFLOPs of work).
- An A100 80 GB GPU delivers ~2 TB/s HBM bandwidth but ~312 TFLOPS of FP16 compute.
- Arithmetic intensity needed to be compute-bound: ~312 TFLOPS / 2 TB/s = ~156 FLOPs/byte.
- Actual decode intensity: ~2 FLOPs/byte (one token). **75× below the roofline** — solidly memory-bound.

**KV cache compounds the problem:**
- Every decode step must also load cached K/V tensors for all prior tokens from HBM.
- KV cache size: `2 × num_layers × num_heads × head_dim × seq_len × batch × dtype_bytes`.
- For a 70B model at 4K context, batch=16: ~20 GB of KV cache — eating into the already-tight 80 GB HBM budget.

**Production consequences:**
- Increasing batch size is the primary lever: with B=64 requests sharing a decode step, the same weight load serves 64 tokens, raising effective arithmetic intensity.
- But batch size is limited by KV cache memory — hence vLLM's **PagedAttention**: KV cache blocks are allocated on demand (like OS virtual memory paging), minimizing waste from reserved-but-unused slots, allowing 2–4× larger effective batch sizes.

### Example / Tradeoff

**vLLM benchmark (A100 80 GB, LLaMA-2 13B):**
- Naïve HuggingFace serving: ~400 tokens/s throughput at batch=1, stalls at batch=8 (OOM).
- vLLM with PagedAttention: ~2,400 tokens/s at batch=32+ — ~6× improvement, same hardware.

**GQA (Grouped Query Attention)** directly attacks KV cache bandwidth: Llama 3 70B uses 8 KV heads instead of 64, reducing KV cache size by 8×, freeing HBM for larger batches.

**Quantization (INT8/INT4):** halving weight size halves memory-bandwidth requirement per step, nearly doubling decode throughput — e.g., AWQ INT4 on Llama 3 70B cuts per-step weight load from ~140 GB to ~35 GB, roughly 4× faster decode on bandwidth-limited GPUs.

**Speculative decoding** side-steps per-step bandwidth cost: a small draft model proposes N tokens, the large model verifies all N in one prefill-like step (compute-bound again), accepting tokens that match. Effective throughput can double at no accuracy cost.

---

## Verbal script

**Opening (30s):**
"LLM inference has two distinct phases with completely different bottlenecks — and most people conflate them. Prefill, where you process the prompt, is compute-bound: lots of tokens, big matrix multiplications, GPUs are happy. Decode, where you generate one token at a time, is memory-bandwidth-bound, and that's the production problem I want to explain."

**Core explanation (2–3 min):**
"During decode, the model has to load all its weights from HBM into SRAM for every single token it generates. For a 70B model in FP16, that's 140 gigabytes of data movement per step — but you only do a matrix-vector multiply on that data, not a matrix-matrix multiply. The arithmetic intensity, meaning FLOPs per byte transferred, is around 2 — but a modern A100 needs about 156 FLOPs per byte to stay compute-bound. So the GPU cores are sitting idle more than 90% of the time waiting for data to arrive from HBM.

The KV cache makes this worse. Every decode step also loads cached keys and values for all prior tokens. At long contexts with large batches, the KV cache itself can consume tens of gigabytes of HBM, crowding out space for more requests.

The primary fix is batch size: if you serve 64 requests simultaneously, one weight-load services 64 tokens, pushing arithmetic intensity up toward the compute-bound region. But bigger batches demand more KV cache memory — which is exactly what vLLM's PagedAttention solves. It treats KV cache blocks like OS virtual memory pages, allocating them on demand rather than reserving contiguous chunks upfront. In practice this gives 2–4× more effective batch capacity on the same hardware."

**Tradeoff / production angle (1 min):**
"There are several complementary levers. GQA — which Llama 3 uses — reduces KV heads from 64 to 8, shrinking KV cache by 8× and freeing HBM headroom for more concurrent requests. Quantization (INT4/INT8) halves or quarters the weight data per step, nearly linearly improving decode throughput on bandwidth-limited cards. Speculative decoding converts the bottleneck from many small memory-bound steps to fewer large compute-bound verification steps, roughly doubling throughput for low-entropy outputs.

The tradeoff to watch is that quantization trades accuracy for bandwidth; speculative decoding adds latency variance on high-entropy outputs; and aggressive batching increases p99 latency for individual requests even as throughput climbs."

**Wrap-up (30s):**
"So the key mental model is: decode is a streaming problem, not a compute problem. Every optimization that either reduces bytes read per step (GQA, quantization) or amortizes reads across more tokens (batching, speculative decoding) moves the needle. Happy to go deeper on PagedAttention mechanics or the speculative decoding acceptance criterion."

---

## Pitfalls

- **Mistake:** Saying "LLM inference is slow because the model is big and needs lots of compute" — **Better:** Distinguish prefill (compute-bound) from decode (memory-bandwidth-bound); the bottleneck during generation is *data movement*, not arithmetic.
- **Mistake:** Claiming more GPU cores or higher TFLOPS directly speeds up decode — **Better:** Explain that decode arithmetic intensity (~2 FLOPs/byte) is far below the compute-bound threshold (~156 FLOPs/byte on A100); adding cores helps prefill, not decode.
- **Mistake:** Describing vLLM/PagedAttention as "just a memory optimization" without connecting it to batch size and throughput — **Better:** Explain that PagedAttention's real impact is allowing 2–4× larger effective batches (which directly raises arithmetic intensity and throughput) by eliminating KV cache fragmentation.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q9: What is KV cache? How does it help in LLM inference?](01-009-what-is-kv-cache-how-does-it-help-in-llm-inference.md) | Prerequisite — KV cache mechanics underpin the memory-bound argument |
| [Q23: What is grouped query attention (GQA)?](01-023-what-is-grouped-query-attention-gqa-how-does-it-differ-from.md) | Direct mitigation — GQA reduces KV cache size and memory bandwidth per step |
| [Q33: What is FlashAttention and how does it work?](01-033-what-is-flashattention-and-how-does-it-work.md) | Related optimization — FA reduces HBM reads during prefill via tiling |

---

## One-liner recall

> LLM decode is memory-bandwidth-bound because each generated token requires loading all model weights and KV cache from HBM (~140 GB for 70B) for only ~2 FLOPs/byte of actual arithmetic — far below the compute-bound threshold — making batch size, GQA, quantization, and PagedAttention the key production levers.
