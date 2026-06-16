# 01. LLM Fundamentals — AI Engineering Interview Category

Covers how large language models work — architecture, tokenization, embeddings, inference mechanics, and sampling — and why these fundamentals are prerequisite knowledge for every AI engineering role in 2026.

---

## Interview signals

| You hear… | This category |
|-----------|---------------|
| "How do transformers / self-attention work?" | Architecture internals |
| "What is tokenization and why does it matter?" | Tokenization & cost |
| "Explain embeddings and how they're used in RAG" | Embeddings |
| "What is KV cache and how does it help inference?" | Inference optimization |
| "Compare temperature, top-k, and top-p sampling" | Decoding strategies |
| "What are scaling laws and why do they matter?" | Training fundamentals |

---

## Mental model

A strong candidate understands that an LLM is fundamentally a *next-token probability machine* built on the transformer's self-attention mechanism, trained at massive scale on next-token prediction. Weak candidates describe LLMs in vague terms ("it understands language") without grasping the mathematical core: query-key-value attention computes weighted sums over token representations, positional encodings inject order information, and autoregressive decoding samples from a learned distribution one token at a time. The critical engineering insight is that this architecture creates sharp resource constraints — inference is *memory-bandwidth-bound* (not compute-bound), KV cache size determines throughput, and tokenization choices directly set cost and context-window limits. Every production decision (caching, quantization, model tiering) flows from these fundamentals.

---

## Sub-topics

### 1. Transformer Architecture & Self-Attention
**When:** Technical screen opens with "how do transformers work?" or "explain self-attention"; asked at nearly every AI engineering interview at any level.
**What:** Self-attention computes relevance scores between all token pairs via dot-product Q·Kᵀ/√d_k, then uses those scores as weights over value vectors — enabling global context without the sequential bottleneck of RNNs.
**Key questions:**
- [Q22: What is self-attention? How does it differ from multi-head attention?](../answers/01-022-what-is-self-attention-how-does-it-differ-from-multi-head-at.md)
- [Q25: Encoder-only vs decoder-only vs encoder-decoder — when use each?](../answers/01-025-encoder-only-vs-decoder-only-vs-encoder-decoder-when-use-eac.md)
- [Q27: What is positional encoding and why is it needed?](../answers/01-027-what-is-positional-encoding-and-why-is-it-needed.md)

### 2. Tokenization & Embeddings
**When:** Asked in screening rounds when the interviewer wants to probe cost awareness; often follows questions about context windows or billing.
**What:** Tokenization splits text into sub-word units (BPE, WordPiece) before the model sees it — the unit of billing, context limit, and vocabulary coverage; embeddings are dense vector representations of those tokens that capture semantic relationships.
**Key questions:**
- [Q3: What is tokenization and how does it affect LLM performance?](../answers/01-003-what-is-tokenization-and-how-does-it-affect-llm-performance.md)
- [Q13: What are embeddings?](../answers/01-013-what-are-embeddings.md)
- [Q24: BPE vs WordPiece vs character-level tokenization — tradeoffs?](../answers/01-024-bpe-vs-wordpiece-vs-character-level-tokenization-tradeoffs.md)

### 3. Inference Mechanics & Sampling
**When:** Arises in system design rounds ("how would you reduce latency?") and technical deep dives ("what is KV cache?", "compare decoding strategies").
**What:** Autoregressive generation samples one token at a time from the model's output distribution; KV cache saves recomputation of past tokens' keys and values; sampling strategies (temperature, top-k, top-p) control output diversity vs. determinism.
**Key questions:**
- [Q9: What is KV cache? How does it help in LLM inference?](../answers/01-009-what-is-kv-cache-how-does-it-help-in-llm-inference.md)
- [Q31: How do LLMs generate text? Autoregressive decoding process.](../answers/01-031-how-do-llms-generate-text-autoregressive-decoding-process.md)
- [Q32: Beam search, top-k, top-p — when use each?](../answers/01-032-beam-search-top-k-top-p-when-use-each.md)

