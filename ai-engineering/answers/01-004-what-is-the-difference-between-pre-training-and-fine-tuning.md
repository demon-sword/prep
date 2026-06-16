# What is the difference between pre-training and fine-tuning?

**Category:** 01-llm-fundamentals
**Question #:** 004
**Source section:** §1 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
This is a core competency question that appears in nearly every technical screen. It probes whether the candidate understands the modern LLM training stack at a conceptual level — pre-training is what creates the base model's language ability and knowledge; fine-tuning adapts that model to specific tasks or behaviors. Confusing these phases (or not knowing the distinction between SFT, RLHF, and LoRA) signals a lack of production AI experience.

### Trigger phrases
- "What is the difference between pre-training and fine-tuning?"
- "When would you fine-tune vs. use prompt engineering?"
- "What is instruction tuning and how does it relate to fine-tuning?"
- "Explain the LLM training pipeline from scratch to a deployed chat model."

### What it tests
Understanding of the full LLM training lifecycle — how base models acquire general knowledge (pre-training), how they're adapted to follow instructions (SFT), and how they're aligned to human preferences (RLHF/DPO) — and practical judgment about when fine-tuning is worth the cost.

---

## Answer

### Concept
**Pre-training** is the foundational training phase where a model learns language structure, world knowledge, and reasoning patterns by predicting the next token over hundreds of billions to trillions of tokens of internet text, books, and code. It trains all model weights from scratch using a self-supervised objective. Pre-training produces a *base model* that is good at completing text but not at following instructions or being safe.

**Fine-tuning** starts from the pre-trained base model and continues training on a smaller, curated dataset to adapt the model's behavior — without needing to re-learn language from scratch. Fine-tuning can target: instruction-following format (SFT), human preference alignment (RLHF/DPO), or domain-specific knowledge and style (domain adaptation).

### Mechanism

**Pre-training:**
- Dataset: 1–15 trillion tokens (web crawls via Common Crawl, books, code, Wikipedia)
- Objective: next-token prediction (causal language modeling), cross-entropy loss
- Scale: hundreds to thousands of GPUs, weeks to months of training
- Cost: $2M–$100M+ (GPT-4 class) in compute
- Output: a base model that can complete any text continuation but doesn't reliably follow instructions

**Supervised Fine-Tuning (SFT):**
- Dataset: 10K–1M high-quality instruction-response pairs (e.g., Alpaca, FLAN, OpenHermes)
- Same next-token prediction objective, but on curated conversational/task data
- Trains all weights (full fine-tune) or a small adapter subset (PEFT/LoRA — typically <1% of parameters)
- Cost: hours to days on a single GPU cluster; dramatically cheaper than pre-training
- Output: a model that follows instruction format and produces structured, helpful responses

**RLHF (Reinforcement Learning from Human Feedback):**
- Trains a separate reward model on human preference comparisons (A vs B response)
- Uses PPO to optimize the LLM to score highly on the reward model while staying close to the SFT policy (KL penalty)
- Addresses sycophancy, refusal patterns, and safety

**DPO (Direct Preference Optimization):**
- Skips the separate reward model entirely
- Directly optimizes the LLM on preference pairs (preferred vs. rejected response) using a contrastive loss
- More stable and cheaper than RLHF; now the dominant approach (used in Llama-3, Mistral-Instruct, Qwen)

**LoRA / QLoRA (Parameter-Efficient Fine-Tuning):**
- Instead of updating all model weights, adds low-rank adapter matrices (rank 8–64) to attention weight matrices
- Only adapter parameters are trained — the base model weights are frozen
- Reduces memory from ~140GB (70B full fine-tune) to ~4–16GB; enables fine-tuning on consumer GPUs with QLoRA (4-bit quantized base + FP16 adapters)

### Example / Tradeoff
A concrete example of the full stack:
1. **Pre-training:** Meta trains Llama-3-70B on ~15T tokens of diverse web text using 16K H100 GPUs over ~6 weeks. Cost: ~$30–50M.
2. **SFT:** Meta fine-tunes on 10M curated instruction examples for ~24 hours on 512 H100s. Cost: ~$50K.
3. **DPO alignment:** 24 more hours with human preference data. Cost: ~$30K.
4. Result: Llama-3-70B-Instruct — which follows instructions, refuses harmful requests, and answers helpfully.

**For an applied AI engineer**, fine-tuning with LoRA on Llama-3-8B requires:
- ~20GB GPU VRAM (single A100/H100)
- Dataset: 10K–100K domain-specific examples
- Training time: 4–12 hours
- Cost: $50–$500 in cloud compute

