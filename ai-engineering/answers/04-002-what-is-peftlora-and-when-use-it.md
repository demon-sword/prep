# What is PEFT/LoRA and when use it?

**Category:** 04-fine-tuning-training
**Question #:** 002
**Source section:** §4 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
This question probes whether a candidate understands the practical mechanics of modern fine-tuning — not just "you can fine-tune," but *how* it's done efficiently at production scale. Full fine-tuning of a 7B+ parameter model requires tens of thousands of dollars of compute; PEFT/LoRA is the technique that makes fine-tuning feasible on a single A100 or even consumer GPUs. Interviewers want to hear you explain the key innovation (low-rank weight updates), the implementation parameters (rank, alpha, target modules), and the concrete tradeoff (slight quality ceiling vs massive compute/memory savings).

### Trigger phrases
- "How would you actually fine-tune a large model in practice?"
- "What is LoRA and how does it work?"
- "Walk me through PEFT — what adapters are you familiar with?"
- "How do you fine-tune on a budget or with limited GPU memory?"

### What it tests
Understanding of parameter-efficient fine-tuning mechanics, ability to select LoRA hyperparameters for a real task, and awareness of when PEFT is preferable to full fine-tuning.

---

## Answer

### Concept
**PEFT (Parameter-Efficient Fine-Tuning)** is a family of techniques that adapt a pre-trained LLM to a new task by training only a small subset of new parameters — typically 0.1%–2% of total model parameters — while keeping the original weights frozen. The most widely used PEFT method is **LoRA (Low-Rank Adaptation)**, which injects trainable low-rank matrix pairs into the model's linear layers, allowing the adapter to learn a task-specific weight delta without modifying the base model.

### Mechanism

**How LoRA works:**

For each target linear layer (typically `q_proj` and `v_proj` in the attention block), LoRA adds two small matrices **A** (d × r) and **B** (r × d) initialized so that `B·A = 0` at training start. During the forward pass, the effective weight is:

```
W_effective = W_frozen + (α/r) · B·A
```

- **W_frozen**: original pre-trained weight, never updated, gradient-free
- **B·A**: low-rank delta trained via gradient descent
- **r (rank)**: bottleneck dimension, typically 4–64; higher r = more capacity but more parameters
- **α (scaling)**: typically set to `2×r`; controls how much the LoRA delta contributes relative to the frozen weight

**Why this is efficient:**
- A frozen 7B model in BF16 requires ~14 GB VRAM. Full fine-tuning adds optimizer states (Adam: 3× model size = another ~42 GB). LoRA adapters for rank=16 add ~20M trainable parameters (~160 MB), keeping total VRAM under 24 GB for a 7B model — feasible on a single A100 40GB.
- Because W_frozen is never updated, the base model's general capabilities are preserved, dramatically reducing catastrophic forgetting risk.

**PEFT adapter taxonomy:**

| Method | Mechanism | Memory overhead | Best for |
|--------|-----------|-----------------|----------|
| **LoRA** | Low-rank A×B weight delta injected into linear layers | Very low (~0.1–2% of params) | Most fine-tuning tasks |
| **QLoRA** | LoRA on a 4-bit NF4 quantized base model | Minimal (4-bit base + adapters) | Consumer GPU fine-tuning (RTX 3090/4090) |
| **Prefix Tuning** | Prepend trainable token embeddings to key/value | Low | Instruction following, generation style |
| **Prompt Tuning** | Trainable soft-prompt prefix in embedding space | Minimal | Few-shot style tasks |
| **IA³** | Rescale hidden states with learned vectors | Minimal | Ultra-low-resource fine-tuning |
| **Adapters (Houlsby)** | Bottleneck FFN modules inserted after each layer | Moderate | Multi-task adapter stacking |

**When to use LoRA (vs alternatives):**

```
Task requires behavior change (style, format, instruction-following)?
  ├── Memory budget > 40GB per node and labeled data > 100K?
  │     → Consider full fine-tuning (max quality ceiling)
  ├── GPU memory 16–40GB and data 1K–100K?
  │     → LoRA (rank 8–64, target q_proj + v_proj)
  └── GPU memory < 16GB or must fine-tune on consumer hardware?
        → QLoRA (4-bit NF4 quantized base + LoRA adapters)
```

**Practical LoRA hyperparameters:**

| Parameter | Typical range | Rule of thumb |
|-----------|--------------|---------------|
| `r` (rank) | 4–64 | Start at 16; increase if loss plateaus, decrease if overfitting |
| `α` (scaling) | 8–128 | Set to `2×r` as default; increase for more aggressive adaptation |
| `lora_dropout` | 0.0–0.1 | 0.05 is safe default; 0 for very small datasets |
| Target modules | `q_proj`, `v_proj` | Add `k_proj`, `o_proj`, FFN layers for harder tasks |
| Learning rate | 1e-4 – 2e-4 | Lower than full fine-tune; use cosine decay |
| Epochs | 1–5 | Monitor val loss; early stop if overfitting |

### Example / Tradeoff

**Concrete example — a small open-weight base model (7–8B class) as a code review assistant (HuggingFace PEFT + TRL):**

```python
from peft import LoraConfig, get_peft_model
from trl import SFTTrainer

lora_config = LoraConfig(
    r=32,
    lora_alpha=64,
    target_modules=["q_proj", "v_proj", "k_proj", "o_proj"],
    lora_dropout=0.05,
    bias="none",
    task_type="CAUSAL_LM",
)

model = get_peft_model(base_model, lora_config)
# Trainable params: ~27M / 8B = 0.34%
```

