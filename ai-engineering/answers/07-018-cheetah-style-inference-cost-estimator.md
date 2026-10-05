# CHEETAH-style inference cost estimator?

**Category:** 07-cost-latency
**Question #:** 018
**Source section:** §9 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
This is an advanced capacity-planning question, one level above "quote the roofline." The interviewer wants to know whether you can build an end-to-end latency estimate from first principles — per-layer bottleneck analysis plus communication and host overheads — instead of guessing from vendor FLOPS. Strong candidates write down the estimator structure (per-layer max of compute vs memory, plus comm, plus CPU), derive the max batch from the HBM budget, and then say what the model gets wrong. It signals you have actually sized a fleet before buying GPUs.

### Trigger phrases
- "CHEETAH-style inference cost estimator?"
- "How do you estimate per-token latency before buying hardware?"
- "Walk me through an analytical model of LLM inference cost."
- "How do you pick batch size and parallelism from first principles?"
- "What breaks when you scale inference to multi-node?"

### What it tests
Ability to compose roofline analysis per layer with communication and CPU-overhead terms into a usable latency/throughput estimate — and to calibrate it (efficiency factor) and bound it (know its limitations) rather than treating the formula as truth.

---

## Answer

### Concept
A **CHEETAH-style analytical estimator** predicts LLM inference latency without running the model: for each Transformer layer, take the max of its compute time and its memory-transfer time (roofline), sum across layers, then add inter-device communication time and host (CPU-overhead) terms. A calibration efficiency factor η absorbs real-world losses (kernel launch gaps, imperfect overlap, framework overhead). The same HBM accounting that feeds the memory term also yields **Bmax** — the largest batch that fits in device memory — which closes the loop between latency estimate and serving configuration.

### Mechanism

**Step 1 — Per-layer bottleneck: max(compute, memory)**

For one layer at batch size B and sequence length S:

