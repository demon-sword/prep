# Constitutional AI and alignment?

**Category:** 08-safety-guardrails
**Question #:** 006
**Source section:** §10 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
This is a "do you actually read the research, and can you turn it into engineering?" question. Plenty of candidates can say "Constitutional AI is when the model critiques itself" and stop there. The interviewer wants to see three things: that you can describe the two-phase training procedure precisely, that you know exactly where AI feedback substitutes for human feedback relative to RLHF, and — most importantly for an application engineer — that you understand you will almost certainly never run CAI training yourself, but you *will* reuse its core pattern as an inference-time self-correction loop and as the structure of your policy documents. It also probes whether you can talk about alignment without drifting into philosophy.

### Trigger phrases
- "What is Constitutional AI and how does it differ from RLHF?"
- "How do you align a model's behavior with your company's policy?"
- "What does RLAIF mean and why would you use AI feedback instead of human labels?"
- "You've read the Anthropic constitution — what would you do with it?"
- "How do you make a model self-correct without a human in the loop?"

### What it tests
Whether you can explain a specific alignment training method at the mechanism level *and* translate it into a shippable application pattern (critique-and-revise loop + a written policy that doubles as system prompt and eval rubric).

---

## Answer

### Concept
**Constitutional AI (CAI)** is an alignment method — introduced by Anthropic in *Constitutional AI: Harmlessness from AI Feedback* (Bai et al., arXiv:2212.08073, 2022) — that replaces human harmlessness labels with a written set of principles (the **constitution**) plus the model's own judgment. The model is shown its own output, asked to critique it against a sampled principle, asked to revise it, and later asked to *choose* between two responses using the constitution as the rubric. Those AI-generated preferences train the reward model. **Alignment** is the broader goal: making a model's behavior track the intended values and policy rather than just the literal instruction.

The core claim is a scalability claim, not a quality claim: human preference labeling is the bottleneck in RLHF, and a written document plus model inference is far cheaper to scale and — crucially — is **auditable and version-controllable** in a way that a pool of human annotators is not.

### Mechanism

**Phase 1 — Supervised stage (critique → revise → finetune):**

1. Prompt a helpful-only model (deliberately *not* harmlessness-trained) with red-team prompts designed to elicit harmful responses. You need the harmful response to exist before you can teach the revision.
2. Sample a principle from the constitution and ask the model to **critique** its own response against it: *"Identify specific ways in which the assistant's last response is harmful, unethical, or racist."*
3. Ask the model to **revise** the response to remove what the critique found.
4. Optionally iterate critique→revise 2–4 times, sampling a different principle each round, so no single principle dominates.
5. Discard the critiques. Finetune the pretrained model on **(original prompt → final revision)** pairs. This is the **SL-CAI** model. Its job is to get the policy distribution roughly right so the RL stage starts from a sane place and converges faster.

**Phase 2 — RL stage (RLAIF):**

6. Sample two responses from SL-CAI for each red-team prompt.
7. Build a multiple-choice prompt: the constitution principle + the prompt + response A + response B, and ask a **feedback model** which is better. Use the normalized log-probabilities of "A" vs "B" as a soft preference label — not just the argmax, because the probability mass carries confidence information.
8. Train a **preference model** on those AI-generated comparisons. Harmlessness comes from AI feedback; helpfulness preferences still typically come from human labels — CAI in practice is a **hybrid**, which is the detail most candidates get wrong.
9. Run RL (PPO, or a direct-optimization method like DPO) against that preference model. Result: **RL-CAI**.

**RLHF vs CAI — where the substitution actually happens:**

| Stage | RLHF | Constitutional AI |
|-------|------|-------------------|
| Initial supervised data | Human-written demonstrations | Model's own critique-and-revise output |
| Harmlessness preference labels | Human crowdworkers rank pairs | Model ranks pairs against a sampled principle (RLAIF) |
| Helpfulness preference labels | Human | Still human, in the published recipe |
| Reward/preference model | Trained on human comparisons | Trained on AI comparisons (harmlessness) |
| RL optimizer | PPO / DPO | PPO / DPO — unchanged |
| Cost driver | Annotator throughput | Inference throughput |
| Auditability of the policy | Implicit in annotator guidelines | Explicit, versioned, diffable document |
| Failure mode | Annotator bias, label noise, fatigue | Feedback model inherits its own blind spots; principles can be gamed |

The single-sentence version: **the RL machinery is identical; CAI swaps the source of the harmlessness preference signal from a human labeler to a model reading a written principle.** It also fixes RLHF's well-documented evasiveness problem — an RLHF-harmless model tends to answer "I can't help with that," whereas a CAI model is trained to *explain its objection*, which is non-evasive harmlessness.

