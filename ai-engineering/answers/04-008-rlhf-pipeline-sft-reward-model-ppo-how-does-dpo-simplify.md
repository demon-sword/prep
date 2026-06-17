# RLHF pipeline: SFT, reward model, PPO. How does DPO simplify?

**Category:** 04-fine-tuning-training
**Question #:** 008
**Source section:** §4 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
This is the deep-dive follow-up to "what is RLHF?" — interviewers expect you to walk the full three-stage pipeline with concrete details: loss functions, the KL leash formula, PPO clipping, reward hacking, and then explain *why* DPO was a significant simplification. It probes whether you actually understand the math and failure modes vs. having pattern-matched on the acronym. Senior candidates should be able to compare RLHF vs. DPO across dimensions and state which to use when.

### Trigger phrases
- "Walk me through the RLHF pipeline end-to-end."
- "What is the reward model's role in RLHF? How is it trained?"
- "How does DPO differ from RLHF? What problem does it solve?"
- "Explain PPO in the context of LLM alignment."
- "Why did people move from PPO to DPO for fine-tuning?"

### What it tests
Deep understanding of the three-stage RLHF pipeline (SFT → RM → PPO+KL), its failure modes (reward hacking, training instability, annotation cost), and how DPO's closed-form reparameterization eliminates the reward model and PPO entirely.

---

## Answer

### Concept
RLHF is a three-stage alignment pipeline: (1) **Supervised Fine-Tuning (SFT)** teaches the model the correct response distribution; (2) a **Reward Model (RM)** is trained on pairwise human preferences to score any response; (3) **PPO with a KL penalty** optimizes the policy to maximize RM-predicted rewards while staying close to the SFT baseline. DPO (Direct Preference Optimization, Rafailov et al. 2023) bypasses stages 2 and 3 by showing that the optimal RLHF policy can be expressed as a **closed-form function of the log-probability ratio** between the policy and the SFT reference — turning alignment into a single binary cross-entropy loss on preference pairs.

### Mechanism

#### Stage 1 — Supervised Fine-Tuning (SFT)

Fine-tune the base pre-trained model on high-quality (prompt, ideal-completion) pairs:

```
L_SFT = -E[log π_θ(y | x)]   # standard cross-entropy on labeled completions
```

The SFT model serves two roles: it is the starting point for RL fine-tuning (Stage 3) and the **frozen reference model** used to compute the KL penalty. InstructGPT used ~13K prompt-completion pairs curated by contractors.

#### Stage 2 — Reward Model (RM) Training

For each prompt `x`, collect `k` completions from the SFT model and have humans rank them: `y_w > y_l` (winner preferred over loser). Train a separate model (SFT backbone + scalar regression head) with a pairwise ranking loss:

```
L_RM = -E[log σ(r_φ(x, y_w) − r_φ(x, y_l))]
```

where `r_φ(x, y)` is the scalar reward. This is a Bradley-Terry preference model. The RM learns to assign higher scores to human-preferred completions. Key implementation details:
- RM is initialized from the SFT model (same architecture) with the final unembedding layer replaced by a linear scalar head.
- InstructGPT trained a 6B RM on ~33K comparison pairs (4–9 pairs per prompt).
- RM generalizes poorly out-of-distribution — this is the root cause of reward hacking.

#### Stage 3 — PPO + KL Leash

Use the frozen RM as the environment reward signal and optimize the SFT policy using Proximal Policy Optimization:

```
objective(x, y) = r_φ(x, y)  −  β · KL[π_θ(y|x) || π_SFT(y|x)]
```

- **KL penalty:** β (typically 0.01–0.1) penalizes the policy for diverging from the SFT reference. Too small → reward hacking (policy exploits RM gaps with verbose/sycophantic outputs). Too large → policy stays near SFT and alignment gain is minimal.
- **PPO clipping:** updates are clipped to prevent large destabilizing steps (`clip(ratio, 1−ε, 1+ε)`, ε≈0.2). Each PPO step samples a batch of prompts, generates completions with the live policy, scores with the RM, and updates with clipped gradients.
- **Value model (critic):** PPO requires a separate value network (estimating baseline advantage) — adding yet another model to maintain.

