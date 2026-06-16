# Citations and source attribution in RAG?

**Category:** 02-rag-systems
**Question #:** 022
**Source section:** §2 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
Interviewers want to see whether you treat citations as a first-class engineering concern, not an afterthought. In production RAG systems — legal, medical, customer support, enterprise search — users need to verify answers, and hallucinations become expensive without an audit trail. This question probes whether you understand the full citation pipeline: tracking chunk provenance through retrieval, threading metadata into the generation prompt, and validating that generated citations actually match source content.

### Trigger phrases
- "How do you show users where the answer came from?"
- "How do you implement source attribution in your RAG system?"
- "What happens when the model cites a document it didn't actually retrieve?"
- "How do you ensure citation accuracy in a legal/compliance chatbot?"

### What it tests
Whether you can design a provenance-preserving data pipeline and enforce citation fidelity at generation time.

---

## Answer

### Concept
Source attribution in RAG means every claim in the generated answer is traceable to a specific retrieved chunk, with the document title, URL, page number, or section heading surfaced to the user. This is a data-pipeline problem as much as a prompting problem: citations can only be accurate if chunk metadata is captured at ingestion, preserved through retrieval, and explicitly included in the generation context.

### Mechanism
**1. Metadata ingestion (the foundation)**
At index time, attach rich metadata to every chunk:
```python
chunk = {
    "text": "...",
    "doc_id": "policy-v3.pdf",
    "page": 7,
    "section": "Section 4.2 — Refund Policy",
    "url": "https://internal.docs/policy-v3",
    "chunk_index": 42
}
```
Pinecone, Qdrant, and Weaviate all support arbitrary metadata fields alongside the vector.

**2. Retrieval with provenance**
Return the full metadata dict alongside the text in every retrieved chunk. Never strip metadata between retrieval and the generation call.

**3. Prompt engineering for citations**
Inject numbered source blocks, then instruct the model to cite by index:
```
Context:
[1] (policy-v3.pdf, p.7, §4.2): "Refunds are processed within 5–7 business days..."
[2] (faq.pdf, p.2): "International orders may take 10–14 days..."

Answer the question using only the context above. After each factual claim, cite the source number in brackets, e.g. [1]. If you cannot answer from the context, say so.
```

**4. Post-generation citation validation**
After generation, verify each `[N]` citation actually references content that supports the claim:
- **String overlap check** (fast): assert that key noun phrases from the cited chunk appear in the surrounding sentence.
- **NLI entailment check** (higher accuracy): run a cross-encoder (e.g. `cross-encoder/nli-deberta-v3-large`) to verify the cited chunk entails the claim. Flag citations below a confidence threshold (e.g. 0.7) for human review.

**5. UI rendering**
Return the citation metadata alongside the answer as structured JSON so the frontend can render inline links:
```json
{
  "answer": "Refunds take 5–7 business days [1].",
  "citations": [
    {"index": 1, "title": "Refund Policy §4.2", "url": "...", "page": 7}
  ]
}
```

### Example / Tradeoff
At a legal document Q&A system processing 50K contracts, we used `[1]…[N]` indexed prompts and a DeBERTa NLI entailment gate. Citations that scored < 0.75 entailment were replaced with "Source reference could not be verified — please check the document directly." This caught ~4% hallucinated citations (model cited a chunk that was topically related but didn't actually contain the claimed fact). The NLI gate added ~120ms per answer; we ran it async and rendered the answer first, then updated citation confidence badges in a second pass.

**Key tradeoff:** Full NLI validation catches subtle hallucinations but adds latency (~80–200ms per check) and cost. For low-stakes domains, string-overlap is fast and catches 80%+ of outright hallucinations. For legal/medical/compliance, NLI entailment is worth it.

---

## Verbal script

**Opening (30s):**
"Citations in RAG are a first-class engineering concern, not just a UI nicety. My approach treats attribution as a data-pipeline problem: you need to capture provenance at ingestion, preserve it through retrieval, and enforce it at generation. Let me walk through the full stack."

**Core explanation (2–3 min):**
"First, at indexing time, every chunk gets rich metadata — doc ID, page number, section heading, URL. I store this alongside the vector in Pinecone or Qdrant. The key rule is: never strip metadata between retrieval and generation.

At generation time, I inject numbered source blocks — `[1] (policy-v3.pdf, p.7): 'Refunds are processed in 5–7 days…'` — and instruct the model to cite by index after every factual claim. This is prompt engineering, not magic: the model follows the citation format if the instruction is explicit.

The gap most candidates miss is *citation validation*. A model can hallucinate by citing `[2]` for a claim that's actually in `[1]`, or cite a chunk that's topically related but doesn't actually support the claim. I address this in two ways: a fast string-overlap check for key noun phrases, and for higher-stakes scenarios, an NLI entailment model like DeBERTa to verify the cited chunk actually entails the generated sentence. Citations below a 0.75 confidence threshold get flagged or replaced with a 'could not verify' message."

**Tradeoff / production angle (1 min):**
"The tradeoff is latency and cost. String overlap is cheap — microseconds — but misses paraphrased hallucinations. NLI entailment catches those but adds 80–200ms. In a legal chatbot, that's worth it. For a customer support bot where deflection rate matters more than legal precision, I'd skip the NLI gate and rely on the retrieval threshold (cosine ≥ 0.70) and prompt discipline. I also return citations as structured JSON so the frontend can render inline links and users can click through to the source document — that's the UX payoff."

**Wrap-up (30s):**
"So: metadata at ingestion, numbered source prompts at generation, entailment validation post-generation, structured JSON to the frontend. Happy to go deeper on the NLI entailment approach or how to handle multi-doc citations where multiple chunks support the same claim."

---

## Pitfalls

- **Mistake:** Treating citations as purely a prompt problem — "just tell the model to cite sources" — without capturing or threading metadata. **Better:** Explain that citations fail if chunk metadata isn't captured at ingestion and passed through to the generation call; the model can only cite what's explicitly in the context.
- **Mistake:** Never validating that generated citations are accurate — assuming the model will always cite correctly. **Better:** Describe string-overlap or NLI entailment post-generation checks; mention that ~3–5% hallucinated citations are common even with explicit citation prompts, making validation non-optional for high-stakes domains.
- **Mistake:** Returning raw text with inline `[1]` markers and leaving citation rendering as a frontend afterthought. **Better:** Return structured JSON with `citations` array so the frontend can render inline links, confidence scores, and page numbers — that's what makes the feature trustworthy to users.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q8: How handle hallucination when no information is found in context?](02-008-how-handle-hallucination-when-no-information-is-found-in-con.md) | Citation validation is a layer of hallucination defense |
| [Q21: How evaluate a RAG pipeline?](02-021-how-evaluate-a-rag-pipeline-ndcg-mrr-precisionk-recall.md) | RAGAS faithfulness measures whether claims are grounded in retrieved context |
| [Q13: Common RAG failure points — how debug them?](02-013-common-rag-failure-points-how-debug-them.md) | Hallucinated citations are a specific failure mode in the taxonomy |

---

## One-liner recall

> Capture metadata at ingestion, inject numbered source blocks into the prompt, validate citations post-generation with NLI entailment, and return structured JSON so the frontend renders inline links — citations require the full pipeline, not just prompt instructions.
