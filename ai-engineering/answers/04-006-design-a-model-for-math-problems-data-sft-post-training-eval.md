# Design a model for math problems — data, SFT, post-training, eval

**Category:** 04-fine-tuning-training
**Question #:** 006
**Source section:** §4 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
Interviewers ask this to probe whether you understand the full model-development lifecycle for a specialized domain—not just "call GPT-4." Math is a canonical hard case because it requires exact symbolic reasoning, step-by-step correctness, and verifiable answers, which exposes gaps in data curation, training-objective design, and evaluation strategy that generic approaches can't paper over.

### Trigger phrases
- "How would you build a model to solve math word problems?"
- "Design the training pipeline for a math reasoning assistant."
- "Walk me through data, SFT, post-training, and eval for a domain-specific model."

### What it tests
End-to-end ML development judgment: data quality strategy, supervised fine-tuning mechanics (SFT), preference alignment (RLHF/DPO/process-reward models), and rigorous eval with verifiable correctness metrics.

---

## Answer

### Concept
Building a math-capable model requires four sequential phases: (1) curating high-quality chain-of-thought training data, (2) supervised fine-tuning (SFT) to establish the base reasoning format, (3) post-training alignment via process reward models (PRMs) or DPO to reinforce correct reasoning paths over incorrect ones, and (4) evaluation on held-out benchmarks with exact-match and step-level correctness metrics. The key insight is that math has *verifiable ground truth*, which unlocks outcome-based RL that language tasks cannot use.

### Mechanism

**Phase 1 — Data curation:**
- **Sources:** GSM8K (8.5K grade-school word problems), MATH (12.5K competition problems), NuminaMath, AoPS forum posts, synthetic data from a stronger teacher model (GPT-4o generating scratchpad solutions).
- **Format:** Every example is a `(problem, chain-of-thought scratchpad, final answer)` triple. The CoT must be step-by-step, not shortcut. Use `\boxed{}` delimiters so answer extraction is deterministic.
- **Quality gates:** Filter by: (a) answer verifiability (LaTeX `\boxed{}` parseable), (b) scratchpad plausibility (does the reasoning reach the stated answer?), (c) difficulty distribution (easy 40% / medium 40% / hard 20% to prevent mode collapse on easy problems).
- **Synthetic augmentation:** Rejection sampling — generate N solutions from a weaker model, keep only correct ones (verified by symbolic solver or strong oracle LLM); this is how DeepSeek-Math and Qwen-Math scale their datasets cheaply.

**Phase 2 — Supervised Fine-Tuning (SFT):**
- Start from a strong base: Llama 3 8B / Qwen2.5-Math-7B / Mistral 7B.
- Use LoRA (rank 32–64, α=64, target `q_proj`, `v_proj`, `gate_proj`) or full fine-tune if you have >4 A100s.
- Training objective: standard next-token cross-entropy over the *full* response (problem + scratchpad + answer) — not just the answer token. This teaches the scratchpad format.
- Hyperparameters: 2–3 epochs, LR 2e-5 (cosine decay), batch size 32–128, gradient checkpointing.
- Milestone: SFT alone on GSM8K should get you from ~55% (base) to ~75–80% pass@1.

**Phase 3 — Post-training (alignment):**
- **Option A — Outcome Reward Model (ORM) + RL:** Binary reward (correct final answer = +1, incorrect = 0). Use PPO or GRPO (Group Relative Policy Optimization, DeepSeek-R1 style) to optimize policy. Simple to implement; reward hacking risk if scratchpad is ignored.
- **Option B — Process Reward Model (PRM):** Train a step-level verifier (e.g., PRM800K dataset from OpenAI). Each reasoning step gets a score; RL optimizes *step quality*, not just final answer. More robust, harder to reward hack; used in o1/o3 and DeepSeek-R1.
- **Option C — DPO on preference pairs:** Generate K solutions per problem, label correct/incorrect, train DPO. Simpler than RL; no online rollout needed. Works well when correctness signal is clean.
- **In practice (2025–2026):** GRPO/STaR-style self-improvement (fine-tune on correct self-generated solutions iteratively) has shown strong results for models like DeepSeek-R1-Zero without labeled preference data.

**Phase 4 — Evaluation:**
- **Offline benchmarks:** GSM8K (grade school, easy bar), MATH Level 3–5 (competition math, hard), AIME 2024 (frontier bar, pass@1 and majority@32).
- **Metrics:** pass@1 (greedy), maj@k (majority vote over k samples), pass@k (any of k correct).
- **Step-level eval:** PRM-scored solution quality; useful even when final answer is wrong.
- **Held-out regression set:** Custom problem set drawn from your actual use case (tutoring platform, SAT prep, etc.) — never contaminate with training data.
- **Failure mode analysis:** Track category breakdowns — algebra vs geometry vs combinatorics vs number theory. Models often collapse on specific sub-domains.

### Example / Tradeoff

**Qwen2.5-Math-7B-Instruct (2024):** SFT on synthetic NuminaMath CoT → ORM-guided MCTS for solution selection → DPO on correct vs incorrect pairs → achieves 95.2% on GSM8K and 83.6% on MATH, rivaling GPT-4o on math despite being 7B parameters. Key: high-quality synthetic CoT data + step-level verification outweighs raw scale.

