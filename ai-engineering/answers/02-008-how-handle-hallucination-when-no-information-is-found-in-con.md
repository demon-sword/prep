# How handle hallucination when no information is found in context?

**Category:** 02-rag-systems
**Question #:** 008
**Source section:** §2 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
The interviewer is probing whether you understand a critical RAG failure mode: the model confidently fabricating an answer when retrieved context contains nothing relevant. This tests production instinct — specifically, whether you know how to make a system abstain gracefully rather than hallucinate fluently. It also probes your layered defense mentality (retrieval quality → generation constraints → post-processing → monitoring).

### Trigger phrases
- "What happens when your RAG system can't find the answer?"
- "How do you prevent confident wrong answers when the docs don't cover the topic?"
- "The chatbot is hallucinating when no relevant context is retrieved — how do you fix it?"
- "How do you handle out-of-scope queries in a RAG chatbot?"

### What it tests
Ability to design a multi-layer abstention strategy — retrieval-side confidence thresholds, generation-side grounding prompts, and post-generation faithfulness checks — rather than treating hallucination as a single-point problem.

---

## Answer

### Concept
When retrieved context contains no relevant information, an LLM without explicit constraints will "fill the gap" by generating plausible-sounding but fabricated text — the most damaging form of hallucination because it is fluent and confident. The fix is a **defense-in-depth stack**: (1) detect low-relevance retrieval before generation, (2) constrain the generator to cite-only answers, (3) validate outputs against the context post-generation, and (4) monitor abstention and hallucination rates in production.

### Mechanism

**Layer 1 — Retrieval confidence gating**
Before passing chunks to the LLM, compute a relevance score between the query and top-retrieved chunks. Two approaches:
- **Bi-encoder cosine similarity threshold:** if `max(cosine_similarity(query_embedding, chunk_embeddings)) < θ` (e.g. θ = 0.70), skip generation and return a canned "I don't have information on that" response. Fast and cheap — no LLM call.
- **Cross-encoder reranker score:** if the cross-encoder relevance score for the top result falls below a calibrated threshold (e.g. 3.5 / 10 for ms-marco-MiniLM-L-6-v2), treat retrieval as failed.

**Layer 2 — Grounding prompt (generation constraint)**
When retrieval passes the threshold, still constrain generation:
```
System: Answer ONLY using the provided context. If the context does not contain 
sufficient information to answer the question, say exactly: 
"I don't have enough information to answer this." Do not infer or extrapolate.

Context:
{retrieved_chunks}

Question: {user_query}
```
Set `temperature=0` for maximum determinism. The explicit refusal instruction shifts the model's prior toward abstention when evidence is thin.

**Layer 3 — Post-generation faithfulness gate**
Run a faithfulness check (NLI-based or LLM-as-judge) on the generated answer vs. the retrieved context:
- **RAGAS `faithfulness` score:** decompose the answer into atomic claims, verify each claim is entailed by the context. If score < 0.8, replace the response with the abstention message.
- **NLI model (DeBERTa-NLI):** classify each claim as `entailed` / `neutral` / `contradiction`; flag any non-entailed claims.
- Cost: ~0.5–2ms for NLI, ~$0.001/check for LLM-as-judge on GPT-4o-mini.

**Layer 4 — Production monitoring**
Track the abstention rate and false-abstention rate in your observability stack (LangSmith, Arize, or custom):
- **Abstention rate too high (>30%):** retrieval or threshold calibration is wrong — recalibrate θ or improve chunking/indexing.
- **Abstention rate too low (<2%):** the model is answering out-of-scope queries — check faithfulness scores and lower the threshold.
- **Hallucination rate in golden set:** run the full pipeline on a 200-question golden dataset weekly; any answer not supported by cited chunks counts as a hallucination.

### Example / Tradeoff
A customer support RAG bot for a SaaS product gets queries about competitor features — completely outside its knowledge base. Without gating, GPT-4 would invent plausible-sounding competitor comparisons. Stack deployed:
1. Cosine threshold (θ = 0.72) catches 85% of out-of-scope queries before the LLM call → saves ~$0.03/query.
2. Grounding prompt + `temperature=0` handles the remaining 15% where partial context exists.
3. RAGAS faithfulness gate catches residual hallucinations; on 500 golden evals, hallucination rate dropped from 12% to 1.4%.

