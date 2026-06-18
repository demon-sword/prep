# How evaluate a chatbot?

**Category:** 05-evaluation-metrics
**Question #:** 002
**Source section:** §5 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
Interviewers probe whether you can build a *rigorous* quality bar for a system whose outputs are non-deterministic and conversational. Weak candidates cite BLEU or say "we look at user ratings." Strong candidates layer offline eval, automated LLM-judge metrics, and production business signals — and explain how to tie them together into a deployment gate.

### Trigger phrases
- "How would you measure chatbot quality?"
- "What metrics do you track for your conversational AI?"
- "How do you know the chatbot is actually working?"
- "Walk me through how you evaluate a support bot before shipping."

### What it tests
Ability to design a multi-layer evaluation framework covering task accuracy, conversation quality, and production business outcomes — and to identify when each layer fires.

---

## Answer

### Concept
Chatbot evaluation requires three distinct layers: *offline accuracy* (does it give correct answers on known test cases?), *conversation quality* (is the interaction fluent, coherent, and on-topic?), and *production business outcomes* (does it actually solve user problems?). No single metric covers all three — conflating them is the most common failure mode.

### Mechanism

**Layer 1 — Offline / golden-dataset eval**
- Maintain a golden dataset of (user query, expected answer, expected citations) tuples — 200–500 representative queries per major intent.
- Run RAGAS on RAG-backed chatbots: **Faithfulness** (answer entailed by retrieved context), **Answer Relevancy** (answer addresses the question), **Context Recall** (retrieved chunks contain needed facts), **Context Precision** (low noise in top-k).
- For task-completion bots (e.g., booking, support tickets): measure **Task Success Rate** (TSR) — did the bot complete the intended action?
- Gate every model/prompt change: Faithfulness ≥ 0.85, Answer Relevancy ≥ 0.80, TSR ≥ target.

**Layer 2 — Automated LLM-judge eval**
- Use GPT-4o as a judge on 3–5% of live traffic (or a larger offline sample): score helpfulness, groundedness, tone, and refusal appropriateness on a 1–5 scale.
- Track **conversation coherence**: does each turn logically follow from prior context? (judge scoring or turn-level perplexity on the multi-turn history)
- For multi-turn flows: measure **conversation depth** (turns to resolution) and **clarification rate** (how often the bot asks a clarifying question vs. guesses).

**Layer 3 — Production / business metrics**
- **Deflection rate**: % of queries fully resolved without human escalation — the primary ROI metric for support bots.
- **CSAT / thumbs signal**: explicit user satisfaction, sampled at end of session.
- **Escalation rate**: inverse of deflection; segment by intent to find weak spots.
- **p95 response latency**: user experience SLO (< 2 s for interactive chat, < 500 ms TTFT for streaming).
- **Hallucination rate SLO**: RAGAS Faithfulness < 0.80 triggers automated alert; sustained breach → rollback.
- **Cost per query**: LLM API + retrieval cost; monitored for budget SLO.

**Linking the layers**
```
Offline eval passes (Faithfulness ≥ 0.85, TSR ≥ 0.90)
  → Shadow deploy: compare new vs. old on 5% traffic via LLM judge
  → Canary: 10% live traffic, watch deflection rate and CSAT for 48h
  → Full rollout + production monitoring dashboard
```

### Example / Tradeoff
For a customer support chatbot at a SaaS company (100K queries/day):
- **Offline**: 400-query golden set, RAGAS Faithfulness target 0.87, Context Recall 0.82.
- **LLM judge**: GPT-4o-mini judging 5% live traffic at ~$0.05/100 queries — affordable and scalable.
- **Production**: Deflection rate 68% → 75% after retrieval fix found via Recall drop on golden set.
- **Pitfall avoided**: CSAT alone missed the drop because users who escalated didn't rate the bot — silent failure. Golden-set regression caught it first.

The key tradeoff: LLM-judge eval is expensive at scale but catches nuanced conversational failures that RAGAS misses (e.g., technically faithful but unhelpfully terse answers). Use LLM judge on samples; use RAGAS on every deploy.

