# Describe text summarization techniques and when you'd use each.

**Category:** 01-llm-fundamentals
**Question #:** 020
**Source section:** §1 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
The interviewer is probing practical breadth: can you distinguish extractive from abstractive approaches, choose the right tool for the document type and latency budget, and reason about hallucination risk in safety-sensitive settings? It surfaces whether you've shipped summarization in production versus only read about it.

### Trigger phrases
- "How would you summarize customer support tickets at scale?"
- "Describe the summarization approaches you've used."
- "What's the difference between extractive and abstractive summarization?"
- "How do you summarize a 200-page PDF without losing key details?"

### What it tests
Ability to select among extractive, abstractive, and hybrid summarization strategies based on document type, latency, accuracy, and hallucination risk constraints.

---

## Answer

### Concept
Text summarization condenses source text into a shorter form while preserving the most important information. There are three broad approaches: **extractive** (copy verbatim spans from the source), **abstractive** (generate novel fluent text using an LLM), and **hybrid** (extract then rephrase). The right choice depends on length, fidelity requirements, and whether hallucinations are acceptable.

### Mechanism

**1. Extractive summarization**
- Sentences are scored by importance (TF-IDF, TextRank graph centrality, or BERT-based sentence embeddings) and the top-k are returned verbatim.
- Tools: `sumy`, `spaCy + TextRank`, `BERT-Extractive-Summarizer`.
- Zero hallucination risk — every sentence came from the source.
- Best for: legal contracts, compliance docs, medical notes where verbatim accuracy is critical.
- Weakness: can be choppy, misses cross-sentence synthesis, fails on structured tables.

**2. Abstractive summarization**
- An LLM (GPT-4o, Claude 3.5 Sonnet, Mistral) reads the source and generates a coherent summary in its own words.
- For short docs (< ~10k tokens): single-call prompting — stuff the full document into context with a system prompt specifying format, length, and tone.
- For long docs: **Map-Reduce** pattern (LangChain `MapReduceDocumentsChain`):
  1. Split into chunks (e.g., 2,000-token windows with 200-token overlap).
  2. Summarize each chunk independently in parallel (Map).
  3. Combine chunk summaries → final synthesis (Reduce).
- Alternatively, **Refine** pattern: summarize chunk 1, then pass that running summary + chunk 2 to the LLM, iterating until the document is exhausted — better coherence, but sequential (higher latency).
- Best for: executive briefs, customer-facing outputs, meeting notes, any case where fluency matters.
- Risk: hallucinations — especially numbers, dates, proper nouns. Requires faithfulness checking.