### 4. Training Paradigms & Advanced Architectures
**When:** Senior-level rounds and roles requiring pre-training or fine-tuning work; also rising in mid-level interviews as RLHF and MoE enter mainstream deployments.
**What:** Pre-training on next-token prediction yields a base model; SFT + RLHF/DPO aligns it to instructions; advanced architectures like MoE (Mixture of Experts) and GQA (Grouped Query Attention) trade parameter efficiency for throughput gains.
**Key questions:**
- [Q4: What is the difference between pre-training and fine-tuning?](../answers/01-004-what-is-the-difference-between-pre-training-and-fine-tuning.md)
- [Q29: RLHF vs DPO — when prefer one over the other?](../answers/01-029-rlhf-vs-dpo-when-prefer-one-over-the-other.md)
- [Q30: What is Mixture of Experts (MoE)? How does it improve efficiency?](../answers/01-030-what-is-mixture-of-experts-moe-how-does-it-improve-efficienc.md)

---

## Decision framework

```
Choosing an LLM configuration strategy:

If the task needs factual, grounded answers from external data:
  → Use RAG (retrieval-augmented generation)  because fine-tuning doesn't add knowledge reliably

Else if the task needs a specific output style / format / domain behavior not achievable by prompting:
  → Fine-tune with LoRA/QLoRA  because it adapts behavior without full retraining cost

Else if the task needs creative / varied outputs:
  → Set temperature > 0.7, use top-p 0.9  because high entropy sampling increases diversity

Else if the task needs deterministic / factual outputs:
  → Set temperature = 0  because greedy decoding reduces variance

Choosing a decoding strategy:
If determinism matters (evals, structured extraction):
  → temperature=0 (greedy)
If diversity matters with bounded risk:
  → top-p=0.9 (nucleus sampling)  — controls tail probability mass
If top-k control is needed (e.g., restricted vocabulary):
  → top-k=40  — limits to k most likely tokens regardless of probability gap
If high-quality sequence search needed (translation, code):
  → beam search (k=4–8)  — slower but finds globally better sequences

Encoder vs decoder architecture:
If classification / embedding task:
  → Encoder-only (BERT family)  because bidirectional context gives richer representations
If generation / chat / completion task:
  → Decoder-only (GPT family)  because causal masking enables autoregressive sampling
If seq2seq (translation, summarization with fixed input → output):
  → Encoder-decoder (T5, BART)  because encoder builds full input repr, decoder attends to it
```

---

## Common mistakes

| Mistake | What to say instead |
|---------|---------------------|
| Describing attention as "the model pays attention to important words" without explaining Q·Kᵀ/√d_k and softmax weighting | Explain that queries and keys compute a dot-product similarity, scaled by √d_k to prevent vanishing gradients in softmax, then used to weight the value vectors |
| Saying "just increase context window" when asked about long documents | Acknowledge that longer context raises memory cost quadratically (O(n²) attention), mention chunking, retrieval, or models with efficient attention (FlashAttention, sliding window) |
| Confusing temperature with top-p — e.g., "temperature controls which tokens are considered" | Temperature scales logits before softmax (affects probability sharpness); top-p filters the candidate set post-softmax (nucleus sampling); they are orthogonal controls |
| Saying KV cache "speeds up training" | KV cache applies only to inference — it caches past tokens' key and value projections to avoid recomputing them during autoregressive decoding |
| Describing tokenization as "splitting by spaces or words" without mentioning BPE/WordPiece | Explain sub-word tokenization: unknown words split into sub-tokens, vocabulary is fixed at ~32K–128K; this creates the token count that drives API cost and context limits |
| Claiming pre-training and fine-tuning are interchangeable | Pre-training trains all weights on next-token prediction over trillions of tokens; fine-tuning (or RLHF/LoRA) adapts the base model on a much smaller, task-specific dataset |

---

## Question checklist

