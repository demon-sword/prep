# 02. RAG Systems — AI Engineering Interview Category

Covers Retrieval-Augmented Generation end-to-end — from chunking strategy and vector indexing through retrieval, reranking, generation, evaluation, and production failure modes — the #1 topic pattern in 2026 AI engineering interviews.

---

## Interview signals

| You hear… | This category |
|-----------|---------------|
| "Design a RAG system for…" | End-to-end RAG pipeline design |
| "How would you evaluate a RAG pipeline?" | Eval metrics (RAGAS, NDCG, faithfulness) |
| "What is hybrid search and when do you use it?" | Dense + BM25 retrieval strategy |
| "Walk me through a RAG project you've built" | Production experience + failure modes |
| "What's the difference between sparse and dense retrieval?" | Retrieval architecture tradeoffs |
| "How do you handle hallucinations when context is missing?" | Generation guardrails + abstention |

---

## Mental model

A strong candidate understands RAG as a **nine-stage production pipeline** — not a two-step "retrieve then generate" sketch. Weak candidates describe RAG as "embedding your docs and asking questions" without grasping why each stage fails independently and how failures cascade: bad chunking degrades recall before a single embedding is computed; vocabulary mismatch means dense-only retrieval silently misses exact-match queries; "lost in the middle" means even perfect retrieval can produce wrong answers if context placement is naïve; and without a faithfulness gate, confident hallucinations ship to users. The expert mental model is: **retrieval is the load-bearing wall** — fix it before tuning generation, and measure it separately from end-to-end answer quality using RAGAS context_recall vs. faithfulness split. Every architectural choice (chunk size, index type, top-k, reranking, caching) is a tradeoff along three axes: accuracy, latency, and cost.

---

## Sub-topics

### 1. Pipeline Design & Chunking
**When:** "Design a RAG system for…", "How do you split documents?", "How handle PDF reports with cross-page context?"
**What:** RAG ingestion converts raw documents into retrievable chunks — the chunk strategy (fixed-size, recursive, semantic, parent-child) is the single biggest lever on retrieval recall before any model runs.
**Key questions:**
- Q1: Design a RAG system for a customer support chatbot. How do you evaluate it?
- Q6: System processing huge PDF reports — how handle context when splitting documents?
- Q16: Financial report: page 1 says "amounts in thousands" — how handle doc-wide context when chunking?

### 2. Retrieval Architecture (Sparse, Dense, Hybrid)
**When:** "Compare sparse vs dense retrieval", "What is hybrid search?", "How does ANN search work?", "Which vector DB would you use?"
**What:** Production RAG stacks hybrid retrieval — BM25 (sparse, keyword-exact) fused with bi-encoder dense HNSW search via Reciprocal Rank Fusion — followed by a cross-encoder reranker that refines the top-N before generation.
**Key questions:**
- Q12: Compare sparse vs dense retrieval. When use each?
- Q17: What is hybrid search? When combine vector + BM25?
- Q18: What is re-ranking? Cross-encoder vs bi-encoder?
- Q23: How does ANN search work? HNSW indexing?

### 3. Evaluation & Failure Modes
**When:** "How do you evaluate a RAG pipeline?", "Your RAG is giving confident wrong answers — how do you debug?", "What metrics do you track in production?"
**What:** RAG evaluation decomposes into retrieval metrics (NDCG, recall@k, MRR) and generation metrics (faithfulness, answer relevancy, context precision/recall via RAGAS) — conflating them hides the root cause of failures.
**Key questions:**
- Q13: Common RAG failure points — how debug them?
- Q21: How evaluate a RAG pipeline? NDCG, MRR, precision@k, recall?
- Q34: Weak evaluation hiding retrieval failures

