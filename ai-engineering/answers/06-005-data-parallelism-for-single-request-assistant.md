# Data parallelism for single-request assistant?

**Category:** 06-ml-fundamentals
**Question #:** 005
**Source section:** §6 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
The interviewer is probing whether the candidate understands the distinction between *training-time* parallelism strategies (data parallelism, model parallelism, pipeline parallelism) and *inference-time* serving architecture. It tests whether you can avoid confusing a distributed training concept with a production-serving scenario, and whether you understand the latency vs. throughput axis clearly.

### Trigger phrases
- "Would you use data parallelism to serve a personal assistant with one request at a time?"
- "How do you optimize for a single-user assistant — throughput or latency?"
- "What parallelism strategy applies when you have just one request in flight?"

### What it tests
Whether the candidate knows that data parallelism targets *throughput* (many requests), while a single-request interactive assistant needs *latency* optimizations — and can articulate the correct levers for each.

---

## Answer

### Concept
Data parallelism is a **training-time** technique that splits a dataset across multiple GPU workers, each holding a full model replica, then aggregates gradients (via AllReduce) to update shared weights. At **inference time** for a *single-request* personal assistant, data parallelism is irrelevant — there is no batch of examples to parallelize over. The relevant lever is latency, not throughput.

### Mechanism
**Data parallelism (training context):**
1. Copy model weights to N GPUs (DDP in PyTorch / FSDP for very large models).
2. Split each mini-batch across GPUs — each GPU processes its shard independently (forward + backward).
3. AllReduce gradients across workers; each GPU applies the same parameter update.
4. Scales throughput linearly with GPU count; communication overhead grows with model size.

**Single-request inference (what actually matters):**
- One request in flight means batch size = 1; data parallelism adds zero value.
- Latency-critical levers: **streaming (SSE)** for first-token UX, **model tiering** (use GPT-4o-mini / a small local model), **KV cache** (avoid re-prefilling on follow-ups), **quantization** (INT8/AWQ reduces memory bandwidth pressure), **semantic caching** (skip LLM call on repeated queries).
- For a *very large* model that doesn't fit on one GPU, **tensor parallelism** (split weight matrices across GPUs, e.g., Megatron-LM) or **pipeline parallelism** (split layers across GPUs) are the inference-time parallelism strategies — not data parallelism.

### Example / Tradeoff
A personal voice assistant running Llama 3 8B on a single A100 (80 GB): the entire model fits, batch size = 1, TTFT target < 200 ms. The correct optimization is **INT8 quantization** (2× throughput, memory bandwidth halved) + **streaming tokens over WebSocket** so the user hears output within 100 ms. If the model were Llama 3 70B (140 GB), one A100 is insufficient — you'd split with **tensor parallelism across 2 × A100s** (Megatron-style), not data parallelism. vLLM supports tensor parallelism via `--tensor-parallel-size 2` with near-linear latency improvement.

| Scenario | Right technique | Why |
|----------|----------------|-----|
| Training on 1 M examples | Data parallelism (DDP/FSDP) | Throughput — many data points |
| 1-request assistant, model fits on 1 GPU | Streaming + quantization + KV cache | Latency — single user |
| 1-request assistant, model too large for 1 GPU | Tensor parallelism (Megatron/vLLM) | Latency — model sharding |
| High-concurrency API (1 000 req/s) | Data parallelism of inference replicas behind load balancer | Throughput — many requests |

---

## Verbal script

**Opening (30s):**
"This is a great question because it forces a distinction between training-time and inference-time parallelism. Data parallelism is a training concept — it helps you process large datasets faster by splitting them across GPU workers. For a single-request personal assistant, it doesn't apply at inference time."

**Core explanation (2–3 min):**
"Let me break down what data parallelism actually is first. In training, you copy the full model to N GPUs, split your mini-batch, run forward and backward passes in parallel on each GPU, then AllReduce the gradients so all workers stay in sync. This scales training throughput linearly with GPU count — it's how large models are trained in hours rather than weeks.

Now at inference for a personal assistant handling one request at a time — your batch size is literally 1. There's no dataset to split. The bottleneck is *latency*, not throughput. The levers I'd reach for are: streaming tokens over SSE so the user sees output within 100–200 ms (TTFT), quantization to reduce memory bandwidth pressure on the GPU, semantic caching to skip the LLM call on repeated queries, and model tiering — use a smaller model like GPT-4o-mini or a local Llama 3 8B for routine turns and escalate to a larger model only when needed.

The *only* inference-time parallelism that helps latency for a single request is **tensor parallelism** — splitting weight matrices across multiple GPUs — which is what vLLM's `--tensor-parallel-size` flag does. That's relevant if your model is too large to fit on one GPU."

**Tradeoff / production angle (1 min):**
"The tradeoff to flag is: more GPU replicas behind a load balancer (replica parallelism / horizontal scaling) increases *throughput* at the cost of more hardware — that's relevant if you have 1 000 concurrent users, not one. For a single-user assistant, adding replicas gives you nothing but redundancy. The winning answer is: optimize for latency via streaming, quantization, and a well-sized model."

**Wrap-up (30s):**
"So the short answer: data parallelism is a training strategy, not an inference latency strategy. For a single-request personal assistant, I'd focus on streaming output, quantized model weights (INT8 or AWQ), KV cache reuse across turns, and model tiering — and add tensor parallelism only if the model doesn't fit on a single GPU."

---

## Pitfalls

- **Mistake:** Saying "I'd use data parallelism to speed up the assistant's responses" — **Better:** Recognize that data parallelism is a *training* concept; at inference with batch size = 1, the right lever is latency-oriented (streaming, quantization, model tiering, KV cache), not dataset-splitting parallelism.
- **Mistake:** Conflating data parallelism with horizontal replica scaling — **Better:** Clarify that running multiple inference replicas behind a load balancer increases *throughput* (many concurrent users), not per-request latency; for a single user, replicas give redundancy but don't reduce TTFT.
- **Mistake:** Jumping to tensor parallelism as the default answer for all inference scenarios — **Better:** Note that tensor parallelism only helps when the model doesn't fit on one GPU; for a Llama 3 8B on an A100, single-GPU + quantization + streaming beats multi-GPU communication overhead.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q4: Optimize for latency or throughput? (personal assistant)](06-004-optimize-for-latency-or-throughput-personal-assistant-one-re.md) | Parent question — this Q is a follow-up on parallelism specifically |
| [Q9: What is KV cache? How does it help in LLM inference?](../answers/01-009-what-is-kv-cache-how-does-it-help-in-llm-inference.md) | KV cache is the key inference-time latency lever for sequential turns |
| [Q12: Quantization — tradeoffs between size, speed, accuracy](../answers/04-012-quantization-tradeoffs-between-size-speed-accuracy.md) | Quantization is the primary memory-bandwidth optimization for single-GPU inference |

---

## One-liner recall

> Data parallelism is a training-throughput technique (split dataset across GPU replicas + AllReduce); for a single-request assistant at inference time, the right levers are streaming, quantization, KV cache reuse, and model tiering — not dataset parallelism.
