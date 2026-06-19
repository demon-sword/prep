# Regularization — L1, L2, dropout?

**Category:** 06-ml-fundamentals
**Question #:** 016
**Source section:** §6 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
The interviewer is probing foundational ML hygiene — whether you understand how to prevent overfitting and why different regularization strategies suit different problem types. For AI engineers this surfaces again in fine-tuning (QLoRA rank constraint = implicit regularization), transformer training (weight decay = L2), and dropout layers in neural architectures.

### Trigger phrases
- "How do you prevent overfitting in a neural network?"
- "What regularization techniques have you used in practice?"
- "When would you use L1 vs L2 regularization?"

### What it tests
Understanding of the bias-variance tradeoff mechanisms and how to select the right regularization strategy for the model type and downstream requirement (sparsity vs smoothness vs stochastic).

---

## Answer

### Concept
Regularization adds a penalty to the loss function (or drops information during training) to constrain model complexity and reduce variance — preventing the model from memorizing training noise. The three core techniques are L1 (Lasso), L2 (Ridge/weight decay), and dropout, each with distinct inductive biases.

### Mechanism

**L1 regularization (Lasso):**
- Penalty term: `λ · Σ|wᵢ|` added to loss
- Gradient: constant `±λ` sign — pushes small weights exactly to zero
- Effect: **sparse weight vectors** — natural feature selector; many weights zero, a few large
- Use when: high-dimensional data, you suspect only a subset of features are relevant, or you want an interpretable sparse model

**L2 regularization (Ridge / weight decay):**
- Penalty term: `λ · Σwᵢ²` added to loss
- Gradient: `2λwᵢ` — shrinks weights proportionally, never reaches exactly zero
- Effect: **small, distributed weights** — stable gradients, prevents any single weight from dominating
- Use when: most features are somewhat relevant, you want smooth generalization (default for neural nets via `weight_decay` in Adam/AdamW)
- AdamW is Adam with correct L2 decoupled from the adaptive learning rate — standard for transformer fine-tuning

**Dropout:**
- During training: randomly zero a fraction `p` (typically 0.1–0.5) of activations each forward pass
- Scales activations by `1/(1-p)` at inference (inverted dropout) so expected value unchanged
- Effect: forces redundant representations — network cannot rely on any single neuron; acts as ensemble averaging over exponentially many thinned subnetworks (Srivastava et al. 2014)
- Use when: large neural networks with abundant training data; common in transformer FFN layers and classification heads
- Note: Transformers often use low dropout (0.1) or none — attention + weight decay usually sufficient

**Combined use:**
- Typical transformer training: AdamW (L2 weight decay `1e-2`) + dropout `0.1` in FFN
- Feature-selection pipeline: Lasso regression or L1-penalized logistic regression → select top-k → downstream model
- QLoRA/LoRA rank as implicit regularization: low rank forces low-dimensional update subspace → reduces overfitting on small fine-tuning datasets

### Example / Tradeoff

| Technique | Effect on weights | Best for | Weakness |
|-----------|-------------------|----------|---------|
| L1 (Lasso) | Sparse (exact zero) | Feature selection, high-dim linear | Non-differentiable at 0; slow convergence |
| L2 (Ridge / weight decay) | Small but non-zero | Neural nets, correlated features | Keeps all features; no sparsity |
| Dropout | Stochastic ensemble | Large NNs, prevents co-adaptation | Adds training time; wrong p hurts convergence |

**Concrete scenario:** Training a fraud detection gradient-boosted classifier on 500 features. L1-penalized logistic regression → 47 non-zero weights (automatic feature selection) → interpretable to compliance team. For a PyTorch transformer fine-tuned on domain data: AdamW `weight_decay=0.01` + `dropout=0.1` on attention projection layers.

---

## Verbal script

**Opening (30s):**
"I think about regularization as the three main tools you reach for when your model is overfitting: L1 for sparsity and feature selection, L2 (weight decay) for smooth generalization, and dropout for stochastic ensemble effects in neural networks. The choice depends on your model type and what you need the weights to look like."

