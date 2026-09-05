# QLoRA vs LoRA — when choose one?

**Category:** 04-fine-tuning-training
**Question #:** 003
**Source section:** §4 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
This question tests whether a candidate can articulate the *specific* memory tradeoff that separates QLoRA from LoRA — not just "QLoRA uses quantization." Interviewers want to hear you reason about GPU memory budgets, quantization impact on quality, and when each technique is appropriate for a production or research workload. It probes practical hands-on experience with modern fine-tuning pipelines.

### Trigger phrases
- "What's the difference between LoRA and QLoRA?"
- "How would you fine-tune a 70B model with limited GPU access?"
- "When would you reach for QLoRA over standard LoRA?"
- "Walk me through how QLoRA reduces memory during fine-tuning."

### What it tests
Understanding of quantization mechanics (NF4, double quantization), memory footprint math, and the practical decision boundary between LoRA and QLoRA based on available hardware and quality requirements.

---

## Answer

### Concept
**LoRA** fine-tunes a model by freezing the pre-trained weights in their original precision (BF16 or FP16) and training small low-rank adapter matrices on top. **QLoRA** (Dettmers et al., 2023) extends this by quantizing the *frozen* base model weights to 4-bit NF4 (Normal Float 4) format, then applying LoRA adapters in 16-bit precision. The result: QLoRA can fine-tune a 65B+ parameter model on a single GPU that LoRA alone cannot fit, with typically < 1% quality degradation versus full BF16 LoRA.

### Mechanism

**Memory comparison for a 7B model (A100 40GB):**

| Technique | Base weight precision | Peak VRAM (7B) | Peak VRAM (13B) | Peak VRAM (70B) |
|-----------|----------------------|----------------|-----------------|-----------------|
| Full fine-tune | BF16 | ~80 GB (+ Adam states) | ~160 GB | ~800 GB |
| LoRA (r=16) | BF16 | ~18 GB | ~30 GB | ~140 GB |
| **QLoRA (r=16)** | **NF4 (4-bit)** | **~9 GB** | **~16 GB** | **~48 GB** |

**How QLoRA achieves this:**

1. **NF4 quantization of frozen weights** — Base model weights are converted from BF16 (2 bytes/param) to 4-bit NF4 (0.5 bytes/param). NF4 is information-theoretically optimal for normally-distributed weights (which LLM weights are, empirically). This alone reduces base model memory by 4×.

2. **Double quantization** — The quantization constants (scale factors) used in step 1 are themselves quantized from FP32 to FP8, saving another ~0.4 bits/param on average.

3. **Paged optimizers** — QLoRA uses NVIDIA unified memory to page optimizer states (Adam moments) to CPU RAM when GPU VRAM is full, preventing out-of-memory crashes during gradient steps. This is critical for large models on single-GPU setups.

4. **LoRA adapters in BF16** — Only the trainable adapter matrices (B and A) are kept in full 16-bit precision; gradients flow through them normally. The quantized base weights are dequantized on-the-fly to BF16 for the forward pass computation, then immediately discarded.

**Decision framework:**

```
Available GPU VRAM?
  ├── > 40 GB per node AND data > 10K samples AND quality matters most?
  │     → LoRA (BF16 base, rank 16–64) — higher quality ceiling, simpler pipeline
  ├── 16–40 GB per node (single A100 40GB / 2× A6000 48GB)?
  │     → LoRA for models ≤ 13B; QLoRA for 13B–30B
  └── < 16 GB (RTX 3090/4090 / A10G / consumer GPU)?
        → QLoRA required for any model > 7B
              Use: bitsandbytes NF4 + HuggingFace PEFT + TRL SFTTrainer
```

**QLoRA implementation (HuggingFace):**

```python
from transformers import BitsAndBytesConfig, AutoModelForCausalLM
from peft import LoraConfig, get_peft_model

bnb_config = BitsAndBytesConfig(
    load_in_4bit=True,
    bnb_4bit_quant_type="nf4",          # NF4 for normally-distributed weights
    bnb_4bit_compute_dtype=torch.bfloat16,  # dequantize to BF16 for compute
    bnb_4bit_use_double_quant=True,     # double quantization for extra savings
)

model = AutoModelForCausalLM.from_pretrained(
    BASE_MODEL_ID,  # a small open-weight base model (7–8B class)
    quantization_config=bnb_config,
    device_map="auto",
)

lora_config = LoraConfig(
    r=16,
    lora_alpha=32,
    target_modules=["q_proj", "v_proj", "k_proj", "o_proj"],
    lora_dropout=0.05,
    task_type="CAUSAL_LM",
)

model = get_peft_model(model, lora_config)
# Peak VRAM for a 7–8B-class model: ~9 GB — fits on an RTX 3090 24GB
```

### Example / Tradeoff

**Concrete comparison — a 13B-class open-weight model fine-tuned for legal document summarization:**

| Metric | LoRA (BF16 base) | QLoRA (NF4 base) |
|--------|-----------------|-----------------|
| VRAM required | 28 GB | 14 GB |
| Hardware needed | 2× A100 40GB | 1× A100 40GB |
| Training cost (cloud) | ~$80 (8h × 2 GPU × $5/hr) | ~$20 (8h × 1 GPU × $2.50/hr) |
| ROUGE-L on test set | 0.81 | 0.79 (−2.5%) |
| Inference adapter | Same PEFT merge | Same PEFT merge |

**The key insight:** QLoRA sacrifices ~2–3% quality to achieve 4× memory reduction, which also translates directly to 4× cost reduction when renting cloud GPUs. For most production tasks, this tradeoff is acceptable. For safety-critical tasks (medical, legal compliance), the extra quality margin from BF16 LoRA may be worth the compute cost.

