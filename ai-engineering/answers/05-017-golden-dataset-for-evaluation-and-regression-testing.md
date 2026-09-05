# Golden dataset for evaluation and regression testing?

**Category:** 05-evaluation-metrics
**Question #:** 017
**Source section:** §5 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
Interviewers want to know whether you have a rigorous, production-grade eval discipline or rely on "vibes." A golden dataset is the anchor that converts subjective human judgment into a repeatable, automatable CI gate — without it, prompt changes and model upgrades ship blind. This question probes whether you can build and maintain a living evaluation system, not just run RAGAS once.

### Trigger phrases
- "How do you know your prompt change actually improved things?"
- "What's your regression testing strategy for LLM outputs?"
- "How do you prevent quality regressions when you swap models or update prompts?"
- "Do you have a formal eval framework, or is it vibes-based?"

### What it tests
Ability to design a systematic, reproducible LLM evaluation pipeline that guards against regressions and supports continuous improvement.

---

## Answer

### Concept
A golden dataset is a curated, human-verified set of (input, expected output) pairs that defines the quality bar for a system. It acts as the ground truth for automated offline evaluation and CI regression gating — the LLM equivalent of a unit test suite. Without one, every model/prompt change is a leap of faith.

### Mechanism

**1. Construction — sourcing and labeling:**
- Pull 150–300 real production queries (random sample + stratified by topic/difficulty/intent).
- Include hard cases: edge cases, adversarial queries, known failure modes, and low-confidence examples from production logs.
- Label by domain experts or annotators: for RAG QA, each example has (query, ideal answer, acceptable source docs); for chatbots, labels include (turn, ideal response, pass/fail rubric).
- For RAG pipelines: label both retrieval (which chunk is relevant) and generation (what the ideal answer is).

**2. Metrics computed against the golden set:**
- **Retrieval layer:** Recall@5, MRR, NDCG on the labeled relevant chunks.
- **Generation layer:** RAGAS Faithfulness (is the answer grounded in retrieved context?), Answer Relevancy (does it address the query?), BERTScore F1 for paraphrase similarity.
- **LLM-as-judge:** a frontier model grades each response on a 1–5 rubric for accuracy, completeness, and tone; cheaper than humans at scale.

**3. Regression gate in CI:**
- Run the eval suite on every PR that touches prompts, model version, chunking, or retrieval config.
- Thresholds: Faithfulness ≥ 0.85, Recall@5 ≥ 0.70, LLM-judge average ≥ 4.0/5.0.
- Block merge if any threshold regresses by > 3% relative to the `main` branch baseline.

**4. Dataset refresh cadence:**
- Monthly: ingest new production queries (especially thumbs-down and escalations), re-label with annotators.
- On distribution shift: trigger a refresh when production query distribution diverges > 10% (measure with JS divergence on TF-IDF or topic cluster proportions).
- Version the dataset (e.g., `golden-v1.3.jsonl` in Git LFS or S3) so eval history is reproducible.

### Example / Tradeoff
At a customer support RAG system (1M queries/day), we maintained a 250-item golden dataset seeded from production thumbs-downs and weekly annotator sessions. Every prompt change ran the eval in CI (~4 min with a small fast model as judge). When we switched from `text-embedding-ada-002` to `text-embedding-3-small`, the golden set flagged a 6-point Recall@5 drop before it reached production — we fixed the chunking overlap and the regression cleared. Without the golden dataset, that change would have shipped and degraded deflection rate silently.

**Key tradeoffs:**
- **Size vs coverage:** 100 examples runs in 2 min but may miss tail distributions; 500+ examples is thorough but adds ~20 min to CI. Start at 150–250, grow to 400+ over time.
- **Static vs dynamic:** Static golden sets are reproducible but go stale; dynamic refresh catches distribution shift but risks label inconsistency — version everything.
- **LLM-judge cost:** a frontier model judge on 250 examples costs ~$0.50/run — cheap for a daily CI gate; use a small fast model for routine eval and escalate to a frontier model for final pre-release runs.
- **Human vs automated labels:** Human labels are ground truth but expensive (~$1–5/example); LLM-generated labels are cheap but risk circular validation (the same model grades itself). Use humans for seed labels, LLM-judge for scale.

