# Prevent factual errors in summarization?

**Category:** 05-evaluation-metrics
**Question #:** 004
**Source section:** §5 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
Summarization is one of the highest-hallucination tasks in production GenAI systems because the model must compress information without inventing details. Interviewers probe whether the candidate understands the failure modes specific to summarization (extrinsic vs intrinsic hallucination, faithfulness vs relevancy) and has a layered mitigation strategy — not just "lower the temperature."

### Trigger phrases
- "How do you prevent factual errors in summarization?"
- "Your document summarizer is making things up — how do you fix it?"
- "How do you ensure the summary only contains information from the source?"

### What it tests
Depth of production hallucination-mitigation experience applied specifically to closed-domain summarization tasks.

---

## Answer

### Concept
Factual errors in summarization fall into two types: **extrinsic hallucinations** (the model adds facts not in the source) and **intrinsic hallucinations** (the model contradicts the source). The root causes are different: extrinsic errors come from the model's parametric knowledge bleeding in; intrinsic errors come from attention drift on long documents. Mitigation requires defense-in-depth at the prompt, generation, and post-processing layers.

### Mechanism

**Layer 1 — Prompt engineering (cheapest)**
- Use a strict **closed-world grounding prompt**: `"Summarize ONLY information present in the document below. If the document does not contain a fact, do not include it."`
- Set `temperature=0` to eliminate stochastic invention.
- Explicitly forbid external knowledge: `"Do not use prior knowledge."`
- Add a **format constraint** (e.g., bullet points with source sentence references) — structured output forces the model to anchor each claim.

**Layer 2 — Chunking strategy**
- For long documents, use **Map-Reduce** (summarize each chunk independently, then reduce) rather than stuffing everything in context. This prevents the "lost in the middle" attention drift that causes intrinsic errors.
- Use **Map-Refine** when sequential context matters (legal contracts, annual reports): each chunk's summary is refined against the previous one.
- Keep chunks within 512–1024 tokens so the model can attend to all content uniformly.

**Layer 3 — Post-generation faithfulness check**
- **RAGAS `faithfulness` metric**: scores each claim in the summary against the source chunks using an LLM judge. Threshold <0.85 → reject or flag for human review.
- **NLI entailment gate**: run a DeBERTa-based NLI model (e.g., `cross-encoder/nli-deberta-v3-base`) to check each summary sentence entails from the source. Contradiction label → discard that sentence or trigger regeneration.
- For regulated domains (healthcare, legal), NLI is preferred over LLM judge for auditability and cost.

**Layer 4 — Production monitoring**
- Sample 5% of production summaries through the faithfulness gate asynchronously (async to avoid latency impact).
- Track `hallucination_rate` as a separate SLO from `answer_quality`. Alert at >2% extrinsic hallucination rate.
- Build a **golden test set** of 200–500 source+summary pairs with human-labeled faithfulness scores; run it on every model version before deployment.

### Example / Tradeoff

At a financial document summarizer handling 10K earnings calls/day:
- Stack: PyMuPDF extraction → 512-token recursive chunks → a small fast model with closed-world prompt at T=0 → async RAGAS faithfulness check (claude-haiku-4-5-as-judge) on 10% sample.
- Switching from a frontier model (full context stuffing) to Map-Reduce with a small fast model reduced intrinsic error rate from 8% → 1.8% while cutting cost by 70%.
- RAGAS faithfulness gate caught a batch where currency normalization failed (model invented "amounts in millions" when source said "thousands") — prevented a compliance incident.

**Tradeoff table:**

| Technique | Latency cost | Error reduction | Best for |
|---|---|---|---|
| T=0 + grounding prompt | None | ~30–40% | All summarization |
| Map-Reduce chunking | +20–40% | ~50–60% for long docs | >4K token sources |
| RAGAS faithfulness async | Negligible (async) | Detects remaining 1–3% | Production monitoring |
| NLI entailment sync | +80–200ms | High recall | Regulated domains |
| Human review gate | High | Near-perfect | High-stakes outputs |

---

## Verbal script

