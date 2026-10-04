# Disaggregated prefill/decode serving?

**Category:** 07-cost-latency
**Question #:** 017
**Source section:** §9 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
This is a senior serving-architecture question. The interviewer wants to know whether you understand that prefill and decode stress completely different hardware resources — and what breaks when you force them onto the same GPUs. Strong candidates can place disaggregation on the taxonomy (naive batching → interleaved/chunked → disaggregated), explain the KV-transfer mechanism and its cost, and say when separation wins versus when it is overkill. It surfaces production maturity: have you sized a serving fleet, or only tuned flags on one replica?

### Trigger phrases
- "Disaggregated prefill/decode serving?"
- "How do you scale prefill and decode independently?"
- "We're TTFT-bound on long prompts but decode GPUs sit idle — how do you fix that?"
- "What is interleaved vs disaggregated serving?"
- "How does JetStream handle prefill and decode?"

### What it tests
Understanding that prefill is compute-bound and decode is memory-bandwidth-bound, so colocating them forces one phase to run on wrongly-provisioned hardware — and that disaggregation fixes the provisioning at the price of shipping KV cache over the network.

---

## Answer

### Concept
**Disaggregated prefill/decode serving** runs the two inference phases on separate GPU pools: prefill-optimized replicas ingest prompts and build the KV cache, then ship that KV cache over the network to decode-optimized replicas that autoregressively generate tokens. Each pool is provisioned and sharded for its own bottleneck — compute-heavy prefill versus bandwidth-heavy decode — instead of compromising on one shared fleet. The canonical reference implementation is Google's **JetStream**, the engine behind much of Cloud TPU LLM serving, which supports disaggregated prefill/decode across TPU slices.

### Mechanism

**Why the two phases want different hardware**

| | Prefill | Decode |
|---|---|---|
| Work per request | One large forward pass over all prompt tokens | One token per forward pass, repeated |
| Bottleneck | Compute (FLOPs), especially attention O(S²) at long context | HBM memory bandwidth (reload weights + KV cache per token) |
| Scales with | Prompt length, batch of prompt tokens | Batch size × sequence length (KV cache footprint) |
| Ideal provisioning | High-FLOP density, tensor-parallel for big matmuls | High-bandwidth HBM, large aggregate KV capacity |

On a colocated replica, a long-prompt prefill stalls every in-flight decode sharing that GPU — decode tokens stop flowing while prefill saturates compute. That is the interference disaggregation eliminates.

**The serving taxonomy (in build order)**

1. **Naive/static batching** — wait for a full batch, run prefill+decode together, return when the longest request finishes. Short requests wait behind long ones; GPU idles between batches.
2. **Interleaved serving (continuous batching + chunked prefill)** — vLLM-style iteration-level scheduling: new requests join at each decode step, and long prefills are split into chunks mixed with decode steps. Removes most static-batch waste on a single pool, but prefill chunks still steal compute from decodes on the same GPU.
3. **Disaggregated serving** — physically separate pools. Prefill replicas run back-to-back compute-saturating prefills with no decodes to stall; decode replicas run pure bandwidth-saturating token generation with no prefill interruptions. A scheduler routes prompts to prefill workers, then migrates the KV cache to decode workers.

**The KV-transfer mechanism and its cost**

After prefill, the full KV cache for that request — size `2 × bytes-per-element × layers × KV-heads × head-dim × sequence-length` (e.g. tens to hundreds of MB per request at long context) — must move over the datacenter network (NVLink/InfiniBand intra-rack, or inter-rack fabric) to the decode worker before the first token can generate. Three consequences:

- **Transfer adds to TTFT.** The user-visible first token now waits for prefill *plus* KV shipment. On high-bandwidth fabrics this is milliseconds; across slow interconnects it can dominate.
- **Independent sharding per phase.** Prefill replicas shard for compute (tensor-parallel across many chips for big matmuls); decode replicas shard for bandwidth/capacity (KV heads, then batch, across replicas to fit aggregate cache). Neither phase compromises for the other — this is the main win.
- **Failure and locality handling.** If the decode worker dies, the KV cache must be re-prefilled or re-transferred; production systems pin request affinity and replicate the scheduler so in-flight migrations survive worker loss.

**When disaggregation wins vs loses**

```
Long prompts + high QPS, strict TTFT SLO (RAG, agents, long-context chat):
  → Disaggregate. Prefill pool scales with prompt-token throughput,
    decode pool scales with concurrent sequences. JetStream-style split
    removes prefill/decode interference entirely.

Short prompts, low concurrency (single-digit batch, prototype scale):
  → Colocated + continuous batching is enough. KV-transfer overhead and
    two-pool operational complexity exceed the interference cost.

Mixed RAG workload (some 500-token, some 50K-token prompts):
  → Disaggregate with size-aware routing: short prompts stay colocated,
    long prompts go to the prefill pool. Avoids paying transfer tax on
    requests that never suffered interference.
```

### Example / Tradeoff

**RAG chat product, 2M queries/day, p95 TTFT SLO < 1 s, contexts 2K–32K tokens:**