**3. Hierarchical / parent-child summarization**
- First summarize each section or chapter, then summarize the summaries into a top-level abstract. Used for book-length or multi-document corpora.
- Common in enterprise RAG pipelines (e.g., LlamaIndex's `DocumentSummaryIndex`) — section summaries stored alongside chunk embeddings improve retrieval relevance.

**4. Query-focused summarization**
- Only summarize information relevant to a specific user question. Implemented as: retrieve relevant chunks (RAG), then ask the LLM to summarize *with respect to the query*.
- Used in customer support knowledge bases, chatbots — avoids surfacing irrelevant contract clauses.

**Evaluation:**
- ROUGE-1/2/L: n-gram overlap with reference (low ceiling for abstractive; use as a floor, not a ceiling).
- BERTScore: semantic similarity via BERT embeddings.
- Faithfulness (RAGAS, TruLens): does every claim in the summary appear in the source? Critical for production.
- Human eval: factual accuracy rate on a sampled golden set.

### Example / Tradeoff

At a legal-tech company processing 10k contracts/day:
- **Extraction** for key-clause identification (no hallucination tolerated for dates, obligations).
- **Abstractive Map-Reduce** (GPT-4o-mini for map, GPT-4o for reduce) for executive summaries shown to clients — Map parallelizes across 4 chunks simultaneously, keeping p95 latency ≈ 8s for a 40-page contract.
- **Faithfulness score** via RAGAS thresholded at 0.85 before returning summary to user; below threshold, fall back to extractive.

Cost tradeoff: GPT-4o-mini for map steps at $0.15/1M input tokens vs GPT-4o at $2.50/1M — 90%+ token volume handled cheaply; only the final reduce step uses the expensive model.

---

## Verbal script

**Opening (30s):**
"There are three families of summarization techniques, and the right choice depends on your fidelity requirements and document length. I'd start by separating extractive approaches — which copy verbatim sentences — from abstractive approaches — which generate new text — and then talk about when I'd reach for each."

**Core explanation (2–3 min):**
"Extractive summarization uses something like TextRank — treating sentences as nodes in a graph, with edges weighted by cosine similarity of their embeddings, and then picking the highest-PageRank sentences. Zero hallucination risk because every word came from the source. I'd use this for legal contracts or medical notes where exact phrasing matters.

Abstractive summarization uses an LLM directly. For short docs under about 10k tokens I just prompt the model inline. For longer docs I'd use the Map-Reduce pattern: split into 2k-token chunks, summarize each in parallel, then synthesize the summaries in a final reduce call. LangChain has this built in. The Refine pattern is an alternative — you pass the running summary forward chunk by chunk — better coherence but sequential, so higher latency.

For RAG pipelines, I layer in query-focused summarization: retrieve the relevant chunks, then ask the model to summarize *only with respect to the user's question*. This avoids surfacing irrelevant boilerplate.

On evaluation: ROUGE is a floor, not a ceiling, especially for abstractive output. The metric I care most about in production is faithfulness — does every claim in the summary appear in the source document? I'd run RAGAS faithfulness checks and threshold at something like 0.85."

**Tradeoff / production angle (1 min):**
"The big production risk with abstractive summarization is hallucinated numbers and proper nouns. A model might confidently write '$2.4M' when the contract says '$2.4B'. My mitigation stack: faithfulness scoring, entity extraction + cross-check against source, and falling back to extractive output when the faithfulness score is too low. Cost-wise, I'll use a cheap model for map steps and reserve the expensive model only for the final reduce or synthesis."

**Wrap-up (30s):**
"So the decision tree is: no hallucination tolerance → extractive; short doc, fluency needed → single-call abstractive; long doc → Map-Reduce or Refine with faithfulness gating. Happy to go deeper on any of the patterns."

---

## Pitfalls

- **Mistake:** Describing only abstractive summarization (just "use GPT-4 to summarize") without mentioning extractive or hybrid approaches — **Better:** Explain the tradeoff triangle: extractive = zero hallucination / choppy; abstractive = fluent / hallucination risk; then choose based on the doc type and safety requirement.
- **Mistake:** Not addressing long-document handling — saying "just put it in context" without a strategy — **Better:** Name Map-Reduce vs Refine patterns explicitly, explain the latency vs coherence tradeoff between them, and give a concrete chunk size (e.g., 2k tokens with 200-token overlap).
- **Mistake:** Citing only ROUGE as the evaluation metric — **Better:** Note that ROUGE measures n-gram overlap, which rewards verbatim copies and penalizes legitimate paraphrases; production systems should also track faithfulness (RAGAS) and entity-level accuracy on a golden set.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q5: Explain context windows and their limitations](01-005-explain-context-windows-and-their-limitations.md) | Long-document summarization strategies depend on context window limits |
| [Q14: How does chunking happen?](01-014-how-does-chunking-happen.md) | Map-Reduce summarization requires the same chunking decisions as RAG indexing |
| [Q12: What's an RAG model? Explain the complete process](01-012-whats-an-rag-model-explain-the-complete-process.md) | Query-focused summarization is a core component of RAG answer generation |

---

## One-liner recall

> Extractive copies verbatim sentences (zero hallucination, choppy); abstractive uses LLM generation with Map-Reduce for long docs; always gate production abstractive output with a faithfulness score and fall back to extractive when it fails.
