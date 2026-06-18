# Chatbot accuracy dropped 95% → 80% in six weeks — diagnose before retraining?

**Category:** 05-evaluation-metrics
**Question #:** 023
**Source section:** §5 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
This is a production-debugging scenario question. The interviewer wants to see whether you have a systematic, hypothesis-driven diagnostic process or whether you jump straight to retraining (an expensive, slow fix). It probes your understanding of all the ways a live AI system can degrade — data drift, retrieval drift, upstream data changes, prompt/config changes, evaluation drift — and your ability to triage root cause before committing resources.

### Trigger phrases
- "Chatbot accuracy dropped from 95% to 80% over six weeks — how would you diagnose this before retraining?"
- "Your LLM-based system regressed in production — walk me through how you'd debug it."
- "Model performance is declining — what do you check first?"
- "We saw a quality drop in our chatbot over the past month — what's your debugging framework?"

### What it tests
Systematic root-cause analysis across data, retrieval, model, evaluation, and infrastructure layers — without defaulting to "retrain the model."

---

## Answer

### Concept
A 15-point accuracy drop over six weeks almost never requires immediate retraining; it almost always has an identifiable upstream cause. The diagnostic framework is: **blame the data/retrieval pipeline first, the model second, and the eval framework last** — because those are the layers that change most frequently in a live production system.

### Mechanism

Work through five investigation layers in order:

**1. Validate the measurement (Day 1)**
- Check whether the accuracy metric itself changed: new golden dataset version, different eval sample, changed labeling criteria, or different judge model/prompt?
- If accuracy is measured via LLM-as-judge, check for model API version updates that could shift judge calibration.
- Rule-of-thumb: if the drop is correlated with a deployment event, investigate config/prompt changes; if it's a smooth drift over weeks, investigate data.

**2. Check for upstream data drift (Day 1–2)**
- Pull retrieval telemetry: compare cosine similarity score distributions (p50/p95) between six weeks ago and today.
- Check embedding coverage: have new document types or domains appeared in the corpus that weren't in training data for the embedder?
- Check index staleness: did a source system change schema, deprecate fields, or stop syncing?
- Pull topic-model clustering on recent queries vs queries from six weeks ago — has the query distribution shifted?

**3. Audit the knowledge base / RAG pipeline (Day 2–3)**
- Run RAGAS `context_recall` and `faithfulness` on a held-out golden query set from six weeks ago.
  - If `context_recall` drops → retrieval is broken (chunking, index drift, embedding model mismatch).
  - If `context_recall` is fine but `faithfulness` drops → generation is broken (model drift, prompt change, temperature misconfiguration).
- Check for stale or corrupted chunks: run the ingestion CDC lag metric, look for spikes in index_lag_seconds.
- Did any connector (Confluence, Salesforce, etc.) auth token expire or a webhook stop firing?

**4. Isolate model and prompt changes (Day 3–4)**
- Review deployment log for the six-week window: any prompt template changes, model version bumps (gpt-4o-2024-05-13 → gpt-4o-2024-08-06), temperature or top_p tweaks?
- Pin the model version and replay 50 golden queries from the old and new config side-by-side.
- Check token budget: did context length grow past the model's reliable attention window, triggering lost-in-the-middle degradation?

**5. Segment the drop (Day 4–5)**
- Break accuracy by topic cluster, user cohort, language, or question type.
- If only one segment regressed, the cause is domain-specific (e.g., a new product line added to docs without re-embedding, or a regulatory change that made old answers wrong).
- If all segments regressed equally, suspect infrastructure or configuration changes.

**Decision matrix:**

| Root cause | Signal | Fix |
|------------|--------|-----|
| Index staleness / CDC failure | cosine score drops, index_lag spike | Force re-index, fix connector |
| Embedding model mismatch | cosine ≈ 0.5 on known-good queries | Re-embed all docs with current model |
| Prompt / model version change | pinned-version replay recovers accuracy | Roll back or re-tune prompt |
| Query distribution shift | topic drift in clustering | Add new training queries, expand golden set |
| Eval framework change | score drops on same outputs | Audit judge config, revert eval change |
| Actual model degradation (rare) | all above pass, retrieval fine | Then consider fine-tune or LoRA DPO |

### Example / Tradeoff
**Concrete incident pattern:** A customer-support chatbot dropped from 94% → 78% over five weeks. Root cause turned out to be a Confluence migration that changed page slugs — the CDC connector missed deletions, so chunks from deprecated pages were still being retrieved (stale index). RAGAS `context_recall` on the golden set dropped from 0.81 to 0.54 while `faithfulness` stayed stable, pointing squarely at retrieval. Fix: force full re-index + add index_lag_seconds alert at 60s threshold. Accuracy recovered to 92% without any model changes.

