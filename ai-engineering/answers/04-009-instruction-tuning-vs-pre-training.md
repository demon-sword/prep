# Instruction tuning vs pre-training?

**Category:** 04-fine-tuning-training
**Question #:** 009
**Source section:** §4 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
Interviewers use this to check whether a candidate understands the two-phase lifecycle of a modern LLM — what each phase teaches the model and what it costs. Strong candidates know that pre-training is a one-time, massively expensive knowledge-injection step, while instruction tuning is a cheap, repeatable behavior-shaping step that runs on top of a frozen or lightly trained base. Confusing the two reveals a textbook-only understanding with no production intuition.

### Trigger phrases
- "What's the difference between pre-training and instruction tuning?"
- "When would you do instruction fine-tuning vs continued pre-training?"
- "Why can't you just instruction-tune to teach the model new domain knowledge?"

### What it tests
Whether the candidate understands the knowledge-vs-behavior distinction and can articulate when each training phase is appropriate, including data requirements, compute cost, and failure modes.

---

## Answer

### Concept
**Pre-training** teaches a model *what to know* — it learns language patterns, world knowledge, and reasoning capabilities by predicting the next token across hundreds of billions to trillions of tokens of raw text. **Instruction tuning** (also called supervised fine-tuning or SFT) teaches the model *how to behave* — it learns to follow instructions, produce structured outputs, stay on-topic, and adopt a consistent tone by training on (instruction, response) pairs, typically with full cross-entropy loss on the response tokens only.

Pre-training is a one-time compute-intensive investment (thousands of GPU-days); instruction tuning is cheap and repeatable (hours to days on commodity hardware with LoRA).

### Mechanism

**Pre-training pipeline:**
1. Collect a massive, diverse corpus (CommonCrawl, Books, arXiv, GitHub, Wikipedia — trillions of tokens).
2. Deduplicate with MinHash/near-dedup, filter quality (perplexity-based, classifier-based).
3. Tokenize with BPE (e.g., tiktoken, SentencePiece), pack sequences to fill context windows.
4. Train a decoder-only transformer with causal language modeling (CLM) loss: predict token `t+1` given `1..t`. No labels — fully self-supervised.
5. Scale: Chinchilla law says optimal allocation is ~20 tokens per parameter; a 7B model trained on 140B tokens is compute-optimal; Llama 3 8B used ~15T tokens (over-trained for inference efficiency).
6. Cost: GPT-3 (175B) cost ~$4M in 2020 GPU time; Llama 3 70B required ~6M H100 GPU-hours.

