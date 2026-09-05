# Design a RAG system for a customer support chatbot. How do you evaluate it? ⭐

**Category:** 02-rag-systems
**Question #:** 001
**Source section:** §2 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
This is the #1 pattern in AI engineering interviews (2024–2026). The interviewer is probing whether you understand RAG as a **production engineering discipline** — not an academic sketch. They want to see: (1) end-to-end pipeline thinking across all 9 stages, (2) awareness of where each stage fails and how failures cascade, (3) concrete evaluation strategy with both offline and production metrics, and (4) cost/latency tradeoffs at real scale. It is also a proxy for system design skill — how you structure a complex distributed system with multiple interacting components.

### Trigger phrases
- "Design a RAG system for a customer support chatbot. How do you evaluate it?"
- "Walk me through how you'd build an LLM-powered support assistant from scratch."
- "How would you architect a chatbot that answers from our documentation?"
- "If I gave you a corpus of 100K support tickets and a KB, how would you build a Q&A system?"

### What it tests
End-to-end production RAG pipeline design — from ingestion through evaluation — including retrieval strategy, failure modes, and measurable eval framework.

---

## Answer

### Concept
RAG (Retrieval-Augmented Generation) is an architecture that grounds LLM responses in a retrieved document corpus, preventing hallucination and enabling the model to answer questions about proprietary or frequently-updated knowledge without fine-tuning. For a customer support chatbot, RAG retrieves the most relevant support articles, product docs, or past tickets, then passes them as context to the LLM to synthesize a grounded answer.

### Mechanism

The production pipeline has **9 stages**:

**Ingestion (offline)**

| Stage | What happens | Key decisions |
|-------|-------------|---------------|
| **1. Ingest** | Pull docs from Confluence, Zendesk, Notion, S3, PDFs | Change detection (webhooks or hash-diff); partial re-index on update |
| **2. Chunk** | Split into retrievable units | Recursive character chunking (512 tokens, 10% overlap) for prose; parent-child for long PDFs; semantic chunking for rich-structure docs |
| **3. Embed** | Encode each chunk into a dense vector | `text-embedding-3-large` (OpenAI) or `bge-large-en-v1.5` (BAAI) for self-hosted; run async batch embed pipeline |
| **4. Index** | Store vectors + metadata | Pinecone (managed) or Qdrant/Weaviate (self-hosted); HNSW index; also maintain BM25 index (Elasticsearch or OpenSearch) for hybrid |

**Retrieval (online, per query)**

| Stage | What happens | Key decisions |
|-------|-------------|---------------|
| **5. Retrieve** | Dual-retrieval: BM25 + dense HNSW; fuse with Reciprocal Rank Fusion (RRF) | Top-50 candidates; metadata filters (product line, language, ticket type) applied pre-retrieval to narrow search space |
| **6. Rerank** | Cross-encoder on top-50 → top-5 | `ms-marco-MiniLM-L-12-v2` (open-source) or Cohere Rerank API; this is the biggest single precision lever |

**Generation**

| Stage | What happens | Key decisions |
|-------|-------------|---------------|
| **7. Generate** | Construct prompt: system instructions + retrieved chunks (most relevant first and last) + user query; call LLM | a small fast model for cost/latency, a frontier model for complex multi-step; temperature=0 for determinism; include citations |

**Eval + Observe (continuous)**

| Stage | What happens | Key decisions |
|-------|-------------|---------------|
| **8. Evaluate** | RAGAS suite: faithfulness, answer_relevancy, context_recall, context_precision on golden dataset | Build 200-question golden set from real support tickets; gate deploys on regression |
| **9. Observe** | Production metrics + tracing | LangSmith or Langfuse for trace-level visibility; Prometheus for p95 latency, cost/query, deflection rate |

### Example / Tradeoff

**Concrete stack for a 50K-article support KB:**
- Pinecone (1536-dim vectors) + Elasticsearch BM25, RRF fusion
- Cohere Rerank v3 on top-50 → top-5
- A small fast model at temperature=0
- RAGAS eval on 200 golden Q&A pairs (real support tickets with verified answers)

**Production numbers to anchor the story:**
- Retrieval p95: ~80ms (HNSW) + ~200ms (cross-encoder rerank) = ~280ms retrieval
- LLM generation: ~600ms p50 (small fast model, streaming)
- Total TTFB: ~400ms with streaming
- Cost: ~$0.002/query at 50K questions/day = ~$100/day before semantic caching
- Semantic cache (GPTCache, cosine threshold 0.95): ~35–40% cache hit rate → ~$60/day

**The tradeoff interviewers probe:** "Why rerank instead of just increasing top-k?"
- Increasing top-k without reranking introduces the **"lost in the middle"** problem (Liu et al. 2023) — accuracy drops from ~70% → ~45% when the relevant chunk sits in the middle of a 20-chunk context window
- Cross-encoder reranking on a small candidate set (top-50) adds ~150ms latency but improves precision@5 by 15–25% — a clear win