**Tradeoff table:**

| Phase | Cheap path | Better path | When to invest |
|-------|-----------|-------------|----------------|
| Data | GSM8K + MATH public data | Synthetic CoT via GPT-4o + rejection sampling | Domain-specific problems exist |
| SFT | LoRA on 1× A100 | Full fine-tune multi-GPU | If base model is weak at format |
| Post-training | DPO on correct/incorrect pairs | PRM + GRPO online RL | MATH Level 5 / competition bar |
| Eval | pass@1 on GSM8K | Held-out domain set + step-level PRM score | Production deployment |

**Cost example:** LoRA fine-tune Llama 3 8B on 50K examples ≈ 4 hours on 2× A100 80GB ≈ $80 on Lambda Cloud. PRM training adds another ~$200. Serving: vLLM with 4-bit GPTQ, 8K context, ~4ms/token on A10G.

---

## Verbal script

**Opening (30s):**
"I'd structure this as four phases: data curation, supervised fine-tuning, post-training alignment, and evaluation. The key insight for math specifically is that answers are verifiable — we know ground truth — so we can use stronger training signals than language tasks typically allow."

**Core explanation (2–3 min):**
"For data, I'd start with public datasets like GSM8K and the MATH benchmark, but the real leverage is synthetic CoT generation — use GPT-4o to produce step-by-step scratchpad solutions, then filter by correctness with a symbolic verifier or oracle LLM. Rejection sampling is how DeepSeek-Math and Qwen-Math scaled without massive human annotation. Every example needs a `(problem, scratchpad, \\boxed{answer})` triple — the scratchpad format teaches the model to reason, not just pattern-match.

"For SFT, I'd start from a strong base like Qwen2.5-Math-7B or Llama 3 8B and fine-tune with LoRA (rank 32–64) using cross-entropy over the full response — not just the answer token. This is important: you need the model to learn the scratchpad format, not shortcut to the answer. Two to three epochs, LR 2e-5, gets you from ~55% to ~75–80% on GSM8K.

"For post-training, the decision is between DPO and process reward models. DPO is simpler — generate K solutions, label correct vs incorrect, train on preference pairs. But for harder competition math, a step-level Process Reward Model like PRM800K plus GRPO-style RL is more robust because it can't reward-hack by producing wrong scratchpads with correct answers. DeepSeek-R1 used GRPO self-improvement with almost no labeled data.

"For eval, I'd run GSM8K for the easy bar, MATH Level 3–5 for the hard bar, and a custom held-out set from the actual domain — SAT math, tutoring curriculum, whatever the product targets. I'd report pass@1 and maj@8, and break down by sub-domain — models often have 90%+ on algebra but collapse on combinatorics."

**Tradeoff / production angle (1 min):**
"The main production tension is between online RL (which requires rollout infrastructure) and offline DPO (simpler but stale). For most teams, I'd start with DPO — generate correct/incorrect pairs offline, ship fast, instrument real usage, then invest in a PRM if you have a high-quality step-level dataset. Also: don't use GSM8K as your only eval signal — it saturates quickly, and a model at 95% on GSM8K can still fail on real student problems with unusual phrasing."

**Wrap-up (30s):**
"So: curate verifiable CoT data, SFT with full-response loss, post-train with DPO or PRM+RL depending on your bar, and evaluate on a held-out domain set beyond GSM8K. Happy to go deeper on any phase — PRM architecture, GRPO mechanics, or the synthetic data pipeline."

---

## Pitfalls

- **Mistake:** Saying "I'd fine-tune on GSM8K" without mentioning scratchpad/CoT format — **Better:** Explain that the training data must include step-by-step reasoning traces, not just (problem, answer) pairs; next-token loss on the scratchpad teaches the reasoning format, not just final answer memorization.
- **Mistake:** Treating math eval as just GSM8K pass@1 and calling it done — **Better:** GSM8K saturates quickly (95%+ for modern models); serious eval uses MATH Level 3–5, domain-specific held-out sets, and step-level PRM scoring; report maj@8 not just greedy pass@1 for a realistic estimate.
- **Mistake:** Jumping straight to RLHF/PPO without explaining why math enables verifiable reward signals — **Better:** Highlight that math's ground-truth verifiability is the key advantage; outcome-based RL (correct/incorrect) or PRM-based RL is only possible because we can check answers symbolically; this is fundamentally different from preference-based alignment for subjective tasks.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q4: What is RLHF and why important?](04-004-what-is-rlhf-and-why-important.md) | RLHF/PPO and DPO are the post-training alignment methods referenced here |
| [Q2: What is PEFT/LoRA and when use it?](04-002-what-is-peftlora-and-when-use-it.md) | LoRA mechanics used in the SFT phase |
| [Q8: RLHF pipeline: SFT, reward model, PPO. How does DPO simplify?](04-008-rlhf-pipeline-sft-reward-model-ppo-how-does-dpo-simplify.md) | Deep dive on the post-training pipeline choices |

---

## One-liner recall

> Design a math model via four phases: curate verifiable CoT data (GSM8K + synthetic rejection-sampling), SFT with full-response cross-entropy loss to teach the scratchpad format, post-train with DPO (simple) or PRM+GRPO (competition bar), and evaluate on held-out domain sets with pass@1 + maj@8 broken down by sub-domain.
