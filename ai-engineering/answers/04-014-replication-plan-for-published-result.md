# How would you plan a replication of a published ML result?

**Category:** 04-fine-tuning-training
**Question #:** 014
**Source section:** §4 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
Teams routinely decide whether to build on a published result — a new training recipe, a fine-tuning method, a benchmark claim. Interviewers ask this to separate candidates who would blindly trust a paper from those who can scope a bounded, falsifiable replication: what exactly is being claimed, what is the cheapest experiment that tests it, and when do you stop. It probes judgment under uncertainty, experimental design, and cost discipline.

### Trigger phrases
- "A paper claims X beats our baseline — how do you verify it before adopting it?"
- "Walk me through how you'd reproduce this result."
- "How do you decide between replicating a paper vs benchmarking it vs building on it?"
- "The authors released code — how much do you trust it?"
- "How would you validate an external claim with limited GPU budget?"

### What it tests
Whether you can turn a paper into a bounded experiment plan — pinned environment, minimum viable replication, stop criteria — instead of an open-ended reimplementation.

---

## Answer

### Concept
A replication plan is a time- and compute-bounded protocol for testing whether a published claim holds in your setting. It is deliberately narrower than a full reimplementation: reproduce the paper's central claim on the cheapest configuration that can falsify it, in a pinned environment, with pre-registered success criteria — then decide whether to adopt, adapt, or discard.

### Mechanism

**1. Scope the claim before touching code:**
- Extract the single falsifiable claim (e.g. "method X improves GSM8K by 4 points over SFT baseline at 7B scale") and the exact conditions it depends on: dataset version, split, metric, baseline, hyperparameters, random seeds.
- Separate the headline claim from auxiliary ablations — replicate the headline first; ablations only if the headline reproduces.
- Check what the paper's own code actually covers: released training script vs inference-only demo vs no code. Inference-only code means you are reimplementing training, which multiplies the budget — price that in.

**2. Pin the environment (reproducibility baseline):**
- Docker image with pinned CUDA, cuDNN, PyTorch, and transformers versions; lock file for Python deps. Record GPU type — results move across architectures (A100 vs H100 numerics, different FlashAttention kernels).
- Fix seeds for data shuffling, init, and sampling; log them. One seed is enough for the first pass; multi-seed variance comes later, only if the effect size is close to the noise floor.
- Version the dataset with a checksum. Re-downloaded or re-tokenized data silently changes results — this is the most common silent replication killer.

