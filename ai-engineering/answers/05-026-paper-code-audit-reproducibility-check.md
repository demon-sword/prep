# How do you audit a paper's code for reproducibility?

**Category:** 05-evaluation-metrics
**Question #:** 026
**Source section:** §5 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
The interviewer is probing whether you treat published results as evidence or as marketing — and whether you have a repeatable method for telling the difference before you bet a product or a research direction on someone else's numbers. Weak candidates say "I'd try running the code" and stop; strong candidates describe a claim inventory, a claim-to-code mapping, tiered verification by cost, and a severity-graded verdict. This is the reproducibility-check agent pattern: the same discipline you would automate in a deep-research pipeline, executed by hand.

### Trigger phrases
- "How do you verify a paper's results before building on them?"
- "The paper claims SOTA — how do you check the code actually does that?"
- "How would you design an agent that audits paper-code consistency?"
- "What do you do when you can't reproduce a published number?"

### What it tests
A systematic method for checking paper claims against public code — inventoried claims, tiered verification, severity-graded findings — not just "run it and see."

---

## Answer

### Concept
A paper-code audit answers one question: **does the public code actually produce the paper's headline claims?** You extract every falsifiable claim from the paper (numbers in tables, algorithm steps, hyperparameters, data handling), map each claim to the code unit that should implement it, verify each mapping at the cheapest tier that can falsify it, and report findings graded by severity — from result-invalidating blockers down to cosmetic drift. The output is a verdict (reproduced / reproduced-with-caveats / not-reproduced), not a vibe.

### Mechanism

**1. Inventory the claims first — never start by running code.**
Read the paper as a list of checkable assertions, roughly in this order:
- **Headline numbers:** every table/figure value the conclusion depends on (accuracy, ablations, error bars). Usually 5–15 claims carry the whole paper.
- **Method assertions:** the algorithm steps, loss terms, and architectural details a reimplementation would need.
- **Setup assertions:** hyperparameters, seeds, splits, preprocessing, compute budget, baseline configurations.
- **Data assertions:** which dataset version, what filtering, train/test boundaries.

If a claim cannot be falsified ("our method learns richer representations" with no probe attached), mark it non-checkable and move on — auditing prose is how audits burn a week and conclude nothing.

**2. Map claims to code units.**
For each checkable claim, find the code that should realise it: the training entry point, the config file with the hyperparameters, the data loader with the split logic, the eval script behind each table. Produce an explicit mapping — claim 3 (Table 2, row 4) ← `train.py --lr` + `configs/exp2.yaml` — because the most common finding is not wrong code but *missing* code: the ablation script, the preprocessing step, or the baseline config simply is not in the repo.

**3. Verify in cost order — three tiers.**
- **Tier 1, static (minutes):** do the hyperparameters in the config match the paper? Does the eval script compute the reported metric, or a friendlier cousin (accuracy vs F1, test vs validation)? Do the data splits match? Most audits end here — the plurality of real discrepancies are config/metric mismatches visible without running anything.
- **Tier 2, cheap execution (hours):** run eval on released checkpoints, run unit-scale training (one epoch, tiny split), check determinism across two seeds. This falsifies "checkpoint doesn't match table" and "result depends on an undisclosed seed."
- **Tier 3, full rerun (days, budgeted):** reproduce the headline number end-to-end in a pinned environment. Reserve for claims that survived tiers 1–2 and actually matter to your decision. A full rerun of every ablation is almost never worth it — reproduce the load-bearing number, spot-check the rest.

**4. Grade every finding by severity.**
- **Blocker (result-invalidating):** headline number unreproducible within error bars, critical code missing, test-set leakage, baseline misconfigured so the comparison is void. One blocker fails the audit.
- **Major (interpretation-changing):** undisclosed hyperparameter differences, evaluation on validation instead of test, missing ablations that the conclusion leans on. Reproduced-with-caveats territory.
- **Minor (cosmetic):** docstring drift, dead flags, renamed configs, README rot. Note and move on — drowning the report in minors is how real blockers get ignored.

**5. Deliver a verdict with a reproduction package.**
The report states the verdict up front, lists findings by severity with claim↔code pointers, and pins the environment (Docker image or lockfile, GPU model, library versions, seeds, dataset checksums) so the next person reruns your audit rather than re-deriving it.

### Example / Tradeoff

**A worked miniature:** a paper claims 82.4% on a benchmark (Table 1) with learning rate 3e-5 ( §4). Tier 1 finds `configs/main.yaml` sets `lr: 5e-5` — Major on its own. Tier 2 evaluates the released checkpoint: 81.1% ± 0.3 over three seeds — the headline number sits outside error bars, and the eval script reports test accuracy while the paper's wording suggests the hidden split — Blocker. Verdict: not-reproduced, two findings, total cost one afternoon. The full rerun was never needed; the audit died honestly at tier 2.