- **Dataset:** 8K (instruction, code-diff, review-comment) triples
- **Hardware:** 1× A100 40GB
- **Training time:** ~4 hours
- **Result:** ROUGE-L 0.71 → 0.84 vs a hosted frontier-model baseline; inference cost roughly 20× lower per review than that baseline
- **Catastrophic forgetting:** MMLU benchmark dropped 0.3 pts — acceptable for production

**Key tradeoff:** LoRA rank controls quality ceiling. A rank-8 adapter is fast and cheap to train but may underfit complex tasks. Rank-64 approaches full fine-tune quality but training memory and time grow proportionally. In practice, rank 16–32 hits the sweet spot for most NLP tasks.

---

## Verbal script

**Opening (30s):**
"PEFT and LoRA are the reason fine-tuning is practical in 2026. The core insight is that you don't need to update all of a model's billions of parameters to change its behavior — you just need a low-rank approximation of the weight change. I'll explain how it works mechanically, then walk through when I'd actually reach for it."

**Core explanation (2–3 min):**
"LoRA works by injecting two small matrices — A and B — into each target linear layer of the model. A is d×r and B is r×d, where r is the rank, typically 8 to 32. The base model weights stay completely frozen; only A and B are trained. The effective weight during the forward pass is the original weight plus the scaled product B×A, weighted by α/r.

The reason this is so efficient: for a 7B model in BF16, full fine-tuning would require storing optimizer states for 7 billion parameters — something like 40+ GB of VRAM on top of the model itself. LoRA with rank 16 adds maybe 20 million trainable parameters — under 200 MB — so you can fine-tune a 7B model on a single A100 40GB.

In practice, I'd target q_proj and v_proj at minimum — those are the query and value projection matrices in the attention blocks, where behavioral changes matter most. For harder tasks, I'd also add k_proj, o_proj, and the FFN layers.

For hyperparameters: r=16 is a solid starting point; I'd set α=32 (2×r), lora_dropout=0.05, learning rate 1e-4 to 2e-4 with cosine decay. I'd train for 1–3 epochs and watch the validation loss curve for overfitting.

If I'm memory-constrained further — say a consumer GPU with 24 GB — I'd use QLoRA, which quantizes the base model to 4-bit NF4 format and applies LoRA adapters on top. This gets a 7B model fine-tune under 16 GB with minimal quality loss."

**Tradeoff / production angle (1 min):**
"The main limitation of LoRA is the quality ceiling from the rank constraint. If a task requires very large behavioral changes — like adapting a general model to a highly specialized legal or medical subdomain — you might need higher rank or even full fine-tuning. The other risk is adapter versioning: if you're serving multiple task-specific adapters on the same base model, you need infrastructure to hot-swap them at inference time. Tools like vLLM support dynamic LoRA adapter loading, which helps. And always run a regression eval on a general benchmark like MMLU after fine-tuning — LoRA is safer than full fine-tuning, but you can still see quality drops if you overtrain."

**Wrap-up (30s):**
"So LoRA is the default approach for fine-tuning in 2026: it reduces trainable parameters to under 1% of total model size, preserves base weights, and dramatically reduces compute cost — making it feasible on a single A100. I'd use QLoRA when memory is the binding constraint. Happy to go deeper on QLoRA quantization mechanics or the DPO training loop on top of LoRA adapters."

---

## Pitfalls

- **Mistake:** Describing LoRA as "just adding layers" without explaining the frozen base weights and the low-rank math — **Better:** Explain that LoRA keeps W_frozen unchanged and trains only B×A (d×r×r×d matrices), which is why gradient memory is negligible and catastrophic forgetting is reduced; the constraint is rank r, not architectural depth
- **Mistake:** Saying "LoRA trains 1% of the model" without knowing which layers or what rank means in practice — **Better:** Be specific: "For a 7B model with rank=16 targeting q_proj and v_proj, trainable params are roughly 20–30M out of 7B — about 0.3–0.4%; I'd increase rank to 32–64 if the task needs more capacity"
- **Mistake:** Not distinguishing LoRA from QLoRA — **Better:** Clarify that QLoRA = 4-bit NF4 quantized base model + LoRA adapters, enabling fine-tuning on consumer GPUs (RTX 3090/4090, ~24 GB VRAM); the quantization is on the frozen base weights only, not the trained adapters

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q1: When fine-tune vs prompt engineering?](04-001-when-fine-tune-vs-prompt-engineering.md) | Prerequisite: the decision to fine-tune is what triggers LoRA selection |
| [Q3: QLoRA vs LoRA — when choose one?](04-003-qlora-vs-lora-when-choose-one.md) | Follow-up: QLoRA is LoRA + 4-bit quantized base for memory-constrained training |
| [Q8: RLHF pipeline: SFT, reward model, PPO. How does DPO simplify?](04-008-rlhf-pipeline-sft-reward-model-ppo-how-does-dpo-simplify.md) | Same category: DPO fine-tuning commonly applied on top of a LoRA SFT checkpoint |

---

## One-liner recall

> LoRA freezes the base model and trains only two small low-rank matrices (B×A, rank 4–64) injected into attention layers, reducing trainable parameters to ~0.1–2% of total model size — enabling fine-tuning on a single A100 40GB with minimal catastrophic forgetting risk.
