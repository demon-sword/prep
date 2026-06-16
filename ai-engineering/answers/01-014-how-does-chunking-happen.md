# How does chunking happen?

**Category:** 01-llm-fundamentals
**Question #:** 014
**Source section:** §1 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
Chunking is the most under-estimated failure point in RAG pipelines. Interviewers ask this to distinguish candidates who understand chunking as a *retrieval quality decision* from those who treat it as a mechanical preprocessing step. Bad chunking choices propagate to every downstream stage: embeddings, retrieval precision, context window budget, and generation quality.

### Trigger phrases
- "How does chunking happen?"
- "How do you decide on chunk size?"
- "What chunking strategy do you use in your RAG pipeline?"
- "System processing huge PDF reports — how do you handle context when splitting documents?"

### What it tests
Whether the candidate understands chunking as a retrieval optimization (semantic coherence + index efficiency) and can reason about tradeoffs: chunk size vs. embedding granularity, fixed-size vs. semantic boundaries, parent-child strategies, and domain-specific edge cases (tables, lists, cross-page references).

---

## Answer

### Concept
Chunking is the process of splitting source documents into smaller, semantically coherent units before embedding and indexing them. The goal is to produce chunks that are *just large enough* to contain a self-contained unit of meaning — enough context to answer a question — but *small enough* that a retrieved chunk doesn't dilute the embedding with irrelevant content or blow the generation context window.

### Mechanism
There are four main chunking strategies, each suited to different content types:

**1. Fixed-size / sliding window (baseline)**
Split on token or character count (e.g., 512 tokens, 100-token overlap). Fast and simple. Overlap prevents splitting a key sentence across chunk boundaries. Fails on documents where structure matters — a paragraph break mid-sentence, or a table split across chunks.

**2. Recursive / structure-aware (most common in production)**
LangChain's `RecursiveCharacterTextSplitter` splits on paragraph breaks first (`\n\n`), then sentences (`\n`), then words. Respects natural document structure. Configurable separators per document type (Markdown headers, HTML tags, code blocks).

**3. Semantic chunking**
Embed each sentence; cluster sentences by embedding similarity; split when cosine similarity drops below a threshold. Produces variable-length, semantically coherent chunks. More CPU-intensive; used when document structure is poor (e.g., raw OCR output). Libraries: `semantic-chunker` in LangChain, `chonkie` OSS library.

**4. Parent-child (hierarchical) chunking**
Index small *child* chunks (128–256 tokens) for precise retrieval, but return the full *parent* chunk (512–1,024 tokens) to the LLM for generation context. Solves the precision-vs-context tradeoff: retrieval is precise, generation has full context. Used in LlamaIndex's `ParentDocumentRetriever`.

**Special cases:**
- **Tables:** OCR'd tables must be kept intact or converted to structured formats (Markdown table or JSON key-value pairs) before chunking; splitting mid-row destroys meaning.
- **Lists:** Numbered or bulleted lists should chunk at the list level, not mid-item.
- **Cross-page metadata:** A PDF that says "amounts in thousands" on page 1 and presents numbers on page 50 needs document-level metadata injected into each chunk (e.g., `metadata: {"currency_unit": "thousands"}`), not reliance on retrieval alone.
- **Code:** Split on function or class boundaries, not arbitrary token counts.

### Example / Tradeoff
**Production benchmark:** For a customer support RAG pipeline over 50,000 support articles, switching from 512-token fixed-size chunks to 256-token recursive chunks with a 50-token overlap improved retrieval recall@5 from 61% to 74% (measured via RAGAS). The smaller chunks allowed the embedding model to encode a single topic per chunk rather than averaging across two or three topics.

**The key tradeoff:**

| Dimension | Small chunks (128–256 tokens) | Large chunks (512–1024 tokens) |
|-----------|-------------------------------|-------------------------------|
| Embedding precision | High — one topic per vector | Low — blended topics blur embedding |
| Retrieval recall@k | Higher precision, lower recall for partial answers | Better recall for multi-sentence answers |
| Context pollution | Low | Higher — may include irrelevant sentences |
| Index size | 4–8× more vectors | Fewer vectors, cheaper index |
| Generation context | Must retrieve more chunks to cover answer | Single chunk often sufficient |

**Rule of thumb:** Start at 256–512 tokens with 10–20% overlap. Benchmark retrieval recall@5 on a golden set of 50–100 question-answer pairs before committing.

