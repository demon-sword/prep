# CNN architecture?

**Category:** 06-ml-fundamentals
**Question #:** 025
**Source section:** §6 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
Interviewers use this to verify foundational computer-vision literacy and to probe whether the candidate understands the inductive biases that make CNNs still relevant today — even in an LLM world where ViTs dominate. It also tests whether the candidate can connect architectural decisions (filter size, pooling, depth) to real-world tradeoffs like parameter count, receptive field, and GPU efficiency.

### Trigger phrases
- "Walk me through CNN architecture."
- "What is a convolutional layer and how does it differ from a fully-connected layer?"
- "Why use CNNs for images instead of MLPs?"
- "Explain convolution, pooling, and the receptive field."

### What it tests
Understanding of spatial inductive bias (translation invariance, local connectivity, weight sharing), key building blocks (conv → BN → ReLU → pool), and where CNNs sit in the 2026 deep-learning landscape relative to Vision Transformers.

---

## Answer

### Concept
A Convolutional Neural Network (CNN) is a deep learning architecture designed for grid-structured data (images, time-series spectrograms) that exploits **spatial locality** and **translation invariance** through three core inductive biases: local receptive fields, shared weights (filters), and pooling-based downsampling. These biases dramatically reduce parameters vs an equivalent MLP and encode strong priors that nearby pixels are more correlated than distant ones.

### Mechanism

**Core building blocks (in canonical order):**

```
Input → [Conv → BN → ReLU]× N → Pooling → ... → GAP → FC → Softmax
```

1. **Convolutional layer** — A bank of K learnable filters of shape `(C_in, h, w)` (e.g. 64 filters of 3×3) slides over the input with stride s and padding p. Each filter computes a dot product at every spatial position → output feature map shape `(K, H_out, W_out)`. Weight sharing: the same filter parameters are reused at every position → translationequivariance and massive parameter savings (3×3 conv: 9×C_in×C_out params vs MLP 9×H×W×C_in×C_out).

2. **Batch Normalization** — Normalizes activations per feature map across the batch (mean 0, var 1) and learns affine γ, β. Speeds training (2–4× fewer epochs), reduces internal covariate shift, provides mild regularization.

3. **Activation (ReLU / GELU)** — Introduces non-linearity. ReLU = max(0, x): simple, fast, sparse activations; dead-ReLU risk for negative-biased inputs. GELU used in newer architectures (ConvNeXt).

4. **Pooling** — Max pooling (dominant) takes the maximum in each k×k window, stride k → downsamples by k×, achieves translation invariance, and grows the effective receptive field. Global Average Pooling (GAP) collapses the entire feature map to a single vector — used before the classification head in ResNet+.

5. **Receptive field** — The region of the input each neuron "sees." Grows with depth: stacking three 3×3 convolutions gives a 7×7 effective receptive field with fewer params than one 7×7. Dilated convolutions expand it without adding parameters (used in segmentation: DeepLab).

**Classic architectures (evolutionary line):**

| Architecture | Year | Key innovation |
|-------------|------|---------------|
| LeNet-5 | 1998 | Proved conv networks on MNIST |
| AlexNet | 2012 | Deep ReLU + Dropout + GPU training on ImageNet |
| VGG-16/19 | 2014 | Uniform 3×3 conv stacking (depth > filter size) |
| GoogLeNet | 2014 | Inception modules (parallel multi-scale convolutions) |
| ResNet-50/101 | 2015 | Skip connections solve vanishing gradient → depth to 152+ layers |
| EfficientNet | 2019 | Compound scaling (depth/width/resolution) via NAS |
| ConvNeXt | 2022 | Modernised CNN (GELU, LN, depthwise sep-conv) matches ViT on ImageNet |

**ResNet skip connection** — the key insight: `H(x) = F(x) + x`. If F(x) = 0, the identity is preserved. This makes it easy to train very deep networks (gradients flow through the skip path, bypassing vanishing-gradient bottleneck).

### Example / Tradeoff

**Production example — image classification pipeline:**
- ResNet-50 fine-tuned on proprietary product images: ~25M params, 4ms inference on T4 GPU, 92% top-1 on internal benchmark.
- Replacing with ViT-B/16: +1% top-1 but 3× latency and requires 10× more data to match ResNet on small datasets.
- For mobile/edge: EfficientNet-Lite (4.7M params, quantized INT8) or MobileNetV3 (depthwise separable convolutions → 10× fewer params).

**CNN vs ViT tradeoffs:**

| Dimension | CNN (ResNet/EfficientNet) | Vision Transformer (ViT) |
|-----------|--------------------------|--------------------------|
| Data efficiency | High (strong spatial prior) | Low (needs 100M+ pretraining) |
| Scalability | Good (depth/width scaling) | Excellent (Chinchilla-like scaling) |
| Inference latency | Fast (optimised CUDA kernels) | Slower at same accuracy |
| Inductive bias | Translation invariance, locality | None (learns all structure) |
| Best use case | <1M samples, edge/mobile | Large-scale, pretraining+fine-tuning |

