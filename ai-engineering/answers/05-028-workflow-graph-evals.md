# How do you evaluate a fixed workflow graph with frontier-reference probabilities?

**Category:** 05-evaluation-metrics
**Question #:** 028
**Source section:** §5 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
Golden datasets with string-match grading work when outputs are short and canonical — they collapse the moment your system is a fixed multi-step workflow (route → retrieve → decide → act) whose intermediate nodes emit probabilities. The interviewer is probing whether you can design an eval for *distributions over a graph*, not strings: using strong reference models as probability ground truth, comparing full output distributions, and reporting cost/quality Pareto frontiers instead of single accuracy numbers. Senior candidates also know exactly where this design is legitimate and where it is circular reasoning dressed up as rigor.

### Trigger phrases
- "How do you eval a multi-step agent workflow, not just a single prompt?"
- "String-match grading fails on our pipeline — what would you replace it with?"
- "Can you use a stronger model as ground truth for evaluation?"
- "How do you report the cost/quality tradeoff of a workflow change?"

### What it tests
Eval design for probabilistic multi-node systems — reference-model ground truth, distribution comparison, and Pareto reporting — plus the judgment to distinguish legitimate reference evals from circular chat-quality judging.

---

## Answer

### Concept
A **workflow-graph eval** treats the system as a fixed compute graph (bounded nodes, typed edges — routing, retrieval, decision, action) and evaluates *node-level output distributions* against a **reference distribution** produced by strong frontier models, rather than grading final strings. The reference ground truth for each eval case is typically the **mean probability vector of two independent frontier models** — averaging two vendors cancels single-model style bias the way one judge's taste would otherwise dominate. Node outputs are compared as distributions (KL divergence, Brier/ECE per node), and system changes are reported as **Pareto cost/quality points** (quality delta vs $/1K runs and p95 latency), never as a lone accuracy number.

### Mechanism

**Eval design (four steps):**
1. **Freeze the graph and instrument the nodes.** Fix prompts, routing rules, and retrieval depth so the only moving part is the change under test. Log per-node outputs with probabilities: router's class distribution, decision head's confidence, retrieval scores. Without node-level logging you can only grade final strings — which is the failure mode this design replaces.
2. **Build the reference distribution.** For each golden case, query two frontier models (different vendors/labs) with a reference prompt that exposes their full probability over the same typed outcome space, and take the **mean of the two probability vectors** as ground truth. Vendor names never enter the eval spec — the pattern is "mean of two frontier references," not any specific model, so the eval survives model deprecations.
3. **Compare distributions, not strings.** Per node: KL divergence or total-variation distance between system and reference distributions for shape; Brier score / ECE where the node emits confidences consumed downstream. A node that picks the right label with garbage probabilities scores well on string-match and badly here — which is precisely correct, because the downstream node consumes the probability.
4. **Report Pareto, gate on dominance.** Every candidate change gets a point: (Δquality vs reference, $/1K eval runs, p95 added latency). Ship only Pareto improvements or explicitly-priced tradeoffs ("−0.4% distribution match for −38% cost, approved for the low-risk tier"). Single accuracy numbers are banned from the report because they hide both cost and calibration regressions.

**Worked shape — document triage workflow (route → retrieve → decide):**
Golden set: 300 historical cases with realized outcomes. Reference: mean-of-two-frontier probability over {auto-approve, human-review, auto-deny}. Router node graded by KL vs reference; decision node by Brier on its confidence; end-to-end by expected cost under the business loss matrix (denied-legit vs approved-fraud). A prompt tweak that moves 4% of cases from review to auto-approve with unchanged Brier is a capacity win; the same move with degraded Brier is a risk increase wearing a cost-saving costume — the distribution view tells them apart, string-match does not.

### Example / Tradeoff

**Legitimate vs circular — the boundary that decides seniority:**

| Legitimate reference eval | Circular pseudo-eval |
|---------------------------|----------------------|
| Outcomes are **typed and probabilistic** (class distributions, confidences, rankings over a fixed schema) | Outcomes are **open-ended text** (chat quality, summaries, creative writing) |
| Reference is **two** frontier models averaged (bias cancellation) | Reference is **one** judge model (its style becomes the spec) |
| System under test is **weaker/cheaper** than references (distillation direction) | System under test is **peer-or-stronger** than the judge (judge cannot see the errors) |
| Reference probabilities are **checked against realized outcomes** where logs exist (Brier on history) | No grounding — judge opinion is the only signal, with known self-preference bias |
| Verdict is a **Pareto point** (quality + cost + latency) | Verdict is a **single score** that hides what regressed |

