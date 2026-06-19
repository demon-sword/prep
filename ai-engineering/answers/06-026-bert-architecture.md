# BERT architecture?

**Category:** 06-ml-fundamentals
**Question #:** 026
**Source section:** §6 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
Interviewers use this to probe whether candidates understand encoder-only transformers at the architectural level — not just that BERT exists, but *why* its bidirectional masked pre-training makes it powerful for classification, NER, and re-ranking tasks while also understanding why it's been largely displaced by decoder-only models in the LLM era. The question also surfaces whether candidates can articulate the practical difference between BERT-family (encoders) and GPT-family (decoders).

### Trigger phrases
- "Walk me through the BERT architecture."
- "How does BERT differ from GPT?"
- "Why would you use BERT for re-ranking instead of a generative model?"
- "What is masked language modeling?"

### What it tests
Depth on encoder-only transformers — bidirectional attention, MLM/NSP pre-training, and when encoder models remain the right tool (cross-encoder re-ranking, NLP classification) versus when to use decoders.

---

## Answer

### Concept
BERT (Bidirectional Encoder Representations from Transformers, Devlin et al. 2019) is an encoder-only transformer pre-trained with Masked Language Modeling (MLM) and Next Sentence Prediction (NSP). Unlike GPT's left-to-right causal attention, BERT attends to both left and right context simultaneously, producing deeply contextualised token representations ideal for understanding tasks (classification, NER, question answering, re-ranking).

### Mechanism

**Architecture:**
- Stack of N transformer *encoder* blocks (BERT-base: 12 layers, 768 hidden dim, 12 heads = 110M params; BERT-large: 24 layers, 1024 dim, 16 heads = 340M params).
- Each block: Multi-Head Self-Attention (bidirectional, no causal mask) → Layer Norm → Feed-Forward (4× hidden dim) → Layer Norm.
- Input embedding = token embedding + segment embedding (sentence A vs B) + learned positional embedding.
- Special tokens: `[CLS]` (pooled representation for classification), `[SEP]` (segment separator), `[MASK]`.

**Pre-training objectives:**
1. **Masked Language Modeling (MLM):** 15% of tokens are randomly masked; the model predicts the original token using bidirectional context. This forces the model to build rich contextual representations.
   - Of the 15%: 80% replaced with `[MASK]`, 10% replaced with a random token, 10% left unchanged (prevents mismatch at fine-tune time).
2. **Next Sentence Prediction (NSP):** Given sentence pairs, predict whether sentence B follows sentence A. Helps with sentence-pair tasks (QA, NLI). *Note: later work (RoBERTa, 2019) showed NSP hurts and removed it.*

**Fine-tuning:**
- Add a task-specific head on top of `[CLS]` (classification) or token representations (NER, span extraction).
- Fine-tune on labeled data for a few epochs — typically 3–5 epochs on moderate datasets.

**Key architectural difference from GPT:**
| Property | BERT (encoder-only) | GPT (decoder-only) |
|---|---|---|
| Attention mask | Bidirectional (full) | Causal (left-to-right) |
| Pre-training objective | MLM + NSP | Next-token prediction (CLM) |
| Best for | Understanding (classification, re-ranking) | Generation |
| Context direction | Both left and right | Left only |
| 2025 relevance | Cross-encoder re-ranking, NLP classification | Instruction-following LLMs |

### Example / Tradeoff

**Cross-encoder re-ranking (production BERT use-case):**
In a RAG pipeline, a bi-encoder (two separate BERT encoders) retrieves top-100 candidates from Pinecone/FAISS. A cross-encoder BERT (both query and document fed together through the same model) then re-ranks the top-100 → top-5. The cross-encoder sees the full joint context, enabling 20–30 point NDCG improvement over bi-encoder alone. Models: `ms-marco-MiniLM-L-6-v2` (Sentence Transformers), Cohere Rerank API.

**Concrete benchmark:** On MS MARCO passage ranking, BERT-large cross-encoder achieves MRR@10 ~36 vs bi-encoder ~33 out of the box; with fine-tuning on domain data it reaches ~39.

**Why not just use GPT-4 for re-ranking?**
Cross-encoder BERT is ~170ms latency for 100 candidate pairs on CPU, costs fractions of a cent per query. GPT-4o for the same task: ~1–2s, ~$0.002–0.01 per query at 100 candidates. For a RAG pipeline at 1M queries/day, BERT re-ranking saves ~$1,500–8,000/day versus LLM-based re-ranking.

