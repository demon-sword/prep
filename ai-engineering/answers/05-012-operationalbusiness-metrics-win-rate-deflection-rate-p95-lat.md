# Operational/business metrics: win rate, deflection rate, p95 latency?

**Category:** 05-evaluation-metrics
**Question #:** 012
**Source section:** §5 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
Interviewers want to know if you can bridge the gap between ML metrics (RAGAS faithfulness, BLEU) and business outcomes (cost savings, user satisfaction, SLA compliance). Strong candidates own the full measurement stack — offline eval *and* production KPIs that executives and PMs care about.

### Trigger phrases
- "How do you know your AI feature is actually working in production?"
- "What metrics do you track for your chatbot beyond accuracy?"
- "How do you report AI system health to stakeholders?"
- "Walk me through the business metrics you used for your AI project."

### What it tests
Ability to translate ML system performance into business-observable outcomes and production SLOs that drive go/no-go decisions.

---

## Answer

### Concept
Operational and business metrics measure the *impact* of an AI system on users and cost — they complement offline eval metrics (RAGAS, golden-dataset accuracy) by capturing what actually happens in production. The key triad is: **quality** (are answers good?), **efficiency** (are we fast and cheap?), and **business value** (does it move the needle?).

### Mechanism

**Quality metrics:**
| Metric | Definition | Target |
|--------|-----------|--------|
| **Win rate** | % of responses rated better than baseline (A/B: new vs. control) | >50% vs prior version |
| **Deflection rate** | % of queries resolved by AI without human escalation | ≥70–80% for support bots |
| **CSAT / thumbs-up rate** | User satisfaction signal from explicit feedback | ≥4.2/5 or ≥80% positive |
| **Hallucination rate** | % responses flagged by NLI/RAGAS faithfulness gate | <3% SLO |

**Latency metrics:**
| Metric | Definition | Target |
|--------|-----------|--------|
| **TTFT** | Time to first token (streaming UX) | <800ms for chat |
| **p95 latency** | 95th-percentile end-to-end response time | <3s for support; <10s for complex queries |
| **p99 latency** | Tail latency — catches cold starts, long queues | <15s |

**Cost metrics:**
| Metric | Definition | Target |
|--------|-----------|--------|
| **Cost per query** | (LLM tokens × price + infra) / query count | <$0.005 for commodity support |
| **Cost per deflection** | Total AI cost / # queries deflected from human agents | vs. human agent cost (~$5–12/ticket) |

**Measurement pipeline:**
1. **Logging layer** — every LLM call logs: query_id, model, input_tokens, output_tokens, latency_ms, retrieval_score, user_id, session_id
2. **Eval sidecar** — async Kafka consumer runs RAGAS faithfulness on 100% of responses; routes <0.80 to hallucination counter
3. **Feedback capture** — thumbs up/down events joined to query_id for CSAT/deflection
4. **Dashboards** — Grafana/DataDog aggregates p95 latency, cost/query, deflection rate with hourly granularity
5. **Alerting** — PagerDuty alert if p95 > 5s or hallucination rate > 5% over a 5-min window

### Example / Tradeoff
A customer support chatbot at a B2B SaaS company tracks:
- **Deflection rate** = 74% (target: ≥70%) — meaning 74% of tickets never reach a human agent
- **Cost per deflection** = $0.08 AI cost vs. $8 human agent cost → 100× ROI
- **p95 latency** = 2.1s (target: <3s) — crossed 3s threshold during GPT-4o outage → auto-fallback to GPT-4o-mini
- **Win rate** = 61% on A/B test vs. previous prompt version → shipped

**Tradeoff:** Deflection rate and CSAT can conflict — aggressive deflection (never escalate) boosts deflection rate but tanks CSAT when AI answers poorly. Production systems set a confidence threshold: escalate when cosine retrieval score < 0.70 or RAGAS faithfulness < 0.80, accepting lower deflection rate in exchange for higher CSAT.

---

## Verbal script

**Opening (30s):**
"I think of production metrics in three buckets: quality, efficiency, and business value. Offline metrics like RAGAS faithfulness tell you about answer quality in a controlled setting, but you need production KPIs to know if the system is actually working — and to have a conversation with product and finance."

**Core explanation (2–3 min):**
"On the quality side, the two metrics I always track are deflection rate and CSAT. Deflection rate is the percentage of queries the AI resolves without human escalation — for a support bot, we'd target 70–80%. CSAT or thumbs-up rate tells us if users are actually satisfied. Win rate is what I use when comparing versions: in an A/B test, if the new prompt wins more than 50% of head-to-head comparisons judged by the LLM or users, that's your shipping signal.

On the efficiency side, I care about p95 latency and cost per query. p95 is more useful than p50 — tail latency is what users complain about, and it catches cold starts or queue buildups. For a chat interface, I target under 3 seconds end-to-end, and under 800ms time-to-first-token for streaming. Cost per query feeds into cost per deflection, which is the business ROI metric — for a support bot deflecting a $8 human ticket at $0.08 AI cost, that's a 100× ROI argument for the CFO.

I tie all of this together in a logging pipeline: every LLM call emits structured logs — tokens in/out, latency, retrieval score, session ID. An async Kafka consumer runs RAGAS faithfulness scoring in the background. Grafana dashboards aggregate hourly, and PagerDuty fires if p95 crosses 5 seconds or hallucination rate exceeds 5%."

**Tradeoff / production angle (1 min):**
"The key tension is between deflection rate and quality. If you never escalate, deflection rate looks great but CSAT tanks when the AI gives bad answers. So I set escalation triggers — if retrieval cosine score is below 0.70 or RAGAS faithfulness is below 0.80, I route to human. You sacrifice some deflection rate in exchange for trust. The other gotcha is hallucination rate as a *separate* SLO from deflection rate — you can deflect a lot of queries with confident but wrong answers. Those need to be tracked independently."

**Wrap-up (30s):**
"So the full stack is: RAGAS/golden-dataset offline, then deflection rate + CSAT + win rate for quality in production, and p95 latency + cost per query for efficiency. Happy to go deeper on any of the measurement infrastructure or how to set the thresholds."

---

## Pitfalls

- **Mistake:** Reporting only RAGAS/accuracy from the eval set and calling the system "working" — **Better:** Always pair offline eval with production business metrics (deflection rate, CSAT, p95 latency); offline metrics don't capture distribution shift or user behavior in the wild.
- **Mistake:** Treating deflection rate as the single success metric without tracking CSAT or hallucination rate separately — **Better:** High deflection + low CSAT = AI is confident but wrong; track all three as an SLO triplet and set escalation thresholds that balance them.
- **Mistake:** Using average latency instead of p95 — **Better:** p95 captures tail latency from cold starts, oversized contexts, or queue backup; users filing support tickets about "slow responses" are the p99 cases, not the median.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q2: How evaluate a chatbot?](05-002-how-evaluate-a-chatbot.md) | Offline eval counterpart — together they form the full eval stack |
| [Q13: Evaluate and monitor model in production, not just offline?](05-013-evaluate-and-monitor-model-in-production-not-just-offline.md) | Deep-dive on production monitoring infrastructure |
| [Q3: How optimize cost at 1M queries/day?](07-003-how-optimize-cost-at-1m-queriesda.md) | Cost per query metric connects to cost optimization levers |

---

## One-liner recall

> Track the operational KPI triplet — deflection rate (AI resolves without human), p95 latency (tail SLA), and cost per deflection (ROI vs. human agent) — alongside CSAT and hallucination rate as separate SLOs, because high deflection with poor answers breaks user trust.