**Tradeoff:** Strict thresholds increase false abstentions (frustrating users with "I don't know" when the answer is actually in the KB). Tune θ on a held-out validation set; monitor false-abstention separately from hallucination rate.

---

## Verbal script

**Opening (30s):**
"This is one of the highest-risk failure modes in production RAG — when the model has nothing relevant to ground on, it fills the gap with confident hallucinations. I'd approach it as a defense-in-depth stack rather than a single prompt fix."

**Core explanation (2–3 min):**
"The first layer is retrieval-side confidence gating. Before I even call the LLM, I compute the cosine similarity between the query embedding and the top retrieved chunk embeddings. If the maximum similarity falls below a calibrated threshold — say 0.70 — I short-circuit and return a canned 'I don't have information on that' response. No LLM call, no hallucination risk, and I save the inference cost.

For queries that pass the threshold, layer two is the generation constraint. The system prompt explicitly says: 'Answer only from the provided context. If insufficient, say exactly: I don't have enough information.' I also set temperature to zero for determinism. This shifts the model's prior toward abstention on thin evidence.

Layer three is a post-generation faithfulness gate. I use RAGAS faithfulness to decompose the answer into atomic claims and verify each is entailed by the retrieved context. If the faithfulness score drops below 0.8, I swap the answer for the abstention message. For lower-latency setups I use a DeBERTa NLI model — a few milliseconds versus a full LLM call.

Finally, in production I monitor the abstention rate as a KPI. An abstention rate over 30% usually means my retrieval threshold is too strict or my index has coverage gaps. Under 2% might mean the model is answering out-of-scope questions it shouldn't. I calibrate on a golden validation set."

**Tradeoff / production angle (1 min):**
"The key tension is precision versus recall on abstention: if I set the threshold too high, I frustrate users who ask legitimate questions where the answer is in the KB but retrieved at low cosine similarity — maybe because of vocabulary mismatch or a poor chunk. If I set it too low, hallucinations slip through. The right answer is to tune the threshold on a held-out set and track both rates separately. Hybrid retrieval also helps — BM25 keyword matching catches exact-match queries that dense retrieval scores low on, reducing false abstentions."

**Wrap-up (30s):**
"So the architecture is: retrieval threshold gate → grounding prompt at T=0 → faithfulness post-check → production monitoring of abstention and hallucination rates. Happy to go deeper on any layer — threshold calibration, the faithfulness check implementation, or the monitoring pipeline."

---

## Pitfalls

- **Mistake:** Saying "just add 'if you don't know, say so' to the system prompt" as the complete solution — **Better:** Explain that LLMs are trained to be helpful and will override soft instructions when context is partially relevant; you need a retrieval-side threshold *before* generation plus a post-generation faithfulness gate, not just a prompt instruction.
- **Mistake:** Setting a single fixed threshold (e.g. "I'll use 0.7") without mentioning calibration — **Better:** "I calibrate θ on a validation set of known in-scope and out-of-scope queries, tuning to maximize F1 on abstention decisions; typical range is 0.65–0.80 depending on the embedding model and domain."
- **Mistake:** Treating hallucination rate and abstention rate as the same metric — **Better:** "I track both separately: hallucination rate (answers that are wrong/not grounded) and abstention rate (legitimate questions the system refuses to answer). Optimizing one in isolation hurts the other."

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q13: Common RAG failure points — how debug them?](02-013-common-rag-failure-points-how-debug-them.md) | Parent: hallucination with missing context is one of the six main failure modes |
| [Q32: Hallucination when retrieved context is irrelevant or absent](02-032-hallucination-when-retrieved-context-is-irrelevant-or-absent.md) | Near-duplicate from the failure modes section — deeper implementation detail |
| [Q43: How do you reduce hallucinations in LLM outputs?](../answers/01-043-how-do-you-reduce-hallucinations-in-llm-outputs.md) | Cross-category: general hallucination mitigation stack (includes non-RAG cases) |

---

## One-liner recall

> Layer the defense: cosine-similarity retrieval gate (θ ≈ 0.70) → grounding prompt + T=0 → RAGAS faithfulness post-check → production monitoring of abstention vs. hallucination rates.