**Post-training merge:** After fine-tuning, QLoRA adapters can be merged into the base model (dequantized back to BF16/FP32) using `peft.merge_adapter()`, enabling standard inference without quantization overhead at serving time.

---

## Verbal script

**Opening (30s):**
"Both LoRA and QLoRA fine-tune by training only small low-rank adapters on a frozen base model — the difference is the precision of those frozen base weights. LoRA keeps the base in BF16; QLoRA quantizes it to 4-bit NF4. That single change cuts base model VRAM by 4×, which determines which hardware you can actually train on. Let me walk through the mechanics and when I'd choose each."

**Core explanation (2–3 min):**
"In LoRA, the frozen weights stay in BF16 — 2 bytes per parameter. For a 7B model, that's about 14 GB just for the weights, plus optimizer states and activations, so you typically need a 40GB A100 to fine-tune comfortably.

QLoRA adds a quantization step: the frozen weights are converted to 4-bit NF4 format — that's 0.5 bytes per parameter, a 4× reduction. NF4 stands for 'Normal Float 4' — it's an information-theoretically optimal quantization for weights that follow a normal distribution, which LLM weights do empirically. QLoRA also uses double quantization: the quantization constants themselves are quantized from FP32 to FP8, saving another fraction of a bit per parameter.

Critically, the LoRA adapter matrices — the parts that are actually trained — remain in BF16 the whole time. So the forward pass dequantizes the frozen weights on-the-fly to BF16 for the matrix multiply, then immediately drops them. The gradient only flows through the small adapter matrices.

In practice: a 13B-class open-weight model needs about 28 GB of VRAM with standard BF16 LoRA — that's two A100s. With QLoRA, the same model fits in 14 GB — a single A100 40GB, and the cloud GPU cost drops from ~$80 to ~$20 for the same training run.

The tradeoff is a small quality loss — typically 2–3 ROUGE-L points or 1–2 points on task-specific evals — because the 4-bit representation introduces quantization error in the base model activations. For most production tasks, that's acceptable. For high-stakes domains — medical coding, legal contract review — I'd benchmark both and decide based on the quality delta."

**Tradeoff / production angle (1 min):**
"One thing I always flag: QLoRA's quantization is on the *frozen base weights during training*, not necessarily at inference. After fine-tuning, you can merge the adapters back into the dequantized base model with `merge_adapter()` and serve in BF16 — so QLoRA training doesn't mean quantized inference unless you want it. That said, if you're cost-constrained at serving time too, you'd combine GPTQ or AWQ quantization with your merged checkpoint independently. The other consideration is paged optimizers — QLoRA uses NVIDIA unified memory to offload Adam states to CPU RAM, which prevents OOM but adds some training latency. On a single GPU, I've seen QLoRA training runs take 15–20% longer than LoRA for the same step count."

**Wrap-up (30s):**
"So the decision rule is straightforward: if your target model fits in available VRAM with BF16 LoRA, use LoRA — simpler pipeline and higher quality ceiling. If you're memory-constrained — consumer GPUs, 30B+ models on a single node — QLoRA is the right call, with typically under 3% quality loss for a 4× memory saving. I'm happy to go deeper on the NF4 quantization math or how GPTQ/AWQ compare for inference-time quantization."

---

## Pitfalls

- **Mistake:** Saying "QLoRA is just quantized LoRA" without explaining *what* is quantized (only the frozen base weights, not the trainable adapters) — **Better:** Clarify that the adapter matrices stay in BF16 for accurate gradient flow; only the frozen W_frozen is in NF4 and is dequantized on-the-fly for the forward pass, so the quality loss comes from the base activation precision, not the adapter training
- **Mistake:** Treating QLoRA as always worse quality and not worth using — **Better:** The quality gap is typically 2–3% on most NLP tasks, and QLoRA enables a 4× VRAM reduction and proportional cost savings; for most production fine-tuning scenarios the tradeoff is clearly favorable — only rule it out after benchmarking on your specific task and quality threshold
- **Mistake:** Confusing QLoRA (training-time technique) with GPTQ/AWQ (inference-time quantization) — **Better:** Explicitly distinguish: QLoRA quantizes the base during *training* to save VRAM; GPTQ/AWQ quantize the *merged final checkpoint* for cheaper *inference* serving; they address different bottlenecks and can be combined (fine-tune with QLoRA, then GPTQ-quantize the merged checkpoint for serving)

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q2: What is PEFT/LoRA and when use it?](04-002-what-is-peftlora-and-when-use-it.md) | Prerequisite: QLoRA extends LoRA; must understand LoRA mechanics first |
| [Q12: Quantization — tradeoffs between size, speed, accuracy?](04-012-quantization-tradeoffs-between-size-speed-accuracy.md) | Follow-up: inference-time quantization (GPTQ, AWQ, INT8) vs QLoRA training-time quantization |
| [Q8: RLHF pipeline: SFT, reward model, PPO. How does DPO simplify?](04-008-rlhf-pipeline-sft-reward-model-ppo-how-does-dpo-simplify.md) | Related: DPO alignment is commonly applied on top of a QLoRA SFT checkpoint to save GPU memory |

---

## One-liner recall

> QLoRA = LoRA + NF4 4-bit quantization of the frozen base weights + paged optimizers, cutting VRAM by ~4× at the cost of ~2–3% task quality — choose LoRA when hardware permits for maximum quality, QLoRA when VRAM is the binding constraint.
