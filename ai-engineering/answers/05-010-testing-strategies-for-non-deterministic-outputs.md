# Testing strategies for non-deterministic outputs

**Category:** 05-evaluation-metrics
**Question #:** 010
**Source section:** §5 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
LLM outputs are stochastic — the same prompt can return different valid answers on every call. Interviewers want to know whether you have moved past "assert output == expected_string" and built a principled testing framework that can catch regressions without false-positives from benign paraphrase variation. This probes production engineering discipline and eval maturity.

### Trigger phrases
- "How do you test an LLM pipeline when the output changes every run?"
- "How do you catch regressions in a generative system?"
- "What's your testing strategy for non-deterministic AI outputs?"

### What it tests
Ability to design a layered eval framework that distinguishes acceptable output variation from real regressions — using property-based assertions, statistical thresholds, LLM-as-judge scoring, and golden dataset regression gates.

---

## Answer

### Concept
Classical unit tests (exact string equality) break immediately for LLM outputs because two semantically identical answers may differ in wording. The fix is a **property-based testing approach**: instead of asserting what the output *is*, assert what it *must have* (format, length, tone, factual entailment, absence of forbidden phrases) and score quality statistically over a fixed golden dataset.

### Mechanism

**Five-layer testing stack:**

1. **Structural / property assertions (unit layer)**
   - Assert output schema, length bounds, format constraints — things that must always be true regardless of wording.
   - Examples: `assert is_valid_json(output)`, `assert 50 < len(output) < 800`, `assert "I don't know" not in output if context_provided`.
   - Run at T=0 for determinism in CI; these are fast (<1s per case).

2. **Semantic similarity (regression layer)**
   - Compare new output to a reference golden answer using cosine similarity on embeddings (e.g. `text-embedding-3-small`).
   - Gate: cosine ≥ 0.85 → pass; < 0.85 → flag for human review.
   - Paraphrase variation typically lands at 0.93–0.97; genuine regression (wrong fact, wrong entity) drops to 0.60–0.75.

3. **LLM-as-judge (quality layer)**
   - Prompt a capable judge model (a frontier model) with a rubric: correctness, faithfulness, completeness (1–5 scale or pass/fail).
   - Sample 5–10% of live traffic plus 100% of golden dataset in nightly batch.
   - Gate: mean score ≥ 4.0 on golden set; alert if score drops > 0.3 from baseline.
   - Tools: `deepeval` DeepEval framework, `promptfoo` for CI harness, `RAGAS` for RAG-specific dimensions.

4. **Statistical assertion over a golden dataset**
   - Maintain 100–500 `(input, expected_properties, reference_answer)` triples.
   - Run the full suite on every model/prompt change; track pass-rate over time, not individual test outcomes.
   - Key metrics: pass-rate@k (run k times, at least one pass for correct tasks), mean RAGAS Faithfulness, mean RAGAS Answer Relevancy.
   - Gate: pass-rate ≥ 95% before deployment promotion.

5. **Shadow / canary in production**
   - Route 5% of live traffic to the new model; compare LLM-judge scores and business metrics (CSAT, thumbs-down) to the control cohort.
   - Auto-rollback if thumbs-down rate rises > 2pp or p95 latency exceeds SLO.

### Example / Tradeoff

**Customer support chatbot (a small fast model, RAG-backed):**
- CI suite: 200 golden (question, context, properties) triples via `promptfoo` — runs in ~4 min, gates PR merge.
- Properties checked: JSON schema valid, answer length 50–600 chars, ≥1 citation present, no fabricated policy numbers (regex check against allowed SKU list).
- Semantic cosine gate (0.85) catches word-salad regressions without penalising paraphrase.
- Nightly: a frontier model judge on 100% of golden set → Faithfulness and Correctness dashboards in Datadog.
- Result: 3 prompt regressions caught pre-deploy over 6 months; 0 customer-facing incidents from prompt changes.

**Tradeoff — T=0 vs sampling:**
- T=0 eliminates within-test variance (CI is stable); sampling (T=0.7) requires running each test 3–5× and checking majority-pass — more realistic but 3–5× slower and more expensive.
- Recommendation: use T=0 in CI for speed, run sampled tests (T=0.7, k=5) monthly for robustness measurement.

