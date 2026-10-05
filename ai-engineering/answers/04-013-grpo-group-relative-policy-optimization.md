# What is GRPO (Group Relative Policy Optimization) and when use it over PPO/DPO?

**Category:** 04-fine-tuning-training
**Question #:** 013
**Source section:** §4 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
GRPO is the post-training algorithm behind DeepSeek-R1-style reasoning models, and interviewers use it to separate candidates who memorized "PPO then DPO" from candidates who follow where the field actually went for verifiable reasoning tasks. The question probes whether you understand the group-baseline advantage math, why the critic can be dropped, and — critically — the half-truth in "GRPO needs no reward model." Senior candidates articulate when verifiable rewards beat learned preference rewards and when they do not.

### Trigger phrases
- "How would you post-train a model for math or code reasoning?"
- "What is GRPO and how does it differ from PPO?"
- "Do you still need a reward model with GRPO?"
- "How did DeepSeek-R1 train reasoning without human preferences?"

### What it tests
Understanding of group-relative advantage estimation — mean/std normalization over sampled response groups as a critic replacement — and judgment about verifiable vs learned reward signals.

---

## Answer

### Concept
**GRPO (Group Relative Policy Optimization)** replaces PPO's learned value network (critic) with a group baseline: for each prompt, sample a group of G responses from the current policy, score each with a reward function, and compute advantages by normalizing within the group — `A_i = (r_i − mean(r_1..G)) / std(r_1..G)`. Responses better than their own group average get reinforced; worse ones get suppressed. No critic, no value-loss, no GAE hyperparameters — the baseline comes from the group's own statistics. It pairs naturally with **RLVR (RL with Verifiable Rewards)**: rule-based checkers (math answer match, unit-test pass rate) as the reward signal instead of a learned reward model trained on human preferences.

### Mechanism

**Group sampling + normalized advantage (the core loop):**
1. For prompt `x`, sample G completions `{y_1, …, y_G}` from the current policy `π_θ` (typical G = 8–64; DeepSeek-R1 used large groups for hard reasoning prompts).
2. Score each with the reward function `r(x, y_i)` — verifiable checker, learned RM, or a combination.
3. Compute the group-normalized advantage: `A_i = (r_i − μ) / σ`, where `μ` and `σ` are the mean and standard deviation of the group's rewards. This is the shared canonical form — see also the [43-grpo-rlvr concept page](../concepts/43-grpo-rlvr.html) for the interactive walkthrough.
4. Update the policy with a clipped objective analogous to PPO's, but with `A_i` in place of the GAE advantage, plus a KL penalty against the reference policy to prevent collapse:
```
L_GRPO = E[ min( ρ_i · A_i, clip(ρ_i, 1−ε, 1+ε) · A_i ) ] − β · KL(π_θ ‖ π_ref)
```
where `ρ_i = π_θ(y_i|x) / π_old(y_i|x)`.

**Why the critic can go (and what that buys):**
PPO needs four live models — actor, critic, reward model, reference policy — because its advantage estimate (`r + γV(s') − V(s)`) requires a learned value function. GRPO's advantage comes from intra-group comparison, so the critic disappears: three models at most (policy, reference, and optionally a learned RM), frequently two when rewards are verifiable. That removes the value-loss term, the GAE `λ`/`γ` tuning surface, and the critic's memory footprint — roughly a quarter of PPO's rollout-time memory. The price: advantage quality now depends on group diversity. If all G samples are near-identical (mode-collapsed policy or G too small), `σ → 0` and the signal degenerates — the standard fix is keeping sampling temperature up during rollouts and filtering zero-variance groups from the batch.

**Precision on the half-truth — critic elimination ≠ reward elimination:**
"GRPO needs no reward model" is wrong as stated. GRPO eliminates the *critic* (value network), not the *reward signal*. Something must still produce `r_i`. Two regimes:
- **Verifiable rewards (RLVR):** deterministic checkers — exact-match on boxed math answers, pass@k on hidden unit tests, format validators. Zero learned parameters, zero reward hacking surface beyond what the checker itself permits. This is the DeepSeek-R1 recipe.
- **Learned rewards:** a standard RM trained on preference pairs, exactly as in RLHF. GRPO works fine here too — it just replaces the PPO update, not the RM.
The correct statement: GRPO drops the critic; whether you also drop the learned reward model depends on whether your task admits a trustworthy verifier.

### Example / Tradeoff

**DeepSeek-R1 (2025) — the canonical GRPO+RLVR deployment:**
- Base: DeepSeek-V3-Base → cold-start SFT on ~1K long-CoT exemplars → GRPO with rule-based accuracy + format rewards on math/code reasoning prompts → second SFT (rejection-sampled) → final GRPO over all scenarios.
- Rewards were verifiable: math answers checked by exact match, code by execution against hidden tests, plus a format reward enforcing `<think>`/`<answer>` structure. No human preference pairs anywhere in the reasoning loop.
- Result: R1-Zero (pure RL, no cold start) already matched OpenAI-o1 on AIME/math benchmarks — evidence that group-relative RL on verifiable signal alone can elicit long chain-of-thought reasoning.

