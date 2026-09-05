# System processing huge PDF reports — how handle context when splitting documents

**Category:** 02-rag-systems
**Question #:** 006
**Source section:** §2 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
Interviewers ask this to probe whether you've actually shipped document processing in production — not just run a tutorial. Large PDFs (annual reports, legal contracts, technical manuals) break naive fixed-size chunking: context spans page boundaries, tables split mid-row, footnotes reference headings 20 pages earlier, and the doc's own metadata (e.g., "all figures in thousands") applies globally but isn't repeated per chunk. A weak candidate chunks by character count and calls it done. A strong candidate designs a pipeline that preserves semantic coherence and document-global context.

### Trigger phrases
- "You have a 300-page annual report — how do you chunk it for RAG?"
- "What happens when a document's context spans multiple pages?"
- "How do you handle large PDFs in a document Q&A system?"
- "A financial report says 'amounts expressed in millions' on page 1 — how does your RAG know that?"

### What it tests
Ability to design structure-aware, semantically coherent chunking pipelines for real-world documents with cross-page and global context dependencies.

---

## Answer

### Concept
Huge PDFs can't be chunked naively because meaning is distributed: a table header on page 4 explains data on pages 5–7, a footnote on page 1 applies to every figure in the document, and chapters form logical units that fixed-size windows shred arbitrarily. The solution is a **multi-layer extraction + parent-child chunking strategy** that preserves document structure and propagates global metadata to every chunk.

### Mechanism

**1. Structure-aware extraction (before chunking)**
- Use a PDF parser that understands layout: **PyMuPDF** (fast, open-source), **Adobe PDF Extract API**, or **AWS Textract** for scanned/complex docs.
- Extract: plain-text blocks, tables (convert to Markdown), images (store separately or caption with a vision-capable model), headers/footers (detect via font size/position heuristics).
- Identify document sections: use heading hierarchy (H1→H2→H3) to build a **section tree**.

**2. Global metadata injection**
- During extraction, identify document-wide context: currency units, date ranges, entity names, jurisdiction, disclaimer language.
- Store these as **chunk-level metadata fields** that every chunk in that document carries (e.g., `{"currency_unit": "thousands", "report_year": 2023, "company": "Acme Corp"}`).
- At generation time, prepend a **document preamble** to the system prompt: *"Note: all monetary values in this document are expressed in thousands of USD."*

**3. Parent-child (hierarchical) chunking**
- **Parent chunks**: natural document sections (chapter, sub-section) — typically 1,000–2,000 tokens. Indexed in the vector store for broad context retrieval.
- **Child chunks**: fine-grained passages — typically 200–400 tokens. Indexed separately for precision retrieval.
- Retrieval: use child chunks to find relevant passages; return the parent chunk (or an expanded window) to the LLM for full context. This is the **"small-to-big" retrieval** pattern used in LlamaIndex's `SentenceWindowNodeParser`.

**4. Table and cross-page handling**
- Tables: extract as Markdown; keep table + 1–2 sentence caption as a single chunk (never split mid-row).
- Cross-page continuations: detect via trailing punctuation or unclosed table rows; merge with the next page's block before chunking.
- Page headers/footers: strip repetitive boilerplate; inject once as metadata.

**5. Overlap windows for boundary safety**
- Use a 10–20% token overlap between adjacent text chunks to prevent sentences from being cut at chunk boundaries and losing context.

### Example / Tradeoff

**Stack:** PyMuPDF → custom section-tree extractor → LlamaIndex `SentenceWindowNodeParser` (child=256 tokens, window=3 sentences) → Pinecone (with metadata filters) → a small fast model with document preamble injection.

**Tradeoff — chunk size:**
| Smaller chunks (128–256 tokens) | Larger chunks (512–1024 tokens) |
|--------------------------------|--------------------------------|
| Higher precision retrieval | More complete context per chunk |
| Risk: misses cross-sentence context | Risk: "lost in the middle" degradation |
| Best for: keyword-dense Q&A | Best for: reasoning over long passages |