---

## Verbal script

**Opening (30s):**
"BERT is an encoder-only transformer — the key architectural insight is that it uses *bidirectional* self-attention, meaning every token can attend to every other token in the sequence. That's fundamentally different from GPT's causal masking, which only lets tokens attend to the left. That bidirectional context makes BERT exceptional for understanding tasks — classification, NER, question answering, and especially cross-encoder re-ranking in RAG pipelines."

**Core explanation (2–3 min):**
"Architecturally, BERT-base is 12 transformer encoder blocks: each block runs multi-head self-attention — 12 heads, 768 hidden dimensions — then a feed-forward sublayer at 4× that width, with layer norm after each. The input combines token, segment, and positional embeddings, with two special tokens: `[CLS]` at the start, whose final hidden state is used as the pooled sequence representation for classification, and `[SEP]` to separate sentence pairs.

Pre-training uses two objectives. The main one is Masked Language Modeling — 15% of tokens are randomly masked, and the model predicts the originals using full bidirectional context. That forces every layer to build rich contextual representations. The second objective, Next Sentence Prediction, predicts whether two sentences are consecutive — useful for sentence-pair tasks but later shown by RoBERTa to actually hurt performance, so modern BERT variants drop it.

Fine-tuning is straightforward: you add a small task head on top of the `[CLS]` token (for classification) or individual token representations (for NER or span extraction), then fine-tune on labeled data for 3–5 epochs. BERT-base achieves excellent results on GLUE benchmarks with just a few thousand labeled examples."

**Tradeoff / production angle (1 min):**
"In 2025–2026, the main production use of BERT-family encoders is *cross-encoder re-ranking* in RAG systems. You use a bi-encoder for fast ANN retrieval at scale — Pinecone, FAISS, Qdrant — then a cross-encoder BERT for precise re-ranking of the top-100 candidates. That two-stage approach delivers the latency of ANN search with the precision of cross-attention, and it's 10–100× cheaper than using a generative LLM for the same re-ranking task. The key tradeoff: cross-encoders can't be pre-indexed, so they only scale to hundreds of candidates, not millions."

**Wrap-up (30s):**
"So BERT's bidirectional architecture makes it ideal for discriminative understanding tasks, and its primary production role today is cross-encoder re-ranking in RAG pipelines — where its accuracy advantage over bi-encoders justifies the query-time latency cost. Happy to go deeper on the cross-encoder vs bi-encoder tradeoff or into RoBERTa and DeBERTa improvements."

---

## Pitfalls

- **Mistake:** Describing BERT as "just a transformer" without explaining what makes the encoder-only / bidirectional design special — **Better:** Explicitly contrast the bidirectional (no causal mask) attention with GPT's causal masking, and explain why MLM requires seeing both directions.
- **Mistake:** Saying BERT is outdated/irrelevant because LLMs replaced it — **Better:** Explain that BERT-family cross-encoders remain the state-of-the-art for re-ranking in RAG pipelines and NLP classification tasks at production scale due to their speed and cost advantage over generative models.
- **Mistake:** Confusing bi-encoder (two separate BERT encoders for ANN retrieval) with cross-encoder (joint query+doc input for re-ranking) — **Better:** Clearly distinguish the two architectures: bi-encoder for scalable ANN retrieval (pre-indexable), cross-encoder for precise re-ranking of top-N candidates (query-time only).

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q25: CNN architecture?](06-025-cnn-architecture.md) | Parallel architecture deep-dive; both probe "explain a foundational deep learning architecture" |
| [Q18: What is re-ranking? Cross-encoder vs bi-encoder?](../answers/02-018-what-is-re-ranking-cross-encoder-vs-bi-encoder.md) | Primary production use-case for BERT cross-encoders in RAG |
| [Q22: What is self-attention? How does it differ from multi-head attention?](../answers/01-022-what-is-self-attention-how-does-it-differ-from-multi-head-attention.md) | BERT's core mechanism — prerequisite for understanding how bidirectional attention works |

---

## One-liner recall

> BERT is an encoder-only transformer with bidirectional (non-causal) self-attention, pre-trained via Masked Language Modeling, and remains production-relevant as a cross-encoder re-ranker in RAG pipelines where it delivers 20–30pt NDCG gains at a fraction of the cost of using a generative LLM.
