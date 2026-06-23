# Quantization and model distillation for inference?

**Category:** 07-cost-latency
**Question #:** 006
**Source section:** §9 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
Interviewers ask this in cost/latency optimization and system design rounds to test whether you understand the hardware reality of LLM inference — that it is memory-bandwidth-bound — and how both quantization and distillation reduce the dominant cost. A weak candidate says "quantization makes the model smaller." A strong candidate explains the precision formats, the PTQ algorithms (GPTQ, AWQ), the VRAM math, the accuracy tradeoffs by task type, and how distillation is a complementary but different technique (training-time vs inference-time) with different applicability conditions.

### Trigger phrases
- "How do you reduce inference cost and latency at scale?"
- "Explain quantization — when does it hurt quality?"
- "When would you use model distillation instead of quantization?"
- "We're running Llama 3 70B — how do we cut costs without switching to GPT-4o-mini?"

### What it tests
Understanding of inference efficiency at the hardware level: memory-bandwidth bottleneck, precision tradeoffs, PTQ algorithm mechanics (GPTQ/AWQ), knowledge distillation training procedure, and the decision framework for when each technique applies.

---

## Answer

### Concept
**Quantization** reduces model weight and activation precision (e.g., from BF16 to INT8 or INT4), cutting VRAM footprint and memory-bandwidth consumption — the primary bottleneck in LLM decode throughput. **Knowledge distillation** trains a smaller "student" model to mimic a larger "teacher" model's outputs or internal representations, achieving similar quality at a fraction of the parameter count. They are complementary: quantization optimizes an existing model at inference time; distillation produces a new, permanently smaller model that may be further quantized.

### Mechanism

**Quantization — precision formats:**

| Format | Bits | VRAM vs BF16 | Notes |
|--------|------|--------------|-------|
| BF16 | 16 | 1× (baseline) | Default training/serving precision |
| INT8 | 8 | ~0.5× | Safe for most tasks; near-lossless |
| INT4 (NF4/GPTQ) | 4 | ~0.25× | 1-3% quality loss on complex tasks |
| FP8 | 8 | ~0.5× | Hardware-native on H100; lossless in practice |

**Post-training quantization (PTQ) algorithms:**

- **GPTQ** (Frantar et al. 2022): reconstructs each layer's weights by minimizing the L2 error of the quantized output vs the full-precision output on a small calibration set (~128 sequences). Weight-only (activations remain FP16/BF16 at runtime). Supported natively in vLLM (`--quantization gptq`), llama.cpp, TGI.
- **AWQ** (Lin et al. 2023, MIT): "activation-aware weight quantization" — identifies the 1% of weight channels that cause the largest activation magnitude (outliers) and protects them with higher precision or scaling. Outperforms GPTQ at 4-bit on most benchmarks, especially reasoning/math tasks. vLLM supports `--quantization awq`.
- **SmoothQuant** (W8A8): migrates quantization difficulty from activations to weights via a mathematically equivalent per-channel scaling; enables full INT8 inference (both weights and activations), maximizing throughput on A100/H100 INT8 tensor cores.

**VRAM math for Llama 3 70B:**

| Precision | VRAM | GPU config |
|-----------|------|------------|
| BF16 | ~140 GB | 2× A100 80GB |
| INT8 | ~70 GB | 1× A100 80GB |
| INT4 (AWQ) | ~35 GB | 1× A100 40GB |

Going BF16→AWQ INT4 halves deployment hardware cost and roughly doubles decode throughput (fewer bytes to stream per token from HBM).

**Knowledge distillation:**

- **Offline (black-box) distillation**: use the teacher model (e.g., GPT-4o) to generate high-quality completions for a task-specific dataset; fine-tune the student (e.g., Llama 3 8B or Mistral 7B) via SFT on these synthetic examples. DistilBERT, Phi-2, and Phi-3 were produced this way. Cost: training + GPU hours, but zero per-query teacher calls afterward.
- **Online (soft-label) distillation**: student trained to minimize KL divergence against teacher's full output distribution (logit-level), not just the argmax token. Requires teacher logit access — not possible with closed-source APIs. Used internally (e.g., DistilBERT from BERT, TinyLlama from Llama).
- **Layer-wise / intermediate distillation**: match hidden states, attention maps, or feature representations layer-by-layer (TinyBERT, PKD). More expensive to train but higher compression ratios.

**Decision: quantization vs distillation:**

```
If model is too large for your GPU budget:
  → First: quantize (PTQ, no training required, hours of effort)
    If INT4 quality is acceptable → done
    If not → distillation (weeks, but permanent smaller model)
If you need a permanently smaller model for edge/mobile:
  → Distillation (train once, quantize the student too)
If you control the serving infra:
  → Quantize the existing model; combine with speculative decoding
If you only have API access (e.g. OpenAI):
  → Model tiering (GPT-4o-mini), not quantization/distillation
```

### Example / Tradeoff

**Production scenario — Llama 3 70B customer support chatbot:**

| Approach | VRAM | Throughput | Quality (RAGAS faithfulness) | Monthly cloud cost |
|----------|------|-----------|------------------------------|--------------------|
| BF16 full precision | 140 GB (2× A100) | 18 tok/s | 0.94 | ~$14K |
| AWQ INT4 | 35 GB (1× A100 40GB) | 35 tok/s | 0.92 | ~$3.5K |
| Distilled student (Llama 3 8B LoRA on teacher outputs) | 16 GB (1× A100 40GB) | 80 tok/s | 0.89 | ~$2K |
| Distilled + AWQ INT4 | 4 GB (1× A10G) | 120 tok/s | 0.87 | ~$600 |

