# Latency vs throughput for LLM serving?

**Category:** 07-cost-latency
**Question #:** 014
**Source section:** §9 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
This is a senior-level serving architecture question. The interviewer wants to know whether you understand that latency and throughput are in fundamental tension for LLM inference — not just vaguely, but mechanically. Strong candidates explain *why* they conflict (memory-bandwidth bottleneck, batching dynamics, KV cache pressure) and how modern serving systems like vLLM navigate that tension. It surfaces production maturity: have you actually tuned a serving stack under load?

### Trigger phrases
- "Latency vs throughput for LLM serving?"
- "How do you tune vLLM for throughput vs latency?"
- "We're running GPUs at 30% utilization but latency is high — what's going on?"
- "What's the tradeoff between batch size and response time in LLM serving?"
- "How do you serve an LLM for a chat product vs a batch pipeline?"

### What it tests
Understanding of the latency-throughput tradeoff in memory-bandwidth-bound inference: why large batches improve GPU utilization but increase TTFT, and which knobs (batch size, max_seq_len, continuous batching, speculative decoding, tensor parallelism) move the needle on each dimension.

---

## Answer

### Concept
**Latency** (specifically TTFT and total time to last token) measures how fast a single request is served. **Throughput** measures how many tokens the system generates per second across all concurrent requests. They are in direct tension because increasing throughput requires larger batches, which delay individual requests. The root cause is that LLM decode is **memory-bandwidth-bound** — the GPU spends most of its time transferring model weights from HBM (GPU DRAM) to compute units, not actually computing. Larger batches amortize that transfer cost and push the GPU toward its compute ceiling, but every request in the batch waits longer.

### Mechanism

**Why decode is memory-bandwidth-bound**

During autoregressive decode, generating one token requires loading all model weights once (a huge data transfer) to do a tiny amount of compute. The arithmetic intensity of decode is roughly:
- ~2 FLOPs per weight byte (at batch size 1)
- An A100's roofline: 312 TFLOPS compute vs 2 TB/s HBM bandwidth → 156 FLOPs/byte compute ceiling

At batch size 1, arithmetic intensity ≈ 2 FLOPs/byte — far below the roofline. The GPU is bottlenecked by the bandwidth needed to stream model weights. Increasing batch size multiplies the compute per weight transfer proportionally, raising arithmetic intensity and utilization.

**Step-time equations: why the curve below has that shape**

Each decode step streams two things from HBM: the model weights (P bytes) once, plus every active request's KV cache (KV bytes per request × batch size B). Minimum step time:

```
t_step ≥ (B·KV + P) / BW
```

- **B·KV** — KV bytes re-read every step; grows with batch size *and* sequence length.
- **P** — parameter bytes; fixed per step regardless of batch.
- **BW** — HBM bandwidth (~2 TB/s on A100).

At B=1 with short context, P dominates: you pay a full weight transfer for a single token. As B grows, the B·KV term rises until it rivals P — that is where adding batch stops being nearly free.

The general split form separates the two terms because they scale differently: the attention term is KV-bound (grows with B × sequence length) while the MLP/linear term is weight-bound (fixed P per step, amortized over B). Roofline each side separately — the step is set by whichever is larger, which is why long-context batches saturate at a smaller B than short-context ones.

**The latency-throughput curve**

| Batch size | GPU utilization | Throughput (tok/s) | TTFT / request latency |
|-----------|----------------|-------------------|----------------------|
| 1 | ~5–10% | Low | Low (fast first response) |
| 8 | ~30–40% | Moderate | Moderate |
| 32 | ~60–75% | High | High (longer wait in queue) |
| 128+ | ~85–95% | Peak | Very high (queue delay dominates) |

Beyond a certain batch size, throughput plateaus (GPU is compute-bound) while latency keeps climbing.

**Key serving knobs**

| Knob | Latency effect | Throughput effect |
|------|---------------|------------------|
| Batch size ↑ | ↑ worse | ↑ better |
| Max output tokens ↓ | ↓ better | ↑ better |
| KV cache budget ↑ | neutral | ↑ better (more concurrent requests fit) |
| Tensor parallelism ↑ | ↓ better (larger model fits faster) | ↓ slightly worse (AllReduce overhead) |
| Continuous batching | ↓ better vs static | ↑ better |
| Speculative decoding | ↓ better (structured outputs) | ↑ better |
| Prefill chunking | ↑ slightly (chunked prefill) | ↑ better (frees decode slots sooner) |