**Key hyperparameters:**
- Filter size: 3×3 (standard), 1×1 (channel mixing, bottleneck), 5×5 (wider RF at cost)
- Stride: 1 (preserve resolution), 2 (downsample by 2×)
- Padding: "same" (preserve H, W), "valid" (shrink)
- Depth vs width: depth wins (residual networks), width used in compound scaling

---

## Verbal script

**Opening (30s):**
"I'd frame this in terms of the inductive biases that make CNNs efficient for image data. A CNN exploits the fact that nearby pixels are correlated and that a useful feature — like an edge or a corner — looks the same regardless of where it appears in the image. Those two properties — local connectivity and translation invariance — are baked into the architecture through shared convolutional filters and pooling."

**Core explanation (2–3 min):**
"The canonical building block is: convolutional layer → batch normalization → ReLU → pooling, repeated N times, then a global average pool and a classification head.

In a convolutional layer, a bank of small filters — say 64 filters of shape 3×3 — slides across the input feature map. Each filter computes a dot product at every spatial position. Because the same filter weights are reused everywhere, we get translation equivariance and we avoid the parameter explosion of a fully-connected approach. A 3×3 conv with 64 output channels on a 224×224 image has only 9 × C_in × 64 parameters regardless of image resolution.

Batch normalization normalises activations per channel across the batch, which stabilises training and lets us use higher learning rates — roughly 2–4× faster convergence. ReLU adds non-linearity cheaply.

Max pooling downsamples the feature map by a factor of k and builds in translation invariance: small shifts in the input don't change the pooled output. It also grows the effective receptive field — stacking three 3×3 convolutions gives a 7×7 receptive field with fewer parameters than one 7×7 filter.

The breakthrough that made very deep CNNs trainable was ResNet's skip connection: output = F(x) + x. If the layer learns nothing, the identity is preserved. Gradients can flow directly through the skip path, bypassing the vanishing gradient problem, and you can train networks hundreds of layers deep."

**Tradeoff / production angle (1 min):**
"The key tradeoff I think about is CNN vs Vision Transformer. On small to mid-size datasets — say, under a million images — a ResNet-50 or EfficientNet will outperform a ViT because the spatial inductive biases are free priors. ViT has to learn locality from scratch and needs massive pretraining data to do so. But at the scale of ImageNet-21k or JFT-3B, ViT dominates. In 2026 practice, most production image classifiers on constrained data still use ResNet or EfficientNet; ViT is the right choice when you're fine-tuning a foundation model. For mobile/edge, I'd reach for MobileNetV3 or EfficientNet-Lite with INT8 quantization to hit sub-10ms on-device."

**Wrap-up (30s):**
"So the key insight is: CNNs encode spatial priors directly in their architecture — local filters, weight sharing, pooling — which makes them data-efficient and fast. ResNet skip connections solved depth. ViTs have overtaken CNNs at scale, but CNNs remain the default for edge inference and smaller datasets. Happy to go deeper on any layer — depthwise separable convolutions, dilated convolutions for segmentation, or the ConvNeXt modernisation."

---

## Pitfalls

- **Mistake:** Describing only the "conv + pooling" basics without mentioning skip connections (ResNet) or batch normalization — **Better:** Explain that vanilla deep CNNs didn't scale due to vanishing gradients; ResNet's skip connections solved this and are the reason modern CNNs work at 50–200 layers.
- **Mistake:** Saying CNNs are "outdated" or "replaced by Transformers" without nuance — **Better:** Distinguish the use case: CNNs are still dominant for data-constrained / edge / mobile scenarios; ViT excels at scale with large pretraining data. ConvNeXt (2022) shows CNNs can match ViTs when modernised.
- **Mistake:** Confusing translation invariance (pooling) with translation equivariance (convolution) — **Better:** Convolution is equivariant (the feature map shifts with the input), pooling induces invariance (small shifts don't change pooled output); being precise here signals depth.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q26: BERT architecture?](06-026-bert-architecture.md) | Contrast: CNN spatial-locality inductive bias vs Transformer global self-attention |
| [Q6: Transformers — why foundational?](06-006-transformers-why-foundational.md) | Follow-up: how ViTs replaced CNNs at scale using Transformer self-attention on image patches |
| [Q12: RNN vs LSTM?](06-012-rnn-vs-lstm.md) | Parallel: inductive-bias comparison across sequence (RNN/LSTM), spatial (CNN), and global (Transformer) architectures |

---

## One-liner recall

> CNNs exploit spatial locality and translation invariance via shared convolutional filters + pooling; ResNet skip connections solved depth; today CNNs beat ViTs on small/edge datasets but ViTs win at scale.
