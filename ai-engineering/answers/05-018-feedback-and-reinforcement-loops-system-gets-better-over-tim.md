# Feedback and reinforcement loops — system gets better over time?

**Category:** 05-evaluation-metrics
**Question #:** 018
**Source section:** §5 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
Interviewers want to know whether you think beyond static deployment. A system that doesn't improve degrades over time (model drift, knowledge staleness, shifting user needs). This probes whether you have production experience building feedback loops that turn user signal into improved model behavior — closing the train→deploy→observe→improve cycle.

### Trigger phrases
- "How do you make sure your AI system improves over time?"
- "How would you build a feedback loop for a chatbot?"
- "How do you use user feedback to retrain or improve the model?"
- "Describe the continuous improvement loop for your AI product."

### What it tests
Ability to design a closed-loop ML system that captures implicit and explicit user signals, validates them, and feeds them back into model improvement — without introducing selection bias or reward hacking.

---

## Answer

### Concept
A feedback loop is a production pipeline that captures user signals (explicit: thumbs up/down; implicit: edits, abandonment, session length), validates them as training signal, and periodically uses them to update the model (via LoRA fine-tuning, DPO preference pairs, or prompt revision) — so the system improves continuously rather than decaying after deployment.

### Mechanism

**1. Signal capture (instrumentation layer)**

| Signal type | Examples | Quality |
|-------------|----------|---------|
| Explicit positive | Thumbs-up, copy button click, "save response" | High confidence |
| Explicit negative | Thumbs-down, regenerate, flag | High confidence |
| Implicit acceptance | No edit, session continues, task completed | Medium confidence |
| Implicit rejection | User edits heavily, abandons, escalates | Medium confidence |
| Gold corrections | Human annotator rewrites | Highest confidence |

Log every signal to a structured event stream (Kafka/Kinesis) with: `session_id`, `query`, `response`, `signal_type`, `timestamp`, `user_cohort`.

**2. Signal validation (quality gate)**

Not all negative signals are model failures — some are user frustration with product UX. Before using signals as training data:
- Filter by edit distance: heavy edits (>30% token diff) = strong negative signal; minor grammar tweaks = discard
- Stratify by cohort: power users vs new users behave differently — avoid selection bias
- Dedup: near-identical queries via MinHash — don't overweight one viral question
- Human review: sample 2–5% of negative signals for annotation quality check

**3. Preference pair construction (DPO)**

For thumbs-up/thumbs-down pairs on the same query:
```
chosen  = thumbs-up response
rejected = thumbs-down response (or heavy-edit original vs cleaned version)
```
Run weekly DPO fine-tuning job (LoRA rank 16, ~4h on 4×A100) on the cleaned preference dataset. Gate deployment on golden-dataset regression: Faithfulness ≥0.85 and task-specific metric must not regress >2%.

**4. RAG knowledge refresh (retrieval loop)**

For knowledge staleness (vs behavior improvement):
- CDC pipeline (Debezium/Kafka) → incremental embedding re-index of changed documents
- Semantic caching TTL-aware invalidation on source updates
- Monitor `index_lag_seconds` SLO (<300s for high-velocity sources)

**5. Prompt refinement loop**

- A/B test prompt variations on 5% traffic slices
- Measure deflection rate, CSAT, and RAGAS Faithfulness per variant
- Promote winner after statistical significance (p<0.05, ≥2 weeks)

**6. Monitoring for loop health**

- Track `feedback_volume` (signal rate must be high enough for weekly training)
- Alert on `reward_hacking_proxy`: if model learns to maximize thumbs-up by adding filler praise, RAGAS Faithfulness drops → revert
- Monitor training cohort drift: if only power users give feedback, the loop skews toward advanced queries

### Example / Tradeoff

**Customer support chatbot improvement loop (concrete):**
- Week 1: 40K interactions, 1,200 thumbs-down events, 800 heavy edits filtered to 600 valid preference pairs
- Weekly DPO LoRA fine-tune on Llama 3 8B (rank 16, 4h on 4×A100, ~$50 compute)
- Golden dataset regression gate: Faithfulness must stay ≥0.85 on 200-question golden set
- After 8 weeks: CSAT 74% → 82%, deflection rate 61% → 71%