The one-line test: *could the reference be wrong in a way the eval would catch?* If yes (logged outcomes disagree with the reference mean → investigate the reference prompt), the design is sound. If the judge is unfalsifiable by construction, it is circular — fall back to golden-string grading plus human audit on samples.

**Cost discipline:** frontier-reference evals are expensive (two frontier calls per case per run). Standard controls: run the full reference set nightly, run a stratified 10% subset per PR, cache reference vectors by case-hash so unchanged cases cost zero, and distill stable references into frozen golden distributions quarterly so the eval keeps working when vendors deprecate models.

---

## Verbal script

**Opening (30s):**
"I'd start by separating two problems people conflate: grading final strings versus evaluating distributions over a fixed graph. When each node emits probabilities that downstream nodes consume, string-match grading is blind to exactly the failures that matter — right label, garbage confidence. So I evaluate node-level distributions against a reference built from the mean of two frontier models, and I report cost/quality Pareto points."

**Core explanation (2–3 min):**
"The design has four steps. First, freeze the graph and log per-node probabilities — router distributions, decision confidences — because without node logging you're back to string grading. Second, build the reference: two frontier models from different labs, same typed outcome space, take the mean probability vector. Two, not one — averaging cancels single-model style bias, and I never name vendors in the spec so the eval survives deprecations. Third, compare distributions: KL or total variation for shape, Brier or ECE where confidences feed downstream nodes. A node with the right label and wrong probabilities must fail here — downstream consumes the number. Fourth, report Pareto: every change is a point with quality delta, dollars per thousand runs, and p95 latency. Ship dominance or explicitly priced tradeoffs, never a lone accuracy number."

**Tradeoff / production angle (1 min):**
"Two things I'd flag. First, legitimacy: this is sound for typed probabilistic outputs where the system is weaker than the references — distillation direction — and where I can check references against logged outcomes. For open-ended chat with a peer-strength judge it's circular, and I'd say so in the interview: unfalsifiable judge, fall back to golden strings plus human audit. Second, cost: two frontier calls per case is brutal, so nightly full runs, stratified ten percent per PR, cache reference vectors by case hash, and freeze stable references into golden distributions quarterly."

**Wrap-up (30s):**
"So: fixed graph, node distributions, mean-of-two reference, Pareto reporting — legitimate for decision workflows, circular for chat. Happy to go deeper on the distribution metrics or the caching economics."

---

## Pitfalls

- **Mistake:** Using a single judge model and reporting its score as ground truth — **Better:** Average two independent frontier references to cancel style bias, and require the reference to be falsifiable against logged outcomes; a lone judge's taste silently becomes the spec (self-preference bias is well documented).
- **Mistake:** Grading only final strings on a probabilistic workflow — **Better:** Evaluate per-node distributions (KL/Brier/ECE), because downstream nodes consume probabilities — a right-label/wrong-confidence node passes string-match while corrupting every downstream decision.
- **Mistake:** Reporting a single accuracy number for a workflow change — **Better:** Report the Pareto point (quality delta + $/1K runs + p95 latency); accuracy-only reporting hides cost explosions and calibration regressions behind an unchanged headline.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q17: Golden dataset for evaluation and regression testing?](05-017-golden-dataset-for-evaluation-and-regression-testing.md) | Prerequisite — golden-set construction this design builds on |
| [Q21: Test new model before full deployment — canary, interleaved, shadow?](05-021-test-new-model-before-full-deployment-canary-interleaved-sha.md) | Follow-up — staged rollout for a workflow change the eval approved |
| [Q22: Two models, same accuracy, different confidence — which choose? Calibration?](05-022-two-models-same-accuracy-different-confidence-which-choose-c.md) | Same concept — calibration measurement applied per workflow node |

---

## One-liner recall

> For fixed probabilistic workflows, grade per-node distributions (KL/Brier) against the mean of two frontier references — not final strings — and report Pareto cost/quality points; legitimate for typed decision outputs in the distillation direction, circular for open-ended chat judged by a peer.
