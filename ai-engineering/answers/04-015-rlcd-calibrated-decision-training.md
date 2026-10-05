# What is RLCD (calibrated-decision training, not contrastive distillation) and when use it over RLHF/RLVR?

**Category:** 04-fine-tuning-training
**Question #:** 015
**Source section:** §4 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
Most candidates can recite RLHF (human preference) and increasingly RLVR (verifiable string reward), but production systems usually end in a typed decision with a confidence attached — approve/deny/escalate at 0.83 — not a paragraph. The interviewer is probing whether you know there is a third objective family that rewards *decision quality under stated probabilities*: calibration, not preference or string-match. Senior candidates explain why the autoregressive LM loss and even RLVR are the wrong shape for parallel decision heads, and when to reach for calibration training instead.

### Trigger phrases
- "How do you train a model whose output is a decision plus a confidence?"
- "Your classifier is accurate but its probabilities are meaningless — how do you fix that in training?"
- "RLHF vs RLVR — what if neither fits because the output is a typed action?"
- "How do you get calibrated confidence out of an LLM decision head?"

### What it tests
Understanding that preference rewards and verifiable rewards optimize different things than decision quality — and that stated probabilities must be trained, not read off logits.

---

## Answer

### Concept
**RLCD (Reinforcement Learning from Calibrated Decisions, "calibrated-decision training")** is a post-training objective whose reward is the *quality of a decision made under the model's own stated probabilities* — typically a proper scoring rule (log-loss, Brier score) over typed outcomes, plus the downstream cost of the action taken. Not to be confused with the earlier, unrelated RLCD of Yang et al. (2023) — Reinforcement Learning from Contrast Distillation — which synthesizes contrastive positive/negative response pairs as preference data; that is a preference-data method in the RLHF family, not a decision-calibration objective, and this note covers only the calibrated-decision meaning. Where RLHF rewards "a human preferred this response" and RLVR rewards "this string matches the checker," RLCD rewards "the action taken at the stated confidence had positive expected value." The point: a model that says "fraud, 0.91" and is right 91% of the time at that confidence level is more useful than a more accurate model whose 0.91 means 0.62 — because thresholds, routing, and escalation policies consume the number, not…

### Mechanism

**Why the standard objectives are the wrong shape for decision heads:**
A parallel decision head emits a typed outcome (approve/deny/escalate, a JSON action schema) plus a scalar confidence in a single forward pass — no autoregressive chain, no KV-cache growth, no serial latency. Three mismatches follow:
1. **Autoregressive LM loss** trains next-token likelihood over open text. It never penalizes a confident-but-wrong scalar, because the scalar is one token among thousands and likelihood does not score probability honesty.
2. **RLHF preference reward** trains "which response reads better to a rater." Raters systematically prefer confident, verbose answers — the exact bias that destroys calibration. Optimizing preference on decision outputs actively uncalibrates them.
3. **RLVR verifiable reward** trains string correctness (exact match, test pass). A checker says right/wrong; it says nothing about whether 0.7 vs 0.95 was the honest confidence. Two policies with identical accuracy but different calibration get identical RLVR reward.

**The RLCD objective:**
Sample decisions from the head, then score each against the realized outcome with a proper scoring rule plus action cost:
```
R(decision, p, outcome) = S(p, outcome) − λ · cost(action | outcome)
```
- `S` is a **proper scoring rule** — minimized in expectation only by stating your true belief. Log-loss `−log p(outcome)` and Brier `(p − 1_outcome)²` are the standards. Because the rule is proper, the policy cannot game it by inflating confidence: overstating `p` on wrong outcomes is punished superlinearly.
- `cost(action | outcome)` is the domain loss matrix — approving a fraudulent transaction costs orders of magnitude more than escalating a legitimate one. `λ` trades probability honesty against business cost; in cost-asymmetric domains the optimal stated threshold moves away from 0.5 even under perfect calibration.
- Training is RL-flavored (sample decisions, score, policy-gradient update with a KL leash to the SFT reference, same as any post-training loop) but the reward needs no human rater and no string checker — just logged outcomes, which decision systems already record.

**Post-hoc vs training-time calibration (know both):**
Post-hoc recalibration — temperature scaling (`softmax(logits/T)`), Platt scaling, isotonic regression on a held-out set — remaps stated probabilities without touching weights (see [the calibration note](05-022-two-models-same-accuracy-different-confidence-which-choose-c.md) for the full treatment). It is cheap and composes with any model. RLCD is the training-time complement: it changes *which* decisions the head makes and how sharply it separates easy from hard cases (resolution), which no post-hoc remap can add. Rule of thumb: RLCD for resolution + honesty jointly during post-training; temperature/Platt afterward as the final honesty pass. One does not replace the other.

### Example / Tradeoff

**RLHF vs RLVR vs RLCD contrast:**