**Key tradeoff — latency of the loop:**
- Faster loops (daily) require smaller batches → noisier signal → risk of reward hacking
- Slower loops (monthly) are safer but miss fast-changing topics (product launches, policy changes)
- Sweet spot: weekly DPO for behavior, hourly RAG index refresh for knowledge

---

## Verbal script

**Opening (30s):**
"A system that doesn't improve is actively degrading — user needs shift, knowledge goes stale, and the model drifts from real-world queries. I'd think about this as a closed feedback loop: instrument → capture → validate → train → monitor. Let me walk through each layer."

**Core explanation (2–3 min):**
"The first thing is instrumentation. I want both explicit signals — thumbs-up/down, regenerate clicks — and implicit ones like heavy edits or session abandonment. All of these go into a structured event stream, something like Kafka, tagged with session ID, query, response, and user cohort.

The key trap is treating all negative signals as model failures. If someone edits a response for tone, that's different from editing for factual correctness. I'd filter by edit distance — only edits that change more than 30% of the tokens count as strong negative signal — and I'd stratify by user cohort to avoid selection bias from power users.

For behavior improvement, I'd construct DPO preference pairs: the thumbs-up response is the chosen, the thumbs-down is the rejected. Run weekly LoRA fine-tuning on those pairs — rank 16, about 4 hours on 4 A100s, costs maybe $50 — and gate every deployment on a golden dataset regression. Faithfulness can't drop more than 2% from baseline.

For knowledge improvement, that's a separate RAG index refresh loop — CDC events from the source-of-truth databases trigger incremental re-embedding and re-indexing, with an index_lag_seconds SLO under 5 minutes for high-velocity sources.

For prompt quality, I'd run A/B tests on prompt variants — 5% of traffic per variant, measure deflection rate and RAGAS Faithfulness, promote the winner after statistical significance."

**Tradeoff / production angle (1 min):**
"The biggest risk in a feedback loop is reward hacking — the model learns to optimize the proxy signal (thumbs-up) rather than actual quality. I've seen models learn to add gratuitous affirmations that users like but that increase hallucination rate. The mitigation is to monitor RAGAS Faithfulness independently of the feedback signal — if Faithfulness drops while thumbs-up rate rises, that's a reward hacking flag and you revert. Also, feedback volume matters: you need enough signal for weekly training to be statistically meaningful — if volume is low, extend the window to bi-weekly rather than adding noise."

**Wrap-up (30s):**
"So the feedback loop has three parts running at different cadences: weekly DPO fine-tuning for behavior, hourly RAG refresh for knowledge, and continuous A/B testing for prompts. Each has its own quality gate so one loop can't silently degrade the others."

---

## Pitfalls

- **Mistake:** Saying "we collect thumbs-down and retrain" without addressing signal validation — **Better:** Explain edit-distance filtering, cohort stratification, and the reward hacking proxy monitor; raw thumbs-downs include UX frustration and are too noisy for direct training
- **Mistake:** Treating behavior improvement and knowledge freshness as the same loop — **Better:** Distinguish DPO/LoRA fine-tuning (weekly, for behavior/style) from RAG index CDC refresh (hourly/near-real-time, for knowledge staleness); conflating them leads to wrong cadence and architecture choices
- **Mistake:** Skipping the golden dataset regression gate before deploying fine-tuned model — **Better:** Every weekly DPO update must pass a fixed golden-dataset checkpoint (Faithfulness ≥0.85, task-specific metric ≤2% regression) before promotion; without this, reward hacking can silently degrade quality while thumbs-up rate rises

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q16: "Vibes-based" eval vs formal eval framework](05-016-vibes-based-eval-vs-formal-eval-framework.md) | The formal eval framework is the quality gate that makes the feedback loop safe |
| [Q13: Evaluate and monitor model in production, not just offline](05-013-evaluate-and-monitor-model-in-production-not-just-offline.md) | Production monitoring generates the signals the feedback loop consumes |
| [Q4: Fine-tune or prompt-engineered RAG — DPO preference pairs](../answers/04-005-fine-tune-or-prompt-engineered-rag.md) | DPO is the fine-tuning technique used to close the behavior improvement loop |

---

## One-liner recall

> Close the loop at three cadences: hourly RAG re-index for knowledge freshness, weekly DPO LoRA fine-tune on validated preference pairs for behavior, continuous A/B testing for prompts — with a golden-dataset regression gate guarding every model update against reward hacking.