### 4. Production Scaling & Cost
**When:** "Scale RAG to 10M+ articles", "How do you reduce latency?", "Semantic caching?", "Cost/latency/accuracy tradeoffs?"
**What:** At production scale, RAG cost and latency are controlled through semantic caching (skip embeddings + LLM for similar queries), model tiering (small reranker before large LLM), ANN index sharding, and prompt compression — each with accuracy tradeoffs to quantify.
**Key questions:**
- Q19: Scale RAG to 10M+ articles — sharding, caching, retrieval optimization.
- Q25: Semantic caching — reduce cost and latency?
- Q28: Optimize RAG latency in production?

---

## Decision framework

```
RETRIEVAL STRATEGY:
If query is exact-match, keyword-heavy, or domain-specific (legal codes, SKUs, IDs):
  → use BM25 (sparse) or hybrid  — keyword tokens must match exactly
Else if queries are semantic / natural language:
  → use dense HNSW (bi-encoder)  — cosine similarity over learned embeddings
Else (production default):
  → use HYBRID (BM25 + dense, fused with RRF)  — covers both failure modes
  → add cross-encoder reranker on top-50 to top-5  — precision over recall

CHUNKING STRATEGY:
If documents are well-structured prose (articles, support docs):
  → recursive character chunking (512 tokens, 10% overlap)
If documents have cross-page context (annual reports, legal contracts):
  → parent-child chunking: store full section + retrieve child chunks
If document structure is rich (markdown, code, tables):
  → semantic / structure-aware chunking that respects section boundaries
If chunk size unknown:
  → benchmark recall@5 on a golden set; typical sweet spot 256–512 tokens

EVALUATION APPROACH:
If debugging a live RAG issue:
  → split: test retrieval (context_recall) separately from generation (faithfulness)
  → fix retrieval first — it's the load-bearing stage
If building an eval framework:
  → RAGAS offline (faithfulness, answer_relevancy, context_recall, context_precision)
  → golden dataset with 50–200 Q&A pairs + ground-truth docs
  → production metrics: deflection rate, thumbs-down rate, p95 latency, cost/query

WHEN TO USE RAG vs. ALTERNATIVES:
If knowledge is stable and behavioral:
  → fine-tuning (LoRA/QLoRA) — baked-in behavior, no retrieval latency
If knowledge is dynamic, proprietary, or attribution is required:
  → RAG — real-time retrieval, source citations
If simple context fits in a single prompt:
  → prompt engineering — no infrastructure overhead
```

---

## Common mistakes

| Mistake | What to say instead |
|---------|---------------------|
| Describing RAG as "embed docs, do semantic search, pass to LLM" — skipping chunking, reranking, eval | Walk the full 9-stage pipeline: ingest → chunk → embed → index → retrieve → rerank → generate → evaluate → observe |
| Treating retrieval and generation failures as the same problem | "I split evaluation: RAGAS context_recall measures retrieval quality separately from faithfulness for generation" |
| Recommending only dense retrieval without mentioning vocabulary mismatch | "Dense retrieval fails on exact-match queries — product IDs, codes, names — so production always needs BM25 hybrid" |
| Choosing chunk size by feel ("I just used 500 tokens") | "I benchmark chunk size using recall@5 on a golden set; the optimal depends on doc structure and query length distribution" |
| Saying "increase top-k to retrieve more context" as a fix for poor answers | "Increasing top-k without reranking introduces noise and 'lost in the middle' degradation — the fix is better retrieval, not more context" |
| Not mentioning reranking | "After initial retrieval I add a cross-encoder reranker (e.g. ms-marco-MiniLM) on top-50 → top-5; it's the single biggest precision lever" |

---

## Question checklist