| Dimension | RLHF (PPO + KL leash) | RLVR (verifiable reward) | RLCD (calibration reward) |
|-----------|----------------------|--------------------------|---------------------------|
| Reward answers | "Would a human prefer this?" | "Does the string match the checker?" | "Was the decision good at the stated confidence?" |
| Reward source | Learned RM on preference pairs | Deterministic checker (tests, exact match) | Proper scoring rule + cost matrix on logged outcomes |
| Output shape | Open-ended text | Text with checkable answer | Typed decision + scalar confidence |
| What it improves | Helpfulness, tone, safety | Correctness on checkable tasks | Probability honesty + cost-aware thresholds |
| Failure mode | Reward hacking, sycophancy | Verifier gaming, format without reasoning | Miscalibrated cost matrix (wrong λ prices honesty away) |
| Canonical example | Chat assistant alignment | Math/code reasoning (R1-style) | Fraud/credit/routing decision heads |

**Worked sketch — transaction routing head:**
Head emits `{action ∈ approve, review, deny; p_fraud}`. Logged outcomes give the ground truth. Brier score on `p_fraud` trains honesty; the cost matrix (deny-legit = lost fee + insult rate, approve-fraud = full loss) sets operating thresholds via expected-value computation, not via accuracy maximization. After RLCD, the `review` band (say 0.3–0.8) contains the genuinely ambiguous cases — measurable as lower Brier within each band — so human reviewers stop wasting time on cases the model already knew were clear.

---

## Verbal script

**Opening (30s):**
"I'd reach for RLCD when the output is a typed decision with a confidence attached, not a paragraph. RLHF optimizes human preference, RLVR optimizes string correctness — neither trains probability honesty, and preference training actually destroys it because raters reward confident-sounding answers. RLCD rewards decision quality under your own stated probabilities using a proper scoring rule plus the business cost matrix."

**Core explanation (2–3 min):**
"The mechanism has three parts. First, recognize the mismatch: an autoregressive loss trains token likelihood, a preference reward trains rater appeal, a verifier trains string-match — none of them penalize saying 0.91 when you mean 0.62. Second, the RLCD reward: score each sampled decision with a proper scoring rule like Brier or log-loss against the logged outcome, minus lambda times the action cost from the domain loss matrix. Proper scoring rules are the key — they're minimized only by stating your true belief, so confidence inflation is punished superlinearly. Third, place it relative to post-hoc calibration: temperature scaling and Platt remap probabilities without touching weights, which is cheap and I always do it last — but they can't add resolution, the model's ability to separate easy from hard cases. RLCD trains resolution and honesty jointly; temperature is the final honesty pass."

**Tradeoff / production angle (1 min):**
"The failure mode I'd watch is the cost matrix, not the scoring rule — a mispriced lambda trains the head to be honestly wrong in expensive ways. And RLCD needs logged outcomes, so it fits systems that already record decisions and ground truth: fraud, credit, routing, triage. For open-ended generation there is no outcome to score, so RLHF or RLVR remain the right tools. Different outputs, different objectives."

**Wrap-up (30s):**
"So my heuristic: paragraphs get preference or verifiable rewards; typed decisions with confidences get calibration rewards plus post-hoc scaling. Happy to go deeper on scoring rules or threshold-setting from the cost matrix."

---

## Pitfalls

- **Mistake:** Saying "RLHF covers decision heads too — just collect preferences on decisions" — **Better:** Explain raters prefer confident-sounding outputs, so preference optimization actively uncalibrates decision heads; decisions need a proper scoring rule on logged outcomes, not rater appeal.
- **Mistake:** Claiming temperature scaling "solves calibration, so training-time calibration is redundant" — **Better:** Post-hoc remaps adjust honesty but cannot add resolution (separating easy from hard cases); RLCD trains both jointly, temperature is the final pass afterward.
- **Mistake:** Treating accuracy as the decision-head metric and ignoring the cost matrix — **Better:** State that thresholds come from expected-value computation over the domain loss matrix; a more accurate but miscalibrated head routes worse than a less accurate calibrated one wherever actions have asymmetric costs.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q29: RLHF vs DPO — when prefer one over the other?](../answers/01-029-rlhf-vs-dpo-when-prefer-one-over-the-other.md) | Sibling — the preference-objective baseline RLCD contrasts against |
| [Q4: What is RLHF and why important?](04-004-what-is-rlhf-and-why-important.md) | Prerequisite — PPO/KL-leash post-training loop RLCD reuses with a different reward |
| [Q22: Two models, same accuracy, different confidence — which choose? Calibration?](05-022-two-models-same-accuracy-different-confidence-which-choose-c.md) | Follow-up — ECE/reliability-diagram measurement for what RLCD trains |

---

## One-liner recall

> RLCD here means calibrated-decision training (not Yang et al.'s 2023 contrastive-distillation method): RLHF rewards rater preference and RLVR rewards string correctness, but typed decisions with confidences need a proper scoring rule plus the business cost matrix on logged outcomes — because thresholds and routing consume the probability, not the label; finish with post-hoc temperature/Platt scaling.
