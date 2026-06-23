# Model tiering — small distilled vs large LLM?

**Category:** 07-cost-latency
**Question #:** 010
**Source section:** §9 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
Interviewers want to see whether you understand that blindly routing all traffic to a frontier model (GPT-4o, Claude 3.5 Sonnet) is a cost anti-pattern. The question probes your ability to design an intelligent routing layer that preserves quality on complex queries while dramatically reducing cost on simpler ones — a real production challenge at any non-trivial scale.

### Trigger phrases
- "When is a small open-source model good enough?"
- "How do you decide which model to use for a given request?"
- "How do you model tier your LLM routing at 1M queries/day?"
- "Walk me through your model selection strategy at scale"

### What it tests
Ability to design a cost-aware routing system that classifies query complexity and routes requests to the cheapest model that meets quality SLOs — not just awareness that multiple model sizes exist.

---

## Answer

### Concept
Model tiering is a cost-optimization pattern where requests are routed to different LLMs based on task complexity: cheap, fast small models (GPT-4o-mini, Llama 3 8B) handle high-volume simple queries; expensive frontier models (GPT-4o, Claude 3.5 Sonnet) are reserved for tasks that genuinely require their capability. The key insight is that in most production systems, 60–80% of queries are FAQ-style, lookup, or classification tasks that a 7–8B model handles with >95% accuracy — paying frontier-model prices for these is pure waste.

### Mechanism
1. **Profile query distribution** — sample 1K–5K production queries, annotate complexity (low / medium / high) using token count, topic category, and a gold-answer quality benchmark. Establish the 80th-percentile complexity threshold.
2. **Build the complexity router** — a lightweight classifier (fine-tuned DistilBERT or even a rules-based signal: input_tokens < 500 AND query_type ∈ {FAQ, lookup, extraction}) scores each query before LLM dispatch. The router itself must be fast (<5ms) and cheap — it runs on every request.
3. **Define model tiers:**
   - **Tier 1 (cheap/fast):** GPT-4o-mini ($0.15/M input, $0.60/M output), Llama 3 8B self-hosted (~$0.001/M at 4× A10G), or Mistral 7B. Target: FAQ, slot-filling, classification, short summarization.
   - **Tier 2 (mid):** GPT-4o-mini with extended context, Llama 3 70B. Target: medium-complexity retrieval + synthesis, most support chatbot turns.
   - **Tier 3 (frontier):** GPT-4o ($2.50/M input, $10/M output), Claude 3.5 Sonnet. Target: multi-step reasoning, long-context synthesis, code generation, regulated-domain queries.
4. **Set quality gates** — run both the Tier-1 model and Tier-3 model on a golden evaluation set (150–300 pairs, RAGAS Faithfulness + task-specific accuracy). Establish the quality gap; accept Tier-1 routing if the gap is < 3 percentage points on your SLO metric.
5. **Monitor and close the loop** — track per-tier quality metrics (thumbs-down rate, RAGAS faithfulness) and escalation rate (Tier-1 → Tier-2 fallback triggered by low-confidence or structured-output parse failure). Adjust routing thresholds weekly.

### Example / Tradeoff
**Customer support chatbot at 500K queries/day:**
- Profiling shows 65% of queries are plan lookups, account status, or FAQ — answerable by a 8B model with 96% accuracy vs GPT-4o's 98% (acceptable 2-point gap for this use case).
- Router: DistilBERT classifier trained on 2K labeled complexity examples, p99 latency 4ms.
- Tier assignment: 65% → GPT-4o-mini ($0.15/M), 30% → GPT-4o-mini + extended context, 5% → GPT-4o ($2.50/M).
- **Cost math:**
  - Naive all-GPT-4o: 500K × 800 avg tokens × $2.50/M ≈ **$1,000/day**
  - Tiered: 65% × $0.15 rate + 30% × $0.15 rate + 5% × $2.50 rate ≈ **$85/day** (92% reduction)
- **Tradeoff:** Router adds ~5ms latency; the 5% that escalates to GPT-4o adds $50/day but protects quality on hard queries. If the router misfires (routes a hard query to Tier-1), you get a quality hit — so golden-set validation before deploying the router is mandatory.
- **Self-hosted angle:** At $85K/month API spend, it's worth evaluating Llama 3 8B on 4× A100s (~$4K/month GPU cost) for Tier-1 — break-even is about 20× API cost.

---

## Verbal script