**Opening (30s):**
"Factual errors in summarization come from two distinct failure modes — the model adding facts from its training data that aren't in the source, which I call extrinsic hallucination, and the model contradicting the source due to attention drift on long documents, which is intrinsic. I'd tackle these with a defense-in-depth approach across prompt design, chunking strategy, and post-generation validation."

**Core explanation (2–3 min):**
"At the prompt layer, I'd use a strict closed-world grounding instruction — something like 'summarize only information present in the document below, do not use prior knowledge' — and set temperature to zero. These two changes alone eliminate a large fraction of extrinsic errors.

For long documents, the single biggest win is switching from context-stuffing to Map-Reduce: summarize each 512-token chunk independently, then synthesize. This prevents the 'lost in the middle' attention failure where the model stops faithfully attending to middle sections and starts filling gaps with parametric knowledge.

For post-generation validation, I'd run RAGAS faithfulness asynchronously on a 5–10% sample. It scores each claim in the summary against the source using an LLM judge. For regulated domains like healthcare or legal, I'd swap in a DeBERTa NLI model — it's cheaper, faster, and auditable. Any summary sentence labeled 'contradiction' gets flagged or regenerated.

A concrete example: at a financial document summarizer I worked on, switching from full-context a frontier model to Map-Reduce with a small fast model dropped intrinsic error rate from 8% to under 2%, while reducing cost by 70%. The async RAGAS gate then caught the tail of remaining errors before they reached users."

**Tradeoff / production angle (1 min):**
"The main tradeoff is latency vs coverage. Synchronous NLI validation adds 80–200ms per summary; async is better for throughput but means some hallucinations reach users before detection. For high-stakes outputs — insurance claim summaries, medical notes — I'd accept the sync latency. For consumer-facing content summaries, async monitoring with a human-review queue for flagged outputs is the right balance.

Also, RAGAS faithfulness uses an LLM judge which itself can hallucinate — so it's important to calibrate it on your domain's golden test set, not just trust the raw score."

**Wrap-up (30s):**
"So the layered approach is: grounding prompt at T=0 → Map-Reduce for long docs → RAGAS/NLI faithfulness gate → production monitoring with a hallucination-rate SLO. Each layer is cheap enough to run in production and together they push factual error rates below 2%. Happy to go deeper on any layer."

---

## Pitfalls

- **Mistake:** Saying "just lower the temperature to 0 and it'll stop hallucinating" — **Better:** Explain that T=0 reduces stochastic errors but not attention-drift intrinsic errors; Map-Reduce chunking is essential for documents >4K tokens, and post-generation faithfulness validation catches what prompting misses.
- **Mistake:** Treating RAGAS faithfulness as synchronous blocking middleware — **Better:** Explain that running it synchronously adds 500ms–2s latency per summary; async sampling on 5–10% of traffic with a human-review queue for flagged outputs is the production-safe pattern.
- **Mistake:** Using BLEU/ROUGE to measure summarization accuracy — **Better:** Explain that n-gram overlap rewards copying and penalizes paraphrase; RAGAS faithfulness and NLI entailment actually measure whether claims are grounded in the source.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q3: Detect and mitigate hallucinations in production](05-003-detect-and-mitigate-hallucinations-in-production.md) | Parent concept — general hallucination stack; this Q is the summarization-specific specialization |
| [Q5: Reduce hallucinations in a medical chatbot](05-005-reduce-hallucinations-in-a-medical-chatbot.md) | Same defense-in-depth pattern applied to a domain-specific use case |
| [Q9: Perplexity, ROUGE, BLEU — pitfalls of n-gram metrics](05-009-perplexity-rouge-bleu-pitfalls-of-n-gram-metrics.md) | Why ROUGE/BLEU are wrong metrics for faithfulness; what to use instead |

---

## One-liner recall

> Prevent summarization hallucinations with a three-layer stack: closed-world grounding prompt at T=0, Map-Reduce chunking for long docs to avoid attention drift, and async RAGAS faithfulness / NLI entailment gate to catch what prompting misses.