**Key tradeoff:** Fine-tuning changes *behavior* (format, style, refusals, instruction adherence) but does not reliably inject *new knowledge* into model weights. For factual knowledge from external sources, RAG is more reliable than fine-tuning — the model won't hallucinate facts it memorized incorrectly during training.

---

## Verbal script

**Opening (30s):**
"These are two fundamentally different phases of the LLM training lifecycle. Pre-training is what builds the model's foundational language ability and world knowledge — it's expensive, done once, and produces a base model. Fine-tuning starts from that base and adapts the model's behavior, and it's where most applied AI engineering happens. Let me walk through each."

**Core explanation (2–3 min):**
"Pre-training trains a model from random initialization on a massive corpus — typically 1 to 15 trillion tokens of web text, books, code, and Wikipedia. The objective is simple: predict the next token, minimize cross-entropy loss. But doing this at scale with 70 billion parameters over weeks on thousands of GPUs is what gives the model its knowledge about the world, its ability to reason in language, and its understanding of code. A pre-trained base model like Llama-3-70B-Base can complete any text — but it doesn't follow instructions, it's not safe, and it might complete a question with another question rather than an answer.

That's where fine-tuning comes in. Supervised fine-tuning, or SFT, continues training on 10K to a million curated instruction-response pairs. You're using the same next-token prediction objective, but on data that shows the model how to behave: user asks a question, assistant answers it helpfully and completely. SFT teaches format and instruction adherence, not new factual knowledge.

After SFT, you typically add alignment — either RLHF, which trains a separate reward model on human preference rankings and then uses PPO to optimize the LLM toward higher reward, or DPO, which skips the reward model and directly optimizes on preferred vs. rejected response pairs. DPO is now more common because it's more stable and cheaper.

For applied engineers, LoRA is the key technique — instead of fine-tuning all 70 billion parameters, you add small low-rank adapter matrices to attention layers and train only those. You can fine-tune a 70B model on a single A100 with QLoRA, taking the memory requirement from 140GB down to 20GB."

**Tradeoff / production angle (1 min):**
"The critical tradeoff is: fine-tuning changes behavior, not knowledge. If you fine-tune on medical Q&A data, the model gets better at the format and style of medical answers — but it doesn't reliably learn new facts. If it hallucinated something during pre-training, fine-tuning won't reliably correct it. For factual grounding, you need RAG. Fine-tune for style, persona, format, refusal patterns, and domain-specific output structure. Use RAG for factual grounding.

Another practical tradeoff: fine-tuning is expensive to iterate on. If you can solve the problem with a good system prompt and few-shot examples, always try that first."

**Wrap-up (30s):**
"So: pre-training = build foundational language ability at massive scale; fine-tuning = adapt behavior cheaply using LoRA/SFT/DPO; don't confuse fine-tuning with knowledge injection — use RAG for that. In practice, the decision tree is: prompt engineering first, RAG if knowledge is missing, fine-tune only if behavior/format can't be fixed above."

---

## Pitfalls

- **Mistake:** Saying "fine-tuning teaches the model new facts" — **Better:** Fine-tuning adapts behavior, format, and style; factual knowledge lives in weights from pre-training and is unreliable to inject via fine-tuning. For new factual knowledge, use RAG or accept that the model may hallucinate memorized-but-wrong facts.
- **Mistake:** Treating fine-tuning as a single technique, not knowing SFT vs. RLHF vs. DPO vs. LoRA — **Better:** Distinguish: SFT = instruction format; RLHF/DPO = preference alignment; LoRA = parameter-efficient adaptation method. In 2026, DPO has largely replaced PPO-based RLHF for alignment due to stability and cost.
- **Mistake:** Recommending fine-tuning before trying prompt engineering or RAG — **Better:** Fine-tuning is expensive and slow to iterate on. The decision order should be: system prompt → few-shot examples → RAG → fine-tuning. Fine-tune only when behavior can't be fixed in the context window.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q29: RLHF vs DPO — when prefer one over the other?](01-029-rlhf-vs-dpo-when-prefer-one-over-the-other.md) | Deep dive on the alignment phase described here |
| [Q40: What is the difference between prompt engineering, RAG, and fine-tuning?](01-040-what-is-the-difference-between-prompt-engineering-rag-and-fi.md) | Broader decision framework for when fine-tuning vs. other approaches |
| [Q1: How do LLMs work?](01-001-how-do-llms-work.md) | Prerequisite — the pre-training phase is part of the full LLM pipeline |

---

## One-liner recall

> Pre-training builds foundational language knowledge via next-token prediction on trillions of tokens (all weights, from scratch, expensive); fine-tuning adapts behavior on curated task data using SFT + RLHF/DPO, efficiently via LoRA — but fine-tuning changes behavior, not factual knowledge (use RAG for that).
