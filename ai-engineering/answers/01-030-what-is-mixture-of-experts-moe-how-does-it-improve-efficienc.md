# What is Mixture of Experts (MoE)? How does it improve efficiency?

**Category:** 01-llm-fundamentals
**Question #:** 030
**Source section:** §1 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
MoE is the architecture behind some of the most important production models (a sparse MoE open-weight model, frontier models). Interviewers ask this to probe whether you understand the fundamental cost-quality tradeoff in LLM scaling — specifically that you can grow *parameter count* without proportionally growing *compute per token*. It also tests whether you understand the engineering complexity this introduces (load balancing, expert routing, communication overhead in distributed setups).

### Trigger phrases
- "How does a sparse MoE open-weight model / a frontier model / Gemini achieve its performance?"
- "What is Mixture of Experts and why do people use it?"
- "How do you scale model capacity without scaling inference cost?"
- "Explain sparse vs dense models"

### What it tests
Understanding that MoE decouples *model capacity* (total parameters) from *active compute per token* (FLOPs), enabling better parameter scaling within a fixed inference budget.

---

## Answer

### Concept
Mixture of Experts (MoE) replaces each dense Feed-Forward Network (FFN) layer in a transformer with a set of N specialized sub-networks ("experts") plus a lightweight router. For each token, the router selects only K experts (typically K=2 out of N=8 or N=64) to process it. The result: a model with, say, 47B total parameters that activates only ~13B parameters per forward pass — matching a 13B dense model in FLOPs while having 47B parameters' worth of knowledge capacity.

### Mechanism
1. **Router (gating network):** A small linear layer produces a probability distribution over N experts for each token. Only the top-K experts by probability are selected; their outputs are weighted-summed.
2. **Expert FFNs:** Standard FFN blocks (often with SwiGLU activation), each specializing on different input distributions through training.
3. **Load balancing loss:** An auxiliary loss penalizes routing imbalance (one expert getting all tokens). Without it, training collapses to using 1–2 experts. A sparse MoE open-weight model and Switch Transformer both use variants of this.
4. **Expert parallelism:** In distributed inference, experts are sharded across GPUs/nodes. Each device holds a subset of experts; tokens are dispatched, processed, and gathered — introducing inter-device communication (all-to-all collectives) as a latency cost.

**Key formulas:**
- Active params per token: `K/N × FFN_params` + attention params (shared across all tokens)
- Total params: `N × FFN_params` + attention params
- Compute savings: roughly proportional to `K/N` for the FFN portion

### Example / Tradeoff

| Model | Total params | Active params/token | K / N |
|-------|-------------|---------------------|-------|
| A sparse MoE open-weight model 8×7B | ~47B | ~13B | 2/8 |
| Switch Transformer | 1.6T | ~26B | 1/256 |
| A frontier model (reported) | ~1.76T | ~220B | 2/16 |
| A frontier model | ~1T+ | undisclosed | undisclosed |

**Advantages:**
- Same inference compute as a much smaller dense model, but benchmark performance of a much larger one
- A sparse MoE open-weight model 8×7B matches or beats Llama 2 70B on most benchmarks at half the active FLOPs

**Disadvantages:**
- Total memory footprint = full parameter count (all experts must be loaded into VRAM, even if only K are active per token)
- Expert routing adds latency overhead; distributed MoE adds all-to-all communication cost
- Training instability: load imbalance, expert collapse, longer convergence
- vLLM and TGI have added MoE-specific optimizations (expert-parallel inference, fused kernels), but serving is still more complex than dense models

---

## Verbal script

**Opening (30s):**
"Mixture of Experts is the architecture that lets you scale a model's parameter count and knowledge capacity without scaling the compute cost of each forward pass. It's the key insight behind models like a sparse MoE open-weight model 8×7B and reportedly a frontier model. I'll explain the mechanism, walk through a concrete example, and cover the tradeoffs — especially memory, which is often the gotcha."

**Core explanation (2–3 min):**
"The core idea: in a standard transformer, every token passes through every FFN layer — so compute scales linearly with parameter count. MoE breaks that by replacing each dense FFN with N separate expert FFNs and a router. The router is just a learned linear layer that scores each expert for a given token and picks the top K — typically K=2 out of N=8 experts.

So for a sparse MoE open-weight model 8×7B: 47 billion total parameters, but only about 13 billion are activated per token. The model gets the knowledge capacity of 47B but pays the compute cost of 13B — roughly matching a 13B dense model in FLOPs. And the benchmarks bear this out: a sparse MoE open-weight model matches or beats Llama 2 70B at half the active FLOPs.

The router needs a load-balancing auxiliary loss during training. Without it, the model quickly learns to always route to 1–2 experts and the rest go idle — the other experts don't learn anything useful. The loss penalizes uneven routing fractions."

**Tradeoff / production angle (1 min):**
"The catch is memory. Even though only K experts run per token, *all N experts* must be loaded into GPU memory. A sparse MoE open-weight model 8×7B requires about 90GB of VRAM, not 13B's worth. That often means multi-GPU setups even for inference. In distributed deployments, expert parallelism shards experts across GPUs, but that introduces all-to-all communication overhead. vLLM has native MoE support with fused kernels, but it's still more operationally complex than serving a dense model. So MoE is a great choice when you want to maximize quality within a compute budget, but not when you're memory-constrained or want dead-simple deployment."

**Wrap-up (30s):**
"The one-liner: MoE decouples parameter count from active compute — you get a 47B-parameter model's knowledge at a 13B-parameter model's inference cost, at the price of higher memory footprint and more complex serving infrastructure. Happy to go deeper on the routing mechanism, load balancing, or distributed inference tradeoffs."

---

## Pitfalls

- **Mistake:** Saying "MoE reduces memory usage because fewer parameters are active" — **Better:** Clarify that *all* expert parameters must reside in memory; only *compute* (FLOPs) is reduced per token. Memory footprint equals total parameter count, not active parameter count.
- **Mistake:** Ignoring load balancing and saying "the router just picks the best expert" — **Better:** Explain the auxiliary load-balancing loss: without it, training collapses to expert mode collapse (1–2 experts handle all tokens), wasting model capacity. This is a real training engineering challenge.
- **Mistake:** Treating MoE as simply "an ensemble of smaller models" — **Better:** Experts share the same attention layers and are trained jointly end-to-end. They're not independently trained models — they specialize through the gradient signal from the load-balanced routing, not pre-designed division of labor.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q2: How do transformers work?](01-002-how-do-transformers-work.md) | Prerequisite — MoE replaces the FFN sublayer in a standard transformer block |
| [Q34: Why is LLM inference memory-bounded?](01-034-why-is-llm-inference-memory-bounded.md) | Follow-up — MoE sharpens this tradeoff: all params loaded, only K active |
| [Q25: Encoder-only vs decoder-only vs encoder-decoder — when use each?](01-025-encoder-only-vs-decoder-only-vs-encoder-decoder-when-use-eac.md) | Same-concept — MoE applies to any architecture, most commonly decoder-only at scale |

---

## One-liner recall

> MoE replaces each FFN layer with N expert FFNs + a learned router that activates only K experts per token, giving a model the knowledge capacity of N×params at only K/N×params compute cost — but the full memory footprint of all N experts.
