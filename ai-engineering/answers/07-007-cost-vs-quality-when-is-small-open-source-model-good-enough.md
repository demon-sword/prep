# Cost vs quality: when is small open-source model "good enough"?

**Category:** 07-cost-latency
**Question #:** 007
**Source section:** §9 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
The interviewer is testing whether you understand that model selection is an engineering tradeoff, not a default to "the best model." Strong candidates can articulate a structured decision process — task complexity, quality SLOs, latency budget, cost at scale, and data-privacy requirements — rather than defaulting to GPT-4 or assuming bigger is always better.

### Trigger phrases
- "When would you use a smaller open-source model instead of GPT-4?"
- "How do you decide which model tier to use?"
- "We're spending $X/day on model calls — where would you start cutting?"

### What it tests
The ability to evaluate model selection as a cost-quality-latency tradeoff using task profiling, benchmarking, and production SLOs — not intuition or brand preference.

---

## Answer

### Concept
A small open-source model (Llama 3 8B, Mistral 7B, Phi-3 Mini) is "good enough" when its task-specific accuracy meets your production quality SLO at a cost and latency that a frontier model cannot justify. The key insight is that most production tasks are simpler than the general benchmark suggests: classification, extraction, summarization with grounding, and intent routing rarely need 70B+ parameters.

### Mechanism
Use a four-step evaluation framework:

**1. Task profiling — classify the task by complexity:**
| Task type | Complexity | Likely tier |
|-----------|-----------|-------------|
| Intent classification, slot filling | Low | 7–8B fine-tuned |
| Grounded RAG summarization (closed-world) | Medium | 7–13B or GPT-4o-mini |
| Multi-step reasoning, open-domain QA | High | 70B or frontier API |
| Code generation, complex math | High | Frontier + verification |

**2. Benchmark on your own data (not academic leaderboards):**
- Build a 100–200 sample golden dataset from production queries
- Run the candidate small model and GPT-4o (or the frontier baseline) on identical prompts
- Measure task-specific accuracy: F1 for extraction, RAGAS Faithfulness for RAG, pass@1 for code
- Accept the smaller model if Δaccuracy < threshold (typically 2–5% depending on stakes)

**3. Cost-quality breakeven math:**
At 1M queries/day:
| Model | Input cost | Output cost | Total/day |
|-------|-----------|------------|-----------|
| GPT-4o (1K in / 200 out tokens avg) | $2.50/1M | $10/1M | ~$12,500 |
| GPT-4o-mini | $0.15/1M | $0.60/1M | ~$750 |
| Llama 3 8B self-hosted (4× A100 @ $2/hr each) | ~$192 server | fixed | ~$200 |
| Mistral 7B (Together AI / Fireworks) | ~$0.10–0.20/1M tokens | | ~$120–240 |

If the smaller model achieves acceptable quality, the savings are 10–60×. Fine-tuning a 7B model on domain data with QLoRA typically costs $20–100 one-time and often matches a frontier model's task accuracy.

**4. Data-privacy / latency secondary filters:**
- PII / regulated data → self-hosted open-source (no data egress)
- p95 latency SLO < 1s → smaller model or semantic caching wins
- Multi-turn complex reasoning → frontier model or 70B

### Example / Tradeoff
**Customer support intent router:** Replace GPT-4o with a fine-tuned Llama 3 8B (QLoRA, 5K labeled examples). Benchmark result: 96.4% F1 vs GPT-4o's 97.1% — Δ0.7%, well within SLO. Cost drops from ~$8K/day to ~$250/day (32× reduction). Latency drops from ~1.8s p95 to ~0.4s because the model runs on-prem with vLLM.

**Where small models fail:** Open-domain factual QA, complex multi-hop reasoning, and creative writing — tasks that genuinely require the breadth of frontier pretraining. Forcing Mistral 7B on legal contract analysis without fine-tuning can drop accuracy 15–20 points.

---

## Verbal script

