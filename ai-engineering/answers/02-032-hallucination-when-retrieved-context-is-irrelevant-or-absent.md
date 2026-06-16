# Hallucination when retrieved context is irrelevant or absent

**Category:** 02-rag-systems
**Question #:** 032
**Source section:** §2 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
The interviewer is probing production debugging instinct: can you identify the specific failure mode where a RAG system retrieves low-relevance chunks (or nothing useful) and the LLM still produces a confident-sounding but fabricated answer? This is the most dangerous failure arc in customer-facing RAG — the system "answers" rather than abstaining.

### Trigger phrases
- "Your RAG system gives confident wrong answers — how do you debug it?"
- "LLM confidently wrong — debug RAG giving confident wrong answers?"
- "How do you handle hallucination when no information is found in context?"
- "What happens when retrieval returns irrelevant docs and the LLM still generates an answer?"

### What it tests
Whether the candidate understands hallucination as a multi-layer problem (retrieval gap + generation behavior) and can prescribe defense-in-depth across the pipeline — not just "add a disclaimer" or "raise temperature=0."

---

## Answer

### Concept
When a RAG pipeline retrieves chunks that are semantically distant from the user's query — or retrieves nothing useful at all — the LLM often "hallucinates forward": it treats the weak context as partial evidence and generates a plausible-sounding but unsupported answer. Unlike pure LLM hallucination (fabricating facts from training data), this failure mode is triggered by retrieval quality and can be prevented before the LLM call ever happens.

### Mechanism
Defense-in-depth has three layers:

**Layer 1 — Retrieval gate (before LLM call):**
- Compute cosine similarity between the query embedding and the top-K retrieved chunks.
- If the max similarity score falls below a threshold (e.g., `< 0.70` for `text-embedding-3-large`), short-circuit: return a canned "I don't have information on that" response without calling the LLM. This eliminates the hallucination before it can happen and saves the API cost.
- Threshold is calibrated on your golden dataset — measure abstention precision and recall. Too low → hallucinations leak through; too high → over-refusal on real questions.

**Layer 2 — Grounding prompt (at generation):**
- System prompt: *"Answer ONLY using the provided context. If the context does not contain the information needed to answer the question, say: 'I don't have enough information to answer that.' Do not speculate or rely on general knowledge."*
- Temperature = 0 to eliminate sampling variance.
- Include numbered source citations so the model anchors each claim to a specific chunk — making hallucinated non-citations visible.

**Layer 3 — Post-generation faithfulness check:**
- Run RAGAS `faithfulness` score on the (context, answer) pair. Faithfulness measures the fraction of answer claims that are entailed by the retrieved context — a score < 0.80 on a production query is a red flag.
- For high-stakes applications (medical, legal, financial), use a DeBERTa-based NLI model to verify entailment of each sentence in the answer against the retrieved chunks. Any sentence with entailment score < 0.75 triggers a fallback to the canned response.
- Async post-check in background for low-latency paths: log flagged responses and suppress future similar queries via semantic cache poisoning (cache the abstention response for that query cluster).

### Example / Tradeoff
**Concrete scenario:** A customer support RAG for a SaaS product. User asks: *"Does your enterprise tier support HIPAA BAAs?"* The retrieval returns chunks about pricing tiers and SSO — semantically adjacent ("enterprise") but missing HIPAA content. Without a gate, GPT-4o-mini generates: *"Yes, our enterprise tier is HIPAA-compliant with BAAs available upon request."* — a confident hallucination.

**With the retrieval gate:** max cosine score = 0.61 < threshold 0.70 → short-circuit → *"I don't have verified information on HIPAA compliance. Please contact sales@company.com."*

**Cost of the gate at 1M queries/day:** The embedding call costs ~$0.13/M tokens — negligible. The LLM call (skipped) costs ~$2–10/1K queries. A 5% abstention rate saves ~$1K–5K/day at scale.

**Tradeoff:** The cosine threshold is the key tuning knob. Setting it too aggressively (> 0.85) causes over-refusal on legitimate paraphrase queries. Setting it too low (< 0.60) lets high-risk mismatches through. Calibrate using a golden test set with labeled abstention examples, targeting precision ≥ 0.95 on abstentions and recall ≥ 0.90 on answerable queries.