**Opening (30s):**
"Model tiering is one of the highest-ROI cost levers in production AI systems. The core idea is that not all queries need a frontier model — in most apps, 60–80% of requests are FAQ-style or classification tasks that a 7–8B model handles almost as well for a fraction of the cost. I'd design a routing layer that classifies complexity and dispatches accordingly."

**Core explanation (2–3 min):**
"I'd start by profiling the actual query distribution — sampling a few thousand production queries and annotating them by complexity: low (FAQ, lookup, slot-filling), medium (short synthesis, multi-turn retrieval), and high (long-context reasoning, code generation). Then I'd build a lightweight complexity router — either a rule-based system using token count and query-type signals, or a fine-tuned DistilBERT classifier, targeting sub-5ms latency so it doesn't dominate the critical path.

The tiers I'd define are: Tier 1 for cheap and fast tasks — GPT-4o-mini at $0.15/M tokens or a self-hosted Llama 3 8B; Tier 2 for mid-complexity; and Tier 3 reserving GPT-4o or Claude 3.5 Sonnet for the hardest 5–10% of queries. Before deploying the router, I'd benchmark each tier on a golden evaluation set — if Tier-1 is within 3 percentage points of Tier-3 quality on the SLO metric, that gap is usually acceptable. The cost math for a 500K-query/day system can go from $1,000/day with all-GPT-4o down to $85/day with tiering — about a 90% reduction.

A concrete example: a customer support chatbot where 65% of queries are plan lookups and account status. The 8B model answers those at 96% accuracy vs 98% for GPT-4o — that 2-point gap is acceptable. The 5% of complex billing disputes or multi-turn investigations go to GPT-4o. The router itself runs a DistilBERT classifier in 4ms."

**Tradeoff / production angle (1 min):**
"The main risk is router miscalibration — if a complex query is mis-routed to Tier-1, you get a quality regression. So I'd add a fallback: monitor structured-output parse failures or low-confidence signals from Tier-1 and escalate to Tier-2 automatically. I'd also track per-tier thumbs-down rate in production and refresh the router's decision threshold monthly. The other risk is self-hosting economics — you need to validate that GPU provisioning costs are lower than API spend before committing; break-even is typically around $20–50K/month API spend."

**Wrap-up (30s):**
"In short: profile first, build a cheap fast router, validate quality on a golden set, and monitor per-tier drift in production. Model tiering typically delivers 80–90% cost reduction on the routed traffic with minimal quality impact if the routing accuracy is high. Happy to go deeper on the router architecture or the self-hosting break-even math."

---

## Pitfalls

- **Mistake:** "I'd just route all queries to a smaller model to save money" — **Better:** "Routing everything to a small model without a complexity classifier will hurt quality on hard queries. The router itself needs to be accurate — I'd validate it on a golden set and set escalation triggers for parse failures or low confidence before deploying."
- **Mistake:** Using leaderboard benchmark scores to choose between tiers instead of task-specific evaluation — **Better:** "MMLU or HumanEval scores don't predict task-specific quality. I'd benchmark each tier on 150–300 golden examples from my own production distribution — that's the only reliable signal for whether Tier-1 quality is acceptable for my use case."
- **Mistake:** Ignoring router latency — saying "I'd add a classifier" without accounting for the latency overhead — **Better:** "The router runs on every request so it must be fast — DistilBERT inference is ~4ms on CPU, which is acceptable; a full GPT-4o-mini call for routing would be counterproductive. Rule-based signals (token count, topic prefix) can be even cheaper at <1ms."

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q7: Cost vs quality: when is small open-source model "good enough"?](07-007-cost-vs-quality-when-is-small-open-source-model-good-enough.md) | prerequisite — the benchmark methodology for deciding Tier-1 acceptability |
| [Q1: Your app gets 1M queries/day — how optimize cost?](07-001-your-app-gets-1m-queriesday-how-optimize-cost.md) | broader cost hierarchy where model tiering is one of 6 levers |
| [Q9: Multi-layer caching: retrieval, prompt, response?](07-009-multi-layer-caching-retrieval-prompt-response.md) | complementary cost lever — caching eliminates LLM calls before tiering even applies |

---

## One-liner recall

> Route 60–80% of low-complexity queries to a cheap fast model (GPT-4o-mini, $0.15/M) via a lightweight complexity classifier, reserve the frontier model for the hard 5–10%, validate routing accuracy on a golden set, and monitor per-tier quality drift — typically yields 85–90% cost reduction on routed traffic.
