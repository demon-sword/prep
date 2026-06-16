# Design a generative QA assistant for your company's knowledge base

**Category:** 02-rag-systems
**Question #:** 005
**Source section:** §2 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
The interviewer wants to see whether you can translate a common product requirement ("make our docs searchable with AI") into a complete, production-grade architecture. It probes: do you think end-to-end (ingestion through evaluation), do you understand the failure modes specific to *internal* knowledge (stale docs, ACLs, messy formatting), and can you make concrete engineering tradeoffs rather than describing a toy demo?

### Trigger phrases
- "Design a QA assistant over our internal knowledge base / Notion / Confluence"
- "We want employees to be able to ask questions and get answers from our docs"
- "Build a generative search experience on top of our internal documentation"
- "How would you make our runbooks / wikis / knowledge base queryable by an LLM?"

### What it tests
End-to-end RAG architecture fluency with internal-data constraints: access control, freshness, heterogeneous sources, and a rigorous eval loop.

---

## Answer

### Concept
A generative QA assistant over an internal knowledge base is a RAG pipeline that (1) indexes company documents with access-control metadata, (2) retrieves the most relevant chunks at query time using hybrid search, and (3) generates a grounded, citation-backed answer using an LLM—with an evaluation layer to catch hallucinations and measure quality over time.

### Mechanism

**Phase 1 — Ingestion & indexing**

| Step | Detail |
|------|--------|
| **Source connectors** | Pull from Confluence, Notion, Google Drive, Slack, GitHub via APIs; webhooks or scheduled polling for freshness (15-min lag typical) |
| **Document parsing** | PyMuPDF for PDFs, `confluence-python-api` for wiki pages, `markdownify` for HTML → Markdown; strip nav/footer boilerplate |
| **ACL extraction** | Capture space/page-level permissions at ingest time; store `allowed_groups: ["eng", "legal"]` as vector metadata |
| **Chunking** | Recursive character splitter: 512 tokens with 64-token overlap; parent-child for long docs (parent=2 048 tokens for context, child=256 for retrieval) |
| **Embedding** | `text-embedding-3-large` (OpenAI) or `bge-large-en-v1.5` (self-hosted); batch via async jobs, store in Pinecone or Qdrant |
| **BM25 index** | Elasticsearch or OpenSearch alongside vector store; same doc IDs for RRF fusion |

**Phase 2 — Retrieval at query time**

```
User query
  → ACL filter (user's groups → metadata filter on vector store)
  → Query rewriting (LLM expands acronyms, disambiguates pronouns in multi-turn)
  → Hybrid search: dense top-20 + BM25 top-20
  → Reciprocal Rank Fusion → top-40 candidates
  → Cross-encoder rerank (Cohere Rerank or ms-marco-MiniLM) → top-5 chunks
  → Context assembly (place most relevant chunk first and last; middle for lower-scored)
```

**Phase 3 — Generation**

- System prompt: *"Answer using only the provided context. If the answer is not in the context, say 'I don't have that information.' Cite sources as [Doc Title, Section]."*
- Model: GPT-4o-mini for ≤3K context (fast, cheap); GPT-4o for complex multi-doc synthesis
- Temperature: 0 (determinism matters for enterprise Q&A)
- Output: answer + inline citations + confidence hint ("Based on 3 documents from…")

**Phase 4 — Evaluation**

| Metric | Tool | Target |
|--------|------|--------|
| Faithfulness | RAGAS | ≥ 0.85 |
| Context recall | RAGAS | ≥ 0.80 |
| Answer relevance | RAGAS | ≥ 0.80 |
| Deflection rate | Production log | < 10% "I don't know" on known topics |
| p95 latency | Datadog | < 3 s end-to-end |

Golden dataset: 100 curated Q&A pairs from SMEs, run on every model/prompt change; block deployment if faithfulness drops > 5%.

### Example / Tradeoff

**Stack decision at 50K internal docs:**
- Pinecone Serverless: simple ops, $70/month at this scale — good start
- Self-hosted Qdrant: $0 infra cost, full control for regulated data (HIPAA, SOC 2) — upgrade path when compliance requires it

**Key tradeoff — freshness vs cost:**
Polling Confluence every 15 min keeps docs fresh but creates embedding churn (~$0.002/1K tokens × N changed pages/day). Webhook-triggered incremental re-embedding (only changed pages) cuts cost 80% but requires reliable webhook infrastructure. Start with polling, migrate to webhooks at scale.

**Key tradeoff — model size vs latency:**
GPT-4o at T=0 costs ~$0.005/query; GPT-4o-mini at ~$0.0005/query. For a 10K-employee company with 5K queries/day that's $25/day vs $2.50/day. Route simple factual questions (short context, high retrieval confidence) to mini; escalate to full GPT-4o when cross-encoder confidence < 0.6.