---

## Verbal script

**Opening (30s):**
"This is a really important failure mode — arguably more dangerous than pure LLM hallucination because it's harder to detect. When retrieval returns irrelevant context, the LLM doesn't say 'I got bad docs' — it treats them as partial evidence and confabulates a confident answer. I think about this as a three-layer defense problem."

**Core explanation (2–3 min):**
"The first and most impactful layer is a retrieval gate before the LLM call. After retrieving top-K chunks, I compute the cosine similarity between the query embedding and each chunk. If the maximum similarity is below a calibrated threshold — I typically start around 0.70 for `text-embedding-3-large` — I short-circuit the pipeline and return a canned abstention response without calling the LLM. This prevents the hallucination from ever being generated and also saves the API cost.

The second layer is the grounding prompt itself. The system prompt explicitly instructs the model: 'Answer only using the provided context. If the context doesn't support an answer, say so.' I also use temperature zero and numbered citations — this forces the model to anchor every claim to a specific chunk, making unsupported claims visible.

The third layer is post-generation validation using RAGAS faithfulness. It measures the fraction of claims in the answer that are entailed by the retrieved context. In production, I run this asynchronously so it doesn't add to latency — if faithfulness drops below 0.80, I flag the response for review and suppress similar queries via a semantic cache poisoning pattern."

**Tradeoff / production angle (1 min):**
"The retrieval gate threshold is the key tuning knob and it requires calibration on your golden dataset — not just any threshold. Too high and you over-refuse on legitimate paraphrase queries; too low and you let high-risk mismatches through. I've seen teams set it arbitrarily at 0.80 and then wonder why users complain the bot never answers anything. The right approach is to measure abstention precision and recall separately and pick the operating point that fits your risk tolerance — in a medical context I'd optimize for precision on abstentions; in a general support context I'd balance both."

**Wrap-up (30s):**
"So in summary: gate at retrieval with cosine threshold, ground the prompt with explicit abstention instruction and citations, validate post-generation with RAGAS faithfulness — and monitor abstention rate and hallucination rate as separate production SLOs. Happy to go deeper on any layer."

---

## Pitfalls

- **Mistake:** Saying "just set temperature=0 to prevent hallucination" — **Better:** Temperature=0 reduces variance but does nothing when the LLM is confidently wrong because the *retrieved context itself* is irrelevant; the fix must start at the retrieval gate before the LLM call.
- **Mistake:** Treating faithfulness scoring as a real-time blocker on every query — **Better:** Run faithfulness checks asynchronously in production to avoid adding 200–500ms latency; use the scores for monitoring, flagging, and training-data curation rather than inline gating (reserve inline NLI entailment for high-stakes regulated domains).
- **Mistake:** Conflating "low retrieval score" with "no documents returned" — **Better:** Distinguish the case where top-K returns 0 results (easy: always abstain) from the case where top-K returns plausible-but-wrong chunks with moderate similarity (dangerous: requires cosine threshold gating and faithfulness validation).

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q8: How handle hallucination when no information is found in context?](02-008-how-handle-hallucination-when-no-information-is-found-in-con.md) | Same failure mode from a different angle — Q8 focuses on generation-time prompt design |
| [Q13: Common RAG failure points — how debug them?](02-013-common-rag-failure-points-how-debug-them.md) | Broader taxonomy of RAG failures; hallucination-on-absent-context is one of six modes |
| [Q21: How evaluate a RAG pipeline? NDCG, MRR, precision@k, recall?](02-021-how-evaluate-a-rag-pipeline-ndcg-mrr-precisionk-recall.md) | RAGAS faithfulness and context_recall metrics used in Layer 3 of the defense stack |

---

## One-liner recall

> Gate at retrieval with a cosine similarity threshold (short-circuit before the LLM call), ground the prompt with explicit abstention instructions and citations at T=0, and validate post-generation with RAGAS faithfulness — monitoring abstention rate and hallucination rate as separate production SLOs.