**Tradeoff:** Systematic diagnosis takes 3–5 days; jumping to retraining takes 2–4 weeks, costs GPU budget, and may not fix a data problem. The 5-layer framework almost always finds the root cause faster.

---

## Verbal script

**Opening (30s):**
"I'd treat this as a production incident, not a model problem — at least not yet. A 15-point drop over six weeks has a systematic cause, and my first job is to find it before touching the model. I follow a five-layer debugging framework: validate the measurement, check for data drift, audit the retrieval pipeline, isolate model and prompt changes, and then segment the drop by topic or user cohort."

**Core explanation (2–3 min):**
"First, I validate the measurement itself — it's surprisingly common for the eval framework to change without anyone noticing. A different LLM judge version, a new golden dataset, a changed labeling prompt — any of these can shift the score without the system actually getting worse. I'd replay the exact same 50 golden queries through the old and new eval stack to confirm the drop is real.

Second, I pull retrieval telemetry. I look at cosine similarity score distributions — p50 and p95 — compared to six weeks ago. If scores have dropped, retrieval has degraded. Then I check the knowledge base: did a connector stop syncing? Did a source system migrate schemas? I'd also run RAGAS `context_recall` on the golden set. If `context_recall` falls, the problem is upstream of generation — bad chunking, stale index, or embedding model mismatch. If `context_recall` is fine but `faithfulness` drops, the problem is in generation — likely a prompt or model version change.

Third, I audit the deployment log for the six-week window. Did the prompt template change? Did the API silently bump model versions? Did token budgets grow past the context window, triggering lost-in-the-middle effects?

Fourth, I segment the drop. If only one topic cluster regressed — say, everything about a new product line — the cause is domain-specific: new docs weren't re-embedded, or a regulatory change made old answers wrong. If all segments degraded equally, it's infrastructure or config.

Only if all five layers come back clean do I consider retraining or fine-tuning. In my experience that's the cause maybe 5% of the time."

**Tradeoff / production angle (1 min):**
"The key tradeoff is speed vs cost. Systematic diagnosis takes 3–5 days of engineering time. Jumping to retraining takes 2–4 weeks and GPU budget, and if the root cause is a stale index or a connector failure, retraining won't fix it at all. The 5-layer framework almost always finds the cause in the first two layers — data or retrieval. I've seen cases where the 'accuracy drop' disappeared entirely after reverting an eval judge model version bump. The lesson is: measure your measurement system first."

**Wrap-up (30s):**
"So my framework is: validate the eval, check retrieval health via RAGAS context_recall, audit deployment changes, segment by cohort, and only then consider model-level interventions. Happy to go deeper on any specific layer — retrieval drift signals, RAGAS diagnostic protocol, or how to instrument for faster detection next time."

---

## Pitfalls

- **Mistake:** Immediately suggesting retraining or fine-tuning as the first response — **Better:** Lead with the 5-layer diagnostic framework; retraining is the last resort after ruling out data drift, retrieval failures, eval changes, and configuration changes.
- **Mistake:** Only checking model-level signals (perplexity, loss) while ignoring retrieval telemetry — **Better:** Run RAGAS `context_recall` vs `faithfulness` as the primary split: a `context_recall` drop indicts retrieval; a `faithfulness` drop indicts generation — this distinction immediately halves the search space.
- **Mistake:** Treating all accuracy drops as equivalent — **Better:** Segment by topic cluster, user cohort, or question type first; a segment-specific drop (one product line, one language) points to a domain-specific data or indexing change, not a global model failure.
- **Mistake:** Forgetting to validate the eval framework itself — **Better:** Always confirm the drop is real by replaying golden queries through the exact same eval config from six weeks ago; LLM-as-judge version bumps and golden dataset changes are silent accuracy killers.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q13: Evaluate and monitor model in production, not just offline?](05-013-evaluate-and-monitor-model-in-production-not-just-offline.md) | Production monitoring infrastructure that catches this drop early |
| [Q17: Golden dataset for evaluation and regression testing?](05-017-golden-dataset-for-evaluation-and-regression-testing.md) | The regression tool that isolates whether the eval or the system changed |
| [Q3: Detect and mitigate hallucinations in production?](05-003-detect-and-mitigate-hallucinations-in-production.md) | Related failure mode — context_recall drop → hallucination spike |

---

## One-liner recall

> Diagnose a chatbot accuracy drop with five layers in order — validate the eval metric, check retrieval health via RAGAS context_recall vs faithfulness, audit deployment/prompt changes, segment by cohort, and only retrain if all upstream causes are ruled out.