| # | Question | Difficulty signal | Status |
|---|----------|-------------------|--------|
| 1 | How do LLMs work? | E | `todo` |
| 2 | How do transformers work? | E | `todo` |
| 3 | What is tokenization and how does it affect LLM performance? | E | `todo` |
| 4 | What is the difference between pre-training and fine-tuning? | E | `todo` |
| 5 | Explain context windows and their limitations. | E | `todo` |
| 6 | What are scaling laws and why do they matter? | M | `todo` |
| 7 | What is temperature and top-p sampling? How do they affect outputs? | E | `todo` |
| 8 | Explain few-shot learning and chain-of-thought prompting. | E | `todo` |
| 9 | What is KV cache? How does it help in LLM inference? | M | `todo` |
| 10 | Can you describe the difference between GenAI and traditional programming for a real-world problem? | E | `todo` |
| 11 | How do you ensure LLM outputs are consistent and accurate in multi-step workflows? | M | `todo` |
| 12 | What's an RAG model? Explain the complete process. | E | `todo` |
| 13 | What are embeddings? | E | `todo` |
| 14 | How does chunking happen? | E | `todo` |
| 15 | What is the difference between discriminative and generative models? | E | `todo` |
| 16 | What is graph RAG? How does it differ from standard RAG? | M | `todo` |
| 17 | What is reflection in the context of LLM agents? | M | `todo` |
| 18 | Explain KL divergence. | M | `todo` |
| 19 | What is the difference between symbolic and connectionist AI? | E | `todo` |
| 20 | Describe text summarization techniques and when you'd use each. | M | `todo` |
| 21 | How do you do memory management and context management with LLMs? | M | `todo` |
| 22 | What is self-attention? How does it differ from multi-head attention? | M | `todo` |
| 23 | What is grouped query attention (GQA)? How does it differ from standard multi-head attention? | S | `todo` |
| 24 | BPE vs WordPiece vs character-level tokenization — tradeoffs? | M | `todo` |
| 25 | Encoder-only vs decoder-only vs encoder-decoder — when use each? | M | `todo` |
| 26 | Why are decoder-only models dominant even for non-generation tasks? | M | `todo` |
| 27 | What is positional encoding and why is it needed? | M | `todo` |
| 28 | MMLU, BigBench, HumanEval — what does each measure? Limitations? | M | `todo` |
| 29 | RLHF vs DPO — when prefer one over the other? | S | `todo` |
| 30 | What is Mixture of Experts (MoE)? How does it improve efficiency? | S | `todo` |
| 31 | How do LLMs generate text? Autoregressive decoding process. | M | `todo` |
| 32 | Beam search, top-k, top-p — when use each? | M | `todo` |
| 33 | What is FlashAttention and how does it work? | S | `todo` |
| 34 | Why is LLM inference memory-bounded? | S | `todo` |
| 35 | How do stop sequences work? | E | `todo` |
| 36 | What happens when you exceed the context window? How handle long documents? | M | `todo` |
| 37 | Risks of general-purpose tokenizers on legal/medical domains? | M | `todo` |
| 38 | How does self-attention work in a transformer? | E | `todo` |
| 39 | What is tokenization, and why does it matter for cost and context windows? | E | `todo` |
| 40 | What is the difference between prompt engineering, RAG, and fine-tuning? | E | `todo` |
| 41 | What are embeddings, and how are they used in RAG? | E | `todo` |
| 42 | Semantic search vs keyword search? | E | `todo` |
| 43 | How do you reduce hallucinations in LLM outputs? | M | `todo` |
| 44 | What is the "lost in the middle" problem? | M | `todo` |
| 45 | When set temperature to 0 vs higher values? | E | `todo` |
| 46 | Bias-variance tradeoff? | E | `todo` |
| 47 | Overfitting — how prevent it? | E | `todo` |
| 48 | Imbalanced datasets — how handle? | E | `todo` |

---

## One-page summary

- **Transformers = self-attention + feedforward + positional encoding**: attention scores are computed as softmax(Q·Kᵀ/√d_k)·V; multi-head attention runs this in parallel across H heads, then concatenates — giving the model the ability to attend to multiple relationship types simultaneously.
- **Tokenization drives cost and context limits**: sub-word tokenizers (BPE, GPT-4 cl100k_base at ~100K vocab) split text into ~0.75 words/token on average; token count = API billing unit and context window consumption; domain-specific text (code, legal, medical) tokenizes less efficiently.
- **Inference is memory-bandwidth-bound, not compute-bound**: the bottleneck is loading model weights from HBM (high-bandwidth memory) for each token, not FLOPs; KV cache trades memory for speed by storing past keys and values, enabling O(1) per-step decoding instead of O(n²) re-attention.
- **Decoding strategy = temperature + nucleus/top-k**: temperature scales logits (0 = greedy, deterministic; 1 = raw distribution; >1 = chaotic); top-p=0.9 (nucleus) keeps tokens whose cumulative probability mass reaches 90%; use temperature=0 for evals/structured outputs, higher values for creative generation.
- **Pre-train → SFT → RLHF/DPO is the modern training stack**: base model learns language from trillions of tokens; SFT teaches instruction-following format; RLHF/DPO aligns outputs to human preference — DPO skips the explicit reward model and optimizes preference pairs directly, making it cheaper and more stable than PPO-based RLHF.
