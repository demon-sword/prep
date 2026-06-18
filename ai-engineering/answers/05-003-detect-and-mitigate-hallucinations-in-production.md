# Detect and mitigate hallucinations in production? ⭐

**Category:** 05-evaluation-metrics
**Question #:** 003
**Source section:** §5 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
This is one of the highest-frequency questions in AI engineering interviews because hallucination is the primary trust-killer for production LLM systems. The interviewer is probing whether you have real production experience — not just theoretical knowledge of hallucination as a concept, but a layered defence strategy with concrete detection mechanisms, measurable SLOs, and feedback loops. Weak candidates describe hallucination and then say "use RAG" or "lower the temperature." Strong candidates walk through a detection-mitigation stack with specific tools and thresholds.

### Trigger phrases
- "How do you detect and mitigate hallucinations at scale?"
- "Your chatbot is giving confidently wrong answers — what do you do?"
- "How do you measure hallucination rate in production?"
- "What's your approach to factual accuracy in LLM outputs?"

### What it tests
Whether you can design a layered, measurable hallucination-control system with concrete detection methods, production SLOs, and a feedback loop — not just describe the problem.

---

## Answer

### Concept
Hallucination is a gap between what the model asserts and what the available evidence (retrieved context, ground truth) supports. It is not a single failure mode — it ranges from intrinsic hallucination (fabricated facts with no retrieval) to extrinsic hallucination (answer contradicts the retrieved context). Detection and mitigation must happen at multiple layers: before the LLM call, during generation, after generation, and in production monitoring.

### Mechanism

**4-layer defence-in-depth stack:**

**Layer 1 — Retrieval gate (prevent hallucination before it starts)**
- Compute cosine similarity between the query embedding and the top-retrieved chunk
- If max cosine score < threshold (typically 0.70 for OpenAI `text-embedding-3-small`), short-circuit before the LLM call and return a canned "I don't have enough information" response
- This eliminates the most common hallucination cause: the model generating plausible-sounding content when the context is empty or irrelevant
- Tool: Pinecone / Qdrant score metadata; Redis for caching the decision

**Layer 2 — Generation controls (constrain what the model says)**
- Set `temperature=0` for factual RAG answers — deterministic sampling reduces stochastic hallucination
- Grounding prompt: *"Answer ONLY using the provided context. If the answer is not explicitly stated, say 'I don't know.'"*
- Require citations: force the model to attribute every claim to a numbered source block — uncited claims are flagged for review
- Use structured output (JSON schema + Instructor/function calling) for structured extraction tasks so the model can't drift into free-form fabrication
- Tool: OpenAI function calling, `instructor` library, Anthropic tool use

**Layer 3 — Post-generation faithfulness gate**
- Run RAGAS `faithfulness` score asynchronously against the generated answer and the retrieved context chunks
- Faithfulness measures what fraction of the answer's atomic claims are entailed by the context (via NLI decomposition)
- Threshold: if `faithfulness < 0.80` → replace with canned safe response or escalate to human review
- For regulated domains (medical, legal, financial): add DeBERTa-based NLI entailment check per sentence (threshold 0.85), which is slower but interpretable and auditable
- Tool: RAGAS, `sentence-transformers/cross-encoder/nli-deberta-v3-large`

**Layer 4 — Production monitoring & feedback loop**
- Collect: thumbs-down rate, explicit correction events, human auditor labels on sampled responses
- Track cosine score distribution over time (anomaly = retrieval quality degradation)
- Set separate production SLOs: hallucination rate SLO (< 2% of answers fail faithfulness gate), distinct from task-accuracy SLO
- Route low-confidence answers (faithfulness 0.75–0.85) into a human audit queue; label them for future golden-dataset expansion
- Weekly batch: compute faithfulness on 1% random production sample using GPT-4o-mini as judge ($0.002/sample at 1M queries/week = $20/week)
- Tool: LangSmith / OpenTelemetry for traces; Prometheus + Grafana for dashboards; Arize for drift detection

### Example / Tradeoff

At a customer-support RAG system (1M queries/day):
- Retrieval gate (cosine < 0.70): blocks ~8% of queries before LLM call, eliminating most intrinsic hallucinations
- Grounding prompt + T=0: reduces post-retrieval extrinsic hallucination ~40% vs T=0.7 with no constraint
- Async RAGAS faithfulness gate (<0.80 threshold): catches ~3% of remaining outputs; redirects to human queue
- Result: end-to-end hallucination rate < 1.5%, measured via 500-sample weekly human audit
- Latency cost: async gate adds 0ms to p50 latency (non-blocking); DeBERTa NLI adds ~120ms if synchronous — use async for most, synchronous only for regulated-domain answers

