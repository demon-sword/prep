# Encoder-only vs decoder-only vs encoder-decoder — when use each?

**Category:** 01-llm-fundamentals
**Question #:** 025
**Source section:** §1 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
Tests whether the candidate understands transformer architecture families at a mechanistic level — not just "BERT is for classification, GPT is for generation," but *why* the architecture shapes constrain what tasks each family is good at. Interviewers at Google, Microsoft, and Meta use this to separate candidates who memorized marketing from those who understand attention masks, bidirectionality, and the pretraining/fine-tuning tradeoff.

### Trigger phrases
- "Explain the different transformer architectures and when you'd use each."
- "Why is BERT better for classification but GPT better for generation?"
- "When would you choose an encoder-decoder over a decoder-only model?"
- "Why are decoder-only models now dominant even for tasks that seem to need understanding?"

### What it tests
Architectural intuition: how attention masking, bidirectionality, and pretraining objectives shape a model's strengths for classification, generation, and seq2seq tasks.

---

## Answer

### Concept
The three transformer families differ in which tokens can attend to which at training time, which drives the pretraining objective, which in turn determines which downstream tasks each family natively excels at. **Encoder-only** models see all tokens bidirectionally (good for *understanding*); **decoder-only** models see only past tokens (causal masking, good for *generation*); **encoder-decoder** models encode the full input bidirectionally then decode autoregressively (good for *conditional generation / transduction*).

### Mechanism

| Dimension | Encoder-only | Decoder-only | Encoder-decoder |
|-----------|-------------|--------------|-----------------|
| **Attention** | Bidirectional (every token sees every token) | Causal (each token sees only past tokens) | Encoder: bidirectional; Decoder: causal + cross-attention to encoder |
| **Pretraining objective** | Masked language modeling (MLM) — predict masked tokens | Next-token prediction (CLM) — predict next token | Span corruption (T5), seq2seq LM, or denoising |
| **Canonical models** | BERT, RoBERTa, DeBERTa, BGE, E5 | a frontier model, Claude, a modern open-weight model, Mistral | T5, BART, mBART, Flan-T5 |
| **Native strengths** | Classification, NER, embeddings, reranking | Open-ended generation, few-shot, instruction following | Translation, summarization, structured generation (code→test) |
| **Context efficiency** | Every token in full attention → O(n²) but over full input | Same O(n²) but KV cache reuse across tokens | Encoder O(n²), decoder O(m²) + cross-attn |
| **Typical size (2025)** | 110M–7B | 1B–100B+ | 250M–11B |

**Why encoder-only models are best for embeddings and classification:**
MLM pretraining forces the model to build rich contextual representations for every position because any token might be masked. The `[CLS]` token or mean-pooled output captures a dense sentence embedding. BERT fine-tuned on a sentiment task updates a tiny classification head; the backbone already "understands" syntax, coreference, and semantics.

**Why decoder-only models are now dominant even for classification:**
Decoder-only models with instruction tuning (RLHF/DPO) can do classification zero-shot by generating the label as text. At 70B+ parameters they outperform fine-tuned BERT on most understanding benchmarks. The tradeoff: they're much larger, slower, and more expensive for the same classification task. For a production classification API at 1M QPS, a fine-tuned BERT-base (110M) at $0.001/1K tokens beats a frontier model by 100×-cost margin.

**Why encoder-decoder models fit seq2seq:**
Cross-attention lets the decoder attend to the *full* encoded input while generating each output token — ideal when output depends on the entire input (translation, summarization). A decoder-only model can do this with "input || output" in one sequence, but wastes KV cache re-encoding the input for every generated token. Encoder-decoder is more parameter-efficient for fixed-length transduction tasks.

### Example / Tradeoff

**Production example — RAG reranking:** Cross-encoders used for reranking (e.g., `cross-encoder/ms-marco-MiniLM-L-6-v2` from sentence-transformers) are encoder-only models that score query-document pairs via classification. They're far more accurate than bi-encoder (also encoder-only) dot-product search, but 10–50× slower because they process each query-doc pair jointly. In practice: bi-encoder for top-K retrieval, cross-encoder reranker on top-16 only.

**Production example — Summarization at scale:** Flan-T5-XL (3B, encoder-decoder) outperforms a small fast model on faithful summarization benchmarks (ROUGE-L, BERTScore) at ~5× lower inference cost. Used in enterprise document workflows where budget matters.

