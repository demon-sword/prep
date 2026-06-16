# What is the difference between prompt engineering, RAG, and fine-tuning?

**Category:** 01-llm-fundamentals
**Question #:** 040
**Source section:** §1 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
This is one of the highest-signal questions in the entire interview bank — it appears at every level from recruiter screen to senior system design. The interviewer wants to see that you have a structured mental model for *when to reach for each tool*, not just that you know what they are. Strong candidates present a decision tree with concrete cost/latency/complexity tradeoffs. Weak candidates list definitions and stop there.

### Trigger phrases
- "When would you use RAG vs fine-tuning?"
- "What's the difference between prompt engineering, RAG, and fine-tuning?"
- "Walk me through how you'd decide whether to fine-tune or use RAG."
- "Why not just fine-tune the model on our domain data?"

### What it tests
The ability to apply a cost-ordered decision framework and articulate concrete tradeoffs across all three approaches — not just define them.

---

## Answer

### Concept
Prompt engineering, RAG, and fine-tuning are three complementary strategies for adapting a base LLM to a specific task — ordered by cost, complexity, and the kind of gap they close. Prompt engineering changes *what the model sees at inference time*; RAG changes *what knowledge is available at inference time*; fine-tuning changes *the model weights themselves*.

### Mechanism

**1. Prompt engineering** — zero cost to deploy, immediate iteration:
- Modify the system prompt, user message, or few-shot examples.
- Techniques: zero-shot, few-shot, chain-of-thought (CoT), self-consistency, structured output constraints (`response_format: json_object`).
- Limits: bounded by the model's existing knowledge and instruction-following ability; doesn't add proprietary knowledge; prompt tokens cost money at scale.

**2. RAG (Retrieval-Augmented Generation)** — moderate engineering cost, no GPU:
- Retrieve relevant chunks from an external knowledge store at query time; inject them into the context window before generation.
- Pipeline: embed query → ANN search (HNSW via FAISS / Pinecone / Weaviate) → optional BM25 hybrid + cross-encoder reranking → inject top-k chunks → generate.
- Closes the *knowledge gap*: proprietary docs, real-time data, or content past the model's training cutoff.
- Does **not** change model behavior/style; hallucinations can still occur if retrieved context is absent or contradictory.

**3. Fine-tuning** — highest cost, weeks of iteration:
- Update model weights via supervised fine-tuning (SFT) on domain data, or alignment via RLHF / DPO.
- PEFT approaches (LoRA, QLoRA) make this tractable on a single A100/H100 with 4-bit quantization.
- Closes the *behavior gap*: custom output format, domain tone, consistent persona, task-specific reasoning patterns.
- Does **not** reliably inject new factual knowledge (models can hallucinate fine-tuned facts with false confidence); combine with RAG for knowledge + behavior.

### Example / Tradeoff

**Decision tree in practice:**

| Question | Answer → Do this |
|----------|------------------|
| Does the model already know the domain? | Yes → start with prompt engineering |
| Is the knowledge proprietary / frequently updated? | Yes → add RAG |
| Is the behavior (style, format, reasoning) wrong even with good context? | Yes → fine-tune |
| Is fine-tune data < 1K high-quality examples? | Probably → few-shot prompting instead |
| Budget / latency critical? | Yes → defer fine-tuning, optimize prompts + RAG |

**Concrete case:** A legal Q&A assistant at a Fortune 500.
- *Prompt only*: GPT-4 already reads contracts well, but hallucinations on specific clause numbers.
- *+ RAG*: Embed 300K contracts into Pinecone; HNSW retrieval; faithfulness score (RAGAS) goes 0.61 → 0.89.
- *+ LoRA fine-tune*: After 6 months, lawyers want a specific citation format and hedging style. Fine-tune on 2K lawyer-reviewed (question, answer) pairs with LoRA rank-16 on Llama 3 70B. Training: ~8 hrs on 4× A100s with QLoRA. Output style now consistent without prompt hacks.

**Cost summary:**
| Approach | Upfront | Per-query | Iteration speed |
|----------|---------|-----------|-----------------|
| Prompt engineering | ~hours | +0 (token cost) | Minutes |
| RAG | Days–weeks (pipeline) | +embedding + retrieval | Days |
| Fine-tuning | Weeks + GPU cost | Smaller model possible | Weeks |

