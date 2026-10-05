# How do you design an LLM-as-reviewer rubric for papers?

**Category:** 05-evaluation-metrics
**Question #:** 027
**Source section:** §5 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
The interviewer wants to know whether you can turn the famously subjective act of peer review into a calibrated measurement instrument — the same skill behind LLM-as-a-judge, golden datasets, and eval rubrics generally. Weak candidates say "I'd ask the model to rate the paper 1–10"; strong candidates decompose quality into scored dimensions with anchored scales, require evidence for every score, calibrate against human judgments, and emit a revision plan rather than a number. If you can design a reviewer, you can design any judge.

### Trigger phrases
- "How would you use an LLM to peer-review papers?"
- "Design a rubric for reviewing model outputs at scale."
- "How do you stop an LLM judge from giving everything a 7/10?"
- "Our reviewers disagree — how do you make evaluation consistent?"

### What it tests
Whether you can build a calibrated review instrument — anchored dimensions, evidence-gated scores, bias controls, human agreement measurement — instead of a vibes-based rating prompt.

---

## Answer

### Concept
An LLM-as-reviewer rubric is **a scoring instrument, not a prompt**: a fixed set of quality dimensions, each with an anchored 1–5 scale (every level described in observable terms), an evidence rule (no score without a quoted passage or a missing-artefact pointer), bias controls (order shuffling, independent scoring passes, length normalisation), and a revision-plan output (each weakness paired with the concrete experiment or rewrite that would fix it). Calibrate it against human reviewers on a golden set until agreement (quadratic-weighted kappa or pairwise concordance) clears your bar — then it is a measurement device; before that it is an opinion generator.

### Mechanism

