# RLHF vs DPO — when prefer one over the other?

**Category:** 01-llm-fundamentals
**Question #:** 029
**Source section:** §1 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
The interviewer is probing whether you understand the full alignment pipeline beyond "we RLHF'd the model." Both RLHF and DPO are production techniques for making models follow instructions safely, but they have very different complexity, stability, and infrastructure requirements. Senior candidates are expected to know which to reach for and why, and to articulate the tradeoffs concretely.

### Trigger phrases
- "How do you align a model to human preferences?"
- "What's the difference between RLHF and DPO?"
- "When would you prefer DPO over PPO-based RLHF?"
- "Walk me through your fine-tuning pipeline."

### What it tests
Understanding of post-training alignment methods — when RL-based approaches are worth the complexity versus when the simpler DPO closed-form objective is sufficient.

---

## Answer

### Concept
**RLHF (Reinforcement Learning from Human Feedback)** aligns a language model by training a separate reward model on human preference pairs, then using PPO (proximal policy optimization) to update the LLM to maximize that reward while staying close to the original model via a KL-divergence penalty. **DPO (Direct Preference Optimization)** skips the reward model entirely, reparameterizing the RLHF objective as a closed-form loss directly over preference pairs (chosen vs rejected responses), making the alignment step as simple as supervised fine-tuning.

### Mechanism

**RLHF pipeline (3 stages):**
1. **Supervised Fine-Tuning (SFT):** Fine-tune the base model on high-quality demonstration data (instruction → ideal response). This is the starting policy `π_SFT`.
2. **Reward Model (RM):** Train a separate model (same architecture, regression head) on human-labeled preference pairs `(prompt, chosen, rejected)` to predict a scalar reward. Loss: `−log σ(r_θ(chosen) − r_θ(rejected))`.
3. **PPO RL loop:** Use PPO to update the policy `π_θ` to maximize `E[r_θ(response)] − β · KL(π_θ ‖ π_SFT)`. The KL term (controlled by `β`) prevents reward hacking — the model drifting into high-reward gibberish. This requires generating rollouts online, scoring them, computing advantages, and updating with clipped gradients. Four models may be live simultaneously: actor, critic, reward model, reference policy.

**DPO (1-stage after SFT):**
DPO shows that the optimal RLHF policy can be expressed in closed form: `π*(y|x) ∝ π_SFT(y|x) · exp(r*(y,x)/β)`. This lets you rearrange the preference objective to train directly on `(prompt, chosen, rejected)` triplets without ever materializing a reward model:

```
L_DPO = −E[ log σ( β · log(π_θ(chosen)/π_ref(chosen)) − β · log(π_θ(rejected)/π_ref(rejected)) ) ]
```

You still need a frozen reference model `π_ref` (the SFT checkpoint) to compute log-prob ratios, but there's no RL loop, no reward model, no online sampling.

### Example / Tradeoff

| Dimension | RLHF (PPO) | DPO |
|-----------|-----------|-----|
| Pipeline complexity | High — RM training + PPO loop, 4 models live | Low — supervised loss, 2 models (policy + ref) |
| Infrastructure | Requires online rollout generation; needs 4× GPU memory headroom | Standard SFT setup; no rollouts |
| Stability | PPO is notoriously finicky (reward hacking, KL collapse) | Stable, reproducible like any SFT run |
| Data | Can incorporate online human feedback or AI feedback in the loop | Offline preference dataset required upfront |
| Performance ceiling | Higher — RL can explore beyond the dataset; used by GPT-4, Claude 2 | Slightly lower ceiling on complex tasks, but closes the gap on instruction following |
| When to use | When you can generate rollouts, have human annotators in loop, or need frontier performance | When you have a fixed preference dataset, limited infra, or need fast iteration |

**Real examples:** Meta's Llama 3 used a combination of SFT + RLHF for chat alignment. Mistral-7B-Instruct-v0.2 was aligned with DPO. TRL (HuggingFace) ships both `PPOTrainer` and `DPOTrainer` — DPO has ~3× fewer lines of config.

