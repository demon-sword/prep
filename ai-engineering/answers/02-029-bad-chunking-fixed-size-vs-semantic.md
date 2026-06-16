# Bad chunking (fixed-size vs semantic)

**Category:** 02-rag-systems
**Question #:** 029
**Source section:** §2 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
Interviewers ask this to probe whether a candidate understands that chunking is the **first and most consequential design decision** in a RAG pipeline — bad chunking degrades retrieval recall before any model runs, and no amount of reranking or prompt engineering rescues it. It tests practical production experience: have they actually debugged retrieval failures caused by chunk boundaries?

### Trigger phrases
- "Walk me through your chunking strategy — why did you choose that approach?"
- "Your RAG retrieval is returning partially relevant chunks — what would you investigate?"
- "Fixed-size vs semantic chunking — when does each fail?"

### What it tests
Whether the candidate can diagnose chunking as a retrieval failure root cause and select the right strategy (fixed-size, recursive, semantic, parent-child) for a given document type and query distribution.

---

## Answer

### Concept
Chunking is the process of splitting source documents into retrievable units before embedding. The strategy determines **what semantic unit the embedding represents** — and therefore whether the retrieved chunk will actually contain the answer. Bad chunking manifests as high embedding similarity at retrieval time but low answer quality at generation time: the chunk is "about" the right topic but the actual answer text is split across a boundary.

### Mechanism
There are four main chunking strategies, each with distinct failure modes:

| Strategy | How it works | Failure mode |
|----------|-------------|--------------|
| **Fixed-size** | Split every N tokens with optional overlap | Cuts mid-sentence, mid-table, mid-code block — destroys semantic units |
| **Recursive character** | Split on paragraph → sentence → word boundaries hierarchically (LangChain default) | Better than fixed-size but still boundary-agnostic for structured content |
| **Semantic / structure-aware** | Split at detected section boundaries (headers, blank lines, code fences) | Requires document structure to be parseable; fails on scanned PDFs |
| **Parent-child** | Index small child chunks (128–256 tokens) for precise retrieval; return larger parent (512–1024 tokens) for context | Extra complexity; parent boundary still needs human-defined or structure-aware logic |

**Fixed-size chunking failures in practice:**
1. **Table splitting** — a financial table with header row on chunk N and data rows on chunk N+1 returns a chunk with data but no column labels → LLM produces nonsense.
2. **Cross-paragraph context** — a conclusion sentence that references a definition from three paragraphs up is retrieved without the definition.
3. **List continuation** — a bulleted list split mid-way means retrieved chunk has "…, and 4) foo" with no items 1–3.
4. **Code blocks** — a function split mid-body returns syntactically invalid code.

**Semantic chunking advantages:**
- Respects document structure; each chunk corresponds to a coherent thought unit.
- Reduces context pollution at generation time (no orphaned fragments).
- Especially important for: legal contracts (clause-level), annual reports (section-level), API docs (function-level), Markdown docs (heading-level).

**Overlap as a partial fix:**
Adding 10–20% token overlap between fixed-size chunks helps recover boundary context but inflates index size by 10–20% and increases cost without solving the semantic unit problem.

**Benchmarking chunk strategy:**
Build a golden set of 50–100 Q&A pairs with known source passages. Measure `Recall@5` and `MRR` at each chunk size/strategy. A real production example: switching from fixed-size 512-token chunks to parent-child (256 child / 1024 parent) on a 200K-article knowledge base improved Recall@5 from 61% to 74% and deflection rate from 58% to 71%.

### Example / Tradeoff
**Tool stack:** LangChain `RecursiveCharacterTextSplitter` (recursive), Unstructured.io (structure-aware for PDFs/HTML), custom header-split for Markdown, PyMuPDF for PDF text extraction.

**Chunk size tradeoff:**
- Smaller chunks (128–256 tokens): higher retrieval precision, but LLM often lacks enough context to answer — answer fragments need parent-context retrieval.
- Larger chunks (512–1024 tokens): more context per chunk, but lower retrieval precision (chunk may be "about" the right topic but answer is diluted).
- **Production sweet spot:** 256–512 token children with 1024 parent for most prose documents; adjust based on golden-set recall benchmarks.