**Instruction tuning pipeline:**
1. Collect (instruction, response) pairs — either human-written (OpenAI's InstructGPT had 13K curated pairs initially) or synthetically generated (Alpaca: 52K GPT-3.5 pairs; Orca: GPT-4 traces).
2. Format as a prompt template (e.g., `### Instruction:\n{inst}\n### Response:\n{resp}`).
3. Apply cross-entropy loss **only on the response tokens** — ignore instruction tokens in the loss (they're the "input," not the target).
4. Train with LoRA (rank 8–64) or full SFT on the base pre-trained checkpoint. Typical: 1–3 epochs, LR 1e-4–2e-4, batch 128, BF16.
5. Optionally follow with DPO/RLHF for preference alignment.
6. Cost: Llama 3 8B instruction-tuned with LoRA on 4× A100 40GB — ~8 hours for 50K examples.

**Key distinction — what each phase can and cannot do:**

| Dimension | Pre-training | Instruction tuning |
|-----------|-------------|-------------------|
| Goal | Teach world knowledge, language patterns | Teach instruction-following, format, style |
| Data | Trillions of raw text tokens | Thousands–millions of (instruction, response) pairs |
| Loss | CLM on all tokens | CE on response tokens only |
| Compute | GPU clusters, weeks–months | 4–8 GPUs, hours–days |
| Updateable? | No (base model frozen after) | Yes — re-run on new data |
| Teaches new facts? | Yes (primary) | Weakly — brittle memorization |
| Risk | Very high (catastrophic if wrong data mix) | Low (LoRA keeps base frozen) |
| Output | Base model (raw, no chat behavior) | Chat/instruction model |

### Example / Tradeoff

**Why instruction tuning does NOT reliably inject new facts:**
Take a domain like proprietary legal contracts. If the base model never saw those contracts during pre-training, instruction-tuning on 5K Q&A pairs can cause the model to *pattern-match the format* (answering like a lawyer) but will hallucinate the underlying clauses — it has no real knowledge of them. For factual knowledge gaps, RAG or continued pre-training on the raw documents is the right tool.

**Real-world example — Llama 3 lifecycle:**
- **Pre-training:** Meta trained Llama 3 8B on 15T tokens (web, code, books, math) for several weeks on 16K H100 GPUs. This gives the base model broad knowledge and language capability.
- **Instruction tuning (SFT):** Meta then applied SFT on ~10M curated instruction pairs (Meta's internal annotation + synthetically generated via Meta's own models) for a few days. This gave Llama 3 8B Instruct its chat behavior, JSON output formatting, and safety refusals.
- **Preference alignment (DPO):** Final alignment pass on preference pairs to reduce harmful outputs.

**Continued pre-training** (domain-adaptive pre-training, DAPT) is a middle ground: you start from a pre-trained base and run CLM loss on domain-specific raw text (e.g., PubMed articles for BioMedLM, legal filings for Harvey AI's models). This injects domain vocabulary and factual knowledge *without* the cost of training from scratch. You then run instruction tuning on top. DAPT typically requires 10B–100B domain tokens to be meaningful.

**Break-even heuristic:**
- Use instruction tuning alone when: behavior gap (style, format, safety, instruction-following) and the model already has general domain knowledge.
- Use DAPT + instruction tuning when: domain vocabulary is highly specialized (clinical codes, legal citations, code in a niche language) AND you have 10B+ raw domain tokens.
- Use RAG when: knowledge needs to stay fresh, authoritative, or citable, and you don't have the compute budget for DAPT.

---

## Verbal script

**Opening (30s):**
"These are two distinct phases in the life of a modern LLM with fundamentally different goals. Pre-training teaches the model *what to know* — world knowledge and language patterns — while instruction tuning teaches it *how to behave* — how to follow instructions, format outputs, and adopt a consistent style. The key production insight is that they're not interchangeable: instruction tuning can't reliably inject new facts, and pre-training can't make a model follow instructions."

**Core explanation (2–3 min):**
"Pre-training is self-supervised: the model predicts the next token across trillions of tokens of raw internet text, books, and code. No labels needed. The result is a base model with broad knowledge — but it's raw, unfiltered, and will complete any prompt as if continuing a document, not as if answering a question. The cost is enormous: Llama 3 8B took 15 trillion tokens and weeks of training on thousands of H100 GPUs.

Instruction tuning starts from that pre-trained base and trains on (instruction, response) pairs — typically tens of thousands to millions of them. Critically, the loss is applied only on the response tokens, not the instruction. The model learns the *conversational format and behavior* — how to answer questions, follow safety guidelines, produce JSON, write code. Llama 3 Instruct, GPT-4, Claude — all were instruction-tuned on top of a pre-trained base. With LoRA, you can do this in hours on a few GPUs by only updating low-rank adapter weights while keeping the base frozen.

The failure mode to call out explicitly: instruction tuning does not reliably inject new factual knowledge. If you fine-tune on Q&A pairs about your proprietary contracts, the model learns to *answer in the style* of a contract lawyer but will hallucinate the underlying clauses because the base model never saw those contracts. For factual knowledge gaps, you need RAG or domain-adaptive pre-training — running CLM loss on raw domain text like PubMed articles or legal filings."

**Tradeoff / production angle (1 min):**
"In practice, there are three common training recipes you see in production: base model → instruction tuning (cheapest, works for most chat products); base model → domain-adaptive pre-training (DAPT) → instruction tuning (for highly specialized domains like clinical or legal); and the increasingly popular 'post-training' approach — base model → SFT → DPO/RLHF — which is what Meta did for Llama 3 Instruct and what OpenAI did for InstructGPT. The choice between these is mostly driven by whether your domain vocabulary and facts are already in the base model or not."

**Wrap-up (30s):**
"So the short version: pre-training = knowledge, instruction tuning = behavior. They're complementary, not alternatives. For most product teams, the base model's pre-training is a given and you're doing instruction tuning — and increasingly just LoRA-based SFT plus DPO. I'm happy to go deeper on LoRA mechanics, the DPO preference-alignment step, or when DAPT is worth the cost."

---

## Pitfalls

- **Mistake:** Saying "instruction tuning teaches the model new information" — **Better:** Clarify that instruction tuning primarily shapes *behavior and format*, not factual knowledge; new facts are best injected via RAG (updateable, citeable) or domain-adaptive pre-training (CLM on raw domain text); instruction-tuned Q&A memorization is brittle and produces confident hallucinations on unseen variants
- **Mistake:** Treating pre-training as something product teams do from scratch — **Better:** In practice, product teams start from an open-source pre-trained base (Llama 3, Mistral, Qwen) or use a hosted API; pre-training from scratch requires billions of dollars in compute and is only done by foundation model labs; the realistic decision is instruction-tune vs DAPT+instruction-tune vs RAG
- **Mistake:** Not knowing the loss function difference — **Better:** In pre-training, CLM loss applies to all tokens; in instruction tuning, cross-entropy loss is applied *only on response tokens* (instruction tokens are masked), which is why instruction tuning converges quickly even on small datasets

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q1: When fine-tune vs prompt engineering?](04-001-when-fine-tune-vs-prompt-engineering.md) | Prerequisite: the full decision ladder (prompt → RAG → SFT → DPO → pre-training) |
| [Q4: What is RLHF and why important?](04-004-what-is-rlhf-and-why-important.md) | Follow-up: the preference alignment stage that typically runs after instruction tuning |
| [Q5: Fine-tune or prompt-engineered RAG?](04-005-fine-tune-or-prompt-engineered-rag.md) | Related: when to use RAG instead of SFT for knowledge gaps — the exact failure mode of instruction tuning |

---

## One-liner recall

> Pre-training injects knowledge via CLM loss on trillions of raw tokens; instruction tuning shapes behavior via CE loss on response tokens only — the two are complementary phases, not alternatives, and IT cannot reliably inject new facts.