**Key tradeoff:** NLI entailment (DeBERTa/synchronous) is more interpretable and auditable but adds 100–200ms. RAGAS faithfulness (async, LLM-judge) is cheaper at scale but has its own judge-model errors. For high-stakes domains, use both; for cost-sensitive consumer products, async RAGAS + thumbs-down monitoring is sufficient.

---

## Verbal script

**Opening (30s):**
"I'd approach this as a defence-in-depth problem — hallucination has multiple causes, so no single fix works. My strategy has four layers: prevent bad retrievals from reaching the LLM, constrain generation, verify outputs post-generation, and monitor in production with a feedback loop. Let me walk through each."

**Core explanation (2–3 min):**
"The first layer is a retrieval gate. Before I even call the LLM, I check the cosine similarity between the query and the top retrieved chunk. If it's below about 0.70, I short-circuit and return a canned 'I don't have enough information' response — that eliminates the most common hallucination cause, which is the model generating confidently when the context is empty or irrelevant.

The second layer is generation controls. I set temperature to zero for factual RAG answers, include an explicit grounding instruction — 'answer only from the provided context, if not present say I don't know' — and require the model to cite its sources. Requiring citations is particularly powerful because uncited claims become visible for audit.

Third is a post-generation faithfulness gate using RAGAS faithfulness score. This runs asynchronously and measures what fraction of the answer's claims are actually entailed by the context. If faithfulness drops below 0.80, I replace the answer with a safe fallback or route it to a human reviewer. For regulated domains like healthcare, I also run DeBERTa NLI entailment per sentence — it's slower but interpretable and auditable.

The fourth layer is production monitoring. I track thumbs-down rate, correction events, and run a weekly faithfulness check on a 1% random sample. I set a separate SLO for hallucination rate — typically under 2% of outputs fail the faithfulness gate — which is independent from task accuracy. That separation matters because a model can pass accuracy evals while still hallucinating in specific edge-case retrieval failures."

**Tradeoff / production angle (1 min):**
"The key tradeoff is synchronous vs asynchronous verification. Running DeBERTa NLI inline adds 100-200ms — fine for high-stakes regulated queries, but too expensive for consumer chat at 1M queries/day. So I use async RAGAS for the bulk of traffic and synchronous NLI only for queries flagged as high-stakes by a classifier. Another tradeoff: the retrieval gate threshold at 0.70 is conservative — if I lower it to 0.60, I let through more borderline retrievals and increase hallucination risk; if I raise it to 0.80, I increase 'I don't know' deflections, which hurts coverage. That threshold needs to be tuned against your golden set."

**Wrap-up (30s):**
"So the key insight is that hallucination control is a layered system, not a single lever. Retrieval gate eliminates the no-context case, generation constraints guide behaviour, faithfulness gating catches what slips through, and production monitoring closes the feedback loop so you can track your hallucination SLO over time. Happy to go deeper on any of the layers."

---

## Pitfalls

- **Mistake:** "I'd lower the temperature and use RAG — that prevents hallucinations" — **Better:** Temperature=0 and RAG reduce hallucination frequency but don't eliminate it; you also need a retrieval cosine gate (empty context = hallucination before generation), a post-gen faithfulness check, and production monitoring with a separate SLO — neither lever alone is sufficient.
- **Mistake:** "I'd have GPT-4 check its own answer for hallucinations" — **Better:** Self-checking is biased toward the model's own style and training distribution; use an independent judge: RAGAS faithfulness (separate judge model) or DeBERTa NLI (non-LLM entailment model) to avoid the judge being anchored by the same errors as the generator.
- **Mistake:** "I'd track accuracy and if it's high, hallucination must be under control" — **Better:** Task accuracy and hallucination rate are separate SLOs — a model can score 90% on accuracy while hallucinating on 5% of queries in specific retrieval edge cases; always measure faithfulness independently with a dedicated metric.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q8: Measure hallucination rate in production?](05-008-measure-hallucination-rate-in-production.md) | deeper dive into production measurement techniques |
| [Q6: LLM confidently wrong — debug RAG giving confident wrong answers?](05-006-llm-confidently-wrong-debug-rag-giving-confident-wrong-answe.md) | diagnostic follow-up when hallucination is already happening |
| [Q1: What metrics for benchmarking LLM performance?](05-001-what-metrics-for-benchmarking-llm-performance.md) | prerequisite: how faithfulness fits into the broader metrics framework |

---

## One-liner recall

> Hallucination defence is a 4-layer stack: retrieval cosine gate (block empty context), generation constraints (T=0 + grounding prompt + citations), async RAGAS faithfulness post-check (<0.80 → fallback), and production monitoring with a separate hallucination-rate SLO independent of task accuracy.
