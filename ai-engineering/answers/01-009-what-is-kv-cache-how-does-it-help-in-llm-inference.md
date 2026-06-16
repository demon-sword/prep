# What is KV cache? How does it help in LLM inference?

**Category:** 01-llm-fundamentals
**Question #:** 009
**Source section:** §1 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
KV cache is one of the most important inference optimizations in production LLM systems. Interviewers ask this to probe whether the candidate understands *why* autoregressive generation is expensive, how memory bandwidth is the bottleneck (not compute), and how caching eliminates redundant work. Senior roles expect the candidate to discuss PagedAttention and GPU memory tradeoffs.

### Trigger phrases
- "How does KV cache work?"
- "How do you reduce inference latency for long conversations?"
- "What is the memory bottleneck in LLM serving?"
- "How does vLLM / TGI optimize throughput?"

### What it tests
Understanding of the autoregressive decoding loop and the memory/compute tradeoffs that define production LLM serving.

---

## Answer

### Concept
KV cache (key-value cache) stores the intermediate attention key and value tensors computed for all previous tokens so they don't need to be recomputed when generating each new token. In autoregressive decoding, the model generates one token at a time and attends to every prior token — without caching, this means re-running the full attention computation over the growing sequence on every step. KV cache reduces per-step compute from O(n²) to O(n) by keeping prior K/V tensors in GPU SRAM or HBM.

### Mechanism
During the **prefill phase**, the prompt is processed in parallel and all K/V tensors are computed and stored in a cache (typically GPU HBM). During the **decode phase**, each new token computes only its own Q/K/V vectors and then attends over the cached K/V tensors for all prior tokens — no recomputation of past tokens. Cache grows by one row per token per layer per head. Memory footprint: `2 × n_layers × n_heads × head_dim × seq_len × bytes_per_param`. For a 70B model at FP16, a 4K token context consumes ~8 GB of KV cache alone.

**PagedAttention (vLLM):** The KV cache for a request can be fragmented across non-contiguous GPU memory blocks (like OS paging), eliminating internal fragmentation and enabling much higher throughput. vLLM reports 2–4× throughput gain over naive contiguous allocation because GPU memory is shared more efficiently across concurrent requests.

### Example / Tradeoff
A 4K-token conversation with GPT-4 scale model: without KV cache each decode step re-processes all 4K tokens (~quadratic cost). With KV cache each step processes exactly 1 new token. Time-to-first-token (TTFT) reflects prefill cost; inter-token latency (ITL) reflects per-decode-step cost. vLLM, TGI (Hugging Face Text Generation Inference), and TensorRT-LLM all implement KV cache as the baseline optimization.

**Tradeoff:** Cache is memory-hungry. A long context or large batch fills GPU HBM, forcing smaller batch sizes (lower throughput). Solutions include quantized KV cache (KVQuant: 4-bit K/V ≈ 4× memory reduction with minimal quality loss), sliding-window attention (Mistral's approach — cache only last W tokens), and cache eviction policies (SnapKV, H2O). There's an inherent tension: longer contexts → bigger cache → less room for batching → lower throughput.

---

## Verbal script

**Opening (30s):**
"KV cache is the single most important optimization in LLM inference. I'd frame it by first explaining why autoregressive decoding is expensive without it, then walk through exactly what gets cached and why, and finally talk about the production tradeoffs around memory."

**Core explanation (2–3 min):**
"When an LLM generates text, it works token by token — it can only produce one token at a time. At each step, the transformer's self-attention mechanism needs to look at every previous token. Without any caching, that means re-running the full attention computation over the entire sequence every single step — cost grows quadratically with sequence length.

The KV cache eliminates that redundancy. In the self-attention mechanism, every token produces three vectors: a Query, a Key, and a Value. For past tokens, the Q vector is irrelevant once we've computed attention — what matter for future steps are the K and V tensors. So we cache them. During what's called the 'prefill' phase, we process the full prompt in parallel and store all the K and V tensors in GPU memory. Then during 'decode', each new token only needs to compute its own Q/K/V, then read the cached Ks and Vs for all prior tokens — no recomputation.

The memory footprint scales as: 2 × layers × heads × head_dim × sequence_length × bytes. For a 70B model at FP16, a 4K token sequence can consume ~8 GB of KV cache alone — that's the memory pressure side of the tradeoff."

**Tradeoff / production angle (1 min):**
"The big production challenge is that KV cache competes with the model weights and the activations for GPU HBM. As batch size or sequence length grows, the cache fills memory and you're forced to reduce batch size — which kills throughput. vLLM's PagedAttention solves a lot of this by managing the cache like virtual memory, allocating it in non-contiguous pages and sharing pages between requests. That alone gives 2–4× throughput improvement. Beyond that, you can quantize the KV cache to INT4/INT8 with KVQuant, or use sliding-window attention like Mistral does, which caps cache size by only attending to the last W tokens rather than the full history."

**Wrap-up (30s):**
"So KV cache converts per-step cost from O(n²) to O(n) and is foundational to making LLM serving practical. The remaining challenge is memory management at scale — which is where PagedAttention and KV quantization come in. Happy to go deeper on any of those."

---

## Pitfalls

- **Mistake:** Describing KV cache as just "saving computation" without specifying *what* is cached (K and V tensors from past tokens) and *why* Q is not cached — **Better:** Explain that Q is only needed to compute the current token's attention weights, while K and V are reused by all future tokens, so caching K/V eliminates all redundant re-reads.
- **Mistake:** Ignoring memory cost — saying KV cache "just makes things faster" without mentioning that it is a major GPU memory consumer that constrains batch size and throughput — **Better:** Quantify the footprint (e.g., 8 GB for a 70B model at 4K tokens) and mention PagedAttention / KV quantization as the production responses.
- **Mistake:** Conflating TTFT (time to first token, dominated by prefill) with ITL (inter-token latency, dominated by decode + cache reads) — **Better:** Distinguish the two latency phases: prefill processes the full prompt in parallel once; decode processes one token at a time with cached K/V reads.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q2: How do transformers work?](01-002-how-do-transformers-work.md) | Prerequisite — self-attention Q/K/V mechanics underpin why KV cache works |
| [Q34: Why is LLM inference memory-bounded?](01-034-why-is-llm-inference-memory-bounded.md) | Follow-up — KV cache is the dominant reason inference is memory-bound at decode time |
| [Q11: How reduce latency in GenAI applications?](07-003-how-reduce-latency-in-genai-applications.md) | Same concept — KV cache is the first lever in any latency reduction discussion |

---

## One-liner recall

> KV cache stores past tokens' Key and Value tensors so each decode step attends over cached history in O(n) instead of recomputing from scratch in O(n²) — the main cost is GPU HBM pressure, addressed by PagedAttention (vLLM) and KV quantization.