**Production failure modes:**
| Failure | Symptom | Mitigation |
|---------|---------|------------|
| Reward hacking | Long, verbose, sycophantic completions score high on RM but fail human review | KL leash tighter; iterative RM retraining on RL samples |
| Training instability | Loss spikes, policy collapse | Careful β tuning, low learning rate, gradient clipping |
| RM out-of-distribution | Policy generates completions the RM has never seen | Diverse SFT data; rule-based guardrails alongside RM |
| Annotation cost | High-quality pairwise comparisons: ~$30–100/prompt | Synthetic pairs from stronger judge (GPT-4o) for cheap preference data |

#### DPO Simplification

Rafailov et al. (2023) showed that the optimal policy under the RLHF KL-constrained objective has a **closed-form solution**:

```
π*(y|x) = π_SFT(y|x) · exp(r*(x,y)/β) / Z(x)
```

Rearranging, the reward can be expressed as:

```
r*(x, y) = β · log[π*(y|x) / π_SFT(y|x)] + β · log Z(x)
```

Substituting into the Bradley-Terry pairwise preference model and cancelling the partition function `Z(x)` (which is the same for both `y_w` and `y_l` for the same prompt), you get the **DPO loss** — a single binary cross-entropy on preference pairs, no reward model required:

```
L_DPO = -E[log σ(β · log(π_θ(y_w|x)/π_ref(y_w|x)) − β · log(π_θ(y_l|x)/π_ref(y_l|x)))]
```

What this does intuitively: increase the log-prob of the winning completion `y_w` **relative to the reference** while decreasing the log-prob of the losing completion `y_l` relative to the reference.

### Example / Tradeoff

**InstructGPT (OpenAI, 2022)** — canonical RLHF:
- SFT: GPT-3 175B on 13K curated pairs
- RM: 6B GPT-3 on 33K pairwise comparisons
- PPO: 20 PPO steps/prompt, β=0.02
- Result: 1.3B InstructGPT preferred over 175B GPT-3 (85% human win rate) — alignment > raw scale

**Llama 2 / Mistral Instruct / Zephyr (2023–2024)** — DPO mainstream adoption:
- Zephyr-7B (HuggingFace 2023): SFT on UltraChat + DPO on UltraFeedback synthetic preference pairs generated by GPT-4 — competitive with GPT-3.5 on MT-Bench at 7B scale
- No reward model, no PPO, no value network — training fits on 4 A100s

**RLHF vs DPO comparison:**

| Dimension | RLHF (PPO) | DPO |
|-----------|------------|-----|
| Pipeline stages | 3 (SFT + RM + PPO) | 2 (SFT + DPO) |
| Extra models needed | RM + value network | None |
| Training stability | Low (PPO finicky) | High (cross-entropy) |
| Reward hacking risk | Higher (RM can be fooled) | Lower (no RM to hack) |
| Iterative improvement | Yes — retrain RM on RL samples | Harder without online rollouts |
| Compute cost | 3–5× more GPU hours | ~Same as SFT |
| Quality ceiling | Higher for frontier models | Sufficient for most production use cases |
| When to use | Frontier model alignment, iterative RM possible | Most production fine-tuning, smaller teams |

**RLHF variants beyond DPO:** IPO (identity preference optimization, avoids overfit on margins), KTO (non-paired feedback — binary good/bad labels), SimPO (no reference model, margin-based), GRPO (used in DeepSeek-R1 for math reasoning with process reward models).

---

## Verbal script

**Opening (30s):**
"I'd frame this as two questions: the full RLHF pipeline with its details and failure modes, then why DPO was such an important simplification. Let me walk the three stages of RLHF first, then explain what DPO does mathematically and when I'd use each."

**Core explanation (2–3 min):**
"Stage one is supervised fine-tuning — you take the base pre-trained model and fine-tune it on high-quality (prompt, completion) pairs curated by humans. This is standard cross-entropy, and it gives you a well-behaved reference model. InstructGPT used about 13,000 such pairs.

Stage two is training a reward model. You sample multiple completions for the same prompt from the SFT model, have humans rank them — chosen over rejected — and train a separate model with a pairwise ranking loss: negative log sigmoid of the reward difference between the winner and loser. The RM learns to predict human preference with a scalar score. The practical detail here is that the RM is usually the same SFT architecture with the final layer swapped for a scalar head.