**What a constitution concretely is:** a plain-language document of principles, not code and not a blocklist. The 2022 paper drew its ~16 principles from the UN Declaration of Human Rights, trust-and-safety terms of service, and prior lab work (DeepMind's Sparrow rules), each phrased as a critique instruction. Anthropic has since published Claude's constitution publicly — most recently a substantially expanded document released 21 January 2026 under CC0, which is notable for two reasons: it is **reason-based rather than rule-based** (it explains *why* a value holds so the model can generalize to unlisted cases), and it states an explicit priority ordering — **safe, then ethical, then compliant with Anthropic's guidelines, then helpful** — so conflicts have a deterministic resolution rather than being left to vibes.

**The engineering angle — what you actually ship.** You will rarely run CAI training. You will use it three ways:

1. **Inference-time critique-and-revise.** Generate a draft → a second call critiques it against your policy → a third call revises. This is Phase 1 with the finetuning removed, and it works today with no training infrastructure. Use it for high-stakes, latency-tolerant paths: outbound customer emails, generated legal or medical summaries, code review comments.
2. **The policy document as a dual-use artifact.** Write your constitution once. It becomes (a) the behavioral section of your system prompt, (b) the rubric your LLM-as-judge evaluator scores against, and (c) the label definition your human reviewers use. When all three drift out of sync, your evals stop measuring your policy — a single source of truth prevents that. Version it in git alongside the code.
3. **Synthetic preference data.** If you *do* fine-tune, use the constitution to generate preference pairs cheaply, then have humans audit a 5–10% sample rather than label 100%.

### Example / Tradeoff

**Concrete deployment — an enterprise support assistant with a 6-principle constitution** (no speculation about refund eligibility, no competitor commentary, no medical or legal advice, always cite the KB article, escalate on distress signals, never claim to be human):

- The document lives at `policy/constitution.md`, versioned in git.
- A build step injects it into the system prompt.
- The same file is the rubric for an LLM-as-judge eval that runs against a 400-case golden set in CI on every prompt change.
- On the ~4% of traffic routed to the high-stakes path (billing disputes, cancellations), a critique-and-revise pass runs before delivery.

Measured effect of the revise loop on that slice: policy-violation rate on human audit fell from roughly 3% to under 1%, at the cost of **2 extra generation passes**. That is the tradeoff and you should say the number out loud: critique-and-revise roughly **triples token spend and p95 latency** for the requests it touches — a ~900ms path becomes ~2.5–3s. That is why it is a route, not a default. The routing rule ("is this action irreversible or financially material?") is the actual engineering decision.

**The other tradeoffs worth naming:**

- **Self-critique is not self-verification.** The critic is the same model with the same blind spots. It reliably catches tone, scope, and policy-shape violations; it does **not** reliably catch factual errors it just confidently generated. For groundedness you need an independent check — an NLI entailment model over the retrieved context, not another sample of the same model.
- **Principle sampling matters.** Applying all principles at once produces shallow, generic critiques. Sampling one or two per pass produces sharper revisions — same reason a code review scoped to one concern is better than "review everything."
- **Over-revision degrades helpfulness.** Loop three or four times and outputs get hedged, caveat-laden, and worse. Cap at one or two revisions and measure helpfulness alongside harmlessness, or you will optimize a metric that only moves in one direction.
- **A constitution is not a guardrail.** It shapes the *default* behavior of a cooperative model. It does nothing against an adversary — an injected instruction does not care what your constitution says. You still need classifiers and structural defenses.

Where this sits in the compliance picture: NIST AI RMF 1.0 (GOVERN-1 and MAP) and EU AI Act Article 50 transparency duties — generally applicable from 2 August 2026 — both effectively require a documented, versioned statement of intended behavior. A written constitution is the cheapest artifact that satisfies "show us your policy" *and* does real work at runtime.

---

## Verbal script

**Opening (30s):**
"I'd separate the research method from the thing I actually ship, because they're different answers. Constitutional AI is a specific two-phase training procedure from the 2022 Anthropic paper where a written document replaces human harmlessness labels. I've never trained a model that way — almost nobody outside a frontier lab has. But the pattern underneath it is something I use in production constantly: a critique-and-revise loop at inference time, and a policy document that serves as system prompt and eval rubric at the same time. Let me do the method first, then the engineering."

**Core explanation (2–3 min):**
"Phase one is supervised. You take a helpful-only model — deliberately not harmlessness-trained, because you need it to actually produce the bad response — and you hit it with red-team prompts. Then you sample a principle from the constitution and ask the model to critique its own last response against that specific principle. Then you ask it to revise. You can loop that a couple of times, sampling a different principle each round. Then you throw away the critiques and fine-tune on original-prompt-to-final-revision pairs. That gives you what the paper calls SL-CAI, and its real job is to get the distribution close enough that the RL stage converges quickly.

Phase two is RLAIF, and this is the part worth being precise about. You sample two responses, build a multiple-choice prompt containing a constitutional principle plus both responses, and ask a feedback model which one is better. You take the normalized log-probs of A versus B as a soft preference label — not just the argmax, because the confidence carries signal. Those AI-generated preferences train the preference model, and then you run PPO or a direct method against it exactly like normal RLHF.

So the honest comparison to RLHF is narrower than people usually state it. The RL machinery is identical. What changes is the *source of the harmlessness preference label* — a model reading a written principle instead of a crowdworker following annotator guidelines. And in the published recipe helpfulness preferences are still human-labeled, so it's a hybrid, not a full replacement. Two things that buys you: you can scale preference data with inference instead of headcount, and your policy becomes an explicit versioned document you can diff, instead of being implicitly encoded in a training vendor's annotator handbook. There's also a quality effect the paper calls out — RLHF-harmless models get evasive, they just say 'I can't help with that.' CAI models are trained to explain the objection, which is non-evasive harmlessness.

On the constitution itself: it's plain language, not code. The original paper used about sixteen principles pulled from the UN Declaration of Human Rights, platform terms of service, and DeepMind's Sparrow rules. Anthropic publishes Claude's constitution publicly — the current one, released January 2026 under CC0, is interesting to me as an engineer for two reasons. It's reason-based rather than rule-based, so it explains *why* a value holds and the model can generalize to cases nobody enumerated. And it has an explicit priority order — safe, then ethical, then compliant with guidelines, then helpful — so conflicts resolve deterministically. That's the thing I steal: my own policy documents now state priority order explicitly, because 'be safe and be helpful' with no tiebreaker is not a spec."

**Tradeoff / production angle (1 min):**
"Where this becomes real engineering: I run critique-and-revise at inference time on high-stakes paths only, because it costs two extra generation passes. A 900ms request becomes 2.5 to 3 seconds and roughly triples token spend for that request. On a support assistant I'd route maybe 4% of traffic through it — the irreversible or financially material actions — and let everything else go straight through. On that slice it took audited policy violations from around 3% to under 1%.

Two limits I'd flag. First, self-critique is not self-verification. The critic is the same model with the same blind spots — it catches tone, scope, and policy violations reliably, and it does *not* reliably catch a fact it just confidently made up. For groundedness I want an independent NLI entailment check against retrieved context, not another sample of the same model. Second, a constitution is not a guardrail. It shapes cooperative default behavior; it does nothing against an adversary, because injected instructions don't care what your policy document says. Classifiers and structural defenses are a separate layer.

The other thing I'd do is make the constitution earn its keep three times: it's the system prompt, it's the LLM-as-judge rubric in CI, and it's the label definition for human reviewers. One file in git. When those three drift apart your evals quietly stop measuring your policy, and you won't find out until an incident."

**Wrap-up (30s):**
"So: two phases, supervised critique-and-revise then RLAIF, and the only substitution versus RLHF is who produces the harmlessness preference label. As an application engineer I don't train it — I run critique-and-revise as a routed inference-time loop where it's worth two extra passes, and I write one versioned policy document that's simultaneously my system prompt and my eval rubric. Happy to go into the preference model details or how I'd structure the eval rubric."

---

## Pitfalls

- **Mistake:** Saying "Constitutional AI is just RLHF but the AI gives the feedback" and stopping. — **Better:** Name both phases and say where the substitution happens: Phase 1 is supervised finetuning on the model's *own* critique-and-revise output; Phase 2 is where AI preferences replace human labels, and only for *harmlessness* — helpfulness preferences are still human in the published recipe. The PPO/DPO machinery is unchanged. That precision is the entire signal in this question.

- **Mistake:** Treating the constitution as a runtime safety control — "we put the constitution in the system prompt, that's our guardrail." — **Better:** A constitution shapes default behavior in a cooperative setting; it is not a security boundary. An injected instruction or a jailbreak doesn't respect it. Position it as the *policy* layer and pair it with classifier-layer enforcement (input/output classifiers) and structural controls (tool allowlisting, delimiter fencing).

- **Mistake:** Proposing an inference-time self-critique loop with no cost analysis and no routing rule — "we just have the model check its own answer." — **Better:** State the price: each critique-and-revise round is an extra generation pass, so a single revision roughly triples tokens and p95 latency for that request. Then give the routing rule — irreversible or financially material actions get the loop, everything else doesn't — and add that self-critique catches policy and tone violations but not the model's own hallucinations, which need an independent entailment check.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q4: What is RLHF and why important?](04-004-what-is-rlhf-and-why-important.md) | prerequisite — CAI is defined by what it changes relative to the RLHF pipeline |
| [Q8: RLHF pipeline: SFT, reward model, PPO — how does DPO simplify?](04-008-rlhf-pipeline-sft-reward-model-ppo-how-does-dpo-simplify.md) | prerequisite — the RL machinery CAI reuses unchanged |
| [Q17: What is reflection in the context of LLM agents?](01-017-what-is-reflection-in-the-context-of-llm-agents.md) | same concept — critique-and-revise is reflection applied to safety policy |

---

## One-liner recall

> Constitutional AI is two phases — supervised finetuning on the model's own critique-and-revise output against sampled written principles, then RLAIF where a model reading those principles produces the *harmlessness* preference labels that a human would have produced in RLHF (helpfulness stays human, PPO/DPO unchanged) — and as an application engineer you ship the pattern, not the training: a routed inference-time critique-and-revise loop costing one extra generation pass, plus one versioned policy document that is simultaneously your system prompt, your LLM-judge rubric, and your human-review label definition.