**Core explanation (2–3 min):**
"Let me walk through each. L1 adds the sum of absolute weight values to the loss. Because its gradient is a constant sign term, it pushes small weights all the way to zero — you end up with a sparse weight vector where irrelevant features truly drop out. That's ideal when you have hundreds of features and suspect only a handful matter, or when you need a model you can explain to a regulator.

L2, or Ridge, adds the sum of squared weights. The gradient is proportional to the weight itself, so large weights shrink fast but small weights almost never reach zero. In deep learning this is called weight decay and is usually applied via AdamW, which correctly decouples the weight decay from the adaptive learning rate — standard practice for fine-tuning transformers like Llama or BERT.

Dropout is different — it's not a loss penalty but a stochastic operation during training. Each forward pass, a random fraction p of neurons is zeroed out. The network is forced to learn redundant, distributed representations because it can't rely on any single activation. At inference the activations are scaled up by 1/(1-p) to match expected magnitudes. It effectively trains an ensemble of 2^n thinned networks and averages them at test time.

In modern transformers you often see both: AdamW with weight_decay=0.01 handles the L2 side, and dropout=0.1 on FFN and attention layers. For fine-tuning with LoRA, the low rank itself acts as an implicit regularizer — you're constraining the update to a low-dimensional subspace."

**Tradeoff / production angle (1 min):**
"The practical tradeoffs: L1 has a non-differentiable point at zero, which can slow optimization — coordinate descent or subgradient methods are often used instead of vanilla SGD. L2 keeps all features, which matters when features are correlated (Lasso picks one arbitrarily from a correlated group). Dropout adds noise during training, so you need more epochs, and with too-high p on already-small networks it can hurt convergence. For transformers, there's evidence that dropout can actually hurt if you have large enough data — GPT-3 was trained without dropout. So I'd say: default to L2 (weight decay) for neural networks, add light dropout (0.1) for classification heads, and reach for L1 or Elastic Net specifically when you need sparsity."

**Wrap-up (30s):**
"So the headline is: L1 for sparse models and feature selection, L2/weight decay as the neural network default, and dropout for stochastic ensemble effects in larger networks. In practice for AI engineering, AdamW + light dropout is the go-to, with LoRA rank as an additional implicit regularization lever during fine-tuning. Happy to go deeper on any of those."

---

## Pitfalls

- **Mistake:** Describing L1 and L2 only in terms of "prevents overfitting" without explaining the weight-sparsity mechanism — **Better:** Explain that L1's constant gradient drives weights to exact zero (sparsity/feature selection) while L2's proportional gradient keeps all weights small but non-zero; the structural difference matters for model interpretation and feature selection decisions.
- **Mistake:** Treating dropout as a replacement for weight decay in transformers — **Better:** Note that AdamW (decoupled L2) is the standard default for transformer fine-tuning, and dropout is a complementary stochastic technique; also mention that high dropout can hurt large pre-trained models with sufficient data (GPT-3 training used none).
- **Mistake:** Not connecting regularization to the fine-tuning context — **Better:** Mention that LoRA rank acts as implicit regularization (low-rank update subspace constrains model capacity), and QLoRA's 4-bit quantization further reduces the effective parameter count, making regularization especially important to tune on small fine-tuning datasets.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q9: Bias-variance tradeoff?](06-009-bias-variance-tradeoff.md) | Regularization is the primary tool for shifting the bias-variance tradeoff |
| [Q13: Debug model that runs but doesn't learn](06-013-debug-model-that-runs-but-doesnt-learn-broadcasting-dimensio.md) | Over-regularization (too-high dropout or weight decay) is a cause of a model that doesn't learn |
| [Q2: What is PEFT/LoRA and when use it?](../answers/04-002-what-is-peft-lora-and-when-use-it.md) | LoRA rank as implicit regularization; QLoRA adds quantization-as-regularization during fine-tuning |

---

## One-liner recall

> L1 (Lasso) drives weights to exact zero for sparsity/feature-selection; L2 (weight decay/Ridge) shrinks all weights smoothly and is the transformer default via AdamW; dropout randomly zeros activations during training to force redundant representations — use all three together for large neural networks, and note LoRA rank as implicit regularization during fine-tuning.