**IPO, KTO, SimPO** are DPO variants that address specific failure modes (distribution shift, need for paired data) — worth mentioning at senior level.

---

## Verbal script

**Opening (30s):**
"Great question — both RLHF and DPO solve the same problem: aligning the model's outputs to human preferences after supervised fine-tuning. The key difference is how they do it. RLHF uses an actual RL loop with a trained reward model, while DPO reparameterizes the same objective as a simple supervised loss, eliminating the reward model entirely. I'll walk through each and then give you my decision framework."

**Core explanation (2–3 min):**
"RLHF is a three-stage process. First you do SFT — fine-tune on demonstration data. Then you train a reward model on human preference pairs: given two responses, which is better? That reward model outputs a scalar. Then you run PPO — you generate rollouts from the current policy, score them with the reward model, compute advantages, and update the policy with clipped gradients. The critical ingredient is the KL penalty: you penalize the policy for drifting too far from the SFT checkpoint, controlled by β. Without it, the model finds adversarial inputs that fool the reward model — reward hacking.

DPO skips all of that. Rafailov et al. showed you can rearrange the RLHF objective so that the reward model is implicit in the policy itself. The loss operates directly on preference triplets and is essentially a binary cross-entropy over log-probability ratios between the current policy and a frozen reference. No rollouts, no reward model, no four-model setup. It trains like standard SFT — stable, reproducible, fast to iterate."

**Tradeoff / production angle (1 min):**
"In practice: if you have a fixed offline preference dataset and limited infra, DPO is the obvious choice. HuggingFace TRL's DPOTrainer lets you go from SFT checkpoint to aligned model in hours. If you need frontier performance — especially on tasks that require exploring beyond your dataset, like RLHF with live human feedback in the loop — PPO is worth the complexity. That's why GPT-4 and Claude 2 used RLHF. The newer DPO variants like IPO and SimPO address some of DPO's edge cases around distribution shift."

**Wrap-up (30s):**
"So my heuristic: reach for DPO first — it's 80% of the benefit at 20% of the complexity. Graduate to PPO-based RLHF only when you're doing frontier model training with online feedback or when DPO's ceiling is measurably insufficient for your task. Happy to go deeper on reward hacking or the KL penalty math."

---

## Pitfalls

- **Mistake:** Saying "RLHF is always better because it uses RL" — **Better:** Explain that DPO closes most of the gap for instruction-following tasks, avoids reward hacking, and is dramatically simpler to run; RLHF's advantage is in online/frontier settings where you can explore beyond your static dataset.
- **Mistake:** Describing RLHF as just "training on human feedback" without mentioning the reward model, PPO, or the KL penalty — **Better:** Walk through all three stages (SFT → RM → PPO with KL leash) and explain why the KL term exists (to prevent reward hacking / model collapse).
- **Mistake:** Not knowing what a preference pair looks like or how DPO's loss is computed — **Better:** Be able to say DPO takes `(prompt, chosen, rejected)` triplets and trains on log-prob ratios between the current policy and a frozen reference; no reward model or rollouts needed.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q18: Explain KL divergence](01-018-explain-kl-divergence.md) | Prerequisite — KL penalty is central to both RLHF and DPO |
| [Q4: What is the difference between pre-training and fine-tuning?](01-004-what-is-the-difference-between-pre-training-and-fine-tuning.md) | Prerequisite — RLHF/DPO are post-SFT alignment stages |
| [Q7: When fine-tune vs prompt engineering?](04-001-when-fine-tune-vs-prompt-engineering.md) | Follow-up — understanding where RLHF/DPO fit in the full adaptation decision tree |

---

## One-liner recall

> RLHF trains a reward model then runs PPO with a KL leash; DPO reparameterizes the same objective as a supervised log-prob-ratio loss on preference pairs, eliminating the reward model and RL loop entirely — reach for DPO first, PPO when you need frontier-level performance with online feedback.