---

## Verbal script

**Opening (30s):**
"I'd approach this as a production RAG system with four concerns unique to internal knowledge bases: access control, freshness, heterogeneous source formats, and a rigorous eval loop — because you can't afford employees getting confidently wrong answers about company policy or legal requirements."

**Core explanation (2–3 min):**
"Let me walk through the pipeline end to end.

**Ingestion:** I'd build connectors for the main sources — Confluence, Notion, Google Drive, Slack, GitHub — using their APIs with either webhooks for near-real-time freshness or 15-minute polling as a simpler start. During parsing, I'd use PyMuPDF for PDFs and markdownify for HTML, and critically I'd strip navigation chrome and footers that pollute chunks. Most importantly, I'd extract ACL metadata at ingest time — which groups or users can see each document — and store that as vector metadata.

**Chunking and embedding:** I'd use recursive character splitting at 512 tokens with 64-token overlap, plus a parent-child pattern for long docs so retrieval fetches the child chunk but the LLM gets the parent context. For embedding, `text-embedding-3-large` for cloud deployments or `bge-large-en-v1.5` self-hosted for regulated environments. I'd run parallel BM25 indexing in Elasticsearch for hybrid search.

**Retrieval:** Every query first enforces ACL — filter by the user's group membership before even hitting the vector store. Then I run hybrid search: dense top-20 plus BM25 top-20, fuse with Reciprocal Rank Fusion, and cross-encoder rerank down to 5 chunks using Cohere Rerank or an MS-MARCO model. The context assembly order matters — I place the highest-scored chunk first, because of the 'lost in the middle' problem.

**Generation:** System prompt explicitly says 'answer only from context, cite your sources, say you don't know if it's absent.' Temperature zero. GPT-4o-mini for simple queries, GPT-4o for complex synthesis — routing based on context length and reranker confidence score."

**Tradeoff / production angle (1 min):**
"The two biggest production challenges are freshness and evaluation. For freshness, I'd start with polling and move to webhook-triggered incremental re-embedding once I've proven the system works — that cuts embedding cost by ~80%. For eval, I'd build a golden dataset of 100 curated Q&A pairs from domain experts and run RAGAS faithfulness and context recall on every deploy. If faithfulness drops more than 5 percentage points, the deploy is blocked. I'd also track deflection rate in production — if 'I don't have that information' responses exceed 10% on topics we *should* cover, that signals a retrieval problem, not a generation problem."

**Wrap-up (30s):**
"So the architecture is: ACL-aware hybrid RAG with cross-encoder reranking, a grounding prompt with citations, model tiering for cost control, and a golden-dataset eval gate. Happy to go deeper on any layer — ACL enforcement, chunking strategies for complex formats, or the eval framework."

---

## Pitfalls

- **Mistake:** Describing a simple vector search with no ACL enforcement — **Better:** Explicitly cover how user group membership filters vector store queries at retrieval time; a knowledge base assistant that leaks confidential docs to unauthorized users is a P0 incident.
- **Mistake:** Saying "I'd just use OpenAI embeddings and GPT-4" without addressing freshness or stale indexes — **Better:** Explain the ingestion loop (webhook vs polling), incremental re-embedding on doc changes, and how you detect embedding drift over time.
- **Mistake:** Skipping evaluation and saying "users will give thumbs up/down" — **Better:** Describe a structured RAGAS-based golden dataset eval (faithfulness ≥ 0.85, context recall ≥ 0.80) run on every prompt or model change, plus production metrics (deflection rate, p95 latency).
- **Mistake:** Ignoring format heterogeneity — **Better:** Call out that internal docs include PDFs, Confluence pages, Slack threads, and code; each needs a different parser, and tables/code blocks need special chunking treatment to avoid splitting logical units.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q1: Design a RAG system for a customer support chatbot](02-001-design-a-rag-system-for-a-customer-support-chatbot-how-do-yo.md) | Same RAG architecture; customer support adds deflection/CSAT metrics; knowledge base adds ACL and internal source heterogeneity |
| [Q10: Design a Q&A system over internal documentation](02-010-design-a-qa-system-over-internal-documentation.md) | Near-identical question — use same 4-phase framework; Q10 may push harder on search ranking metrics (NDCG, MRR) |
| [Q11: How ensure quality of data the LLM interacts with?](02-011-how-ensure-quality-of-data-the-llm-interacts-with.md) | Direct follow-up: data quality pipeline (deduplication, freshness, formatting normalization) is a prerequisite for good QA assistant accuracy |

---

## One-liner recall

> A generative QA assistant over an internal knowledge base is ACL-aware hybrid RAG (dense + BM25 → RRF → cross-encoder rerank → grounding prompt at T=0 with citations) with a golden-dataset RAGAS eval gate and webhook-driven incremental re-embedding for freshness.