- `t_compute = FLOPs_layer(B, S) / (peak_FLOPS × η_compute)` — matmul and attention FLOPs over achievable (not peak) throughput.
- `t_memory = bytes_layer(B, S) / peak_bandwidth` — weights (shared across the batch) plus per-request KV cache read from HBM.
- `t_layer = max(t_compute, t_memory)` — the roofline rule. Prefill layers land compute-bound (large B·S matmuls); decode layers land memory-bound (one token's worth of compute per full weight read).

Sum over all L layers: `t_forward ≈ Σ t_layer`. Prefill cost scales ~O(B·S) in linears plus O(B·S²) in attention; decode cost scales with weights + B·S KV bytes per step.

**Step 2 — Add communication**

Under tensor/parallel sharding each layer pays an AllReduce or AllToAll:

- `t_comm = bytes_collective / fabric_bandwidth (+ latency term at small messages)` — NVLink intra-node vs InfiniBand inter-node differ by an order of magnitude, which is why the estimator must know the topology.
- Overlapped vs serial matters: if comm overlaps compute, add only the non-overlapped fraction; if the framework serializes them (a known XLA-overlap failure mode on some stacks), add the full term. Getting this wrong is the most common source of optimistic multi-node estimates.

**Step 3 — Add CPU/host overheads**

Kernel launches, scheduling gaps, and framework dispatch cost a roughly fixed per-step tax (`t_cpu`) that dominates at small batch / short sequence — the regime where the GPU finishes each kernel faster than the host can enqueue the next. Total:

```
t_step ≈ Σ_layers max(t_compute, t_mem) + t_comm + t_cpu
throughput ≈ B × S_gen / t_step   (decode tokens/sec across the batch)
```

**Step 4 — Bmax from the HBM budget**

```
Bmax = floor((HBM_capacity − weights_bytes − reserve) / bytes_KV_per_request(S))
```

KV bytes per request grow with S (2 × bytes × layers × KV-heads × head-dim × S), so Bmax shrinks as context grows — long-context serving is capacity-bound before it is compute-bound. Bmax feeds back into Step 1: estimate latency *at* Bmax (or at the SLO-constrained batch below it), not at an arbitrary B.

**Step 5 — Calibrate η, then state limitations**

- **η calibration:** measure one real configuration (e.g. batch=8 decode step time on the target GPU), solve for the η that reconciles estimate with measurement, then project neighboring configurations. Never trust uncalibrated peak-FLOPS arithmetic — sustained efficiency is typically 30–60% of peak.
- **Limitations to name:** the model assumes steady-state dense matmuls (no MoE expert-imbalance, no sparsity), perfect batching (no continuous-batching fragmentation), and stable sequence lengths (no mixed-length batching drag). It also misses tail effects: straggler collectives, thermal throttling, and allocator fragmentation all show up in p99 but not in the formula.

### Example / Tradeoff

**Sizing a 70B-class deployment on 8× H100 (HBM 80 GB each) for 4K-context chat:**

1. Weights (~140 GB bf16) leave ~500 GB aggregate HBM; KV per request at 4K context ≈ 2 × 2 B × 80 layers × 8 KV-heads × 128 × 4096 ≈ 1.3 GB → Bmax ≈ 350 sequences cluster-wide before reserve; per-GPU planning uses the sharded share.
2. Estimator at B=128: decode layers memory-bound (weights + 128× KV reads per step dominate), t_step ≈ (weights + KV)/bandwidth + NVLink AllReduce +ort launch tax ≈ single-digit ms/step → ~thousands of tokens/sec aggregate.
3. Calibrate: run batch=8 once, fit η (~0.4–0.5 typical), re-project B=128. If measured t_step exceeds the estimate by >2×, the comm-overlap assumption is the first suspect — profile collectives before buying more nodes.
4. Decision output: one 8-GPU node serves peak load at ~60% sustained utilization with TTFT inside SLO; adding a second node only if the calibrated projection (not the peak-FLOPS one) says so.

**Key tradeoff to call out:** the estimator buys *ordering* of options (which GPU, what batch, how many nodes) cheaply, but its absolute numbers are only as good as η and the overlap assumption. Use it to rule out bad architectures on paper; confirm the shortlist with one real measurement per candidate.

---

## Verbal script

**Opening (30s):**
"I'd build it the CHEETAH way — per-layer roofline, plus communication, plus host overhead, calibrated against one real measurement. The structure is: each layer costs the max of its compute time and its memory time, summed over layers, plus collectives, plus a CPU tax. And the HBM budget gives me max batch, which closes the loop."

**Core explanation (2–3 min):**
"Step one, per layer: compute time is the layer's FLOPs over achievable throughput, memory time is weights plus KV bytes over HBM bandwidth, and the layer takes the max. Prefill layers come out compute-bound, decode layers memory-bound — that's just the roofline applied per phase. Step two is communication: under tensor parallelism every layer pays a collective, and I need the fabric bandwidth plus whether comm overlaps compute or serializes — assuming overlap when the stack actually serializes is the classic way to be 2× optimistic on multi-node. Step three is the host tax: kernel launches and dispatch, which dominates at small batch. Step four inverts the HBM accounting into Bmax — capacity minus weights over KV-per-request — because long context caps batch before compute does. Step five is calibration: measure one point, fit the efficiency factor, typically landing at 30 to 60 percent of peak, then project. And I'd close by stating what the model misses: MoE imbalance, batching fragmentation, and p99 tail effects like stragglers."

**Tradeoff / production angle (1 min):**
"The estimator's job is ranking architectures on paper — H100 vs H200, one node vs two, batch 64 vs 256 — not replacing measurement. Its failure modes are all on the optimistic side: perfect batching, perfect overlap, dense steady state. So the production pattern is estimate-then-verify: use the model to shortlist, run one real configuration per finalist, recalibrate, and only then commit to hardware. The most expensive mistake is buying nodes off uncalibrated peak-FLOPS math."

**Wrap-up (30s):**
"So the estimator is per-layer max of compute versus memory, plus comm, plus CPU, closed by Bmax from HBM and disciplined by a measured efficiency factor. It tells me which serving design to test, and measurement tells me whether to buy it."

---

## Pitfalls

- **Mistake:** Quoting peak FLOPS/bandwidth as achievable and skipping η calibration — **Better:** State sustained efficiency explicitly (30–60% of peak typical), fit η from one measured configuration, and project from there; uncalibrated roofline math routinely underestimates step time by 2×.
- **Mistake:** Adding compute and memory terms instead of taking the max, or omitting the comm-overlap question — **Better:** Apply the roofline rule per layer (bottleneck, not sum), then ask whether collectives overlap compute on the specific stack — serialized comm on multi-node setups is the largest single source of optimistic estimates.
- **Mistake:** Estimating latency at an arbitrary batch size disconnected from memory capacity — **Better:** Derive Bmax from the HBM budget first (weights + B×KV-per-request ≤ capacity), since long-context KV growth caps batch before compute does, and evaluate the estimator at operationally feasible batches.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q14: Latency vs throughput for LLM serving?](07-014-latency-vs-throughput-for-llm-serving.md) | Prerequisite — the latency/throughput tradeoff curve the estimator quantifies |
| [Q17: Disaggregated prefill/decode serving?](07-017-disaggregated-prefill-decode-serving.md) | Sibling estimate — run the estimator separately per pool since prefill is compute-bound and decode is memory-bound |
| [Q4: Cost and capacity planning for LLM app at scale?](07-004-cost-and-capacity-planning-for-llm-app-at-scale.md) | Capacity-planning consumer — estimator output (GPUs, batch, nodes) feeds the cost model |

---

## One-liner recall

> Estimate inference cost per layer as max(compute time, memory time) plus collective-comm plus host overhead, close the loop with Bmax from the HBM budget (weights + batch×KV ≤ capacity), calibrate the efficiency factor η against one real measurement, and distrust any uncalibrated peak-FLOPS projection — especially its comm-overlap assumption.
