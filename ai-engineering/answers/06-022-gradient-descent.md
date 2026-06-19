# Gradient descent?

**Category:** 06-ml-fundamentals
**Question #:** 022
**Source section:** §6 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
Interviewers use this to check foundational ML fluency — whether a candidate understands *why* models learn at all (the optimization engine), not just how to call `.fit()`. For senior/LLM-focused roles it also tests whether the candidate knows how Adam, learning-rate schedules, and batch size interact in practice with large-scale training.

### Trigger phrases
- "Walk me through how a neural network actually learns."
- "What is gradient descent and how do its variants differ?"
- "Why does your training loss oscillate / not converge?"
- "Compare SGD, Adam, and AdamW."

### What it tests
Understanding of the core iterative optimization algorithm that drives all neural network and LLM training, plus practical intuition for variant selection and common failure modes.

---

## Answer

### Concept
Gradient descent is an iterative first-order optimization algorithm that minimizes a loss function L(θ) by repeatedly moving parameters θ in the direction *opposite* to the gradient: **θ ← θ − η · ∇L(θ)**, where η is the learning rate. The gradient tells us the direction of steepest ascent; we step downhill toward a minimum.

### Mechanism

**Core update rule:**
```
θ_new = θ_old − η · ∇_θ L(θ_old)
```

**Three regimes by batch size:**

| Variant | Batch size | Properties |
|---------|-----------|------------|
| Batch GD | Full dataset | Exact gradient, slow per step, memory intensive |
| SGD | 1 sample | Noisy, fast per step, escapes local minima |
| Mini-batch SGD | 32–512 | GPU-efficient, best of both worlds — industry default |

**Adaptive optimizers (the modern stack):**

- **Momentum SGD** — exponential moving average of gradients; reduces oscillation in ravines.  
  `v_t = β·v_{t-1} + (1−β)·g_t`; `θ ← θ − η·v_t`

- **Adam** — per-parameter adaptive learning rates using first moment (mean, m_t) and second moment (uncentered variance, v_t):  
  `m_t = β₁·m_{t-1} + (1−β₁)·g_t`  
  `v_t = β₂·v_{t-1} + (1−β₂)·g_t²`  
  `θ ← θ − η · m̂_t / (√v̂_t + ε)`  
  Bias-corrected m̂_t, v̂_t compensate for zero-initialization.  
  Defaults: β₁=0.9, β₂=0.999, ε=1e-8.

- **AdamW** — Adam + decoupled weight decay (L2 penalty applied directly to θ, not folded into gradient). This is the default for LLM pre-training and fine-tuning (Hugging Face Transformers default).

**Learning rate schedules:**
- Warmup + cosine decay: standard for LLM training (linear warmup 1–5% of steps, cosine anneal to 0.1× peak LR).
- OneCycleLR: fast convergence for image models.

**Gradient issues and fixes:**

| Problem | Symptom | Fix |
|---------|---------|-----|
| Exploding gradients | Loss → NaN, gradient norm spikes | Gradient clipping (`clip_grad_norm_`, threshold=1.0) |
| Vanishing gradients | Layers not learning (near-zero grads) | ReLU/GELU activations, residual connections, LayerNorm |
| Learning rate too high | Loss oscillates / diverges | LR warmup, reduce η |
| Learning rate too low | Loss plateaus slowly | Increase η or use LR finder |

### Example / Tradeoff
Training Llama 3 8B with QLoRA: AdamW with β₁=0.9, β₂=0.999, η_peak=2e-4, 100-step linear warmup, cosine decay to 2e-5, gradient clipping at 1.0. Mini-batch size 4 with gradient accumulation steps=8 (effective batch=32) to fit in 16 GB VRAM. Without gradient clipping, loss spikes to NaN within the first 50 steps on noisy instruction data.

SGD with momentum is still used in computer vision (ResNet ImageNet training) because it generalizes better than Adam in some regimes (Wilson et al., 2017) — but Adam dominates NLP/LLM training due to sparse gradient handling.