**Overlap tradeoff:** 10% overlap recovers ~60% of boundary failures for fixed-size chunking at a 10% storage cost. Better than nothing; not a substitute for semantic chunking.

---

## Verbal script

**Opening (30s):**
"Bad chunking is the most common root cause of RAG retrieval failures I've seen in production — and it's insidious because it's invisible at the embedding level. The chunk returns with high cosine similarity, but the actual answer text was cut off at a boundary. Let me walk you through the failure modes and when each strategy helps."

**Core explanation (2–3 min):**
"There are basically four strategies on a spectrum. Fixed-size — split every N tokens — is the default but has serious problems: it'll split a financial table mid-row, cut a conclusion sentence away from its premise, or break a code block mid-function. The embedding still scores high because the topic is right, but the answer is gone.

Recursive character splitting — what LangChain uses by default — is better because it tries to split on paragraph then sentence then word boundaries, so you're less likely to break mid-sentence. But it's still structure-blind for formatted documents.

Semantic or structure-aware chunking uses document structure signals — markdown headers, HTML tags, section titles, code fences — to split at meaningful boundaries. For anything with rich structure — API docs, legal contracts, annual reports — this is the right approach.

Parent-child chunking is the production pattern I reach for most: you index small 256-token child chunks so the retrieval embedding is tight and precise, but when a child chunk is retrieved you return its parent 1024-token section to the LLM for full context. This separates the precision of retrieval from the context richness of generation.

The way to validate any of these is a golden dataset: 50–100 Q&A pairs with known source passages. I measure Recall@5 and MRR at each strategy. When I switched a 200K-article knowledge base from fixed-size 512 to parent-child 256/1024, Recall@5 jumped from 61% to 74%."

**Tradeoff / production angle (1 min):**
"The tradeoffs are chunk size vs. context richness vs. index size. Smaller chunks give better retrieval precision but the LLM may not have enough context — hence the parent-child pattern. Larger chunks give more context but introduce noise (lower precision). Overlap — say 10% — is a cheap partial fix for boundary failures but inflates your index by 10–20% and doesn't solve the semantic unit problem.

One thing I always flag: bad chunking is upstream of everything. You can't fix it with a better reranker or a smarter prompt — if the answer text doesn't appear in any retrieved chunk, the model has nothing to work with."

**Wrap-up (30s):**
"Bottom line: default to recursive character splitting with 10% overlap for prose; add structure-aware splitting for formatted content; use parent-child for precision-plus-context needs. Always validate with a golden recall benchmark — chunk strategy is one of the highest-leverage decisions you'll make in a RAG system."

---

## Pitfalls

- **Mistake:** Choosing chunk size by intuition ("I used 512 tokens because that's the default") without benchmarking — **Better:** "I always validate chunk size and strategy with a golden Q&A set measuring Recall@5; the optimal depends on document structure and query length distribution."
- **Mistake:** Proposing "just add more overlap" as the fix for bad chunking — **Better:** "Overlap recovers some boundary failures but inflates index size and doesn't solve the semantic unit problem — for structured documents I switch to structure-aware or parent-child chunking."
- **Mistake:** Using fixed-size chunking on tables or code without acknowledging the failure mode — **Better:** "Fixed-size chunking splits tables mid-row and code blocks mid-function; for those I use structure-aware extraction that treats a table or function as a single chunk regardless of token count."

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q13: Common RAG failure points — how debug them?](02-013-common-rag-failure-points-how-debug-them.md) | Parent taxonomy — bad chunking is one of the six failure modes |
| [Q6: System processing huge PDF reports — how handle context when splitting?](02-006-system-processing-huge-pdf-reports-how-handle-context-when-s.md) | Same concept applied to cross-page document context |
| [Q21: How evaluate a RAG pipeline? NDCG, MRR, precision@k, recall?](02-021-how-evaluate-a-rag-pipeline-ndcg-mrr-precisionk-recall.md) | Validation methodology for chunking strategy selection |

---

## One-liner recall

> Fixed-size chunking silently destroys semantic units (tables, code, cross-paragraph context) — use recursive character splitting for prose, structure-aware splitting for formatted docs, and parent-child (small child for retrieval, large parent for context) for precision-plus-richness; always validate with Recall@5 on a golden set.