**3. Minimum viable replication (cheapest falsifying test):**
- Start at the smallest scale where the effect should be visible: fewer steps, smaller model, data subset — chosen so that a negative result actually means something (if the paper's ablations show the effect only appears at 70B, say so and either budget for it or decline).
- Reproduce the baseline first, then the method. If your baseline doesn't match the paper's baseline within noise, stop — you have an environment or data mismatch, not a method result. Debugging the method on a broken baseline wastes the whole budget.
- Compare with the paper's reported variance. A 2-point gain against a baseline with ±3-point seed variance is not a replication — it is noise.

**4. Bounded loop with stop criteria (write these down first):**
- Budget: N GPU-hours and M days, fixed up front. A replication without a budget becomes a reimplementation.
- Stop and adopt: central claim reproduces within reported variance on your pinned stack.
- Stop and adapt: effect direction holds but magnitude differs — adopt the idea, retune for your data/scale, treat the paper as inspiration rather than a recipe.
- Stop and discard: no effect after baseline parity is confirmed, or the effect requires conditions you cannot meet (proprietary data, 10× your compute). A clean negative with a matched baseline is a successful replication — it just has a negative answer.

**5. Replicate vs benchmark vs build on:**
- **Replicate** when the claim would change a technical decision (adopting a method, citing a number externally).
- **Benchmark** (run the released artifact as-is on your data, no retraining) when you only need to know if it works for you — cheaper and often sufficient for model or dataset releases.
- **Build on** directly when the idea is well-established across multiple independent reproductions; the marginal value of your own replication is low.

### Example / Tradeoff

**A concrete plan:** a paper claims a new preference-tuning variant beats DPO by 5 points on a math benchmark at 8B scale, with code released.
- Day 1–2: pin Docker image (torch version from the repo's requirements), checksum the dataset, reproduce the paper's SFT baseline. Budget: 1×8×A100 for a day.
- Day 3–5: run the paper's method config unchanged. If baseline matched and the method matches within ~2 points, adopt. If baseline never matched, stop and report the mismatch (tokenizer version, data split, and eval harness version are the usual suspects) rather than tuning the method to hit the number.
- Pre-registered rule: if the gap is under 2 points after baseline parity, call it noise and discard — do not run five more seeds hoping for significance.

**Tradeoff:** full reimplementation maximizes understanding but is unbounded in cost; benchmark-only evaluation is cheap but tells you nothing about why something works or whether it transfers. The bounded replication sits between: enough rigor to trust a decision, cheap enough to run routinely. The failure mode to avoid is the middle that satisfies neither — weeks of unbudgeted tinkering with no baseline parity and no stop rule.

---

## Verbal script

**Opening (30s):**
"I'd treat a replication as a bounded experiment, not a reimplementation. My plan has four parts: scope the exact falsifiable claim, pin the environment, reproduce the baseline first, then test the method against pre-registered stop criteria — with a fixed GPU budget written down before I start."

**Core explanation (2–3 min):**
"The key insight is baseline-first. The most common replication failure isn't the method — it's that your baseline doesn't match the paper's baseline because of a tokenizer version, a data split, or an eval harness difference. So step one is reproducing their baseline in a pinned Docker image with checksummed data and logged seeds. If that doesn't match within noise, I stop — I have an environment mismatch, not a method result.

Only then do I run the method config unchanged, at the smallest scale where the effect should be visible. And I pre-register the decision rule: reproduce within variance means adopt; right direction but wrong magnitude means adapt the idea to our setting; no effect after baseline parity means discard — and that's a successful replication with a negative answer, not a failure.

I'd also distinguish three levels of effort. If I just need to know whether a released artifact works on our data, I benchmark it as-is without retraining. Full replication is reserved for claims that would change a technical decision. And if an idea already has multiple independent reproductions, the marginal value of mine is low and I'd build on it directly."

**Tradeoff / production angle (1 min):**
"The budget is the whole game. Without a fixed GPU-hour and calendar cap, every replication drifts into an open-ended reimplementation. I'd also flag scale-dependence explicitly: if the paper's own ablations show the effect only at 70B and I have 8B budget, I'd say so up front and either decline or reframe as an adaptation experiment. And effect size versus noise — a 2-point gain against ±3-point seed variance is not evidence of anything, so I check the paper's variance reporting before promising a verdict."

**Wrap-up (30s):**
"Short version: scope one falsifiable claim, pin everything, baseline first, pre-register stop rules, and spend full-replication budget only on claims that change decisions. Happy to walk through a specific example."

---

## Pitfalls

- **Mistake:** Tuning the method until it hits the paper's number without ever reproducing the baseline — **Better:** Reproduce the baseline first; if it doesn't match within noise, you have an environment or data mismatch, and any method result on top of it is meaningless.
- **Mistake:** Starting a replication with no budget or stop criteria ("let's just try to reproduce it") — **Better:** Fix GPU-hours and days up front plus pre-registered adopt/adapt/discard rules; otherwise it becomes an unbounded reimplementation.
- **Mistake:** Treating a clean negative result as a failed replication — **Better:** A negative with confirmed baseline parity is a successful replication with a negative answer — report it as evidence against adoption, which is exactly what the business needed.
- **Mistake:** Ignoring scale-dependence ("it worked at 70B, let's replicate at 1B on a subset") — **Better:** Check the paper's ablations for where the effect appears; if the effect is scale-dependent and you can't afford that scale, decline or reframe rather than running a test that can't falsify anything.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q6: Design a model for math problems — data, SFT, post-training, eval](04-006-design-a-model-for-math-problems-data-sft-post-training-eval.md) | The eval harness and data-versioning discipline from model design transfers directly to replication baselines |
| [Q17: Golden dataset for evaluation and regression testing?](05-017-golden-dataset-for-evaluation-and-regression-testing.md) | Pre-registered success criteria for a replication are a golden-set comparison — same pattern, applied to external claims |
| [Q37: Agents collaborating on research reports with citations](03-037-agents-collaborating-on-research-reports-with-citations.md) | Automated replication pipelines reuse the planner-plus-verifier structure with provenance tracking |

---

## One-liner recall

> A replication plan scopes one falsifiable claim, pins the environment, reproduces the baseline first, and tests the method against pre-registered adopt/adapt/discard rules inside a fixed GPU budget.
