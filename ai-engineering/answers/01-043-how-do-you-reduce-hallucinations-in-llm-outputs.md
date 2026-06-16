# How do you reduce hallucinations in LLM outputs?

**Category:** 01-llm-fundamentals
**Question #:** 043
**Source section:** §1 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
Hallucination is the #1 reliability problem in production LLM systems. Interviewers want to know whether you understand the *root causes* (not just that hallucinations exist), can layer defenses, and have closed-loop production monitoring to detect regressions. It probes depth-of-production-experience — junior candidates cite "use RAG"; senior candidates describe multi-layer mitigation with measurable outcomes.

### Trigger phrases
- "How do you reduce hallucinations in LLM outputs?"
- "Your chatbot is confidently giving wrong answers — what do you do?"
- "How do you ensure factual accuracy in a customer-facing LLM?"
- "Walk me through your hallucination mitigation strategy."

### What it tests
The candidate's ability to diagnose hallucination root causes and apply layered, measurable mitigations across retrieval, generation, and post-processing.

---

## Answer

### Concept
Hallucination occurs when an LLM generates fluent text that is factually wrong or ungrounded — either fabricating facts not in its training data (*intrinsic* hallucination) or contradicting information present in the provided context (*extrinsic* hallucination). Mitigation is multi-layered: fix the *retrieval* first, constrain *generation*, then validate *outputs*.

### Mechanism

**Layer 1 — Fix retrieval (most impactful)**
- Improve chunk quality: semantic chunking, parent-child retrieval, metadata filtering
- Add hybrid search (BM25 + dense vectors via Reciprocal Rank Fusion) to catch exact-match failures
- Add a cross-encoder re-ranker (e.g., `cross-encoder/ms-marco-MiniLM-L6-v2`) to surface truly relevant passages
- Retrieve more candidates, re-rank to top-3, so the generator has high-quality context

**Layer 2 — Constrain generation**
- Set `temperature=0` for factual tasks (eliminates random token sampling)
- Use grounding prompts: *"Answer only from the provided context. If the context doesn't contain the answer, say 'I don't know'."*
- Return citations with every claim — forces the model to anchor to retrieved text; allows post-hoc verification
- Use structured output (Instructor + Pydantic) for predictable, validatable responses

**Layer 3 — Post-generation validation**
- **Faithfulness check**: compute RAGAS `faithfulness` score — for each claim in the response, verify it is entailed by the retrieved context using an LLM-as-judge; threshold at 0.8
- **NLI/entailment guard**: pass (response, source_doc) through a lightweight NLI model (e.g., `cross-encoder/nli-deberta-v3-small`) — reject responses where entailment score < threshold
- **Self-consistency**: sample N responses at temperature > 0, accept only if ≥ 60% agree on the key claim (expensive; use for high-stakes paths only)
- **HITL escalation**: route low-confidence responses (faithfulness < 0.7 or no relevant context retrieved) to a human queue

**Layer 4 — Observe and regress**
- Maintain a golden dataset of 200–500 question/answer pairs with known ground truth
- Track `hallucination_rate` (flagged by RAGAS faithfulness < 0.8) as a production metric in your observability stack (LangSmith, Weights & Biases, Arize)
- Set alerts when hallucination rate exceeds SLO (e.g., > 5%); block deployment if regression detected on golden set

### Example / Tradeoff
At a customer support deployment, baseline GPT-4 RAG at temperature=0.7 had ~18% hallucination rate (RAGAS faithfulness). Adding hybrid search + cross-encoder reranker dropped it to ~9%; grounding prompt + temperature=0 dropped it to ~5%; RAGAS faithfulness gate (auto-flag + HITL) reduced user-visible errors to < 2%. Full NLI post-processing added ~120ms latency per response — a tradeoff that's only viable on high-stakes queries (e.g., medical dosage, legal contract terms) rather than general Q&A.

**Key tradeoff:** Faithfulness gates reduce hallucinations but increase "I don't know" rate (deflection). Monitor both; optimizing only faithfulness can make the system feel useless.

