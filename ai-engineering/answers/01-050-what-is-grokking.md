# What is grokking?

**Category:** 01-llm-fundamentals
**Question #:** 050
**Source section:** §1 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
Grokking is the sharpest known counterexample to "flat validation metric means training is done." Interviewers ask it to probe whether a candidate understands training dynamics beyond the loss curve — memorization vs generalization as competing circuits, the role of weight decay, and how mechanistic interpretability turned a mysterious delayed-jump into an explained three-phase process. It separates candidates who have only read about overfitting from those who follow modern training-dynamics research.

### Trigger phrases
- "Have you heard of grokking?"
- "Train accuracy hits 100% but test stays at chance — then test suddenly jumps. What happened?"
- "Why would you keep training a model whose validation metric has been flat for thousands of steps?"
- "What did Nanda et al. find inside the grokking transformer?"

### What it tests
Whether you can explain delayed generalization mechanistically — not just name it — and draw the correct training-run lesson from it.

---

## Answer

### Concept
Grokking (Power et al., OpenAI, 2022) is delayed generalization: a small transformer trained on an algorithmic task such as modular addition first memorizes the training set — train accuracy hits ~100% while test accuracy sits at chance — and then, thousands of optimization steps later with no change in the training setup, test accuracy suddenly snaps to ~100%. The model was not stuck; it was silently building a generalizing circuit underneath a flat test curve, and weight decay eventually deleted the memorization circuit in favor of it.

### Mechanism
The canonical setup is `a + b mod p` with `p = 113`, trained on a fraction of all pairs with a 1-layer transformer. Three phases, reverse-engineered by Nanda et al. (2023):

**1. Memorization.** The model fits the training pairs with a high-norm lookup-table-style circuit. Train accuracy → 100%, test accuracy ≈ 1/113 ≈ 0.9%. Train loss is near zero, so gradient signal looks dead — but it is not.

**2. Circuit formation (the hidden plateau).** Alongside the memorizer, the model gradually builds a generalizing Fourier circuit: embeddings learn sparse sinusoidal features (`cos(w·a)`, `sin(w·a)` at a few key frequencies such as `8π/113`), attention routes them, MLP neurons combine them through the trig identity `cos(x)·cos(y) − sin(x)·sin(y) = cos(x+y)`, and the unembedding sums each frequency's "vote" into a sharp peak at `c = a+b mod p`. Nanda's **excluded loss** — a progress measure that factors out the memorization component — improves smoothly through this phase even while ordinary train/test loss look completely flat. The plateau hides real progress.

**3. Cleanup.** The Fourier circuit is far more weight-efficient (lower norm) than the lookup table. Weight decay therefore penalizes the memorizer more steeply; once the generalizing circuit explains the training data on its own, the memorization weights collapse and test accuracy jumps. Grokking is what it looks like when regularization selects the efficient circuit late. Turn weight decay down and grokking weakens or vanishes — the model just memorizes.

### Example / Tradeoff
**Concrete numbers:** on mod-113 addition with ~30–50% of pairs in training, a 1-layer transformer reaches 100% train accuracy in the first few thousand steps while test accuracy sits at ~1% for tens of thousands of steps — then climbs to ~100% in a sharp transition. The DFT of the embedding matrix shows a handful of dominant frequencies where a random initialization shows none; that spectral signature is the observable fingerprint of the generalizing circuit.

**Training-run lesson:** on small-data algorithmic training, a flat validation metric is not evidence of convergence — it may be phase 2. Before declaring "done," check (a) whether weight decay is strong enough to ever force cleanup, and (b) an internal progress measure (probe accuracy, excluded-loss-style metric) rather than the headline loss alone. **The tradeoff cuts the other way at LLM scale:** large-model pre-training and SFT live in regimes where grokking-style delayed jumps are not the operating dynamic — data is vast, compute per step is expensive, and early stopping on a held-out eval plus learning-rate decay is still the correct default. Do not cite grokking to justify training past a flat eval on a production LLM run; cite it to show you know *when* flatness hides progress (small algorithmic tasks, heavy weight decay, long horizons) and when it genuinely means stop.

