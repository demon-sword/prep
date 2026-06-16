# What's an RAG model? Explain the complete process.

**Category:** 01-llm-fundamentals
**Question #:** 012
**Source section:** §1 — LLM fundamentals (Core concepts)
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
Interviewers use this as a gating question at technical screens and deep dives. It distinguishes candidates who can parrot a definition ("retrieval-augmented generation") from those who understand the full production pipeline — including chunking strategy, embedding choice, retrieval failures, and evaluation. It's also a warm-up for system design rounds where a RAG pipeline is the core deliverable.

### Trigger phrases
- "What is RAG and how does it work?"
- "Walk me through how you'd build a RAG system."
- "How would you use GPT-4 to answer questions from our internal documents?"

### What it tests
End-to-end pipeline fluency: can the candidate describe the 9 stages of a production RAG system, name the failure points at each stage, and explain why RAG is often better than fine-tuning for knowledge injection.

---

## Answer

### Concept
RAG (Retrieval-Augmented Generation) is an architecture that gives an LLM access to an external knowledge store at inference time — rather than baking knowledge into model weights via fine-tuning. The model receives a query, relevant documents are retrieved from a vector store, and those documents are injected into the prompt as context before generation. This keeps the model's parametric knowledge general while the retrieved context supplies up-to-date, domain-specific facts.

### Mechanism
A production RAG system has two main phases: **offline indexing** and **online serving**.

**Offline (indexing pipeline):**
1. **Ingest** — load raw documents (PDFs, HTML, databases). Handle updates via change-data-capture or periodic re-index.
2. **Chunk** — split documents into retrievable units. Fixed-size (512 tokens) is simple; semantic / parent-child chunking (LlamaIndex) preserves context. Chunk size is the single biggest tuning lever.
3. **Embed** — encode each chunk with an embedding model (OpenAI `text-embedding-3-large`, Cohere `embed-v3`, or `bge-large-en` for self-hosted). Store the dense vectors.
4. **Index** — insert vectors into a vector DB (Pinecone, Weaviate, pgvector, FAISS). Use HNSW for ANN search at recall/latency tradeoff. Optionally build a BM25 sparse index in parallel for hybrid search.

**Online (serving pipeline):**
5. **Retrieve** — encode the user query, run ANN top-k (k=10–20) against the vector DB. Apply metadata filters (date, source, tenant) at the DB layer.
6. **Rerank** — optionally pass top-k results through a cross-encoder (Cohere Rerank, `bge-reranker-v2`) to re-score by query-document relevance and keep top-3–5. This improves precision without hurting recall.
7. **Generate** — assemble retrieved chunks into the prompt context and call the LLM (GPT-4o, Claude 3.5 Sonnet). Place most-relevant chunks at the beginning or end of context — not the middle — to avoid "lost in the middle" degradation.
8. **Evaluate** — measure faithfulness (does the answer stick to the retrieved context?), answer relevancy, and context precision/recall using RAGAS or a custom LLM-as-judge harness.
9. **Observe** — trace every request end-to-end (LangSmith, Phoenix/Arize). Maintain a golden QA set; run regression before any index or prompt change.

### Example / Tradeoff
At a customer support chatbot serving 500K queries/day: 
- **Chunk size tradeoff**: 256-token chunks give precise retrieval but may split key answers across chunks; 1024-token chunks capture more context but dilute relevance scores and inflate prompt cost.
- **Retrieval vs fine-tuning**: fine-tuning a model on support docs would lock knowledge at training time and cost $5K+; a nightly re-index costs ~$50/month and keeps answers current.
- **Reranking cost**: a cross-encoder adds ~30ms per query and reduces hallucination-on-wrong-context by ~40% in A/B tests. Worth it for high-stakes domains; skip for latency-sensitive chat.
- **Evaluation**: RAGAS metrics — faithfulness >0.85, answer relevancy >0.80 — gate weekly model upgrades.

---

## Verbal script