**GRPO vs PPO vs DPO tradeoff:**

| Dimension | PPO (RLHF) | GRPO | DPO |
|-----------|-----------|------|-----|
| Advantage source | Learned critic + GAE | Group mean/std normalization | None (supervised loss on pairs) |
| Models live | 4 (actor, critic, RM, ref) | 2–3 (policy, ref, optional RM) | 2 (policy + ref) |
| Reward type | Learned RM (preference) | Verifiable checker or learned RM | Implicit in preference pairs |
| Exploration | Online rollouts, critic-guided | Online rollouts, group-relative | None — offline dataset only |
| Failure mode | Critic misfit, PPO instability | Zero-variance groups, verifier gaming | Distribution shift, ceiling on reasoning |
| When to use | Frontier alignment with human feedback in loop | Reasoning tasks with checkable answers (math, code, tool-use) | Instruction-following on fixed preference data |

**Verifier gaming caveat:** verifiable ≠ ungameable. A format checker rewards the tags, not the thinking; a unit-test suite rewards passing *those* tests. DeepSeek's answer was multi-reward composition (accuracy + format) plus held-out test splits for the final gate — the same defense-in-depth you would apply to any reward function.

---

## Verbal script

**Opening (30s):**
"I'd start by placing GRPO in the post-training ladder: DPO when you have fixed preference pairs, PPO-based RLHF when you have humans in the loop, and GRPO when your task has checkable answers and you want online RL without paying for a critic. The key insight is that the baseline for the advantage estimate comes from the response group itself — mean and standard deviation over G samples — so the value network disappears."

**Core explanation (2–3 min):**
"Concretely: for each prompt you sample G completions, score each one, and the advantage for response i is its reward minus the group mean, divided by the group standard deviation. Better-than-group-average gets reinforced. The update is PPO-style clipping on the probability ratio times that advantage, plus a KL leash to the reference model. Three consequences. First, you drop the critic — no value loss, no GAE lambdas, roughly a quarter less rollout memory. Second, the failure mode moves: if the group has zero variance the signal degenerates, so you keep rollout temperature up and drop degenerate groups. Third — and this is the point most people get wrong — dropping the critic is not dropping the reward. Something still scores each response. In the DeepSeek-R1 recipe that's a verifier: exact-match math, hidden unit tests for code. That's the RLVR pairing, and it's why GRPO shines on reasoning: checkers don't suffer preference-model reward hacking."

**Tradeoff / production angle (1 min):**
"In production I'd reach for GRPO over PPO whenever the reward is verifiable — math, code, structured tool-use — because you delete the critic-tuning surface and the learned-RM brittleness at once. I'd keep PPO or DPO for open-ended alignment where no checker exists: helpfulness, tone, safety. And I'd always hold out verifier splits, because models game checkers exactly the way they game reward models — format rewards get you well-formed nonsense if accuracy isn't weighted above them."

**Wrap-up (30s):**
"So: GRPO is PPO minus the critic, with the group statistics as baseline, and its natural partner is verifiable reward. Happy to go deeper on the advantage math or the R1 training recipe."

---

## Pitfalls

- **Mistake:** Saying "GRPO needs no reward model" — **Better:** Say it eliminates the *critic* (value network), not the reward signal; something must still score each response — a verifiable checker in RLVR mode or a learned RM otherwise. Conflating the two suggests you have not traced where `r_i` comes from.
- **Mistake:** Describing GRPO as "just PPO with bigger batches" — **Better:** Explain the advantage is group-normalized (`(r_i − μ)/σ` over G samples from the same prompt), which removes the value loss and GAE hyperparameters entirely but introduces the zero-variance-group failure mode.
- **Mistake:** Claiming verifiable rewards end reward hacking — **Better:** Note verifiers get gamed too (format tags without reasoning, overfitting to visible tests); mitigation is multi-reward composition plus held-out verifier splits for the final gate.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q8: RLHF pipeline: SFT, reward model, PPO. How does DPO simplify?](04-008-rlhf-pipeline-sft-reward-model-ppo-how-does-dpo-simplify.md) | Prerequisite — PPO/critic machinery GRPO replaces |
| [Q4: What is RLHF and why important?](04-004-what-is-rlhf-and-why-important.md) | Prerequisite — reward-hacking and KL-leash foundations |
| [Q6: Design a model for math problems — data, SFT, post-training, eval](04-006-design-a-model-for-math-problems-data-sft-post-training-eval.md) | Follow-up — math-reasoning pipeline where GRPO is the post-training step |
| [Q29: RLHF vs DPO — when prefer one over the other?](../answers/01-029-rlhf-vs-dpo-when-prefer-one-over-the-other.md) | Cross-category — the PPO/DPO decision ladder GRPO extends |

---

## One-liner recall

> GRPO drops PPO's critic by computing advantages as group-normalized scores `(r_i − μ)/σ` over G sampled responses — critic elimination, not reward elimination — and pairs naturally with verifiable checkers (RLVR), making it the default post-training choice for checkable reasoning tasks like math and code.