Key tradeoff: AWQ INT4 on complex math/code tasks can degrade by 3-5%; for RAG factual Q&A, degradation is typically <1% (faithfulness 0.94→0.92). Always validate on your golden task set before switching to INT4 in production.

---

## Verbal script

**Opening (30s):**
"This question really comes down to two complementary techniques that both reduce inference cost and latency, but at different stages and with different tradeoffs. Quantization is an inference-time technique — you reduce weight precision from BF16 to INT8 or INT4, cutting VRAM and memory-bandwidth consumption, which is the actual bottleneck in LLM decoding. Distillation is a training-time technique — you train a smaller student model to mimic a larger teacher, so you get a permanently smaller, faster model. I'll cover both and when to use each."

**Core explanation (2–3 min):**
"Starting with quantization. LLM inference is memory-bandwidth-bound — during decode, the GPU streams model weights from HBM for every token, so fewer bytes per weight means more tokens per second. The main formats are INT8, which is essentially lossless for most tasks, and INT4, which cuts VRAM to 25% of BF16 but introduces a 1-3% quality hit on complex reasoning.

The two leading post-training quantization algorithms are GPTQ and AWQ. GPTQ minimizes the L2 error of quantized layer outputs on a calibration set. AWQ is smarter — it identifies the small fraction of weight channels that produce large activations and protects them with higher precision; it outperforms GPTQ at 4-bit, especially on math and code tasks. Both are supported in vLLM with a flag: `--quantization awq` or `--quantization gptq`.

Concretely, Llama 3 70B in BF16 requires two A100 80GB GPUs at ~$14K/month. With AWQ INT4, it fits on one A100 40GB at ~$3.5K/month, and decode throughput roughly doubles because you're streaming fewer bytes per token from memory.

Knowledge distillation is a different lever. You use the big teacher model — say GPT-4o — to generate high-quality completions for your task-specific dataset, then fine-tune a smaller student like Llama 3 8B on those synthetic examples using SFT. The student learns the teacher's behavior, not its weights. Phi-2, Phi-3, and DistilBERT were all produced this way. The tradeoff is training cost upfront — days of GPU time — but the resulting model is permanently smaller and can be further quantized."

**Tradeoff / production angle (1 min):**
"The key production decision is: quantize first, distill only if needed. PTQ takes hours and no training data; distillation takes weeks and a curated dataset. I always benchmark INT4 against my golden task set before deploying — for RAG factual Q&A the quality loss is typically under 1%; for math-heavy or multi-step reasoning tasks, INT4 can lose 3-5%, which may not be acceptable.

The other common trap is validating quantization accuracy on generic benchmarks like MMLU instead of your actual production tasks. A model that scores 85% on MMLU at INT8 can still fail your specific legal extraction or medical coding task if those rely on rare tokens that quantization degrades."

**Wrap-up (30s):**
"In summary: use AWQ or GPTQ quantization first — it's a quick, no-training win that cuts VRAM by 2-4× and improves throughput. Combine it with speculative decoding in vLLM for further latency gains. Use distillation when you need a permanently smaller model for edge deployment or when INT4 quality is insufficient and you have the training resources to build a student. The two techniques compose: distill to a smaller model, then quantize the student."

---

## Pitfalls

- **Mistake:** Conflating quantization and distillation as "both just make the model smaller" — **Better:** Clarify that quantization is inference-time (no retraining, compresses weights/activations in-place) while distillation is training-time (trains a new, smaller model to mimic the teacher's outputs); they target different cost axes and have different effort/data requirements; they are also composable.
- **Mistake:** Saying "quantization always hurts quality" without being specific — **Better:** INT8 is near-lossless for most tasks (<0.5% degradation); INT4 with AWQ loses 1-3% on complex reasoning and math but is typically <1% on factual RAG Q&A; the correct answer is "it depends on the task, and you must validate against your production golden set."
- **Mistake:** Not knowing any specific PTQ algorithm (GPTQ, AWQ) and just saying "quantize to 4-bit" — **Better:** Name AWQ as the 2025 production standard for 4-bit quantization (outperforms GPTQ on most benchmarks), explain that it protects outlier weight channels, and mention vLLM's `--quantization awq` flag; this signals hands-on familiarity rather than textbook knowledge.
- **Mistake:** Claiming distillation is easy or fast — **Better:** Acknowledge that offline distillation (generating teacher completions + SFT) still requires days of GPU training, careful dataset curation, and hyperparameter tuning; it is justified when you need a permanent, deployable artifact for edge or cost reasons, not when you just want to test quickly.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q1: Your app gets 1M queries/day — how optimize cost?](07-001-your-app-gets-1m-queriesday-how-optimize-cost.md) | Quantization and distillation are two of the six levers in the broader cost hierarchy |
| [Q16: Real bottleneck in LLM serving throughput? PagedAttention?](07-016-real-bottleneck-in-llm-serving-throughput-pagedattention.md) | Memory-bandwidth bottleneck is the root cause that quantization addresses |
| [Q12: Quantization — tradeoffs between size, speed, accuracy?](../answers/04-012-quantization-tradeoffs-between-size-speed-accuracy.md) | Fine-tuning category answer with deeper GPTQ/AWQ mechanics and QLoRA distinction |

---

## One-liner recall

> Quantization (AWQ INT4: 4× smaller, 2× faster, <1% RAG quality loss) is the first inference-cost lever — no training needed; knowledge distillation (SFT student on teacher outputs) is the second — permanent model reduction requiring training data and GPU weeks, composable with quantization.