---

## Verbal script

**Opening (30s):**
"Chunking is one of those places where small decisions early in the pipeline have outsized effects on everything downstream. The core problem is simple: documents are long, embedding models have a max input length, and the LLM's context window has a cost. So you need to split documents into pieces — but the strategy you choose determines whether your retrieval actually works."

**Core explanation (2–3 min):**
"I think about chunking strategies on a spectrum from simple to sophisticated.

The baseline is fixed-size chunking: split every 512 tokens, 100-token overlap so you don't cut mid-sentence. It's fast, deterministic, and works well enough on well-structured documents. The overlap is important — without it, a key phrase that straddles a chunk boundary gets split and neither chunk embeds it correctly.

One step up is recursive chunking, which is what LangChain's `RecursiveCharacterTextSplitter` does. It tries to split on natural boundaries first — double newline for paragraphs, single newline for sentences — and only falls back to character-level splits if the chunk is still too long. This respects document structure and is what I'd use by default on Markdown or structured text.

For documents with messy structure — raw OCR, scraped web content, annual reports — semantic chunking works better. You embed each sentence, compute similarity between adjacent sentences, and split when the similarity drops below a threshold. This produces variable-length chunks that are semantically coherent. Tools like the LangChain `SemanticChunker` or the OSS `chonkie` library do this.

The most sophisticated approach for production is parent-child chunking. You index small child chunks — say 128 tokens — for precision retrieval, but when a child chunk hits, you return its parent chunk (512 tokens) to the LLM. So you get precise retrieval + rich generation context. LlamaIndex's `ParentDocumentRetriever` implements this pattern."

**Tradeoff / production angle (1 min):**
"The two biggest failure modes I've seen in production are: first, chunks that are too large — the embedding averages across multiple topics, so the vector doesn't strongly match any single query, and recall drops. Second, naively splitting tables or lists mid-row — the retrieved chunk is semantically broken and the LLM either hallucinates or returns 'I don't know.'

For tabular content, I convert tables to Markdown or structured JSON before chunking, and keep the entire table as a single chunk with clear metadata. For cross-document context — like 'amounts in thousands' on the first page — I inject that as chunk-level metadata so the LLM always has the context it needs, regardless of which chunk gets retrieved."

**Wrap-up (30s):**
"So: start with recursive or fixed-size at 256–512 tokens with ~15% overlap, benchmark retrieval recall@5 on a golden question set before you scale, and use parent-child chunking when you need both high retrieval precision and rich generation context. Happy to dig into how this connects to the reranking stage or how you'd handle specific document types."

---

## Pitfalls

- **Mistake:** Saying "I just split on 512 tokens" without mentioning overlap or structure — **Better:** Explain that fixed-size chunking without overlap cuts sentences across boundaries (degrading embedding quality), and that structure-aware splitting (recursive on `\n\n` → `\n` → space) should be the default; mention chunk size as a tunable hyperparameter validated against retrieval recall on a golden set.
- **Mistake:** Treating chunking as a one-time, one-size-fits-all decision — **Better:** Explain that chunk size and strategy are document-type-specific (code splits on function boundaries, tables must be kept intact, OCR output needs semantic chunking) and should be validated empirically before production; many teams use different chunking configs for different document types in the same pipeline.
- **Mistake:** Ignoring the relationship between chunk size and embedding model input limits — **Better:** Note that most embedding models have a 512- or 8192-token max input; chunks exceeding the limit get silently truncated, which quietly degrades recall; always check the model's `max_seq_length` and chunk below it.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q13: What are embeddings?](01-013-what-are-embeddings.md) | Prerequisite — what each chunk gets encoded into |
| [Q12: What's an RAG model? Explain the complete process.](01-012-whats-an-rag-model-explain-the-complete-process.md) | Parent pipeline — chunking is Stage 2 of the 9-stage RAG pipeline |
| [Q5: Explain context windows and their limitations.](01-005-explain-context-windows-and-their-limitations.md) | Related constraint — chunk size must fit within the LLM's context window at generation time |

---

## One-liner recall

> Chunking splits documents into semantically coherent units (typically 256–512 tokens with 10–20% overlap) using strategies from fixed-size to semantic to parent-child hierarchical, where the key tradeoff is embedding precision (small chunks) vs. generation context richness (large chunks), validated against retrieval recall@5 on a golden question set.