**Global metadata gotcha:** Without metadata injection, a RAG pipeline answering "What was Acme's revenue?" returns "$4,200" with no unit — leading to a 1,000× error if the model assumes dollars instead of thousands. The fix is trivial (one metadata field) but commonly missed.

**Cost signal:** A 300-page PDF ≈ 75,000 tokens. Embedding all child chunks (256 tokens each, ≈300 chunks) at $0.0001/1K tokens costs ~$0.003 per document. The extraction step (Textract for scanned docs) is the expensive part (~$0.015/page for complex layout).

---

## Verbal script

**Opening (30s):**
"I'd frame this as a two-part problem: how you extract structure from the PDF before you even think about chunks, and then how you handle the fact that some context is global to the document — like currency units or a disclaimer — that needs to be attached to every chunk, not just the first page."

**Core explanation (2–3 min):**
"Starting with extraction — for a well-formed PDF I'd use PyMuPDF to pull text blocks with their layout positions, which lets me detect headers by font size and reconstruct a section hierarchy. For scanned or complex layout documents, I'd route through AWS Textract. The key insight at this stage is to handle tables as units — extract them as Markdown and keep the caption with the table; never let a chunker split a table mid-row.

Then for global metadata — if page 1 says 'all amounts in thousands,' I detect that during extraction and store it as a metadata field on every chunk for that document. At query time, I prepend a one-line preamble to the system prompt: 'Note: all monetary figures are in thousands.' This is how you prevent a model from misreading $4,200 as $4,200 instead of $4.2M.

For the actual chunking, I use a parent-child strategy: large parent chunks (around 1,000 tokens) aligned to document sections give semantic coherence, while smaller child chunks (256 tokens) give precision retrieval. Retrieval finds the child, but returns the parent to the LLM. LlamaIndex calls this the sentence window pattern. For boundary safety I add a 15% token overlap between adjacent chunks."

**Tradeoff / production angle (1 min):**
"The main tradeoff is chunk size vs. context completeness. Smaller chunks give you better vector-search precision but risk breaking semantic units. Larger chunks ensure coherence but increase 'lost in the middle' risk and raise token costs. My default is 256-token children with 1,024-token parents and I tune based on recall@5 on a golden set of representative questions. The other failure mode to watch for is embedding drift — if you re-index with a new embedding model, you need to re-embed everything, including those metadata fields."

**Wrap-up (30s):**
"So the core pattern is: structure-aware extraction → global metadata as chunk fields → parent-child chunking → document preamble at generation time. Happy to go deeper on table handling, multi-modal PDFs with charts, or the cost breakdown for Textract at scale."

---

## Pitfalls

- **Mistake:** Describing fixed-size character chunking (e.g., "I split every 500 characters with 50-character overlap") without acknowledging that this shreds tables, sentences, and cross-section context — **Better:** Lead with structure-aware extraction first; chunking strategy follows from document structure, not arbitrary byte counts.
- **Mistake:** Ignoring global document metadata — answering "how do you know the currency unit?" with "the model will figure it out from context" — **Better:** Explicitly describe metadata extraction during ingestion and preamble injection at generation time; the model cannot reliably infer document-global facts from a 256-token chunk.
- **Mistake:** Treating all PDFs the same — not distinguishing between native-text PDFs (PyMuPDF) and scanned/image PDFs (Textract/OCR) — **Better:** Describe a routing step based on PDF type, noting that scanned PDFs require OCR and have confidence-score gating before indexing.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q14: How does chunking happen?](../answers/01-014-how-does-chunking-happen.md) | Core chunking strategies (prerequisite) |
| [Q16: Financial report — how handle doc-wide context](02-016-financial-report-page-1-says-amounts-in-thousands-how-handle.md) | Direct extension: global metadata injection |
| [Q3: Design a GenAI document-processing pipeline for unstructured data](02-003-design-a-genai-document-processing-pipeline-for-unstructured.md) | Broader pipeline: multi-format doc processing |

---

## One-liner recall

> For huge PDFs: extract structure first (PyMuPDF/Textract), inject global metadata (currency, date range) as chunk fields + generation preamble, use parent-child chunking (1024/256 tokens) with overlap, and never split tables mid-row.
