# Quantization — tradeoffs between size, speed, accuracy?

**Category:** 04-fine-tuning-training
**Question #:** 012
**Source section:** §4 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
Quantization is the primary lever for reducing LLM inference cost and latency without retraining. Interviewers probe whether you understand the full tradeoff space — not just "smaller is faster" — but when accuracy degrades unacceptably, which bit-widths are safe, which layers are sensitive, and how to validate a quantized model before deploying it. This is especially relevant for cost/latency optimization, edge deployment, and model serving at scale.

### Trigger phrases
- "How do you reduce inference cost at scale?"
- "We need to deploy a 70B model on fewer GPUs — how do you approach that?"
- "What's the tradeoff between quantization and accuracy?"
- "Walk me through INT8 vs FP16 vs 4-bit quantization."
- "How do you make a large model fit on consumer hardware?"

### What it tests
Whether you can navigate the size/speed/accuracy tradeoff triangle with concrete bit-width comparisons, tool knowledge (GPTQ, AWQ, bitsandbytes), and a systematic validation approach before production deployment.

---

## Answer

### Concept
Quantization reduces the numerical precision of model weights (and optionally activations) from 32-bit or 16-bit floats to lower-precision integers (INT8, INT4, FP8), shrinking memory footprint and accelerating compute-bound operations. The central tradeoff: each bit you drop saves memory and can increase throughput, but risks accuracy degradation — especially in outlier-heavy layers and on reasoning tasks.

### Mechanism

**Precision levels and their profiles:**

| Format | Memory/param | Typical accuracy loss | Use case |
|--------|-------------|----------------------|----------|
| BF16 / FP16 | 2 bytes | Baseline (training/inference standard) | Default serving |
| FP8 (e8m0/e4m3) | 1 byte | <1% on most tasks | H100 training + inference |
| INT8 (W8A8) | 1 byte | 1–2% on reasoning | Throughput-optimized serving |
| INT4 (W4A16) | 0.5 bytes | 2–5%, 10–20%+ on math/code | Consumer GPU / cost-optimized |
| INT2/INT3 | 0.25–0.375 bytes | Significant; not production-ready at scale | Research |

**Key techniques:**

1. **Post-Training Quantization (PTQ)** — quantize a trained BF16 model without retraining:
   - **GPTQ** (Frantar et al., 2022): Layer-by-layer Hessian-based weight rounding that minimizes output error. Supports W4A16 (4-bit weights, 16-bit activations). Used in AutoGPTQ / llama.cpp.
   - **AWQ** (Lin et al., 2023): Activation-aware weight quantization — identifies and protects 1% of weights responsible for large activations (outliers). Often beats GPTQ on perplexity at 4-bit.
   - **bitsandbytes**: INT8 and NF4/FP4 quantization via absmax/LLM.int8() outlier decomposition; used in QLoRA during training.

2. **Quantization-Aware Training (QAT)** — simulate quantization during fine-tuning (straight-through estimator for gradients). Best accuracy at target bit-width; requires training budget.

3. **Activation quantization (W8A8 vs W4A16)**: Quantizing activations is harder than weights because activations have dynamic range and outliers. W4A16 (4-bit weights only) is safer than W4A8. Hardware support for W8A8 INT8 GEMM is mature on NVIDIA (TensorRT).

**Sensitive layers:** embedding tables and the first/last transformer layers are most sensitive to quantization — common to skip these or use higher precision for them (mixed-precision quantization).

**Calibration dataset:** PTQ methods require a calibration set (512–1024 samples from the target distribution) to compute quantization scales. Wrong domain → poor scale estimates → degraded accuracy.

### Example / Tradeoff

**Llama 3 70B on 2×A100 80GB:**
- BF16: 140 GB VRAM — doesn't fit on 2×A100.
- INT8: 70 GB VRAM — fits on 1×A100 with ~1.5% perplexity increase.
- AWQ W4A16: 35 GB VRAM — fits easily, ~3–4% perplexity increase, 1.6× decode throughput gain vs BF16 due to lower memory bandwidth pressure.

**Accuracy sensitivity by task type:**
- Perplexity (general text): 4-bit ≈ 1–3 ppl increase — often acceptable.
- Math/coding (GSM8K, HumanEval): 4-bit can drop 5–15 accuracy points on smaller models (<13B); larger models (>70B) are more robust.
- RAG generation (T=0, grounding prompt): 4-bit often indistinguishable in production eval — retrieval quality dominates.

**Toolchain:** vLLM natively supports AWQ/GPTQ for production serving; llama.cpp GGUF for CPU/edge.