---

## Verbal script

**Opening (30s):**
"These three form a cost-ordered ladder that I always evaluate in sequence. Prompt engineering is the cheapest and fastest — start there. RAG solves a different problem: missing or stale knowledge. Fine-tuning solves a third problem: wrong *behavior*, even when the knowledge is present. Let me walk through each and when I'd reach for it."

**Core explanation (2–3 min):**
"Prompt engineering is just structuring what the model sees — system prompt, few-shot examples, chain-of-thought instructions. It costs nothing to deploy, iterates in minutes, and solves maybe 60–70% of problems. The limit is that you're bounded by the model's existing knowledge and behavior.

When users need answers grounded in proprietary or up-to-date documents — internal wikis, legal contracts, support tickets — that's the RAG signal. I'd build a standard pipeline: chunk the docs, embed with a model like text-embedding-3-large, index with FAISS or Pinecone using HNSW, then at query time retrieve top-20 by cosine similarity, rerank with a cross-encoder down to top-5, and inject into context. RAGAS gives me faithfulness and context precision metrics to track quality. RAG is engineering effort — maybe two to four weeks for a production system — but no GPU training.

Fine-tuning is for the behavioral gap. If the model gives technically correct answers but in the wrong format, wrong tone, or with inconsistent reasoning patterns — even when given perfect context — that's when I'd consider it. I'd use LoRA or QLoRA to keep cost manageable. The key caution: fine-tuning does not reliably bake in new facts. Models often confabulate fine-tuned knowledge with false confidence. So in production I combine RAG + fine-tuning: RAG handles the knowledge, fine-tuning handles the behavior."

**Tradeoff / production angle (1 min):**
"The failure mode I see most often is teams jumping to fine-tuning too early. Someone sees the model output is wrong, assumes it needs training, spends three weeks on a fine-tuning pipeline, and then realizes the real problem was the retrieval was returning irrelevant chunks. I always fix the retrieval layer first. Another pattern: underestimating the data requirement — if you have fewer than a few hundred high-quality examples, few-shot prompting almost always beats fine-tuning. Fine-tuning really shines at 1K–10K carefully curated pairs."

**Wrap-up (30s):**
"So the decision sequence: prompt engineering first, RAG when there's a knowledge gap, fine-tuning when there's a behavioral gap that RAG can't fix — and often you end up combining all three in production. Happy to go deeper on any of the three, or talk through the RAGAS eval metrics I'd use to validate the RAG layer."

---

## Pitfalls

- **Mistake:** Treating the three as mutually exclusive alternatives — "RAG *or* fine-tuning" — **Better:** Explain that production systems commonly combine all three: prompt engineering sets the frame, RAG grounds the knowledge, fine-tuning tunes the behavior — each closes a different gap.
- **Mistake:** Saying "fine-tune when you have domain data" without qualifying how much data is needed or what fine-tuning actually changes — **Better:** Specify that fine-tuning changes model *behavior*, not reliably *knowledge*, and that you need 500–10K high-quality labeled examples for SFT to outperform few-shot prompting; also mention LoRA/QLoRA for cost efficiency.
- **Mistake:** Presenting the decision as purely technical without mentioning cost, latency, or iteration speed — **Better:** Show the cost ladder (prompting = hours/free, RAG = days/engineering, fine-tuning = weeks/GPU) and say you always start cheapest.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q7: When fine-tune vs prompt engineering?](01-007-what-is-temperature-and-top-p-sampling-how-do-they-affect-ou.md) | Detailed fine-tuning decision criteria |
| [Q12: What's an RAG model? Explain the complete process.](01-012-whats-an-rag-model-explain-the-complete-process.md) | Deep dive on the RAG pipeline referenced here |
| [Q4: What is the difference between pre-training and fine-tuning?](01-004-what-is-the-difference-between-pre-training-and-fine-tuning.md) | Prerequisite — clarifies what fine-tuning changes |

---

## One-liner recall

> Prompt engineering → RAG → fine-tuning is a cost-ordered ladder: prompting is free and fast; RAG closes knowledge gaps without training; fine-tuning changes model behavior when context alone isn't enough — and production systems often need all three together.
