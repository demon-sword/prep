# 04. Fine-Tuning & Training — AI Engineering Interview Category

When and how to adapt pre-trained LLMs to production tasks — covering PEFT/LoRA, RLHF/DPO, quantization, speculative decoding, and the decision tree that separates great candidates from good ones.

---

## Interview signals

| You hear… | This category |
|-----------|---------------|
| "When would you fine-tune instead of prompting?" | Fine-tuning decision framework |
| "Walk me through LoRA / PEFT" | Parameter-efficient fine-tuning |
| "How does RLHF work? How does DPO improve on it?" | Alignment techniques |
| "How do you reduce inference cost / latency?" | Quantization, speculative decoding |
| "Design a training pipeline for [math / code / domain]" | End-to-end training system design |
| "How do you capture user feedback as training signal?" | Implicit feedback + RLHF data flywheel |

---

## Mental model

Strong candidates treat fine-tuning as a **last resort on the cost-quality ladder**, not the first tool they reach for. The mental model is a tiered decision tree: exhaust prompt engineering → then RAG → then PEFT fine-tuning → only then consider full fine-tuning or continued pre-training. Within fine-tuning they understand three distinct adaptation goals — *knowledge injection* (pre-training/continued pre-training), *behavior alignment* (SFT/RLHF/DPO), and *efficiency* (quantization/speculative decoding) — and they can articulate when each applies, what it costs in compute and data, and how to evaluate it. Weak candidates say "I'd fine-tune it" without specifying LoRA vs QLoRA vs full fine-tuning, without naming the data requirement (~1K–100K samples for SFT vs billions of tokens for pre-training), and without mentioning catastrophic forgetting or the evaluation framework needed to verify the adaptation actually helped.

---

## Sub-topics

### 1. Fine-tuning decision & PEFT methods (LoRA/QLoRA)
**When:** "When would you fine-tune?", "What is LoRA?", "QLoRA vs LoRA — when use each?"
**What:** PEFT methods inject trainable low-rank adapter matrices into frozen model weights, dramatically reducing GPU memory and training time vs full fine-tuning.
**Key questions:**
- [Q1: When fine-tune vs prompt engineering?](../answers/04-001-when-fine-tune-vs-prompt-engineering.md)
- [Q2: What is PEFT/LoRA and when use it?](../answers/04-002-what-is-peftlora-and-when-use-it.md)
- [Q3: QLoRA vs LoRA — when choose one?](../answers/04-003-qlora-vs-lora-when-choose-one.md)
- [Q5: Fine-tune or prompt-engineered RAG?](../answers/04-005-fine-tune-or-prompt-engineered-rag.md)

### 2. Alignment: RLHF, DPO, and instruction tuning
**When:** "How does RLHF work?", "What's DPO?", "Compare SFT vs pre-training vs instruction tuning"
**What:** Alignment techniques shape model behavior toward human preferences — SFT learns from demonstrations, RLHF optimizes a reward model with PPO, DPO replaces the reward model with a closed-form classification loss on preference pairs.
**Key questions:**
- [Q4: What is RLHF and why important?](../answers/04-004-what-is-rlhf-and-why-important.md)
- [Q8: RLHF pipeline: SFT, reward model, PPO. How does DPO simplify?](../answers/04-008-rlhf-pipeline-sft-reward-model-ppo-how-does-dpo-simplify.md)
- [Q9: Instruction tuning vs pre-training?](../answers/04-009-instruction-tuning-vs-pre-training.md)

### 3. Training system design at scale
**When:** "Design a training pipeline for X", "How do you handle compute and data constraints?", "How do you capture implicit feedback as training signal?"
**What:** Scalable LLM training requires tensor/pipeline/data parallelism, gradient checkpointing, mixed-precision (BF16/FP8), and a data flywheel that converts user behavior into curated preference pairs.
**Key questions:**
- [Q6: Design a model for math problems — data, SFT, post-training, eval](../answers/04-006-design-a-model-for-math-problems-data-sft-post-training-eval.md)
- [Q7: Scalable efficient LLM training system — compute and data constraints](../answers/04-007-scalable-efficient-llm-training-system-compute-and-data-cons.md)
- [Q11: Convert implicit user behavior into training signals](../answers/04-011-convert-implicit-user-behavior-edits-acceptance-into-trainin.md)

### 4. Inference efficiency: quantization & speculative decoding
**When:** "How do you reduce inference cost?", "What is speculative decoding?", "Quantization tradeoffs?"
**What:** Quantization reduces weight/activation precision (FP16→INT8→INT4) to shrink memory footprint and increase throughput; speculative decoding uses a cheap draft model to propose tokens that the large model verifies in parallel, cutting wall-clock latency by 2–3×.
**Key questions:**
- [Q10: Speculative decoding — speed up inference?](../answers/04-010-speculative-decoding-speed-up-inference.md)
- [Q12: Quantization — tradeoffs between size, speed, accuracy?](../answers/04-012-quantization-tradeoffs-between-size-speed-accuracy.md)

---

## Decision framework