**Opening (30s):**
"RAG stands for Retrieval-Augmented Generation. The core idea is that instead of baking all domain knowledge into model weights, you retrieve relevant documents at query time and inject them as context. I'll walk through the full pipeline — there are two phases: offline indexing and online serving — and then highlight where things typically go wrong in production."

**Core explanation (2–3 min):**
"On the offline side, I start with ingestion — loading PDFs, databases, HTML, whatever the knowledge source is — and I need a strategy for updates: either event-driven re-indexing or a nightly batch job. Then comes chunking: I'm splitting documents into retrievable units. The chunk size is probably the single most impactful tuning decision. Too small and you miss context; too large and retrieval scores get diluted. I often start with 512-token chunks with 50-token overlap, then experiment.

Each chunk gets embedded — turned into a dense vector using a model like OpenAI's `text-embedding-3-large` or `bge-large-en` if I need self-hosted. Those vectors go into a vector database — Pinecone, Weaviate, pgvector — indexed with HNSW for fast approximate nearest-neighbor search.

At query time, the user's question is embedded the same way, and I retrieve the top-k most similar chunks — typically k=10 to 20. If the vocabulary mismatch is likely (technical terms, product names), I'll run hybrid search: BM25 for exact keyword matching combined with dense retrieval, fused via Reciprocal Rank Fusion. Then I pass the top candidates through a cross-encoder reranker to sharpen precision before sending the top 3–5 into the prompt. The LLM generates a grounded answer — and critically, I place the most-relevant chunks at the start or end of context to avoid the 'lost in the middle' phenomenon."

**Tradeoff / production angle (1 min):**
"The most common failure arc I've seen: retrieval silently degrades — wrong chunks come back — and the LLM still produces fluent-sounding answers, which users initially trust. That's why evaluation is non-negotiable: I run RAGAS metrics on a golden QA set — faithfulness, context precision, answer relevancy — and gate any index or prompt change on those numbers. I also instrument full request traces (LangSmith or Phoenix) so when a user flags a wrong answer, I can replay the exact retrieval and generation steps."

**Wrap-up (30s):**
"So RAG is a 9-stage pipeline, not a library call. The two most critical decisions are chunk size and retrieval quality — everything else is relatively straightforward. Happy to go deeper on any stage, or I can walk through how I'd evaluate this system end-to-end."

---

## Pitfalls

- **Mistake:** Describing RAG as "embed documents, store in a vector DB, retrieve and generate" — stopping at 3 steps. — **Better:** Walk the full 9-stage pipeline including chunking strategy, reranking, evaluation with RAGAS, and observability/tracing. Interviewers at FAANG and AI startups expect production depth.
- **Mistake:** Saying "RAG prevents hallucinations" without qualification. — **Better:** RAG reduces hallucinations by grounding generation in retrieved context, but the LLM can still hallucinate if the retrieved chunks are irrelevant or if it ignores them. Faithfulness scoring (RAGAS) and a temperature=0 setting are needed to make that claim defensible.
- **Mistake:** Recommending fine-tuning first, then RAG if it doesn't work. — **Better:** The decision tree is prompt engineering → RAG → fine-tune. RAG should be the first tool for knowledge injection because it's cheaper to update, auditable, and doesn't require retraining.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q13: What are embeddings?](01-013-what-are-embeddings.md) | Direct prerequisite — embeddings power RAG retrieval |
| [Q5: Explain context windows and their limitations](01-005-explain-context-windows-and-their-limitations.md) | Context window limits constrain how many retrieved chunks fit in the prompt |
| [Q1: How do LLMs work?](01-001-how-do-llms-work.md) | Foundation — RAG extends the base LLM generation loop |

---

## One-liner recall

> RAG is a 9-stage offline+online pipeline (ingest → chunk → embed → index → retrieve → rerank → generate → evaluate → observe) that grounds LLM generation in live retrieved context instead of baked-in weights, making knowledge cheap to update and answers auditable.
