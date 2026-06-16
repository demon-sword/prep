# How ensure quality of data the LLM interacts with?

**Category:** 02-rag-systems
**Question #:** 011
**Source section:** §2 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
The interviewer is probing whether you treat data quality as a first-class engineering concern or an afterthought. In production RAG systems, the LLM's output is only as good as the context fed to it — garbage-in is garbage-out at inference time. Strong candidates articulate a layered quality system covering ingestion validation, chunking hygiene, embedding drift detection, and runtime relevance gating.

### Trigger phrases
- "How do you ensure quality of data the LLM interacts with?"
- "What does your data quality pipeline look like for a RAG system?"
- "How do you prevent bad context from reaching the model?"
- "What guardrails exist before documents hit your vector store?"

### What it tests
Data engineering discipline applied to LLM pipelines — schema validation, quality gates at each RAG stage, and production monitoring to catch data degradation before it silently ruins outputs.

---

## Answer

### Concept
Data quality for LLM systems is enforced in three layers: **ingestion-time validation** (structural and content checks before anything is stored), **retrieval-time relevance gating** (cosine-similarity thresholds and cross-encoder reranking that filter low-quality context before it reaches the LLM), and **output-time faithfulness monitoring** (RAGAS/NLI checks that detect when bad context caused a bad generation). You cannot rely on the LLM to compensate for poor data — it will confidently hallucinate from noisy context.

### Mechanism

**Layer 1 — Ingestion & pre-processing quality gates**
1. **Schema validation:** Every ingested document must pass a schema check (file type allowlist, minimum text length ≥ 100 chars, encoding UTF-8, language detection). Reject or quarantine malformed docs.
2. **Content deduplication:** Exact-hash (MD5/SHA-256) dedup on document IDs, then near-duplicate detection with MinHash/LSH (Jaccard ≥ 0.85 → deduplicate). Prevents vector-store bloat and biased retrieval toward duplicated content.
3. **PII scrubbing:** Run a NER pass (spaCy + Presidio) to detect and mask SSNs, credit card numbers, and email addresses before embedding. Prevents PII leakage through LLM outputs.
4. **Chunk-level quality:** After chunking, filter out chunks that are < 50 tokens (likely header/footer noise), > 95% numeric (likely a table fragment with no linguistic context), or have OCR confidence < 0.80 (Textract confidence score).
5. **Metadata completeness:** Every chunk must carry `source_url`, `doc_id`, `created_at`, `last_modified`. Missing metadata prevents citation generation and freshness filtering.

**Layer 2 — Retrieval-time gating**
6. **Cosine-similarity threshold:** After ANN retrieval from Pinecone/Qdrant, discard any chunk with cosine similarity < 0.70 (tune threshold on golden eval set). Low-similarity chunks are noise.
7. **Cross-encoder reranking:** Run a cross-encoder (Cohere Rerank, BGE-Reranker-v2) on the top-20 retrieved chunks. Only pass the top-5 with score > 0.5 to the LLM. This is your strongest quality filter — cross-encoders catch semantic irrelevance that bi-encoders miss.
8. **Freshness filter:** Add a recency boost or hard cutoff for time-sensitive domains (e.g., legal/medical: only chunks with `last_modified` within 90 days).

**Layer 3 — Output-time monitoring**
9. **Faithfulness gate:** Post-generation, run RAGAS `faithfulness` score. If < 0.80, suppress the LLM answer and return a canned "I don't have reliable information" response.
10. **Production drift monitoring:** Track weekly distribution of retrieval cosine scores and chunk-level quality signals. An embedding drift (caused by reindexing with a different model version) shows up as a sudden drop in average cosine similarity — alert and re-embed.

### Example / Tradeoff

At a fintech company ingesting 300K legal contracts (PDF+DOCX), the ingestion pipeline ran:
- Textract → confidence-gated OCR → Presidio PII masking → SHA-256 dedup → MinHash near-dedup → chunk quality filter (< 50 tokens dropped) → parent-child chunking (1024/256 tokens) → `text-embedding-3-small` batch embedding → Pinecone upsert with metadata sidecar.

The cross-encoder reranking step (BGE-Reranker-v2) alone improved precision@5 from 61% to 78% on the golden eval set, because early ANN retrieval was pulling in structurally similar but topically irrelevant boilerplate clauses.