**Opening (30s):**
"The way I approach this is: every model selection decision is a cost-quality tradeoff, not a default to the largest available model. I have a four-step framework — task profiling, golden-dataset benchmarking, cost-breakeven math, and secondary filters like privacy and latency — that tells me when a smaller open-source model is 'good enough.'"

**Core explanation (2–3 min):**
"First, I profile the task. Most production tasks fall into three complexity buckets: low — things like intent classification, slot filling, and structured extraction; medium — grounded RAG summarization where the context is provided; and high — open-domain reasoning, complex math, code generation. Small models (7–13B) handle low and often medium tasks well. High-complexity tasks usually need 70B+ or frontier APIs.

Second, I benchmark on my own data, not academic leaderboards. I'll pull 100–200 representative production queries, label ground truth, and run both the candidate small model and the frontier baseline. The key metric is task-specific — RAGAS Faithfulness for RAG, F1 for extraction, pass@1 for code. If the accuracy gap is under two to five percent, I accept the smaller model.

Third, I do the cost math. At 1M queries per day, GPT-4o might cost $12,000/day at typical token lengths. GPT-4o-mini drops that to around $750. A self-hosted Llama 3 8B on four A100s runs about $200/day fixed, or I can use Fireworks or Together AI for around $120–240 variable. Fine-tuning the 7B model on domain data with QLoRA costs $20–100 one-time and often closes the remaining accuracy gap.

A concrete example: I replaced GPT-4o as an intent router for a customer support system with a QLoRA fine-tuned Llama 3 8B. The benchmark showed 96.4% vs 97.1% F1 — a 0.7-point delta that was within our SLO. Cost went from $8K/day to $250/day, and p95 latency dropped from 1.8s to 0.4s because the model ran on-prem with vLLM."

**Tradeoff / production angle (1 min):**
"The failure mode is over-indexing on benchmarks. A 7B model that scores 88% on MMLU is not interchangeable with GPT-4o on MMLU-level tasks in your domain. Academic benchmarks are saturated and contaminated. The only reliable signal is a task-specific golden dataset built from your actual production queries. Also, small models degrade faster on complex multi-step reasoning — if the task requires synthesizing across six documents or doing multi-hop inference, the accuracy delta grows quickly and you're better off with a larger model."

**Wrap-up (30s):**
"The bottom line: for low-to-medium complexity tasks with a stable domain, a fine-tuned small open-source model is almost always good enough and 10–60× cheaper. The decision gate is always a task-specific benchmark on production data, not a gut feeling about model size."

---

## Pitfalls

- **Mistake:** Defaulting to GPT-4o for everything "to be safe" without benchmarking — **Better:** Build a 100-sample golden dataset and measure the actual accuracy delta; quantify the cost difference and present it as a justified engineering decision.
- **Mistake:** Citing academic benchmark scores (MMLU, HumanEval) as evidence a small model "is good enough" — **Better:** Acknowledge that leaderboard scores don't reflect task-specific production accuracy; run your own evaluation on representative domain queries and report task-specific metrics.
- **Mistake:** Ignoring fine-tuning as a gap-closer — **Better:** Explain that QLoRA fine-tuning on 1K–10K domain examples typically costs $20–100 and often brings a 7B model to within 1–2% of frontier accuracy on narrow tasks, which completely changes the cost-quality calculus.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q1: Your app gets 1M queries/day — how optimize cost?](07-001-your-app-gets-1m-queriesday-how-optimize-cost.md) | model tiering is one of the primary levers in the cost-optimization hierarchy |
| [Q10: Model tiering — small distilled vs large LLM](07-010-model-tiering-small-distilled-vs-large-llm.md) | deeper dive into the tiering architecture and routing logic |
| [Q6: Quantization and model distillation for inference](07-006-quantization-and-model-distillation-for-inference.md) | techniques for making open-source models even cheaper/faster to serve |

---

## One-liner recall

> Profile the task complexity, benchmark on a 100–200 sample golden dataset (not leaderboards), do cost-breakeven math, and accept the smaller model when Δaccuracy is within SLO — fine-tuning with QLoRA for $20–100 typically closes the remaining gap.