| # | Question | Difficulty signal | Status |
|---|----------|-------------------|--------|
| 1 | Design a RAG system for a customer support chatbot. How do you evaluate it? ⭐ | S | `todo` |
| 2 | How would you design an LLM-powered enterprise search system? | S | `todo` |
| 3 | Design a GenAI document-processing pipeline for unstructured data (emails, PDFs, images). | S | `todo` |
| 4 | How would you use GPT-4 to generate accurate answers from proprietary documents? | M | `todo` |
| 5 | Design a generative QA assistant for your company's knowledge base. | M | `todo` |
| 6 | System processing huge PDF reports — how handle context when splitting documents? | M | `todo` |
| 7 | How efficiently generate and store embeddings for products and queries? | M | `todo` |
| 8 | How handle hallucination when no information is found in context? | M | `todo` |
| 9 | What RAG projects have you worked on? | E | `todo` |
| 10 | Design a Q&A system over internal documentation. | M | `todo` |
| 11 | How ensure quality of data the LLM interacts with? | M | `todo` |
| 12 | Compare sparse vs dense retrieval. When use each? | M | `todo` |
| 13 | Common RAG failure points — how debug them? | S | `todo` |
| 14 | How protect sensitive/confidential data in a RAG pipeline? | M | `todo` |
| 15 | What vector databases have you used? Which and why? | M | `todo` |
| 16 | Financial report: page 1 says "amounts in thousands" — how handle doc-wide context when chunking? | S | `todo` |
| 17 | What is hybrid search? When combine vector + BM25? | M | `todo` |
| 18 | What is re-ranking? Cross-encoder vs bi-encoder? | M | `todo` |
| 19 | Scale RAG to 10M+ articles — sharding, caching, retrieval optimization. | S | `todo` |
| 20 | RAG returns relevant docs but users can't find the answer — search engine vs answer engine? | M | `todo` |
| 21 | How evaluate a RAG pipeline? NDCG, MRR, precision@k, recall? | S | `todo` |
| 22 | Citations and source attribution in RAG? | M | `todo` |
| 23 | How does ANN search work? HNSW indexing? | M | `todo` |
| 24 | Where do embeddings fail? Negation, temporal reasoning, precision requirements. | M | `todo` |
| 25 | Semantic caching — reduce cost and latency? | M | `todo` |
| 26 | RAG with multi-turn conversation context? | M | `todo` |
| 27 | Key tradeoffs: latency vs accuracy, chunk size vs context, cost vs quality? | S | `todo` |
| 28 | Optimize RAG latency in production? | S | `todo` |
| 29 | Bad chunking (fixed-size vs semantic) | M | `todo` |
| 30 | Vocabulary mismatch (dense-only failing on keywords) | M | `todo` |
| 31 | Lost in the middle / context pollution | M | `todo` |
| 32 | Hallucination when retrieved context is irrelevant or absent | M | `todo` |
| 33 | Stale indexes, embedding drift | M | `todo` |
| 34 | Weak evaluation hiding retrieval failures | S | `todo` |

---

## One-page summary

- **RAG = 9 stages, not 2:** ingest → chunk → embed → index → retrieve → rerank → generate → evaluate → observe. Retrieval is the load-bearing stage — fix it before touching generation.
- **Always hybrid retrieval in production:** BM25 handles exact-match/keyword queries that dense retrieval silently misses (product IDs, names, codes). Fuse with Reciprocal Rank Fusion; rerank top-50 → top-5 with a cross-encoder (ms-marco-MiniLM or Cohere Rerank).
- **Evaluation is split:** RAGAS `context_recall` measures retrieval; `faithfulness` measures generation. A high faithfulness score with low context_recall means the model is hallucinating fluently — the retrieval is broken, not the generator.
- **Production levers for cost/latency:** semantic cache (GPTCache, skip embed+LLM for similar queries ~40% hit rate), async embedding pipeline, top-N reranking only (not full corpus), LLMLingua prompt compression, model tiering (small model for simple queries).
- **Key failure modes to name explicitly:** bad chunking (fixed-size splits tables mid-row), vocabulary mismatch (dense misses keywords), lost in the middle (Liu et al. 2023 — accuracy drops from 70%→45% when gold doc is in the middle of context), embedding drift (re-embed after model upgrade), weak eval (vibes-based eval hides retrieval failures until users complain).