```
Goal: adapt an LLM to a new task/domain

Step 1 — Is it a knowledge gap or a behavior/style gap?
  Knowledge gap (new facts, proprietary docs):
    → Try RAG first (cheaper, updateable, no retraining)
    → If retrieval alone isn't enough: continued pre-training on domain corpus
  Behavior/style gap (follow instructions better, tone, format, safety):
    → Go to Step 2

Step 2 — How much labeled data do you have?
  < 100 examples:
    → Prompt engineering + few-shot (no training needed)
  100–10K examples:
    → SFT with LoRA (rank 8–64, α=2×rank, target q_proj/v_proj)
    → If GPU memory is scarce (consumer hardware): QLoRA (4-bit NF4 base + LoRA adapters)
  10K–1M preference pairs:
    → DPO (simpler than RLHF, no separate reward model, train on (prompt, chosen, rejected) triples)
  1M+ preference pairs + reward signal:
    → RLHF (SFT → reward model → PPO with KL leash β≈0.1)

Step 3 — Inference budget?
  Latency-sensitive (p95 < 200ms):
    → Quantize to INT8 (bitsandbytes) or INT4 (GPTQ/AWQ); speculative decoding with small draft model
    → Consider distillation to a smaller model
  Throughput-sensitive (batch workloads):
    → vLLM with PagedAttention + continuous batching; FP8 if H100 available
  Cost-sensitive (high QPS):
    → Model tiering: small fine-tuned model for routine queries, large model for hard cases only
```

---

## Common mistakes

| Mistake | What to say instead |
|---------|---------------------|
| "I'd fine-tune it" without specifying LoRA rank, data size, or evaluation plan | Name the PEFT method (LoRA rank 16–64, α=2×rank), state minimum data requirements (~1K samples for SFT), and describe the eval: golden dataset before/after, hallucination rate |
| Treating RLHF and DPO as identical ("DPO is just simpler RLHF") | Explain the key difference: RLHF trains a separate reward model then uses PPO; DPO derives the reward implicitly from preference pairs via a log-probability-ratio loss — no reward model, no RL instability |
| Saying fine-tuning "injects new knowledge" | Fine-tuning primarily changes *behavior* (style, format, instruction-following). For new factual knowledge, RAG or continued pre-training is more reliable — SFT on Q&A pairs can memorize facts but is brittle and causes forgetting |
| Skipping catastrophic forgetting | Strong candidates mention regularization strategies: low learning rate (1e-4–2e-4), LoRA's inherent protection of frozen weights, replay buffers, or evaluation on held-out general benchmarks (MMLU) alongside the domain task |
| Ignoring quantization accuracy degradation cases | INT4 is "almost always fine" except for long-chain reasoning tasks and arithmetic — mention that GPTQ/AWQ use calibration datasets to minimize accuracy loss, but you always measure perplexity delta before deploying |
| Treating speculative decoding as "free" | Draft model must share tokenizer and be significantly cheaper; acceptance rate (typically 60–80%) determines actual speedup; mismatch in tokenizer or model family breaks it entirely |

---

## Question checklist

| # | Question | Difficulty signal | Status |
|---|----------|-------------------|--------|
| 1 | When fine-tune vs prompt engineering? ⭐ | M | `todo` |
| 2 | What is PEFT/LoRA and when use it? | M | `todo` |
| 3 | QLoRA vs LoRA — when choose one? | M | `todo` |
| 4 | What is RLHF and why important? | M | `todo` |
| 5 | Fine-tune or prompt-engineered RAG? | M | `todo` |
| 6 | Design a model for math problems — data, SFT, post-training, eval | S | `todo` |
| 7 | Scalable efficient LLM training system — compute and data constraints | S | `todo` |
| 8 | RLHF pipeline: SFT, reward model, PPO. How does DPO simplify? | S | `todo` |
| 9 | Instruction tuning vs pre-training? | M | `todo` |
| 10 | Speculative decoding — speed up inference? | M | `todo` |
| 11 | Convert implicit user behavior (edits, acceptance) into training signals? | S | `todo` |
| 12 | Quantization — tradeoffs between size, speed, accuracy? | M | `todo` |

---

## One-page summary

- **Decision ladder (memorize this):** Prompt engineering first → RAG if knowledge gap → SFT/LoRA if behavior gap with 100–10K examples → DPO if preference pairs available → RLHF only at scale with a reward signal.
- **LoRA mechanics:** Freeze base weights; inject trainable low-rank matrices A (d×r) and B (r×d) into attention projections; r=8–64 typical, α=2×r, trained in BF16. QLoRA adds 4-bit NF4 quantization of the frozen base so a 70B model fits on 2×A100 40GB.
- **RLHF vs DPO:** RLHF = SFT → reward model trained on (chosen, rejected) → PPO with KL divergence penalty (β≈0.1) against SFT reference. DPO eliminates the reward model entirely — closed-form loss directly on preference pairs; stable, simple, same final quality at smaller scale.
- **Catastrophic forgetting:** Fine-tuned models lose general capabilities. Mitigation: LoRA's frozen base weights, low LR, replay buffers, eval on MMLU/general benchmarks alongside the domain task.
- **Inference efficiency:** Quantization (INT8 bitsandbytes → INT4 GPTQ/AWQ) cuts memory 2–4×; speculative decoding (draft+verify) cuts wall-clock latency 2–3× at same quality; vLLM PagedAttention enables continuous batching for throughput at scale.