---

## Verbal script

**Opening (30s):**
"I'd approach this as a 9-stage production pipeline — the naive sketch of 'embed docs, do semantic search, pass to the LLM' misses where real systems actually fail. Let me walk through it end-to-end, and then I'll talk about how I'd evaluate it in production."

**Core explanation (2–3 min):**
"The pipeline has two phases: offline ingestion and online retrieval-generation.

For ingestion, I'd pull docs from wherever they live — Confluence, Zendesk, PDFs — using a change-detection system so we re-index only what's changed. The chunking strategy matters a lot: for support articles that are mostly prose, I'd use recursive character chunking at about 512 tokens with 10% overlap. For longer structured docs like manuals, I'd use parent-child chunking — small retrieval chunks pointing to larger parent sections — so we get precise retrieval without losing surrounding context. Then I'd embed with something like `text-embedding-3-large` or `bge-large-en-v1.5` for self-hosted. I'd maintain two indexes: a vector index in Pinecone or Qdrant using HNSW, and a BM25 index in Elasticsearch.

On the retrieval side, production RAG always needs hybrid retrieval. Dense embeddings fail on exact-match queries — product IDs, model numbers, codes — which are extremely common in support. BM25 handles those. I'd fuse the two result lists using Reciprocal Rank Fusion to get top-50 candidates, then run a cross-encoder reranker — something like ms-marco-MiniLM or Cohere Rerank — to reorder to top-5. Reranking is the single biggest precision lever I've seen in production.

For generation, I'd call a small fast model at temperature=0, with a grounding prompt that says 'Answer only based on the provided context; if the answer isn't there, say so.' I'd place the most relevant chunks first and last in the context window to avoid the lost-in-the-middle problem."

**Tradeoff / production angle (1 min):**
"For evaluation, I separate retrieval quality from generation quality. I'd build a golden dataset of 200 real support questions with verified answers and the ground-truth docs that contain those answers. Then I'd run RAGAS: `context_recall` tells me whether my retrieval is finding the right chunks; `faithfulness` tells me whether the LLM is staying grounded in what was retrieved. These can diverge — you can have high faithfulness but low recall, which means the model is confidently wrong because it never retrieved the right doc.

In production, I'd track: deflection rate (did the user resolve without escalating?), thumbs-down rate, p95 latency, and cost per query. I'd gate every model or prompt change on the RAGAS golden set to catch regressions before they ship."

**Wrap-up (30s):**
"The key insight is that retrieval is the load-bearing wall. If your retrieval is broken, no amount of prompt tuning will fix it. Measure them separately, fix retrieval first, and never ship without a golden regression dataset. Happy to go deeper on any stage — chunking strategy, the reranking tradeoff, or how I'd scale this to 10M articles."

---

## Pitfalls

- **Mistake:** Describing RAG as "embed your docs and do semantic search" — stopping after 2 stages — **Better:** Walk the full 9-stage pipeline; name chunking, hybrid retrieval, reranking, and evaluation as distinct engineering decisions, not afterthoughts
- **Mistake:** Naming one big model for everything without discussing cost, latency, or when to use a smaller model — **Better:** "I'd default to a small fast model at temperature=0 for roughly an order of magnitude in cost savings; escalate to a frontier model for complex multi-step queries where reasoning quality matters"
- **Mistake:** Proposing "increase top-k" as the fix when answers are wrong — **Better:** "Increasing top-k without reranking causes 'lost in the middle' degradation — I'd add a cross-encoder reranker on the existing top-50 candidates instead"
- **Mistake:** Conflating retrieval failures with generation failures in evaluation — **Better:** "I separate RAGAS `context_recall` (did we retrieve the right chunks?) from `faithfulness` (did the LLM stay grounded?) — they fail for different reasons"

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q21: How evaluate a RAG pipeline? NDCG, MRR, precision@k, recall?](02-021-how-evaluate-a-rag-pipeline-ndcg-mrr-precisionk-recall.md) | Deep-dive on the eval metrics introduced here |
| [Q17: What is hybrid search? When combine vector + BM25?](02-017-what-is-hybrid-search-when-combine-vector-bm25.md) | Expands on the retrieval strategy recommended in this answer |
| [Q18: What is re-ranking? Cross-encoder vs bi-encoder?](02-018-what-is-re-ranking-cross-encoder-vs-bi-encoder.md) | Expands on the reranking stage — the biggest precision lever |

---

## One-liner recall

> RAG for customer support = 9-stage pipeline (ingest→chunk→embed→index→hybrid-retrieve→cross-encoder-rerank→generate@T=0→RAGAS-evaluate→observe); retrieval is the load-bearing stage — measure context_recall separately from faithfulness and fix retrieval first.