**The trend (2025–2026):** Decoder-only models with instruction tuning have eaten encoder-decoder's lunch for most NLP tasks because scale and RLHF compensate for the architectural mismatch. Encoder-only models remain dominant for *embedding* and *fast classification* use cases where latency and cost are paramount. T5/BART family persists in specialized seq2seq pipelines where training data and compute efficiency matter.

---

## Verbal script

**Opening (30s):**
"There are three families, and the key variable is the attention mask — which tokens can see which. I'd frame it as: encoder-only for understanding and embeddings, decoder-only for generation and instruction-following, and encoder-decoder for transduction tasks like translation and summarization."

**Core explanation (2–3 min):**
"Encoder-only models like BERT use *bidirectional* attention — every token attends to every other token — and are pretrained with masked language modeling, where you randomly mask 15% of tokens and predict them. Because any token might be masked, the model learns rich contextual representations. That makes the output embeddings excellent for classification, NER, or sentence similarity — you fine-tune a tiny head on top. The cost is that they can't generate text autoregressively.

Decoder-only models like GPT and Llama use *causal* masking — each token only attends to past tokens. They're pretrained to predict the next token, which gives them powerful generative ability. The KV cache makes autoregressive generation efficient because you reuse past key/value computations. With instruction tuning and RLHF, decoder-only models can now do classification, summarization — basically anything — just by generating the answer as text. At 70B scale they beat fine-tuned BERT on most tasks, but they cost 100× more per query.

Encoder-decoder models like T5 and BART take the best of both: the encoder reads the full input bidirectionally, the decoder generates output autoregressively and attends back to the encoder via cross-attention. This is architecturally ideal for translation or summarization where the output depends on the entire input. The classic use case is Flan-T5 for summarization — it outperforms a small fast model on some benchmarks at a fraction of the inference cost."

**Tradeoff / production angle (1 min):**
"In production, I'd choose encoder-only for embedding generation or fast classification — DeBERTa or BGE give me top-tier accuracy at 110M–400M parameters with low latency. I'd choose a decoder-only model when I need open-ended generation, instruction-following, or few-shot adaptability and I can afford a frontier model / Claude pricing. I'd consider encoder-decoder for a constrained seq2seq pipeline — say a medical report summarizer — where I have fine-tuning data and need cost efficiency at scale. The trend is that decoder-only models with enough scale and instruction tuning have become general-purpose, but encoder-only models for embeddings and cross-encoders for reranking remain the right call in RAG pipelines."

**Wrap-up (30s):**
"So the one-liner: encoder-only = understand/embed, decoder-only = generate/instruct, encoder-decoder = transduce — and decoder-only has taken over most of the middle ground at scale. Happy to go deeper on any of the three."

---

## Pitfalls

- **Mistake:** Saying "BERT is for classification, GPT is for generation" without explaining *why* — the attention mask and pretraining objective — **Better:** Explain bidirectional vs causal masking and how MLM vs CLM shapes what the model learns; the architecture difference is the *cause*, not just the outcome.
- **Mistake:** Claiming encoder-only models "can't be used for generation at all" — **Better:** Clarify that encoder-only models can do autoregressive generation with modifications (e.g., causal masking at fine-tune time), but it's architecturally unnatural and inefficient; say "optimized for" not "limited to."
- **Mistake:** Dismissing encoder-decoder (T5/BART) as "obsolete" because decoder-only LLMs are dominant — **Better:** Note that encoder-decoder remains competitive for *production seq2seq tasks* (translation, summarization) where fine-tuning data exists and inference cost matters; Flan-T5 still ships in enterprise workflows.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q2: How do transformers work?](01-002-how-do-transformers-work.md) | Prerequisite — self-attention mechanism underlying all three families |
| [Q22: What is self-attention? How does it differ from multi-head attention?](01-022-what-is-self-attention-how-does-it-differ-from-multi-head-at.md) | Deep dive into attention mechanics that explain bidirectional vs causal difference |
| [Q26: Why are decoder-only models dominant even for non-generation tasks?](01-026-why-are-decoder-only-models-dominant-even-for-non-generation.md) | Direct follow-up — the architectural + scaling argument for decoder-only dominance |

---

## One-liner recall

> Encoder-only (BERT) = bidirectional attention + MLM → best for embeddings/classification; decoder-only (GPT/Llama) = causal masking + CLM → best for generation/instruction-following; encoder-decoder (T5/BART) = bidirectional encode + autoregressive decode → best for seq2seq transduction; decoder-only has taken over most tasks at scale but encoder-only wins on latency/cost for embeddings.
