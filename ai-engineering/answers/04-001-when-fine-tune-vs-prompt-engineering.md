# When fine-tune vs prompt engineering? ⭐

**Category:** 04-fine-tuning-training
**Question #:** 001
**Source section:** §4 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
This is the #1 fine-tuning question because it exposes whether a candidate understands the *cost-quality ladder* of LLM adaptation. Interviewers want to see that you won't jump straight to fine-tuning (expensive, slow, risky catastrophic forgetting) when a well-crafted prompt or RAG pipeline would solve the problem. They're probing production maturity: have you shipped both approaches and know when each one actually justified its cost?

### Trigger phrases
- "When would you fine-tune instead of just prompting the model?"
- "You have a domain-specific task — what's your approach?"
- "Prompt engineering vs RAG vs fine-tuning — when do you use each?"

### What it tests
Mastery of the cost-ordered LLM adaptation decision tree and the ability to articulate concrete thresholds (data size, latency, cost, behavior gap type) that trigger each approach.

---

## Answer

### Concept
Prompt engineering and fine-tuning sit on a cost-quality ladder: prompt engineering is free and instant but limited by what the base model already knows and how it behaves; fine-tuning changes model weights to produce a reliably different behavior or style, but requires labeled data, compute, and an evaluation framework to verify it helped. The decision is driven by three gap types: **knowledge gap** (new facts the model doesn't know), **behavior gap** (consistent style, format, instruction-following the model can't reliably achieve in-context), and **efficiency gap** (reducing token cost by baking instructions into weights).

### Mechanism

Work through the decision ladder in order — abort as soon as a cheaper option works:

1. **Prompt engineering first** — zero-shot, then few-shot, then chain-of-thought. Costs nothing. Works when the base model already has the knowledge and just needs guidance. Fails when the task requires consistent specialized style, privacy (can't put all instructions in every prompt), or the context window is too expensive to fill with examples every call.

2. **RAG when there's a knowledge gap** — if the model gives wrong answers because it lacks domain facts (proprietary docs, recent events, product catalog), add retrieval instead of training. RAG is updateable, cheaper, and doesn't risk catastrophic forgetting.

3. **SFT with LoRA when there's a behavior gap** — if the model has the knowledge but can't reliably follow a specialized format, tone, safety policy, or instruction pattern, fine-tune with LoRA. Requires ~1K–10K labeled (prompt, completion) pairs. Use rank 8–64, α = 2×rank, target `q_proj`/`v_proj` layers, train in BF16 at LR 1e-4–2e-4.

4. **DPO when you have preference pairs** — if you have (prompt, chosen, rejected) triples from human or LLM-judge feedback, DPO directly optimizes behavior alignment without a separate reward model. More stable than RLHF, works with 10K–500K preference pairs.

5. **Full fine-tuning / continued pre-training** — only when you need to inject genuinely new vocabulary, a specialized subdomain (clinical notes, legal citations), and have millions of domain tokens. Requires H100-class GPU clusters and is almost never justified for a startup product.

**Key signals that fine-tuning is correct:**
- Prompt engineering produces inconsistent results despite many iterations
- Task requires a stable style/format that varies dangerously in-context
- Inference cost is prohibitive (baking behavior into weights reduces per-call token usage)
- Latency requires a smaller specialized model to outperform a larger prompted one

### Example / Tradeoff

**Real example — code review assistant:**
- Prompt-only baseline: GPT-4o with a 2K-token system prompt describing the review rubric → inconsistent rating calibration across reviewers, ~$0.04/review, but the style varied enough to lose user trust.
- SFT with LoRA on 5K human-reviewed diffs (Llama 3 8B, rank=32, α=64, 3 epochs on 4× A100 40GB): consistent rubric, $0.002/review, p95 latency < 800ms.
- Outcome: 95% cost reduction, ROUGE-L alignment with senior reviewer 0.71→0.84, catastrophic forgetting confirmed by MMLU drop of 0.3 pts (acceptable).

**The trap:** Jumping to fine-tuning when better few-shot examples or chain-of-thought would have achieved 90% of the benefit. The 2-week fine-tuning iteration cycle (data curation → training → eval → regression test) vs a 30-minute prompt iteration is a real organizational cost.

| Approach | Data needed | Compute | Updateable | Latency | Best for |
|----------|-------------|---------|-----------|---------|----------|
| Prompt engineering | 0–20 examples | None | Instant | Base model | Knowledge present, style guidance needed |
| RAG | No labeled data | Inference only | Yes (index update) | +50–200ms | Knowledge gap, fresh data |
| SFT + LoRA | 1K–100K (prompt, completion) | 4–8× A100 days | Redeploy required | Smaller model possible | Behavior gap, cost pressure |
| DPO | 10K–500K preference pairs | Moderate | Redeploy required | Same as SFT | Alignment, safety, preference shaping |
| Full fine-tune | 1M+ samples | GPU cluster | Redeploy required | Smallest for task | Domain vocab, pre-training knowledge |

---

## Verbal script

**Opening (30s):**
"I think of this as a cost-quality ladder — you start at the cheapest rung and only climb when the cheaper option demonstrably fails. So I'd never jump to fine-tuning without first exhausting prompt engineering. The core question is: what *type* of gap am I closing — knowledge, behavior, or efficiency?"

**Core explanation (2–3 min):**
"Step one is always prompt engineering: zero-shot, then few-shot, then chain-of-thought. This is free and instant. If the model already knows the domain and just needs guidance on format or reasoning style, this is often enough.

If the model gives wrong answers because it lacks the facts — proprietary documents, recent product data — then I'd add RAG rather than fine-tune. RAG is updateable and doesn't risk catastrophic forgetting.

Fine-tuning with LoRA becomes the right call when there's a *behavior* gap: the model has the knowledge but can't reliably produce a consistent style, safety-constrained format, or specialized instruction-following pattern, even with extensive prompting. I'd want at least 1K labeled examples, use rank 8–64 LoRA adapters targeting `q_proj` and `v_proj`, train in BF16, and evaluate against a golden dataset before and after — including a regression check on general benchmarks to catch forgetting.

DPO is the right next step if I have preference pairs — chosen vs rejected completions — because it directly optimizes for human preference without needing a separate reward model or PPO's instability.

Full fine-tuning or continued pre-training is almost never my first answer for a product; it's for domain-specific vocabulary injection at scale and requires GPU cluster access and millions of tokens."

**Tradeoff / production angle (1 min):**
"The real cost of fine-tuning that people underestimate isn't compute — it's the data curation and iteration cycle. A prompt change ships in minutes; a LoRA fine-tune requires curating data, running training (hours to days), running evals, potentially finding regression bugs, and redeploying. The break-even is when you've spent more engineering time fighting prompt inconsistency than a fine-tune iteration would take. Concretely, I'd give prompt engineering at least 2–3 serious iteration cycles before declaring it insufficient."

**Wrap-up (30s):**
"So the hierarchy is: prompt → RAG → SFT/LoRA → DPO → full fine-tune. Fine-tuning earns its place when there's a confirmed behavior gap, you have labeled data, and the business case justifies the iteration cost. Happy to go deeper on LoRA mechanics or the DPO vs RLHF tradeoff."

---

## Pitfalls

- **Mistake:** Jumping straight to "I'd fine-tune it" without working through the ladder — **Better:** State the full decision tree (prompt → RAG → LoRA/SFT → DPO) and name the concrete signal that each step is insufficient before moving to the next (e.g., "if few-shot produces inconsistent style after 3 iteration cycles, that's the trigger for SFT")
- **Mistake:** Saying fine-tuning "teaches the model new facts" — **Better:** Clarify that SFT primarily changes behavior and style; for new factual knowledge, RAG or continued pre-training is more reliable; SFT on Q&A pairs can memorize facts but is brittle and causes catastrophic forgetting on general capabilities
- **Mistake:** Not mentioning catastrophic forgetting — **Better:** Proactively note that LoRA mitigates forgetting by keeping base weights frozen, but you still run MMLU or a general benchmark regression check before deploying any fine-tuned model

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q2: What is PEFT/LoRA and when use it?](04-002-what-is-peftlora-and-when-use-it.md) | Follow-up: once you decide to fine-tune, how does LoRA actually work? |
| [Q5: Fine-tune or prompt-engineered RAG?](04-005-fine-tune-or-prompt-engineered-rag.md) | Same decision but framed as fine-tune vs RAG specifically |
| [Q3: What is the difference between prompt engineering, RAG, and fine-tuning?](../answers/01-040-what-is-the-difference-between-prompt-engineering-rag-and-fi.md) | Cross-category: LLM fundamentals framing of the same decision ladder |

---

## One-liner recall

> Fine-tune only after exhausting prompt engineering and RAG — use LoRA/SFT when there's a confirmed *behavior* gap and ≥1K labeled examples; use DPO for preference alignment; never use fine-tuning to inject new facts.