---

## Verbal script

**Opening (30s):**
"Hallucination is really a multi-layer problem — there's no single fix. I think about it across three stages: *retrieval*, *generation*, and *post-processing*. In my experience, the biggest wins come from fixing retrieval first, because if the context is garbage, the model has no choice but to hallucinate."

**Core explanation (2–3 min):**
"On the retrieval side, I'd start with hybrid search — combining BM25 and dense embeddings with Reciprocal Rank Fusion. Dense search alone misses exact-match queries like product codes or drug names. Then I'd add a cross-encoder re-ranker to pick the top 3 truly relevant passages from a larger candidate pool. Better context = fewer hallucinations downstream.

On generation, temperature=0 for factual tasks eliminates randomness. A grounding prompt — 'answer only from the provided context, say I don't know if it's not there' — gives the model an explicit fallback. I also add citation anchors: the model must quote the source passage, which forces it to stay grounded and gives users a way to verify.

For post-processing, I use RAGAS faithfulness scoring — for each claim in the response, an LLM judge checks if it's supported by the retrieved context. Anything below 0.8 gets flagged. On high-stakes paths like medical or financial queries, I'll add an NLI model to do entailment checking as a second gate. Both add latency — RAGAS faithfulness is maybe 200ms, NLI is 50–100ms — so I tier these by query risk.

Finally, production monitoring: a golden dataset of 500 Q&A pairs with known answers, RAGAS faithfulness tracked as a production SLO, alerts if it exceeds 5%, and gate deployments on golden-set regression."

**Tradeoff / production angle (1 min):**
"The key tension is between faithfulness and deflection rate. If the faithfulness gate is too aggressive, the system says 'I don't know' too often and frustrates users. I've found that tracking both metrics and setting balanced SLOs — e.g., hallucination rate < 5%, deflection rate < 15% — gives the right tension. The other tradeoff is latency: full NLI post-processing adds ~120ms, which matters at p95. I'd only apply that on high-stakes query paths."

**Wrap-up (30s):**
"So the answer isn't one thing — it's a stack: better retrieval, constrained generation, faithfulness gating, and production monitoring. Happy to go deeper on any layer — retrieval, the RAGAS metrics, or the golden-set regression setup."

---

## Pitfalls

- **Mistake:** Saying "just use RAG and it solves hallucinations" — **Better:** RAG reduces but doesn't eliminate hallucination; the model can still misinterpret retrieved context or hallucinate when context is insufficient; you need the full mitigation stack.
- **Mistake:** Only mentioning generation-side fixes (temperature=0, prompting) and ignoring retrieval quality — **Better:** Lead with retrieval as the highest-leverage fix; poor context means the model has nothing to ground on regardless of generation settings.
- **Mistake:** Not mentioning *how to measure* hallucination rate in production — **Better:** Specify RAGAS `faithfulness`, golden datasets, LLM-as-judge scoring, and production SLOs with alert thresholds.
- **Mistake:** Treating hallucination mitigation as binary (on/off) rather than tiered — **Better:** Explain that mitigation intensity should match query risk: general Q&A gets faithfulness scoring; medical/legal paths get NLI + HITL.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q9: Detect and mitigate hallucinations in production](../answers/05-005-detect-and-mitigate-hallucinations-in-production.md) | Follow-up: production monitoring and metrics layer |
| [Q5: Explain context windows and their limitations](01-005-explain-context-windows-and-their-limitations.md) | Prerequisite: lost-in-the-middle problem worsens hallucination |
| [Q12: What's an RAG model? Explain the complete process](01-012-whats-an-rag-model-explain-the-complete-process.md) | Prerequisite: RAG is the primary architectural defense |

---

## One-liner recall

> Reduce hallucinations in layers: fix retrieval with hybrid search + re-ranking → constrain generation with temperature=0 and grounding prompts → validate outputs with RAGAS faithfulness gating → monitor with a golden dataset and production SLOs.
