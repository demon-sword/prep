# Why are decoder-only models dominant even for non-generation tasks?

**Category:** 01-llm-fundamentals
**Question #:** 026
**Source section:** §1 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
The interviewer is probing architectural intuition — whether you understand the practical and empirical reasons the field converged on decoder-only Transformers (GPT-style) even for tasks like classification, summarization, and embedding that were historically encoder or encoder-decoder territory. It tests depth beyond "GPT generates, BERT classifies."

### Trigger phrases
- "Why do we use GPT-4 for classification instead of BERT?"
- "Why are decoder-only models dominant even for non-generation tasks?"
- "What's the architectural advantage of causal models over bidirectional models at scale?"

### What it tests
Understanding of the scaling, training-efficiency, and emergent-capability arguments that made the decoder-only paradigm the production default by 2024–2026.

---

## Answer

### Concept
Decoder-only models (GPT-series, Llama, Mistral, Claude) use causal (left-to-right) self-attention and are trained with a next-token prediction objective. Despite lacking bidirectional context, they outperform encoder and encoder-decoder architectures on almost every benchmark at large scale — including tasks where bidirectional context would seem to help.

### Mechanism
Four compounding reasons explain the dominance:

1. **Unified pretraining objective** — Next-token prediction is a single, scalable loss that consumes all the text in the internet corpus without any labeling. Encoder-only models need masked-LM plus auxiliary tasks; encoder-decoder models need paired sequences. The simpler objective scales cleaner with compute.

2. **One architecture, every task** — A decoder can classify (generate a label token), summarize (generate a shorter sequence), embed (pool the last or a special token), translate, do QA, and reason — all in one model. Encoder-only (BERT) needs a task-specific head; encoder-decoder (T5) works well for seq2seq but is awkward for open-ended generation. A single large decoder avoids maintaining a zoo of specialized models.

3. **In-context learning unlocks zero/few-shot** — The causal LM objective teaches the model to continue any prefix, which naturally enables prompting and few-shot examples in the input. BERT cannot do this natively. At inference, you can adapt a decoder-only model to any new task with a few examples in the prompt — no retraining required.

4. **Scaling laws favor next-token prediction** — Kaplan et al. (2020) and Chinchilla (2022) both characterize decoder-only architectures. Empirically, performance on downstream tasks improves smoothly with model size and data for next-token prediction. Encoder architectures hit diminishing returns earlier; encoder-decoder models have double the parameter count for the same effective depth, making large-scale training more expensive.

**For classification specifically:** A decoder-only model simply generates the class label as the first token after a prompt like `"Classify: [text]\nLabel:"`. With temperature=0, this is deterministic and achieves competitive or SOTA accuracy — eliminating the need for encoder fine-tuning entirely.

**For embeddings:** Decoder-only models produce strong embeddings by mean-pooling the last hidden states or using a `<EOS>` token representation. Models like `text-embedding-3-large` (OpenAI) and `Mistral-Embed` are decoder-only and top MTEB leaderboards, disproving the assumption that bidirectional attention is required for embedding quality.

### Example / Tradeoff
**Llama 3 70B for classification vs fine-tuned BERT-large:**
- Llama 3 zero-shot via prompt: ~85% accuracy on SST-2
- BERT-large fine-tuned: ~93% accuracy, but requires labeled data and a classification head
- Llama 3 fine-tuned with LoRA: ≥95%, same task, and the same model handles generation tasks without duplication

**The remaining case for encoder-only:** Cross-encoder reranking in RAG pipelines still uses BERT-style models (e.g., `ms-marco-MiniLM`) because they process query+document jointly and are 10–50× cheaper to run than a 70B decoder at inference. For reranking on top-100 candidates this specialized use case still wins on latency and cost.

---

## Verbal script

**Opening (30s):**
"The short answer is: scaling works better on a single architecture with a single objective. But let me walk through the four compounding reasons, because the answer is more interesting than just 'GPT is bigger.'"

**Core explanation (2–3 min):**
"First, training efficiency. Next-token prediction uses every token in every document as a training signal — no masking overhead, no paired examples, no auxiliary tasks. That single loss scales smoothly with compute and data according to Chinchilla's laws.

Second, one model, every task. A decoder can classify by generating a label token, summarize by generating fewer tokens, translate, embed via token pooling — anything. That means in production you maintain one large model instead of a BERT for classification, a T5 for summarization, and a GPT for generation. The operational simplicity is massive.

Third, in-context learning. Because the model is trained to continue any prefix, you can give it a few examples in the prompt and it adapts without retraining. BERT fundamentally cannot do that — it needs gradient updates for each new task.

Fourth, empirics. Every scaling study from 2020 onward characterizes decoder-only models. We don't have good scaling laws for masked-LM at the 70B+ scale because nobody trains BERT-70B — there's no evidence it would work as well."

**Tradeoff / production angle (1 min):**
"The one place encoder-only still wins is cross-encoder reranking. In RAG, I still use a small BERT-style cross-encoder to rerank the top 50–100 candidates because it's 10–50× cheaper per call and query+document bidirectional context genuinely helps. But that's a narrow, latency-critical use case, not a general argument for BERT."

**Wrap-up (30s):**
"So: decoder-only dominates because training is simpler, one model covers all tasks, prompting replaces fine-tuning for adaptation, and empirical scaling evidence supports it. Happy to go deeper on any of these — KV caching advantages, or why embeddings from decoder models are competitive."

---

## Pitfalls

- **Mistake:** Saying "encoder models are better for classification because they see both directions" — **Better:** Acknowledge the theoretical bidirectional advantage but explain why it doesn't matter at scale: large decoder-only models achieve equal or better accuracy via zero-shot prompting or LoRA fine-tuning, with no labeled data requirement for the former.
- **Mistake:** Treating this as purely a "GPT is just bigger" argument without addressing the architectural reasons — **Better:** Walk through the four factors (unified objective, multi-task capability, in-context learning, scaling laws) to show architectural and training-regime insight, not just benchmark citation.
- **Mistake:** Forgetting that encoder-only still has a valid production niche — **Better:** Call out cross-encoder reranking (ms-marco-MiniLM in RAG pipelines) as the concrete carve-out where BERT-style wins on cost and latency.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q25: Encoder-only vs decoder-only vs encoder-decoder — when use each?](01-025-encoder-only-vs-decoder-only-vs-encoder-decoder-when-use-eac.md) | Direct prerequisite — architectural taxonomy |
| [Q2: How do transformers work?](01-002-how-do-transformers-work.md) | Foundation — attention mechanism and causal masking |
| [Q14: What is re-ranking? Cross-encoder vs bi-encoder?](02-014-what-is-re-ranking-cross-encoder-vs-bi-encoder.md) | Counter-example where encoder-only retains a production role |

---

## One-liner recall

> Decoder-only models dominate because next-token prediction is a single scalable objective that trains on all text, one model handles every task via prompting, in-context learning replaces per-task fine-tuning, and empirical scaling laws only exist for this architecture — making the encoder-only advantage of bidirectional context irrelevant at scale.