---

## Verbal script

**Opening (30s):**
"I'd start by framing grokking as delayed generalization — the 2022 OpenAI finding where a small transformer on modular addition memorizes first, sits at chance on test for thousands of steps, then suddenly generalizes to ~100%. The key insight is that the flat test curve was hiding real progress, and we know this because Nanda et al. reverse-engineered the exact circuit in 2023."

**Core explanation (2–3 min):**
"The setup is a 1-layer transformer learning `a + b mod 113`. Phase one is pure memorization — a high-norm lookup table that nails the training pairs and gets ~1% on test. Phase two is invisible on the loss curve: the model builds a Fourier circuit. Embeddings learn sine and cosine features at a few key frequencies, the MLP combines them with the trig identity `cos x cos y − sin x sin y = cos(x+y)`, and the unembedding adds up each frequency's vote into a peak at the right answer. Nanda's excluded-loss metric tracks this hidden construction while the headline metrics look dead. Phase three is cleanup: the Fourier circuit uses far smaller weights than the lookup table, so weight decay kills the memorizer once the generalizer can carry the training data — and test accuracy snaps up. Remove weight decay and you mostly just get memorization."

**Tradeoff / production angle (1 min):**
"The practical lesson is narrow but real: on small algorithmic training runs, flat validation is not proof of convergence — check internal progress measures and make sure weight decay is strong enough to force cleanup before you stop. But I wouldn't over-apply this: at LLM pre-training or SFT scale, flat eval plus a decayed learning rate genuinely means stop. Grokking needs the small-data, heavy-decay, long-horizon regime; invoking it to justify extra epochs on a production fine-tune is the classic misapplication."

**Wrap-up (30s):**
"So in summary: memorization first, silent Fourier-circuit construction second, weight-decay-driven cleanup third. Excluded loss is the metric that sees through the plateau. Happy to go deeper into the trig-identity mechanism or the cleanup dynamics."

---

## Pitfalls

- **Mistake:** Calling grokking "just overfitting that fixes itself" — **Better:** Distinguish them: overfitting is a persistent train-val gap from fitting noise; grokking is a transient phase where a generalizing circuit is still under construction, and it resolves without any intervention except continued training under weight decay.
- **Mistake:** Saying "always train longer when validation is flat" — **Better:** Scope the lesson to the grokking regime (small algorithmic tasks, strong weight decay, long horizons); at LLM scale flat eval with a decayed schedule means stop, and extra epochs burn budget or overfit the fine-tune set.
- **Mistake:** Naming grokking without any mechanism — "test accuracy jumps later, it's weird" — **Better:** Walk the three phases and name the Fourier circuit (sin/cos embeddings → trig identity → unembedding vote) plus cleanup via weight decay; the mechanism is the whole point of the 2023 follow-up.
- **Mistake:** Claiming weight decay is incidental — **Better:** State its causal role: the generalizing circuit wins cleanup specifically because it is lower-norm, so weight decay selects it; weakening decay suppresses grokking.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q46: Bias-variance tradeoff](01-046-bias-variance-tradeoff.md) | Prerequisite — memorization vs generalization is the variance failure mode grokking resolves late |
| [Q47: Overfitting — how prevent it?](01-047-overfitting-how-prevent-it.md) | Adjacent phenomenon — overfitting persists while grokking's gap closes; weight decay is the shared lever |
| [Grokking Fourier circuit](../concepts/55-grokking-fourier-circuit.html) | Follow-up deep dive — DFT features, clock geometry, trig mechanism, cleanup, interactive demos |

---

## One-liner recall

> Grokking is delayed generalization in three phases — memorization, hidden Fourier-circuit construction (visible only in excluded loss), then weight-decay cleanup that deletes the memorizer — so on small algorithmic runs flat validation hides progress, while at LLM scale flat eval still means stop.
