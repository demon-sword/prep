# How do you run error analysis on eval failures — from open coding to axial categories?

**Category:** 05-evaluation-metrics
**Question #:** 24
**Source section:** §5 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
An aggregate score (accuracy 82%, faithfulness 0.79) tells you the system is broken but never tells you what to fix. The interviewer is probing whether you have a repeatable discipline for turning a pile of failed eval samples into a ranked list of fixable causes — the skill that separates engineers who improve systems from engineers who stare at dashboards.

### Trigger phrases
- "Your eval came back at 80% — what do you do next?"
- "How do you decide what to fix first?"
- "Walk me through how you'd analyze these failures."

### What it tests
Whether you can convert unstructured failures into countable, actionable categories without fooling yourself.

---

## Answer

### Concept
Error analysis is qualitative coding applied to eval misses: sample 50–100 failures, label each one in the annotator's own words (**open coding**), then group those labels into a small set of mutually exclusive failure axes (**axial coding**) and count. The output is a Pareto of causes — "34% retrieval-miss, 22% judge-error, 18% ambiguous-gold" — each with a named owner and fix.

### Mechanism
1. **Sample, don't census.** Stratify 50–100 failures across slices (task type, cohort, difficulty). Below ~50 the tail buckets are noise; above ~100 you are coding past the point of new categories.
2. **Binary-only rule.** Every sample gets a binary in/out verdict per candidate bucket — never a severity score, never partial credit, never two buckets for one failure. If a failure seems to fit two buckets, the buckets are wrong: split or redefine them until each failure has exactly one home. Binary verdicts are what make the counts honest and the fix-rate math (re-coded after the fix) comparable.
3. **Annotator doctrine, written before anyone touches samples.** Three clauses: (a) judge the output against the ground truth and retrieved context, never what you think the model meant; (b) blind annotators to model/prompt version so the new system gets no benefit of the doubt; (c) every sample double-annotated, disagreements adjudicated by a third read, agreement tracked (Cohen's kappa — below ~0.6 your buckets are undefined, fix the doctrine not the annotators).
4. **Open code first, axial second.** Round one: free-text labels per failure ("answered from parametric memory despite context containing the answer"). Round two: cluster into 4–7 axial buckets with one-sentence definitions and a canonical example each. More than ~7 buckets means you are describing samples, not causes.
5. **Always include the eval itself as a bucket.** Reserve axial slots for judge-error and gold-error (wrong reference, ambiguous question). In generative evals 15–30% of "failures" are measurement failures — fixing the model for those is pure waste.
6. **Attach a fix and a re-measure.** Each bucket gets one intervention (retrieval threshold, prompt constraint, judge swap, gold correction) and the coded sample set is re-run after the fix. A bucket that survives its fix was miscoded — send it back to open coding.

### Example / Tradeoff
RAG support bot, faithfulness eval at 0.78 on 2,000 golden queries. Sampled 80 failures; open coding produced 23 free labels, axial coding collapsed them to five: retrieval-miss (34% — correct chunk ranked below cutoff, fixed by raising top-k 5→8 plus a cosine floor), stale-index (21% — new docs unindexed, fixed operationally not by modeling), judge-error (17% — DeBERTa NLI entailment failing on valid paraphrases, fixed by swapping the judge), ambiguous-gold (12% — two defensible answers, gold corrected), generation-drift (16% — faithful but off-tone). Two prompt/model iterations moved only the last bucket; the headline metric went 0.78 → 0.89 with zero retraining. Concrete tooling: RAGAS `faithfulness` + `context_recall` to pre-split retrieval vs generation before human coding, Label Studio or a spreadsheet for the double-annotate pass, kappa computed in the same notebook that draws the Pareto.

---

## Verbal script

**Opening (30s):**
"I'd start by saying an aggregate score is a smoke alarm, not a diagnosis. My move is always the same: sample the failures, code them into countable buckets, and let the Pareto decide what gets fixed first."

**Core explanation (2–3 min):**
"I pull 50 to 100 failures stratified across task types — enough that the tail buckets stabilize, not so many I'm coding past new categories. Then two passes borrowed from qualitative research. First open coding: each failure gets a free-text label in the annotator's own words. Then axial coding: cluster those into four to seven mutually exclusive buckets with a one-sentence definition and a canonical example each. Two rules keep it honest. The binary-only rule: every sample gets an in-or-out verdict per bucket, no severity scores, no partial credit, and if a failure fits two buckets the buckets are wrong — redefine until each failure has exactly one home. That's what makes the counts and the before-after fix math trustworthy. Second, the annotator doctrine, written before anyone labels: judge the output against ground truth, never model intent; blind annotators to which system version produced it; double-annotate everything with third-read adjudication and track kappa — below about 0.6 the buckets are undefined. And I always reserve buckets for the eval itself: judge-error and gold-error routinely explain 15 to 30 percent of generative 'failures,' and retraining against those is pure waste."

**Tradeoff / production angle (1 min):**
"The tradeoff is coding rigor versus speed — a full double-annotated pass takes a day or two of team time, so for a fast iteration loop I'll single-annotate with a spot-checked adjudication sample and accept wider error bars on small buckets. What I never skip is the binary-only rule, because graded scores during coding are how teams smuggle their preferred conclusion into the Pareto. And buckets rot: after any retrieval, prompt, or judge change, re-run the coded set — a bucket that survives its fix was miscoded."

**Wrap-up (30s):**
"So: sample, open-code, axial-code into binary buckets under a written annotator doctrine, always budget buckets for judge and gold error, and attach one fix plus a re-measure to each bucket. Happy to go deeper — the adjudication workflow, kappa computation, or how RAGAS pre-splits retrieval versus generation before humans touch it."

---

## Pitfalls

- **Mistake:** Averaging failure severities or assigning 1–5 scores per failure instead of binary bucket verdicts — **Better:** Enforce the binary-only rule; one failure, one bucket, in or out — graded coding lets the coder's priors leak into the Pareto and makes before-after comparisons meaningless.
- **Mistake:** Coding failures solo with no doctrine and treating the resulting buckets as ground truth — **Better:** Write the three-clause annotator doctrine first (output-vs-gold, blinded versions, double-annotate plus adjudication) and report kappa alongside the Pareto; low agreement indicts the buckets, not the annotators.
- **Mistake:** Forgetting judge-error and gold-error buckets and attributing every miss to the model — **Better:** Always reserve axial slots for measurement failure; re-examine the judge and the references before scheduling any model work, since 15–30% of generative misses are typically eval artifacts.
- **Mistake:** Producing buckets with no attached fix or re-measure — **Better:** Each bucket ships with exactly one intervention and a re-run of the coded set; descriptive buckets that never drive an experiment are taxonomy for its own sake.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q17: Golden dataset for evaluation and regression testing?](05-017-golden-dataset-for-evaluation-and-regression-testing.md) | Prerequisite — the coded failure sample is drawn from this golden set |
| [Q8: Measure hallucination rate in production?](05-008-measure-hallucination-rate-in-production.md) | Same measurement discipline — production-side bucketing of flagged outputs |
| [Q23: Chatbot accuracy dropped 95% → 80% in six weeks — diagnose before retraining?](05-023-chatbot-accuracy-dropped-95-80-in-six-weeks-diagnose-before.md) | Follow-up — error analysis is the diagnostic core inside that 5-layer framework |

---

## One-liner recall

> Sample 50–100 failures, open-code them into free labels, axial-code into 4–7 binary buckets under a written annotator doctrine — always reserving judge-error and gold-error — then attach one fix and one re-measure per bucket.
