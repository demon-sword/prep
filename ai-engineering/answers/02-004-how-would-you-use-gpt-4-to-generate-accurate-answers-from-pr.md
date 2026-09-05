# How would you use a frontier model to generate accurate answers from proprietary documents?

**Category:** 02-rag-systems
**Question #:** 004
**Source section:** §2 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
This question tests whether you know that "just throw documents into a frontier model" is not a production architecture. Interviewers want to see: (1) RAG as the preferred pattern for proprietary knowledge (not fine-tuning), (2) pipeline discipline around accuracy — chunking, hybrid retrieval, reranking, grounding prompts, (3) eval and hallucination control, and (4) practical knowledge of a frontier model's API (context limits, cost, structured outputs). It often comes from less technical interviewers who frame it around the model name rather than the system.

### Trigger phrases
- "How would you use a frontier model to generate accurate answers from our internal documents?"
- "We have a large knowledge base — how do you get a frontier model to answer from it?"
- "Can you just feed all our docs to a frontier model and have it answer questions?"
- "How do you ground a frontier model answers in proprietary data without fine-tuning?"

### What it tests
Production RAG architecture for proprietary documents — grounding LLM outputs in retrieved context while controlling hallucination, cost, and accuracy.

---

## Answer

### Concept
You do not feed all documents to a frontier model at once — you build a **Retrieval-Augmented Generation (RAG)** pipeline that retrieves only the most relevant excerpts at query time and passes them as grounding context to a frontier model. This keeps the model accurate (it only answers from what was retrieved), cost-efficient (you pay for ~2K tokens of context per query, not the full corpus), and up-to-date (new docs are indexed without retraining).

### Mechanism

**Step 1 — Ingest and chunk proprietary documents**
- Parse all formats: PDFs (PyMuPDF), Word docs (python-docx), HTML, Confluence pages, Notion exports, Zendesk articles
- Chunk into retrievable units: recursive character chunking at 512 tokens (80-token overlap) for prose; parent-child chunking for structured manuals (256-token child, 1024-token parent); table-aware chunking for financial/legal docs (keep rows intact)
- Tag each chunk with metadata: source, doc type, section, last-updated timestamp

**Step 2 — Embed and index**
- Embed every chunk with `text-embedding-3-large` (OpenAI, 3072-dim, cheapest per-token for quality) or `bge-large-en-v1.5` (open-source, self-hosted, avoids vendor lock-in)
- Store in a vector index (Pinecone, Qdrant, or pgvector for small-scale) with HNSW for sub-100ms ANN search
- Also maintain a BM25 keyword index (Elasticsearch or Typesense) for exact-match queries

**Step 3 — Hybrid retrieval at query time**
- Run both dense ANN and BM25 in parallel; fuse with Reciprocal Rank Fusion (RRF) → top-50 candidates
- Apply metadata filters pre-retrieval if relevant (document type, department, date range)
- Run a cross-encoder reranker (Cohere Rerank v3 or `ms-marco-MiniLM-L-12-v2`) on top-50 → select top-5 chunks

**Step 4 — Grounded prompt construction**
```
System: You are an assistant for Acme Corp internal knowledge.
Answer ONLY from the context below. If the answer is not in the context, say
"I don't have enough information to answer this" — do not guess or fabricate.

Context:
[Chunk 1 — most relevant]
[Chunk 2]
[Chunk 3]
[Chunk 4]
[Chunk 5 — second most relevant]

User question: {user_query}
```
- Place highest-ranked chunks first and last (avoiding the "lost in the middle" degradation)
- Include source attribution in the prompt instruction so the model outputs citations

**Step 5 — Generate with a frontier model**
- Use a small fast model such as `claude-haiku-4-5` for standard queries (temperature=0 for accuracy; ~$0.001 per 1K input tokens)
- Escalate to `claude-sonnet-5` for complex multi-document synthesis (longer context, stronger reasoning)
- Request JSON-structured output with `response_format={"type": "json_object"}` if downstream systems need it

**Step 6 — Post-process and validate**
- Extract citations from the response; strip any answer not grounded in a retrieved chunk
- Run a faithfulness gate if accuracy SLO is strict: RAGAS `faithfulness` score (NLI-based entailment) or a lightweight LLM-as-judge call
- Return `answer + sources[]` to the user

### Example / Tradeoff

**Proprietary legal knowledge base (300K contracts):**
- Embedding: `text-embedding-3-large` → Qdrant (HNSW, cosine)
- BM25: Elasticsearch for exact clause/reference number retrieval
- Reranker: Cohere Rerank v3 (API) — avoids infra overhead for legal team
- Generator: `claude-sonnet-5` at T=0 (accuracy requirement overrides cost for legal)
- Faithfulness gate: custom LLM-judge prompt checking "does the answer follow directly from the cited context?" before returning to user

**Cost at scale (1M queries/day):**
| Component | Cost/query | Daily |
|-----------|-----------|-------|
| Embedding (query only) | ~$0.0001 | ~$100 |
| Cohere Rerank | ~$0.001 | ~$1,000 |
| A small fast model generation | ~$0.0045 | ~$4,500 |
| Semantic cache hit (~30%) | saves ~$1,700 | |
| **Net total** | **~$0.0039** | **~$3,900** |