**The tradeoff is audit depth versus decision value.** A tier-3 rerun of everything costs days of GPU time and usually confirms what tier 1 already showed. The practical allocation: tier 1 over all claims (cheap, highest hit rate), tier 2 on the load-bearing numbers, tier 3 only when you are about to invest months building on the result. An audit that costs more than the decision it informs is theater.

**Real tools:** arXiv source for the exact version under audit, GitHub for the code snapshot (pin the commit — repos drift after publication), Docker/conda lockfiles for the environment, Papers With Code for independent numbers, dataset checksums (SHA-256) for split integrity.

---

## Verbal script

**Opening (30s):**
"I'd run a paper-code audit: extract every falsifiable claim from the paper, map each one to the code unit that should implement it, verify each mapping at the cheapest tier that can falsify it, and report severity-graded findings with a verdict — reproduced, reproduced-with-caveats, or not-reproduced. The key insight is that most discrepancies die at the static tier, so I never start by running code."

**Core explanation (2–3 min):**
"First I inventory the claims — headline table numbers, method assertions, hyperparameters and splits, data handling — and I mark anything non-falsifiable as out of scope, because auditing prose burns a week and concludes nothing. Then I map each checkable claim to code: the training entry point, the config, the data loader, the eval script behind each table. The most common finding is missing code — the ablation script or the preprocessing step just isn't in the repo.

Verification runs in cost order. Tier one is static: do the configs match the paper, does the eval script compute the reported metric or a friendlier cousin, are the splits what they claim. Most real discrepancies — config mismatches, test-versus-validation reporting — are visible here without running anything. Tier two is cheap execution: eval the released checkpoint, run a unit-scale training, check a second seed. Tier three is the full end-to-end rerun, reserved for the load-bearing number when I'm about to invest months building on it.

Every finding gets a severity: blockers invalidate the result — unreproducible headline number, missing critical code, test leakage, void baselines. Majors change the interpretation. Minors are docstring drift and README rot, noted but never allowed to drown the blockers. And the report pins the full environment so the next person reruns my audit instead of re-deriving it."

**Tradeoff / production angle (1 min):**
"The tradeoff is audit depth versus decision value. Tier one over all claims is cheap and has the highest hit rate; tier two covers the numbers that matter; tier three only when the downstream investment justifies GPU-days. In an agentic research pipeline I'd automate exactly this shape — a researcher agent extracts claims, a verifier agent runs the tiered checks, a reviewer agent grades severity — which is also why I'd want the audit to emit structured findings, not prose."

**Wrap-up (30s):**
"So: inventory falsifiable claims, map them to code, verify static-first in cost order, grade blockers versus majors versus minors, and verdict up front with a pinned reproduction package. One honest afternoon at tiers one and two beats a GPU-week that confirms what the configs already said."

---

## Pitfalls

- **Mistake:** "Code is on GitHub, so the paper is reproducible" — **Better:** Code existence proves nothing. Check the commit is pinned, the configs match the paper's hyperparameters, the eval script computes the reported metric, and the missing pieces (ablations, preprocessing, baselines) are actually present. Most audit failures are missing-or-mismatched, not missing-entirely.
- **Mistake:** Starting with a full end-to-end rerun — **Better:** Verify static-first. A config mismatch or a test-vs-validation switch is visible in minutes and falsifies the claim just as decisively as a week of GPU time. Reserve full reruns for load-bearing numbers that survived the cheap tiers.
- **Mistake:** Auditing the paper's prose instead of its numbers ("the motivation seems sound") — **Better:** Only falsifiable claims go in the inventory. Untestable assertions get marked non-checkable, not debated. An audit of opinions is a book review.
- **Mistake:** Reporting every nit at equal weight — **Better:** Grade by severity and lead with the verdict. A report where docstring drift sits next to test-set leakage teaches the reader to ignore both. One blocker fails the audit; minors get an appendix line.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q: Agent reviewing code and suggesting improvements?](03-038-agent-reviewing-code-and-suggesting-improvements.md) | prerequisite — the code-reading agent pattern this audit specialises to papers |
| [Q17: Golden dataset for evaluation and regression testing?](05-017-golden-dataset-for-evaluation-and-regression-testing.md) | related — the pinned claim↔code mapping plays the same role as a golden set: a regression gate on future versions |
| [Q10: Testing strategies for non-deterministic outputs?](05-010-testing-strategies-for-non-deterministic-outputs.md) | related — seed-sensitivity and error-bar checks behind the tier-2 verdict |

---

## One-liner recall

> Audit paper code by inventorying falsifiable claims, mapping each to its code unit, verifying static-first in cost order (configs/metrics → cheap execution → full rerun only for load-bearing numbers), grading blockers vs majors vs minors, and leading with a reproduced / caveats / not-reproduced verdict plus a pinned reproduction package.