---

## Verbal script

**Opening (30s):**
"Gradient descent is the optimization engine behind all neural network training. At its core it's simple: compute how much each parameter contributes to the loss, then nudge each parameter in the direction that reduces the loss. The interesting part is in the variants — how you compute that nudge efficiently at scale."

**Core explanation (2–3 min):**
"The basic update is θ ← θ − η · ∇L(θ). The learning rate η controls step size. Too large and you overshoot the minimum; too small and you never get there.

In practice we use mini-batch SGD — we don't compute the gradient over the whole dataset (too slow) or a single sample (too noisy). Mini-batches of 32–512 give us GPU-efficient computation with a good gradient signal.

Modern training almost always uses adaptive optimizers. Adam maintains a running average of both the gradient (first moment) and the squared gradient (second moment), giving each parameter its own effective learning rate. This is great for sparse gradients — which is why it dominates NLP and LLM training. AdamW adds decoupled weight decay, which corrects a subtle bug in how L2 regularization interacts with Adam — it's the default in Hugging Face Transformers.

For LLM training we also layer on a learning rate schedule: linear warmup for the first 1–5% of steps (so we don't blow up the model on garbage gradients early on), then cosine decay to roughly 10% of the peak LR. And we clip gradients at norm 1.0 to prevent NaN loss from noisy batches."

**Tradeoff / production angle (1 min):**
"The main tradeoffs I watch in practice: learning rate is the most sensitive hyperparameter — I use a warmup period and monitor gradient norms, not just loss. Batch size interacts with effective learning rate (linear scaling rule: if you double the batch, double the LR). And for fine-tuning LLMs with QLoRA, AdamW's paged optimizer variant (bitsandbytes) lets you avoid OOM by offloading optimizer state to CPU, which is critical when training on a single 16 GB GPU."

**Wrap-up (30s):**
"So the short answer: gradient descent is step-by-step downhill on the loss surface. Mini-batch SGD with Adam/AdamW plus warmup + cosine decay is the production standard for LLMs. The two things that bite you in practice are learning rate (too high → NaN, too low → slow convergence) and gradient explosion (fix: clip at 1.0). Happy to go deeper on any piece — Adam's bias correction, gradient clipping, or LR scheduling."

---

## Pitfalls

- **Mistake:** Describing only batch gradient descent ("you compute the gradient over all training data") — **Better:** Distinguish batch / SGD / mini-batch, explain why mini-batch is the practical default (GPU parallelism + gradient signal), and note that batch GD is infeasible at scale.
- **Mistake:** Treating Adam as a black box without mentioning AdamW — **Better:** Explain that AdamW decouples weight decay from the gradient update (L2 is applied to θ directly), which is why it's the default for transformer/LLM training; plain Adam's weight decay interacts with the adaptive LR in a way that under-regularizes.
- **Mistake:** Ignoring learning rate schedules — **Better:** Mention warmup (prevents large early updates destabilizing untrained layers) + cosine or linear decay (prevents oscillation near convergence); LLM fine-tuning without warmup commonly causes loss spikes in the first 50–100 steps.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q9: Bias-variance tradeoff](06-009-bias-variance-tradeoff.md) | Gradient descent is the mechanism that moves a model toward fitting data; bias/variance determines whether it under- or over-fits |
| [Q16: Regularization — L1, L2, dropout](06-016-regularization-l1-l2-dropout.md) | Weight decay / L2 regularization is applied during or alongside gradient descent (AdamW decouples it) |
| [Q4: Fine-tuning & training — QLoRA vs LoRA](../answers/04-003-qlora-vs-lora-when-choose-one.md) | QLoRA uses paged AdamW optimizers and gradient checkpointing to make gradient descent feasible on consumer GPUs |

---

## One-liner recall

> Gradient descent minimizes loss by iteratively stepping parameters opposite the gradient (θ ← θ − η·∇L); mini-batch + AdamW + warmup/cosine decay + gradient clipping at 1.0 is the production LLM training stack.