---

## Verbal script

**Opening (30s):**
"Evaluating a chatbot well requires three layers: an offline golden-dataset layer, an automated LLM-judge layer for conversation quality, and production business metrics. I'll walk through each and explain how they connect into a deployment gate."

**Core explanation (2–3 min):**
"I'd start with the offline layer. I maintain a golden dataset — maybe 300–500 representative queries with known expected answers. For a RAG-backed chatbot I run RAGAS: Faithfulness to make sure the answer is entailed by retrieved context, Answer Relevancy to check it actually addresses the question, and Context Recall to confirm retrieval is surfacing the right chunks. For task-completion bots — like a booking or support-ticket flow — I also track Task Success Rate: did the bot actually complete the intended action?

"The second layer is automated LLM judging. I'll run GPT-4o or GPT-4o-mini as a judge on 3–5% of live traffic, scoring helpfulness, groundedness, and tone on a 1–5 scale. For multi-turn conversations I also look at clarification rate — how often does the bot ask for more info vs. confidently guess wrong — and conversation depth, meaning turns-to-resolution.

"The third layer is production business metrics: deflection rate is the headline for support bots — what fraction of queries are fully resolved without escalating to a human? CSAT thumbs signal, p95 latency for UX, and cost per query round it out.

"These link together: a change passes offline eval, goes into shadow mode where I compare new vs. old via LLM judge on 5% of traffic, then a canary at 10% for 48 hours watching deflection and CSAT before full rollout."

**Tradeoff / production angle (1 min):**
"The key tradeoff is coverage vs. cost. RAGAS is cheap enough to run on every deploy — it's automated and fast. LLM judging is 5–10× more expensive per query but catches nuanced failures like technically faithful but unhelpfully terse answers. So I use RAGAS as the automated gate and LLM judge as the sample-based quality signal. CSAT alone is a lagging indicator and has selection bias — users who escalated often don't rate the bot at all, so silent failures hide."

**Wrap-up (30s):**
"So the framework is: golden-dataset RAGAS gate on every deploy, LLM-judge sampling for conversation quality, and deflection rate + CSAT as the production north-star. Happy to go deeper on any layer — especially the LLM judge rubric design or how to build the golden dataset."

---

## Pitfalls

- **Mistake:** Citing only CSAT or thumbs-up rate as the primary eval signal — **Better:** Explain that CSAT is a lagging, selection-biased signal (escalated users skip the rating); pair it with a RAGAS golden-dataset gate and LLM-judge scoring to catch failures before users notice them.
- **Mistake:** Using BLEU or ROUGE for chatbot evaluation — **Better:** BLEU/ROUGE measure n-gram overlap against a reference string, which is meaningless for conversational output where many valid phrasings exist; use RAGAS Faithfulness + Answer Relevancy + production deflection rate instead.
- **Mistake:** Treating chatbot eval as a single-number metric — **Better:** Layer offline accuracy (RAGAS), conversation quality (LLM judge / coherence), and business outcomes (deflection rate, CSAT, latency) and set separate SLO thresholds for each; a single composite score hides which layer is failing.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q1: What metrics for benchmarking LLM performance?](05-001-what-metrics-for-benchmarking-llm-performance.md) | Broader metric taxonomy; chatbot eval is a specialization |
| [Q3: Detect and mitigate hallucinations in production?](05-003-detect-and-mitigate-hallucinations-in-production.md) | Faithfulness / hallucination layer of chatbot eval |
| [Q17: Golden dataset for evaluation and regression testing?](05-017-golden-dataset-for-evaluation-and-regression-testing.md) | How to build and maintain the offline eval foundation |

---

## One-liner recall

> Evaluate a chatbot with three layers: RAGAS golden-dataset gate (Faithfulness, Answer Relevancy, Context Recall) for every deploy, LLM-judge sampling for conversation quality, and production business metrics (deflection rate, CSAT, p95 latency) as the north-star.