---

## Verbal script

**Opening (30s):**
"A golden dataset is essentially a test suite for LLM behavior — without one, you're shipping changes based on gut feel. I'd build it as a curated, versioned set of (input, expected output) pairs that runs in CI on every relevant change and blocks merge if quality regresses beyond a threshold."

**Core explanation (2–3 min):**
"I'd start by pulling 150–300 real production queries — random sample plus a deliberate oversample of hard cases: edge cases, known failures, and thumbs-down examples from user feedback. Then I'd get domain experts to label ideal answers and, for a RAG system, which chunks are relevant.

Against that golden set, I'd compute three layers of metrics: retrieval quality (Recall@5, NDCG on labeled relevant chunks), generation quality (RAGAS Faithfulness and Answer Relevancy), and an LLM-as-judge score on a 1–5 rubric for accuracy and completeness. I'd run this in CI — GitHub Actions or similar — so every PR that touches a prompt, model version, or retrieval config gets gated. Thresholds look like Faithfulness ≥ 0.85, Recall@5 ≥ 0.70, and I block merge on any > 3% relative regression.

For maintenance, I'd refresh monthly — pulling new production queries, especially from the thumbs-down stream and human escalations — and version the dataset in Git LFS or S3 so eval history is fully reproducible."

**Tradeoff / production angle (1 min):**
"The key tensions are size vs CI speed — I start at 150–250 examples to keep it under 5 minutes, then grow to 400+ as the system matures. Static golden sets are reproducible but go stale as distribution shifts; I address that with JS divergence monitoring on query topics and trigger a refresh when it exceeds 10%. For the judge model, I use a small fast model for routine CI runs and reserve a frontier model for final pre-release validation to control cost — roughly $0.50/run vs $2/run at 250 examples."

**Wrap-up (30s):**
"The bottom line: a golden dataset turns subjective 'does it feel better?' into a hard, automatable regression gate. It's the single most impactful thing I've added to an LLM evaluation pipeline. Happy to go deeper on construction methodology or the CI integration."

---

## Pitfalls

- **Mistake:** Saying "we use RAGAS to evaluate" without mentioning a static labeled ground truth — **Better:** Explain that RAGAS metrics need a golden set with human-labeled ideal answers to be meaningful regression anchors; otherwise each run scores against itself and regressions go undetected.
- **Mistake:** Building the golden set from synthetic or LLM-generated data only — **Better:** Seed the golden set with real production queries (especially failures/thumbs-downs) and human annotations; LLM-generated examples miss the actual distribution and can create circular validation loops.
- **Mistake:** Treating the golden dataset as static forever — **Better:** Describe a monthly refresh cadence, distribution-shift monitoring (JS divergence), and versioning (e.g., `golden-v1.3.jsonl`) so historical eval results remain reproducible and the dataset stays aligned with production.
- **Mistake:** Skipping the retrieval eval layer and only evaluating generation — **Better:** Label relevant chunks per query and compute Recall@5/NDCG; generation metrics (Faithfulness) can look fine even when retrieval is silently degrading if the LLM happens to answer correctly from the wrong context.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q16: "Vibes-based" eval vs formal eval framework](05-016-vibes-based-eval-vs-formal-eval-framework.md) | Prerequisite — golden dataset is the cornerstone of a formal eval framework |
| [Q3: Detect and mitigate hallucinations in production](05-003-detect-and-mitigate-hallucinations-in-production.md) | The production monitoring layer that the golden dataset regression gate feeds into |
| [Q21: Test new model before full deployment — canary, interleaved, shadow](05-021-test-new-model-before-full-deployment-canary-interleaved-sha.md) | Follow-up — golden dataset offline gate is step 1; canary/shadow is step 2 in the deployment pipeline |

---

## One-liner recall

> A golden dataset is 150–300 human-labeled (query, ideal answer, relevant-chunk) pairs versioned in CI, used to gate every prompt/model/retrieval change on hard thresholds (Faithfulness ≥ 0.85, Recall@5 ≥ 0.70) and refreshed monthly from production thumbs-downs.