**Validation protocol:**
1. Run calibration perplexity on held-out validation set — compare to BF16 baseline.
2. Run golden-task benchmark (GSM8K pass@1, RAGAS faithfulness on RAG golden set, HumanEval for code).
3. Shadow deploy: route 5% of traffic to quantized model, compare output quality signal (thumbs-up/down, edit rate).
4. Check p95 latency and throughput (tokens/s) — quantized models can have higher decode throughput but similar TTFT if prefill is compute-bound.

---

## Verbal script

**Opening (30s):**
"Quantization is the primary lever for fitting large models on available hardware and cutting inference cost — but it's a tradeoff triangle: size, speed, and accuracy. I'd structure my answer around the main precision formats, the two quantization approaches (post-training vs quantization-aware training), and then how I'd validate a quantized model before shipping it."

**Core explanation (2–3 min):**
"The key formats to know are BF16 as the baseline, INT8 at half the memory with ~1–2% accuracy cost, and 4-bit (INT4 or NF4) at a quarter of BF16 with 2–5% cost on general tasks but potentially 10–15% on math or code for smaller models.

For post-training quantization — which is what you'd use in production when you don't want to retrain — GPTQ and AWQ are the go-to algorithms. AWQ is often better because it's activation-aware: it identifies the ~1% of weights that correspond to outlier activations and protects them at higher precision. GPTQ does layer-by-layer Hessian-minimization. Both are supported in vLLM and AutoGPTQ.

A concrete example: Llama 3 70B in BF16 needs 140GB VRAM — that's 2 A100s with no room for the KV cache. AWQ W4A16 brings it down to ~35GB, so it runs on a single A100 with headroom for batching, and you get about a 1.6× decode throughput boost because you're under less memory-bandwidth pressure — which is the actual bottleneck at decode time.

The critical point people miss is that accuracy loss is task-dependent. For RAG-based QA at temperature=0 with a grounding prompt, 4-bit is often indistinguishable in practice because retrieval quality dominates. But for math reasoning or code generation, especially on models under 13B, 4-bit can cost you meaningful points on GSM8K."

**Tradeoff / production angle (1 min):**
"My validation protocol before deploying a quantized model: first, compare perplexity on a held-out validation set. Second, run the golden task benchmarks for the use case — GSM8K for math, HumanEval for code, RAGAS faithfulness on the RAG golden set. Third, shadow deploy at 5% traffic and compare thumbs-up/down or edit rates. I also check that p95 latency actually improves — if the model is prefill-bound (long system prompts), quantization helps less than if it's decode-bound."

**Wrap-up (30s):**
"The short version: use AWQ or GPTQ W4A16 for cost and memory reduction in most production settings, validate on task-specific golden sets not just perplexity, and be cautious about 4-bit for math/code tasks on smaller models. Happy to go deeper on any of the quantization algorithms or the serving stack."

---

## Pitfalls

- **Mistake:** Saying "quantization always cuts accuracy so just use INT8 to be safe" without distinguishing task sensitivity — **Better:** Explain that RAG generation at T=0 is often fine at 4-bit while math/code tasks are more sensitive, so the right bit-width depends on the application benchmark, not a blanket rule.
- **Mistake:** Conflating QLoRA (4-bit during training) with GPTQ/AWQ (PTQ for inference) — treating them as the same thing — **Better:** Clarify that QLoRA uses NF4 quantization of the frozen base weights during fine-tuning, but the trained adapter is typically merged back into BF16 or separately quantized with GPTQ/AWQ for production serving.
- **Mistake:** Skipping the calibration dataset quality check — **Better:** Explain that PTQ quantization scale estimates depend on the calibration set's distribution; using out-of-domain data (e.g., Wikipedia for a medical model) leads to poor scales and larger accuracy loss than necessary.
- **Mistake:** Assuming quantization speeds up prefill as much as decode — **Better:** Clarify that decode is memory-bandwidth-bound (low arithmetic intensity) so quantization helps most there; prefill is compute-bound and benefits less from weight-only quantization (W4A16).

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q3: QLoRA vs LoRA — when choose one?](04-003-qlora-vs-lora-when-choose-one.md) | QLoRA uses NF4 quantization during training; GPTQ/AWQ is PTQ for inference — important to distinguish |
| [Q10: Speculative decoding — speed up inference?](04-010-speculative-decoding-speed-up-inference.md) | Complementary inference optimization — quantization reduces memory bandwidth pressure; speculative decoding increases throughput on structured tasks |
| [How do you reduce latency in GenAI applications?](07-003-how-do-you-reduce-latency-in-genai-applications.md) | Quantization is the primary model-level latency lever in the cost/latency optimization toolkit |

---

## One-liner recall

> Quantization reduces model precision (BF16→INT8→INT4) to shrink memory and boost decode throughput, with AWQ/GPTQ as the standard PTQ algorithms — validate on task-specific golden sets because accuracy loss is task-dependent (RAG is forgiving; math/code at 4-bit on small models is risky).