Stage three is PPO fine-tuning. You use the RM as the environment — it scores the policy's completions — and optimize with Proximal Policy Optimization. The critical addition is a KL divergence penalty: β times the KL between the current policy and the frozen SFT reference. This is what prevents reward hacking — without the KL leash, the policy quickly learns to produce very long, verbose, or sycophantic responses that score high on the RM but that humans don't actually prefer. β is typically 0.01 to 0.1; tuning it is one of the hardest parts of the pipeline.

Now for DPO. The key insight — Rafailov et al. 2023 — is that the optimal policy under the KL-constrained RLHF objective has a closed-form expression: the policy is the reference model reweighted by exp(reward/β), normalized by the partition function. If you substitute that into the Bradley-Terry pairwise preference model — the same one the RM uses — the partition function cancels out, and you're left with a binary cross-entropy loss on preference pairs that involves only log-probability ratios between the current policy and the reference. No reward model needed, no PPO, no value network. You just train on preference pairs with a standard optimizer. That's why Llama 2, Mistral Instruct, and most smaller-team fine-tuning projects now use DPO."

**Tradeoff / production angle (1 min):**
"The main tradeoffs: RLHF with PPO has a higher quality ceiling because you can iteratively retrain the RM on samples the policy actually generates — this is how frontier models push alignment quality further. DPO is a static offline method; it can't easily do that online loop. On the other hand, DPO is dramatically simpler — no extra models, no PPO instability — and for most practical alignment tasks it's sufficient. For a small team fine-tuning a 7–70B model for a product, I'd start with DPO, using synthetic preference pairs from GPT-4o as cheap labeled data. I'd only consider full RLHF if we were training a frontier model and had the infrastructure to iterate the RM."

**Wrap-up (30s):**
"So the key points: RLHF is SFT → RM (pairwise ranking loss) → PPO+KL penalty. The KL leash is what prevents reward hacking. DPO simplifies by deriving the optimal RLHF policy in closed form — turning it into a single cross-entropy loss without a reward model. For production fine-tuning today, DPO is the default; PPO is for frontier-scale alignment. Happy to go into DPO loss math, reward hacking mitigations, or variants like KTO and SimPO."

---

## Pitfalls

- **Mistake:** Saying "PPO updates the model to get high rewards" without mentioning the KL penalty — **Better:** Always include the KL leash formula `objective = E[reward] − β·KL(π_RL || π_SFT)` and explain that without it the policy will reward-hack by finding adversarial completions that fool the RM (verbosity, sycophancy), which is a documented failure mode in InstructGPT ablations
- **Mistake:** Describing DPO as "just a simpler training loop" without explaining the mathematical derivation — **Better:** State that DPO derives from the fact that the optimal KL-constrained policy has a closed-form expression; substituting it into the RM's pairwise loss cancels the partition function, yielding a log-probability-ratio cross-entropy on (y_w, y_l) pairs — this shows you understand *why* DPO works, not just that it does
- **Mistake:** Saying DPO is strictly better than RLHF — **Better:** Acknowledge that DPO is an offline method; frontier models (GPT-4, Claude) still use RLHF variants because iterative online RM retraining on policy-generated samples captures distribution shift that DPO misses; DPO is best for smaller-scale production alignment where simplicity and stability outweigh the quality ceiling

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q4: What is RLHF and why important?](04-004-what-is-rlhf-and-why-important.md) | Prerequisite: high-level RLHF overview before this deeper dive |
| [Q1: When fine-tune vs prompt engineering?](04-001-when-fine-tune-vs-prompt-engineering.md) | RLHF/DPO sits at the top of the fine-tuning decision ladder |
| [Q29: RLHF vs DPO — when prefer one over the other?](01-029-rlhf-vs-dpo-when-prefer-one-over-the-other.md) | Cross-category: LLM fundamentals treatment of RLHF vs DPO tradeoffs |

---

## One-liner recall

> RLHF aligns LLMs via SFT → RM trained on pairwise human preferences → PPO with KL penalty (β·KL prevents reward hacking); DPO eliminates the RM and PPO by showing the optimal RLHF policy has a closed-form log-probability-ratio expression, reducing alignment to a single cross-entropy loss on preference pairs.