---

## Verbal script

**Opening (30s):**
"Testing non-deterministic outputs is one of the most under-solved problems in LLM engineering. The mistake I see most often is teams writing unit tests that assert exact output strings — those break on every model update even when the answer is correct. I'd replace that with a five-layer strategy: property assertions, semantic similarity gating, LLM-as-judge scoring, golden dataset pass-rate tracking, and shadow/canary in production."

**Core explanation (2–3 min):**
"The first layer is structural property assertions — things that must always be true regardless of wording. For a RAG chatbot that might be: output is valid JSON, length is between 50 and 800 characters, at least one citation present, no hallucinated policy IDs. These are fast and deterministic — I run them at temperature zero in CI.

The second layer is semantic similarity regression. I embed both the new output and a stored reference answer with `text-embedding-3-small` and compute cosine similarity. Paraphrase variation from the same correct answer typically lands at 0.93–0.97; genuine regression — wrong fact, wrong entity — drops to 0.60–0.75. So a threshold of 0.85 cleanly separates benign variation from real errors.

The third layer is LLM-as-judge. I prompt a frontier model with a structured rubric: correctness, faithfulness to context, completeness — each scored 1–5. I run this on 100% of my golden dataset nightly and on a 5–10% sample of live traffic. A drop of 0.3 in mean score from baseline triggers a Slack alert.

Tying it all together is a golden dataset of 100–500 `(input, expected properties, reference answer)` triples. Every prompt or model change runs the full suite. I track pass-rate, not individual test outcomes, because individual runs can flake. A gate of 95% pass-rate blocks the deploy.

Finally, in production I use shadow or canary routing — 5% of traffic to the new version — with auto-rollback if thumbs-down rate rises more than 2 percentage points."

**Tradeoff / production angle (1 min):**
"The main tension is T=0 vs sampled testing. T=0 makes CI stable and cheap — each test runs once and the result is deterministic. But it misses variance that users actually see. Sampled testing at T=0.7, run k=5 times per case, gives a more honest picture but is 5× slower and more expensive. My pattern: T=0 in CI for fast gate, sampled monthly for robustness audit. LLM-as-judge is the other cost tension — it adds ~$0.002 per golden case with a frontier model, so 500 cases is $1/run, which is fine nightly but expensive if you run it on every PR commit."

**Wrap-up (30s):**
"So the key insight is: don't test for exact output equality — test for properties, semantic proximity, and quality scores statistically over a golden dataset. That gives you real regression signal without penalising benign paraphrase variation. Happy to go deeper on golden dataset curation or LLM-judge rubric design."

---

## Pitfalls

- **Mistake:** Writing unit tests with `assert output == "expected string"` and calling that a test suite — **Better:** Use property-based assertions (schema, length, presence of required fields) plus semantic cosine gating; exact string equality fails on every model update even when the answer is correct.
- **Mistake:** Running all tests at the default sampling temperature (T=0.7) and treating a single pass/fail as conclusive — **Better:** Use T=0 for CI determinism, or run k=3–5 samples and gate on majority-pass; single-sample tests at high temperature have high false-positive rates.
- **Mistake:** Skipping the golden dataset entirely and relying only on LLM-as-judge on live traffic — **Better:** Maintain a curated golden set with expected properties so you can gate deploys *before* they reach users; live-only eval discovers regressions too late.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q8: Measure hallucination rate in production](05-008-measure-hallucination-rate-in-production.md) | Same async eval pipeline — NLI + LLM-judge + golden dataset |
| [Q17: Golden dataset for evaluation and regression testing](05-017-golden-dataset-for-evaluation-and-regression-testing.md) | Deep dive on building the golden set used in this strategy |
| [Q21: Test new model before full deployment — canary, interleaved, shadow](05-021-test-new-model-before-full-deployment-canary-interleaved-sha.md) | Production deployment layer of this same framework |

---

## One-liner recall

> Test non-deterministic outputs with property assertions (schema/length/format) at T=0, semantic cosine gating (≥0.85) for regression, LLM-as-judge scoring on a golden dataset, and canary/shadow routing with auto-rollback in production — never exact string equality.