**1. Fix the dimensions — seven cover nearly every paper.**
- **Novelty:** is the contribution new relative to cited prior work, or a relabelling? (Requires a prior-art check, not just the paper's own related-work section.)
- **Technical soundness:** do the method, proofs, and derivations hold? Are assumptions stated?
- **Empirical rigour:** ablations isolating the claim, error bars over multiple seeds, baselines configured fairly (same compute, same tuning budget).
- **Reproducibility:** code, configs, data versions, and environment pinned enough to rerun (pairs with the paper-code audit).
- **Clarity:** could a competent reader reimplement from the text alone?
- **Significance:** does the result change what anyone should do next?
- **Ethics / limitations:** risks disclosed, failure modes and scope limits stated honestly.

Seven is a ceiling, not a floor — fewer, sharper dimensions beat a twelve-item checklist the judge applies sloppily.

**2. Anchor every scale level with observable criteria.**
A bare "1–5" collapses to 3s and 4s. Each level needs a behavioural description: e.g. for empirical rigour, 5 = ablations isolate every claim + ≥3 seeds with error bars + fairly-tuned baselines; 3 = main ablations present, single seed, baselines plausible; 1 = no ablations, numbers without variance, baselines missing or strawmen. Anchors are what make two runs — and a human and a model — mean the same thing by "4."

**3. Gate every score on evidence.**
The reviewer must quote the passage (or name the missing artefact) behind each score: "Soundness 2 — Lemma 3 assumes i.i.d. batches but §4 trains with correlated replay, p.6." Scores without citations are discarded by the harness, not down-weighted. This single rule eliminates the largest failure mode of LLM review — confident, fluent, evidence-free praise — and makes disagreements adjudicable: two reviewers citing different passages can be reconciled; two bare numbers cannot.

**4. Control judge biases explicitly.**
- **Leniency / central tendency:** models over-award 3–4. Counter with anchored scales plus a calibration set of known-accept / known-reject papers that pins the ends.
- **Verbosity bias:** longer papers read as more thorough. Normalise by asking for the evidence quote first and the score second, and by scoring concision inside Clarity.
- **Position and self-preference:** shuffle review order across runs; never let the author's own model family be the sole judge of its lineage without a human tiebreak.
- **Prompt-sensitivity:** freeze the rubric text under version control and re-run calibration on any edit — a reworded anchor is a new instrument.

**5. Emit a revision plan, not just a verdict.**
Each scored weakness pairs with the smallest fix that would raise it: "add the no-replay ablation (est. 1 GPU-day)", "report 3-seed variance for Table 2", "tune the baseline's learning rate before claiming SOTA." The output format is decision-ready: per-dimension score + evidence + fix, then an overall recommendation (accept / revise / reject) derived from the dimensions by a stated rule — never a free-floating number the reader must trust.

**6. Calibrate against humans before trusting it.**
Hold out a golden set of ~50 papers with expert reviews. Measure agreement per dimension (quadratic-weighted kappa for ordinal scales, pairwise concordance for accept/reject) and iterate the anchors until the model clears your bar — typically kappa ≥ 0.6 per load-bearing dimension. Below that, the rubric is a triage assistant (flag papers for human attention), not a decision-maker. Report the agreement number alongside every deployment; a judge whose calibration you cannot quote is uncalibrated.

### Example / Tradeoff

**A miniature calibration story:** v1 of a soundness dimension ("rate correctness 1–5") agreed with experts at kappa 0.31 — the model gave 4s to papers with impressive-looking theorems it had not checked. V2 anchored each level to checkable artefacts (proofs complete / assumptions flagged / derivations sketched-only) and added the evidence-quote gate; agreement rose to 0.64. The prompt barely changed — the instrument did. That is the point to make in the interview: calibration lives in anchors and evidence rules, not in cleverer wording.

**The tradeoff is automation versus authority.** A calibrated rubric triages hundreds of submissions (workshop pre-screening, internal paper clubs, agent-generated literature reviews) at near-zero marginal cost — but it should not be the final authority on accept/reject, because its failure modes (fluent leniency, missed deep flaws) concentrate exactly where stakes are highest. The practical deployment: model reviews everything, humans decide the borderline and audit a sample of the clears. Cost scales with submissions; authority stays with people.

**Real tools:** LLM-judge harnesses (promptfoo, RAGAS-style rubric scorers) for the plumbing, arXiv/OpenAlex APIs for the corpus and prior-art checks, DeBERTa-NLI or citation-resolution for the evidence behind soundness claims, Cohen's kappa / concordance metrics for calibration, human expert panels for the golden set.

---

## Verbal script

**Opening (30s):**
"I'd build a scoring instrument, not a prompt: fixed quality dimensions with anchored one-to-five scales, an evidence rule that discards any score without a quoted passage, explicit bias controls, and a revision-plan output. Then I'd calibrate it against expert reviewers on a golden set until per-dimension agreement clears the bar — before that it's an opinion generator, after that it's a measurement device."

**Core explanation (2–3 min):**
"I'd fix about seven dimensions — novelty, soundness, empirical rigour, reproducibility, clarity, significance, and ethics — because fewer sharp dimensions beat a twelve-item checklist the judge applies sloppily. Every scale level gets an observable anchor: for empirical rigour, a five means ablations isolate every claim with multi-seed error bars and fairly-tuned baselines, a three means main ablations with a single seed, a one means no ablations and no variance. Anchors are what make a human and a model mean the same thing by 'four.'

Every score must cite evidence — quote the passage or name the missing artefact — and the harness discards scores without it. That kills the biggest failure mode, which is fluent evidence-free praise, and it makes disagreements adjudicable. Then bias controls: anchored scales plus known-accept and known-reject papers to pin the ends against leniency, evidence-before-score ordering against verbosity bias, order shuffling and model-family rotation, and the rubric text version-controlled with recalibration on every edit.

The output is a revision plan, not a number — each weakness paired with the smallest fix that raises it, plus an overall recommendation derived from the dimensions by a stated rule."

**Tradeoff / production angle (1 min):**
"The tradeoff is automation versus authority. A calibrated rubric triages hundreds of submissions at near-zero marginal cost, but it must not be the final authority, because its failures concentrate where stakes are highest. So the model reviews everything, humans decide the borderline and audit a sample of the clears. And I'd quote the calibration number — typically kappa above point-six per load-bearing dimension — alongside every deployment, because a judge whose agreement you can't state is uncalibrated."

**Wrap-up (30s):**
"So: anchored dimensions, evidence-gated scores, bias controls, revision plans, human calibration with a reported kappa. The interview one-liner is that calibration lives in anchors and evidence rules, not in cleverer prompt wording."

---

## Pitfalls

- **Mistake:** "Rate this paper 1–10 and explain" — **Better:** Decompose into dimensions with anchored scales and evidence gates. A single free number collapses to lenient 7s, cannot be adjudicated, and teaches you nothing about what to fix.
- **Mistake:** Trusting the judge's fluency as accuracy — praising "rigorous ablations" that don't exist — **Better:** The evidence-quote gate: no citation, no score. Fluency is the failure mode, not the signal; design the harness to discard what it cannot ground.
- **Mistake:** Deploying without a human-agreement number — **Better:** Calibrate on ~50 expert-reviewed papers and report kappa per dimension. Below ~0.6 the rubric is triage assistance, not a decision-maker. "The LLM agrees with reviewers" without a statistic is vibes-based eval of your eval.
- **Mistake:** Letting the rubric drift — rewording anchors or swapping judge models without recalibration — **Better:** Version-control the rubric text and re-run the golden set on any change. A reworded anchor is a new instrument; judge-model swaps silently shift leniency. Treat the rubric like a model artefact with its own regression suite.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q26: How do you audit a paper's code for reproducibility?](05-026-paper-code-audit-reproducibility-check.md) | prerequisite — the reproducibility dimension scored here is audited there |
| [Q16: "Vibes-based" eval vs formal eval framework?](05-016-vibes-based-eval-vs-formal-eval-framework.md) | same concept — anchored rubrics plus golden-set calibration are the formal framework |
| [Q1: What metrics for benchmarking LLM performance?](05-001-what-metrics-for-benchmarking-llm-performance.md) | related — judge-bias controls (position, verbosity, self-preference) apply to both |

---

## One-liner recall

> Review papers with an instrument, not a prompt: anchored 1–5 dimensions (novelty, soundness, rigour, reproducibility, clarity, significance, ethics), evidence-quote-gated scores, bias controls (calibration papers, shuffling, versioned rubric), revision-plan output, and human agreement (kappa ≥ 0.6) quoted before trusting it — automate triage, keep authority with people.