**Key tradeoff:** Long-context (a current ~1M-token window) vs RAG
- With ~1M-token windows, far more documents now *fit* than in 2024 — so "it doesn't fit" is no longer the argument. The argument is economics and precision: a 500K-token prompt at frontier input pricing is about $2.50 per query in input tokens alone, versus well under a cent with RAG, plus tens of seconds of prefill latency and no precision routing
- RAG wins on cost, latency, and accuracy at scale; long-context is a fallback for complex multi-document synthesis tasks

---

## Verbal script

**Opening (30s):**
"The framing of 'using a frontier model on documents' is the right goal, but the naive approach — uploading all your docs and asking questions — doesn't work at scale. What you actually build is a RAG pipeline: you retrieve only the relevant excerpts for each query and pass them as grounding context to a frontier model. That's how you get accuracy, control cost, and stay current without retraining."

**Core explanation (2–3 min):**
"The pipeline has six main steps. First, you ingest your proprietary documents — PDFs, Word files, Confluence pages, whatever — and chunk them into retrievable units. Chunk size matters: 512 tokens with 10% overlap works well for prose; parent-child chunking handles longer structured documents. Then you embed each chunk and build two indexes: a vector index in something like Pinecone or Qdrant for semantic search, and a BM25 index in Elasticsearch for exact keyword matching. Proprietary documents almost always have specific product names, IDs, or clause references that dense embeddings alone miss.

At query time, you run both retrievals in parallel, fuse the result lists with Reciprocal Rank Fusion, then run a cross-encoder reranker — I'd use Cohere Rerank or a local ms-marco model — to get the five most relevant chunks. That's your context for a frontier model.

The prompt structure is critical for accuracy. You tell a frontier model explicitly: 'Answer only from the context below. If the answer isn't there, say you don't know.' Temperature=0 for determinism. Place the best chunks first and last — there's strong evidence that models attend less to the middle of long contexts. Include a citation instruction so every answer comes with a source reference."

**Tradeoff / production angle (1 min):**
"The question I always get is: 'Windows are a million tokens now — why not just dump all the docs in?' In 2024 the answer was 'it doesn't fit.' That answer is gone, and if you still give it you sound two years out of date. The honest 2026 answer is economics, latency, and precision. A 500K-token prompt costs on the order of dollars per query in input tokens alone at frontier pricing, against roughly $0.004 per query with RAG — at 1M queries/day that difference is the whole company. Prefill latency on a very long prompt runs to tens of seconds versus sub-2 seconds with RAG. RAG also gives you precision routing — you only send the relevant paragraphs, so the model doesn't get confused by noise from unrelated documents.

For strict accuracy requirements — legal, medical, financial — I'd add a faithfulness gate: an LLM-as-judge call that checks whether the answer can be directly entailed from the cited chunks before returning it to the user."

**Wrap-up (30s):**
"So the recipe is: RAG pipeline with hybrid retrieval + cross-encoder reranking + grounding prompt at T=0 + source citations. That's how you get a frontier model to be both accurate and trustworthy on proprietary data. Happy to go deeper on any stage — the chunking strategy for complex documents, the faithfulness gate, or how I'd set up the eval framework."

---

## Pitfalls

- **Mistake:** Suggesting "just fine-tune a frontier model on the proprietary documents" as the primary approach — **Better:** Fine-tuning teaches behavior (style, format, tone), not knowledge retrieval; RAG is the right tool for grounding answers in proprietary data that updates frequently; fine-tuning is only warranted when behavior can't be fixed by prompt engineering or RAG
- **Mistake:** Proposing dense-only semantic search without hybrid BM25 — **Better:** Proprietary documents are full of exact-match tokens (product codes, clause numbers, policy IDs, acronyms) that dense embeddings systematically miss; always add BM25 and fuse with RRF
- **Mistake:** Saying "use temperature=1 so the model is creative" — **Better:** For factual Q&A from proprietary docs, temperature=0 is mandatory; you want deterministic, reproducible, grounded answers, not creative hallucinations
- **Mistake:** Not mentioning evaluation — treating accuracy as qualitative — **Better:** Build a 100–200 question golden dataset with verified answers from the actual document corpus; gate every change on RAGAS faithfulness and context_recall before shipping

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q1: Design a RAG system for a customer support chatbot](02-001-design-a-rag-system-for-a-customer-support-chatbot-how-do-yo.md) | Full 9-stage pipeline this answer abbreviates |
| [Q8: How handle hallucination when no information is found in context?](02-008-how-handle-hallucination-when-no-information-is-found-in-con.md) | Directly addresses the "what if retrieval returns nothing useful?" failure mode |
| [Q12: Compare sparse vs dense retrieval. When use each?](02-012-compare-sparse-vs-dense-retrieval-when-use-each.md) | Expands on the hybrid BM25 + dense retrieval layer recommended here |

---

## One-liner recall

> Accurate a frontier model answers from proprietary docs = RAG pipeline: hybrid BM25+dense retrieval → cross-encoder rerank to top-5 → grounding prompt at T=0 with explicit "answer only from context" instruction + citations; evaluate with RAGAS faithfulness on a golden dataset.
