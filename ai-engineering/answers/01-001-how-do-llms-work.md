# How do LLMs work?

**Category:** 01-llm-fundamentals
**Question #:** 001
**Source section:** §1 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
This is the foundational screen question. Interviewers aren't looking for a textbook recitation — they want to see that you have a working mental model of the full pipeline: pretraining on massive corpora, the transformer architecture's role, autoregressive generation, and how alignment (RLHF/DPO) shapes behavior. Weak answers stop at "it predicts the next token"; strong answers connect architecture to production behavior (hallucinations, context limits, sampling variance).

### Trigger phrases
- "How do LLMs work?"
- "Can you explain how a language model generates text?"
- "Walk me through what happens when I send a prompt to GPT-4."
- "What's happening under the hood when an LLM responds?"

### What it tests
Depth of foundational ML understanding and ability to connect architecture to real-world behavior and limitations.

---

## Answer

### Concept
Large Language Models are neural networks — specifically transformer-based architectures — trained to predict the next token in a sequence. After pretraining on trillions of tokens of web text, code, and books, these models develop rich internal representations of language, facts, reasoning patterns, and world structure. They generate text autoregressively: one token at a time, each token conditioned on all prior tokens.

### Mechanism
1. **Tokenization:** Input text is split into tokens (subword units via BPE or similar). "Unbelievable" might become ["Un", "believ", "able"]. GPT-4's vocabulary is ~100K tokens.
2. **Embedding:** Each token is mapped to a high-dimensional vector (~4096 dims in Llama-3-70B). Positional encodings (or rotary embeddings — RoPE) are added to preserve sequence order.
3. **Transformer layers:** The sequence passes through N stacked transformer blocks. Each block applies:
   - **Multi-head self-attention:** Every token attends to every other token, computing weighted importance scores (Q·Kᵀ / √d, then softmax → weighted sum of V). This is where context understanding happens.
   - **Feed-forward network (FFN):** A per-token non-linear projection (2 linear layers + activation), roughly 4× the model width.
   - Residual connections + layer norm stabilize training.
4. **Output projection:** The final hidden state is projected to vocabulary size (~100K logits), then softmax converts to a probability distribution over next tokens.
5. **Sampling:** A token is selected (greedy, top-k, top-p/nucleus, temperature scaling). This token is appended to the sequence and the process repeats — autoregressive generation.
6. **Alignment (post-training):** Raw pretrained models are sycophantic or unsafe. RLHF (Reinforcement Learning from Human Feedback) or DPO (Direct Preference Optimization) fine-tunes the model toward helpful, harmless responses. This is what separates "base" GPT-4 from the chat-optimized API version.

### Example / Tradeoff
A 70B-parameter model like Llama-3-70B has ~80 transformer layers, each with ~8192-dim hidden states and 64 attention heads with GQA (Grouped Query Attention) to reduce KV cache memory. At inference, a single forward pass generates one token in ~30ms on an H100 GPU, bottlenecked by memory bandwidth (loading 140GB of weights) not compute. The KV cache stores past token activations so attention doesn't recompute from scratch each step — trading VRAM for speed. At 128K context, this KV cache alone can consume 10–20GB of GPU memory.

The core tradeoff: bigger models (more parameters) = better reasoning but higher latency, memory, and cost. GPT-4 achieves ~1.8 tokens/sec per user at full quality; distilled models like GPT-4o Mini run 10× faster at 60–70% quality for most tasks.

---

## Verbal script

**Opening (30s):**
"I'd frame this at a few levels — the architecture, the training pipeline, and then how that translates to production behavior. At its core, an LLM is a transformer neural network trained to predict the next token, but there's a lot of nuance in how that creates something that feels like reasoning."

**Core explanation (2–3 min):**
"The pipeline starts with tokenization — text gets split into subword tokens, typically using BPE. Each token becomes an embedding vector, and positional information is encoded so the model knows token order.

Then the input runs through stacked transformer blocks — typically 32 to 96 layers in production models. Each layer has two key operations: self-attention, where every token attends to every other token and learns which context is relevant, and a feed-forward network that applies a non-linear transformation per token. Self-attention is what gives LLMs their ability to do long-range reasoning — a token at position 500 can directly attend to position 1.

After the final layer, a projection head converts the last hidden state to a probability distribution over the vocabulary, and we sample from it — greedy gives the highest-probability token, but top-p or temperature sampling adds diversity. Generation is autoregressive: one token at a time, appended to the input, repeated until a stop sequence or max length.

What makes modern LLMs useful isn't just this pretraining — it's the alignment stage. Raw pretrained models are good at completing text but not at following instructions or being safe. RLHF trains a reward model on human preference data, then uses PPO to optimize the LLM toward higher-reward responses. DPO does this more stably by directly optimizing on preference pairs without a separate reward model."

**Tradeoff / production angle (1 min):**
"In production, the key bottleneck is memory bandwidth, not compute. Loading 70B or 405B parameters from GPU HBM on every forward pass is the limiting factor — this is why inference is memory-bound. The KV cache mitigates this by storing attention keys and values for prior tokens, so we don't recompute them, but it grows linearly with context length — a 128K context on a 70B model can use 20GB+ of VRAM for the cache alone.

Practically, this means model selection isn't just about quality — it's about the cost and latency curve. GPT-4-class models have 4–8× the latency of smaller distilled models, so for most production RAG use cases, I'd start with a smaller model and only escalate if quality requires it."

**Wrap-up (30s):**
"So the short version: LLMs are transformer networks trained autoregressively on massive text corpora, then aligned with human feedback to be useful and safe. The production implications — context limits, KV cache memory, sampling variability — all flow directly from this architecture. Happy to go deeper on any layer."

---

## Pitfalls

- **Mistake:** Saying "it predicts the next word" and stopping there, never connecting to transformers, attention, or training — **Better:** Explain the full pipeline: tokenization → embeddings → transformer layers (self-attention + FFN) → sampling → alignment, and how each step affects production behavior.
- **Mistake:** Treating pretraining and the chat product as the same thing, ignoring RLHF/DPO alignment — **Better:** Explicitly distinguish base model (next-token predictor) from instruction-tuned model (aligned via RLHF/DPO), since alignment is why the model follows instructions and refuses harmful requests.
- **Mistake:** Not knowing why inference is slow — vague answers like "it's a big model" — **Better:** Say "inference is memory-bandwidth-bound: loading weights from GPU HBM is the bottleneck, not arithmetic throughput, which is why KV cache and quantization matter so much."

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q2: How do transformers work?](01-002-how-do-transformers-work.md) | Deep dive on the architecture introduced here |
| [Q9: What is KV cache? How does it help in LLM inference?](01-009-what-is-kv-cache-how-does-it-help-in-llm-inference.md) | Follows from the inference/memory-bound discussion |
| [Q29: RLHF vs DPO — when prefer one over the other?](01-029-rlhf-vs-dpo-when-prefer-one-over-the-other.md) | Deep dive on the alignment stage touched here |

---

## One-liner recall

> LLMs are transformer networks that predict the next token autoregressively — trained on trillions of tokens (pretraining), then aligned to follow instructions (RLHF/DPO) — with inference bottlenecked by memory bandwidth, not compute.