- Colocated baseline (vLLM, continuous batching, chunked prefill): a 32K-token prefill chunk stalls all in-flight decodes on that replica for ~200–400 ms; p95 TTFT ~1.6 s, p99 ~3 s. Chunked prefill bounds but does not remove the stall.
- Disaggregated (JetStream-style): 4× prefill replicas (TP=8, compute-dense) + 12× decode replicas (KV-capacity-dense). Long prefills never touch decode GPUs. KV transfer over NVLink/IB fabric adds ~10–50 ms per request. Result: p95 TTFT ~800 ms, decode tokens/sec per GPU up ~30% because decode batching is never interrupted.
- Cost of the win: two autoscaling groups, KV-transfer fabric bandwidth provisioning, and a migration-aware scheduler. At <100 RPS with short prompts, the same setup adds operational cost for ~zero latency gain — stay colocated.

**Key tradeoff to call out:** disaggregation converts a compute-vs-bandwidth *interference* problem into a *network-transfer + operations* problem. You pay KV-shipment latency on every request and run two fleets instead of one; in exchange each fleet runs near its own roofline. The breakeven is workload-dependent: long prompts and high concurrency favor splitting, short prompts and low QPS favor colocating.

---

## Verbal script

**Opening (30s):**
"I'd start by naming why prefill and decode fight each other on shared hardware — prefill is compute-bound, decode is memory-bandwidth-bound — and then place disaggregation on the serving taxonomy: naive batching, then interleaved serving with continuous batching and chunked prefill, then physically separate prefill and decode pools with KV transfer between them. The reference system is Google's JetStream."

**Core explanation (2–3 min):**
"On a colocated replica, a long-prompt prefill saturates GPU compute and every in-flight decode on that GPU stalls — no tokens flow until prefill finishes. Chunked prefill bounds the stall by splitting the prompt into pieces, but the interference is still there. Disaggregation removes it structurally: prefill replicas do nothing but back-to-back prefills, sharded for compute with wide tensor parallelism, and decode replicas do nothing but token generation, sharded for HBM bandwidth and KV capacity. The handoff is a KV-cache transfer over the network — roughly two bytes times layers times heads times head-dim times sequence length per request — which adds a small TTFT tax on fast fabrics and a large one on slow ones. So each pool runs near its own roofline, at the price of shipping the KV cache on every request."

**Tradeoff / production angle (1 min):**
"The decision is workload-dependent. Long prompts at high QPS with a TTFT SLO — RAG, agents, long-context chat — that's where disaggregation pays: size-aware routing sends long prompts to the prefill pool and keeps short ones colocated to avoid the transfer tax. At prototype scale with short prompts, two fleets and a migration-aware scheduler are pure overhead — colocated vLLM with continuous batching is the right call. And operationally, you now have two autoscaling groups plus failure handling for in-flight KV migrations, so I'd only split once colocated p99 TTFT provably misses SLO."

**Wrap-up (30s):**
"So the mental model is: disaggregation trades prefill/decode interference for KV-transfer cost plus operational complexity. Split when long-prompt interference dominates your TTFT tail; stay colocated otherwise. Happy to go deeper on the KV-transfer sizing math or the JetStream scheduling model."

---

## Pitfalls

- **Mistake:** Recommending disaggregation for every serving setup without naming the KV-transfer tax — **Better:** Quantify the handoff (tens–hundreds of MB per long-context request over the fabric adds directly to TTFT) and state the breakeven: long prompts + high concurrency favor splitting, short prompts + low QPS favor colocated continuous batching.
- **Mistake:** Describing disaggregation as "just two vLLM instances" without explaining independent sharding — **Better:** Explain that prefill replicas shard for compute (wide tensor-parallel matmuls) while decode replicas shard for bandwidth/capacity (KV heads then batch), and that this independent provisioning — not merely separation — is the performance win.
- **Mistake:** Confusing chunked prefill with disaggregation — **Better:** Chunked prefill is still colocated (prefill pieces interleave with decodes on the same GPU and still steal compute); disaggregation is physical separation with zero shared-GPU interference and a network handoff instead.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q14: Latency vs throughput for LLM serving?](07-014-latency-vs-throughput-for-llm-serving.md) | Prerequisite — the latency/throughput curve and continuous batching that disaggregation builds on |
| [Q15: Time to first token — why matter for UX?](05-015-time-to-first-token-why-matter-for-ux.md) | TTFT is the metric disaggregation optimizes; KV-transfer latency lands directly in it |
| [Q16: Real bottleneck in LLM serving throughput? PagedAttention?](07-016-real-bottleneck-in-llm-serving-throughput-pagedattention.md) | Same serving stack — PagedAttention/continuous batching (colocated) vs pool separation (disaggregated) |

---

## One-liner recall

> Prefill is compute-bound and decode is bandwidth-bound, so colocated GPUs suffer prefill/decode interference — disaggregated serving (JetStream-style) splits them into independently-sharded pools at the price of shipping the KV cache over the network on every request, which pays off for long-prompt high-QPS workloads and is overkill for short-prompt low-concurrency ones.