**Tradeoff:** Every quality gate adds latency. PII scrubbing + cross-encoder reranking adds ~200ms per query. For high-QPS systems, run PII scrubbing offline (ingestion-time) and limit the reranker to top-20 candidates to control online latency.

---

## Verbal script

**Opening (30s):**
"Great question — data quality is where most RAG systems fail silently. I think about it in three layers: ingestion gates that prevent bad data from entering the index, retrieval gates that filter low-relevance context before it reaches the LLM, and post-generation monitoring that catches when bad context slips through. Let me walk through each."

**Core explanation (2–3 min):**
"At ingestion time, I'd run schema validation — file type allowlist, minimum text length, encoding checks — plus near-duplicate detection with MinHash/LSH. Anything with Jaccard similarity above 0.85 to an existing doc gets deduplicated. I'd also run PII scrubbing with Presidio before embedding, because if SSNs or credit card numbers get embedded, they can surface in LLM outputs. At the chunk level, I filter out chunks under 50 tokens — those are usually headers or footers — and anything with OCR confidence below 0.80 from Textract. And every chunk must carry structured metadata: source URL, doc ID, created/modified timestamps. Without that, you can't do freshness filtering or citations.

At retrieval time, after ANN retrieval from Pinecone, I apply a cosine similarity threshold — typically around 0.70, tuned on a golden eval set. Anything below that gets dropped before the LLM call. Then I run a cross-encoder reranker like Cohere Rerank or BGE-Reranker on the top-20 candidates, keeping only the top-5 with reranker score above 0.5. In my experience, this reranking step is the single highest-ROI quality gate — bi-encoders miss semantic irrelevance that cross-encoders catch easily.

Post-generation, I run RAGAS faithfulness on a sampled set of outputs. If faithfulness drops below 0.80, I suppress the answer and return a canned response. And I monitor the weekly distribution of retrieval cosine scores — a sudden drop signals embedding drift, usually from a model version mismatch."

**Tradeoff / production angle (1 min):**
"The tradeoff is latency and cost. PII scrubbing and cross-encoder reranking together add about 200ms per query. For high-QPS systems, I move PII scrubbing fully offline at ingestion time, and I cap the reranker input to top-20 to bound the latency hit. For cost, RAGAS faithfulness checks are expensive to run on every query — I sample 10% in production and run full checks on golden-set regressions before each deployment."

**Wrap-up (30s):**
"So the core principle is: never let the LLM compensate for bad data — it will hallucinate confidently from noisy context. Enforce quality gates at every stage: ingest, retrieval, and post-generation. Happy to go deeper on any layer."

---

## Pitfalls

- **Mistake:** Treating data quality as a one-time ETL concern and not monitoring for drift post-deployment — **Better:** Explain ongoing monitoring: track weekly cosine score distributions, alert on drops > 5% from baseline, and gate deployments with golden-set regression tests via RAGAS.
- **Mistake:** Saying "we validate the data before loading it" without specifying what validation means — **Better:** Name concrete checks: schema validation, near-dedup with MinHash/LSH (Jaccard threshold), OCR confidence gating, chunk-length filtering, PII scrubbing with Presidio.
- **Mistake:** Relying solely on ingestion-time quality and assuming retrieval will self-correct — **Better:** Emphasize that retrieval-time gating (cosine threshold + cross-encoder reranking) is often more impactful than ingestion validation, because the LLM sees ranked context, not raw documents.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q1: Design a RAG system for a customer support chatbot](02-001-design-a-rag-system-for-a-customer-support-chatbot-how-do-yo.md) | Parent architecture — data quality is a sub-concern of the full RAG pipeline |
| [Q18: What is re-ranking? Cross-encoder vs bi-encoder?](02-018-what-is-re-ranking-cross-encoder-vs-bi-encoder.md) | The cross-encoder reranking gate is the retrieval-layer quality mechanism |
| [Q14: How protect sensitive/confidential data in a RAG pipeline?](02-014-how-protect-sensitiveconfidential-data-in-a-rag-pipeline.md) | PII scrubbing is a data quality + privacy concern addressed at ingestion |

---

## One-liner recall

> Data quality in RAG requires three layers — ingestion-time validation (schema, dedup, PII, chunk hygiene), retrieval-time gating (cosine threshold + cross-encoder reranking), and post-generation faithfulness monitoring — because the LLM cannot compensate for bad context and will hallucinate confidently from it.