**Continuous batching (vLLM's key innovation over static batching)**

Static batching waits for a full batch to form before starting inference — short requests must wait for the slowest request in the batch to finish. Continuous batching (iteration-level scheduling) allows new requests to join the batch at each decode step once a slot opens. Result: higher GPU utilization without forcing short requests to wait for long ones. vLLM implements this with PagedAttention to manage KV cache memory without fragmentation.

**When to optimize for latency vs throughput**

```
Interactive chat / copilot / real-time completions:
  → Optimize for TTFT (p95 < 1s)
  → Small effective batch size, streaming SSE, speculative decoding
  → Accept lower GPU utilization (~30–50%)

Batch processing / offline eval / nightly jobs:
  → Optimize for throughput (tokens/sec/GPU-hour)
  → Large batch size, no streaming, continuous batching, vLLM Batch API
  → Accept high latency per request (minutes OK)

Mixed workload (interactive + batch on same cluster):
  → Priority queues: interactive requests jump the queue
  → Reserve GPU headroom (max 70% sustained utilization) to absorb spikes
  → Use vLLM's prefix caching to amortize shared system-prompt prefill
```

### Example / Tradeoff

**vLLM tuning for a RAG chat product (interactive, p95 TTFT SLO: < 800 ms):**

- `--max-num-seqs 32` — cap concurrent sequences to limit KV cache contention
- `--max-num-batched-tokens 4096` — bound prefill cost per scheduling step
- `--speculative-model llama-3-8b` with `--num-speculative-tokens 5` — 2–3× decode speedup for short structured answers
- `--enable-prefix-caching` — cache system-prompt KV for all requests sharing the same prefix

Result: p95 TTFT ~650 ms at 40 RPS on a single A100 80GB, GPU utilization ~45%.

**vLLM tuning for a batch eval pipeline (throughput-first, nightly golden-set re-eval):**

- `--max-num-seqs 256`
- `--max-num-batched-tokens 32768`
- No speculative decoding (eval outputs are diverse, low acceptance rate)
- vLLM OpenAI-compatible Batch API — queue all 10K requests, process continuously overnight

Result: 1,800 tokens/sec vs 300 tokens/sec at interactive settings — 6× throughput gain at the cost of 5–10× higher per-request latency.

**Worked example: LLaMA-2-13B step time vs batch (A100, BF16, 2K context)**

LLaMA-2-13B in BF16: P ≈ 26 GB of weights; KV ≈ 0.8 MB per token (40 layers × 5120 dim × 2 K/V × 2 bytes), so ≈ 1.7 GB per request at 2K tokens. A100 BW ≈ 2 TB/s. Plugging into t_step ≥ (B·KV + P)/BW:

| Batch (B) | KV re-read (GB) | Min step time | Token throughput |
|-----------|----------------|---------------|------------------|
| 1 | 1.7 | ≈ 14 ms | ≈ 70 tok/s |
| 8 | 13.4 | ≈ 20 ms | ≈ 400 tok/s |
| 32 | 53.7 | ≈ 40 ms | ≈ 800 tok/s |
| 128 | 215 | ≈ 120 ms | ≈ 1,050 tok/s (memory-infeasible — see below) |

Read it as the curve made quantitative: 8× the batch costs only ~1.4× the step time (weight transfer amortized), but 32× costs ~3× (KV term now dominates P). The B=128 row does not fit an 80 GB A100 (26 GB weights + 215 GB KV) — the KV budget caps batch before the math does, which is exactly why the `--max-num-seqs` cap in the tuning examples above is a memory decision first and a latency decision second.

**Worked example: FLOPs → wall time, why the KV cache is worth ~890×**

On a toy 6-layer transformer (2048-token prompt + 1000 generated tokens), exact FLOP counting gives ~177 TFLOP without a KV cache (every token recomputes all prefixes) vs ~198 GFLOP with it — roughly a 890× gap. Divide by A100 FP32 throughput (19.5 TFLOPS):

- No cache: 177×10¹² / 19.5×10¹² ≈ **9.0 s**
- Cached: 198×10⁹ / 19.5×10¹² ≈ **10.1 ms**

Caveat — point back at the roofline section above: this is theoretical-compute time, not measured wall time. Real decode is bandwidth-bound, so actual step time comes from the (B·KV+P)/BW equation, not from dividing FLOPs by peak TFLOPS. The translation still lands the interview point: recompute is seconds, cached decode is milliseconds.

**Key tradeoff to call out:** throughput and latency are not independently tunable — you are always on a curve. The right operating point depends on your SLO and workload mix. For mixed systems, priority queuing with reserved capacity for interactive traffic is the production standard.

### Scheduling distorts mean TTFT

Say each request needs prefill time t and B requests arrive together. Serve them **sequentially**: the last request's TTFT is B·t — it waits behind every earlier prefill. Interleave them with continuous batching and the **mean** TTFT falls to (B+1)/2·t. Same hardware, same work, roughly half the reported mean — the only change is scheduling order.

Interview consequence: mean TTFT is gameable. A scheduler that always prioritizes short prompts reports a great mean while long-context requests starve in the queue. So never quote a mean alone — report the TTFT distribution (p50/p95), and ask how the serving tier trades mean against tail.

---

## Verbal script

**Opening (30s):**
"Latency and throughput are fundamentally in tension for LLM inference, and the reason is mechanical — decode is memory-bandwidth-bound, not compute-bound. Once you understand that, the rest of the tradeoff falls out naturally. I'd frame it as: for interactive workloads you optimize for TTFT, accepting lower GPU utilization; for batch workloads you maximize tokens per second per GPU-hour. Let me walk through why, and then the concrete knobs."

**Core explanation (2–3 min):**
"During autoregressive decode, generating each token requires loading the entire model's weights from GPU HBM memory once. On an A100, that's 2 terabytes per second of bandwidth — and at batch size 1, you're doing roughly 2 FLOPs per byte transferred, far below the GPU's 156-FLOPs-per-byte compute ceiling. So the GPU is idle most of the time waiting for weight transfers, not computing.

The fix for throughput is increasing batch size — batching 32 requests means you amortize that same weight transfer across 32 compute operations, pushing arithmetic intensity up and GPU utilization from maybe 5% to 60-75%. Throughput climbs. But now every request waits behind 31 others, so TTFT and latency per request increase.

Continuous batching — which is what vLLM implements — partially resolves the static-batching waste: instead of waiting for the whole batch to finish before accepting new requests, each decode step can insert new requests when a slot opens. So short requests don't get stuck behind long ones. PagedAttention manages the KV cache paging to make that work efficiently without memory fragmentation.

The practical settings: for a chat product targeting p95 TTFT under a second, I'd cap max concurrent sequences around 32, enable speculative decoding with a small draft model for structured outputs like JSON or code, and enable prefix caching so the system prompt's KV is shared across requests. For a batch pipeline, I'd increase max sequences to 256 and max batched tokens to 32K — GPU utilization goes up, per-request latency goes up, but tokens per second per GPU-dollar is maximized."

**Tradeoff / production angle (1 min):**
"The tricky production situation is mixed workloads — interactive traffic during the day and batch jobs at night. The standard pattern is priority queuing: interactive requests get priority slots, batch jobs fill remaining capacity. You also want to reserve headroom — running at 100% utilization means any spike causes latency spikes. Keeping sustained utilization under 70% gives you room to absorb bursts. The other tension is speculative decoding: it's a huge latency win for structured, predictable outputs, but if the draft model acceptance rate is low — say for creative generation — it can actually hurt throughput by doing extra compute on rejected drafts."

**Wrap-up (30s):**
"So the mental model is: latency and throughput are on a curve governed by the memory-bandwidth bottleneck of decode. You pick your operating point based on your SLO — interactive or batch. Continuous batching and PagedAttention in vLLM are the baseline, then you tune batch size, speculative decoding, and tensor parallelism for your specific workload. Happy to go deeper on the PagedAttention mechanics or the speculative decoding acceptance rate dynamics."

---

## Pitfalls

- **Mistake:** Treating latency and throughput as independent dials — saying "I'd tune both" without explaining the tradeoff — **Better:** Explicitly name the memory-bandwidth-bound root cause: at batch size 1 the GPU is ~5% utilized; larger batches improve GPU utilization and throughput but force individual requests to wait longer; you're always trading one for the other.
- **Mistake:** Confusing TTFT latency with total latency in the context of throughput — **Better:** Clarify that throughput optimization (large batches) hurts TTFT the most because requests queue before prefill starts; total latency is affected too, but TTFT is the interactive UX metric that breaks first.
- **Mistake:** Citing "just use continuous batching" as the full answer — **Better:** Continuous batching reduces static-batch waste but doesn't eliminate the fundamental tradeoff; explain that the max concurrent sequences cap and KV cache budget still determine where you sit on the latency-throughput curve.
- **Mistake:** Ignoring KV cache memory pressure as a throughput lever — **Better:** KV cache size determines how many concurrent sequences can fit in GPU memory; quantizing the KV cache (e.g., FP8 or INT8 key/value) or using GQA to reduce KV size directly increases sustainable batch size and throughput without changing model weights.
- **Mistake:** Quoting mean TTFT as the latency SLO without asking how requests are scheduled — **Better:** Mean TTFT is gameable by scheduling order (sequential B·t vs interleaved (B+1)/2·t for the same work); always report the distribution (p50/p95) and check tail behavior for long-context requests.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q3: How reduce latency in GenAI applications?](07-003-how-reduce-latency-in-genai-applications.md) | Application-level latency levers (caching, tiering, compression) that complement serving-layer tuning |
| [Q16: Real bottleneck in LLM serving throughput? PagedAttention?](07-016-real-bottleneck-in-llm-serving-throughput-pagedattention.md) | Deep-dive on KV cache fragmentation and how PagedAttention solves it |
| [Q1: Your app gets 1M queries/day — how optimize cost?](07-001-your-app-gets-1m-queriesday-how-optimize-cost.md) | Cost and throughput are tightly linked — higher GPU utilization lowers cost per token |

---

## One-liner recall

> LLM decode is memory-bandwidth-bound (arithmetic intensity ~2 FLOPs/byte at batch=1, far below the GPU roofline), so larger batches increase GPU utilization and throughput but increase TTFT — tune for latency (small batch, speculative decoding, continuous batching) for interactive workloads and for throughput (large batch, max concurrent sequences, vLLM PagedAttention) for batch pipelines, and reserve ~30% GPU headroom for mixed-workload priority queuing.
