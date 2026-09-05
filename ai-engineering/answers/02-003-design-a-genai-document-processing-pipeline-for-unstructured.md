# Design a GenAI document-processing pipeline for unstructured data (emails, PDFs, images)

**Category:** 02-rag-systems
**Question #:** 003
**Source section:** §2 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
Unstructured data (emails, PDFs, scanned images, slide decks) makes up ~80% of enterprise data but arrives in formats that break naive chunking pipelines. The interviewer wants to see that you understand the pre-RAG ingestion layer — parsing, multi-modal handling, document-structure-aware chunking — and can design a production pipeline that doesn't collapse on messy real-world input.

### Trigger phrases
- "We have thousands of PDFs, emails, and scanned images — how do you build a pipeline to make them queryable?"
- "Design a document ingestion system for unstructured enterprise data."
- "How do you handle PDFs with tables and images in a RAG system?"

### What it tests
Ability to design the full ingestion/parsing/structuring layer of a RAG system, not just the vector-store-and-retrieve part.

---

## Answer

### Concept
A GenAI document-processing pipeline transforms raw unstructured documents (PDFs, emails, images, HTML) into clean, semantically chunked, metadata-tagged text that a retrieval system can index and an LLM can accurately cite. The key insight is that **parsing and structure extraction are upstream of chunking**, and failures here — undetected tables, missing headers, garbled OCR — propagate silently into hallucinations or retrieval misses.

### Mechanism

**Stage 1 — Ingest & route**
- Accept documents via S3 event trigger, email webhook (SendGrid/SES), or API upload.
- Detect MIME type and route to the correct parser: PDFs → Unstructured.io or PyMuPDF, emails → MIME parsing + inline-attachment extraction, images → OCR, scanned PDFs → PDFplumber + Tesseract/AWS Textract.
- Enqueue each doc in a durable job queue (SQS, Celery) for async processing. Dead-letter queue for parse failures.

**Stage 2 — Parse & extract**
| Document type | Tool / approach |
|---------------|-----------------|
| Native PDF | PyMuPDF or pdfplumber — extract text with font/bbox metadata preserved |
| Scanned PDF / images | AWS Textract (tables + forms) or Google Document AI; fallback Tesseract |
| Emails | Python `email`/`mailparser` — strip boilerplate signatures, parse HTML body |
| HTML / web | BeautifulSoup + readability-lxml to extract article body |
| Tables | Textract AnalyzeDocument API or Camelot for structured table extraction → Markdown table strings |
| Charts/graphs | A frontier vision-capable model with image captioning → caption stored as metadata |

**Stage 3 — Clean & normalize**
- Strip headers/footers (detected by repeated string matching across pages).
- Normalize whitespace, ligatures, Unicode.
- Detect and preserve document structure: headings (via font size/bold markers) → markdown `##`, bullet lists, numbered sections.

**Stage 4 — Chunk (structure-aware)**
- Use recursive/semantic chunking that respects document structure boundaries: never split mid-sentence or mid-table.
- **Parent-child chunking**: large parent chunks (1024 tokens) for context; small child chunks (256 tokens) for retrieval. At query time, retrieve child, return parent.
- Tables: keep entire table as one chunk. If too large, split by row groups. Store table caption in metadata.
- Email threads: chunk each reply separately; store `thread_id`, `sender`, `date` as metadata for filtering.

**Stage 5 — Embed & index**
- Embed with a domain-appropriate model: `text-embedding-3-large` (OpenAI) for general enterprise text, or `BAAI/bge-m3` for multilingual corpora.
- Index in Pinecone / Qdrant / Weaviate with rich metadata: `doc_id`, `source_type`, `page_number`, `section_heading`, `date`, `author`, `department`.
- Build BM25 index (Elasticsearch) on the same text for hybrid search.

**Stage 6 — Quality gate**
- Run a lightweight classifier to detect parse failures: if `char_count < 50` for a "document" page, flag as likely OCR miss.
- RAGAS-style automated eval on a golden set of 50–100 representative documents: check that retrieval returns expected chunks for known questions.

**Stage 7 — Observe & re-index**
- Version every document's chunks; when the source doc updates, delete old chunks by `doc_id` and re-ingest.
- Track parse failure rate and OCR confidence scores in a dashboard (Datadog/Prometheus).

### Example / Tradeoff

A legal firm processing 50K contracts (PDFs with tables of clauses, scanned exhibits, email attachments): using PyMuPDF for native PDFs catches ~90% of text cleanly; Textract handles scanned exhibits at ~95% word accuracy. Tables are extracted as Markdown and chunked whole — splitting mid-table causes the LLM to lose column context. Parent-child chunking (1024/256) improves recall@5 from 61% → 79% on clause-lookup queries. Cost: Textract runs ~$0.015/page, so batching scanned pages and caching already-extracted pages in S3 is essential at scale.

**Key tradeoff — accuracy vs cost:** Textract/Document AI gives best accuracy but is expensive per page. Use it only for scanned/image PDFs; PyMuPDF (free, local) for native PDFs. Route by detection heuristic (text layer present? → PyMuPDF; absent → Textract).

---

## Verbal script

**Opening (30s):**
"I'd approach this as a multi-stage ingestion pipeline with specialized parsing per document type, because the single biggest failure mode I've seen is treating every document as a flat text blob. The pipeline has to handle structure — tables, headers, multi-page context — before you ever touch chunking or embeddings."

**Core explanation (2–3 min):**
"I'd start with an ingest router that detects MIME type and dispatches to the right parser. For native PDFs I'd use PyMuPDF or pdfplumber — they preserve font metadata which helps detect headings. For scanned PDFs and images I'd use AWS Textract, because it has table and form extraction built in, not just raw OCR. Emails I'd parse with Python's email library, stripping signature boilerplate and extracting inline attachments separately.

After parsing, I normalize and clean: strip headers and footers that repeat across pages, fix Unicode ligatures, and rehydrate document structure into markdown — headings, lists, tables.

For chunking, I'd use structure-aware recursive splitting — never cut mid-sentence or mid-table. Tables stay as single chunks. For the rest of the document I'd use parent-child chunking: 1024-token parent chunks for context, 256-token children for retrieval precision. At query time I retrieve the child chunk, then return its parent for generation context.

Then I embed with text-embedding-3-large or bge-m3 for multilingual, index in Pinecone with rich metadata — source type, page number, section heading, date — and build a parallel BM25 index in Elasticsearch for keyword matches.

For multi-modal: charts and graphs I handle with a frontier vision-capable model to generate a caption, stored as metadata alongside the image reference. This lets the LLM cite 'Figure 2: revenue trend' even though it can't embed the pixel data."

**Tradeoff / production angle (1 min):**
"The big tradeoff is accuracy vs cost on OCR. Textract gives 95%+ word accuracy but costs ~$0.015/page. For a legal firm with 50K contracts that's a meaningful bill. So I route: if the PDF has a native text layer, use PyMuPDF for free; only send to Textract if text extraction returns fewer than 50 characters per page. I also cache extracted text in S3 so re-indexing on document updates doesn't re-run OCR. The other failure mode is embedding drift — if you swap embedding models, you must re-embed everything, so I version the embedding model alongside the index."

**Wrap-up (30s):**
"The key insight is that parsing quality determines retrieval quality. Every downstream metric — faithfulness, context recall, hallucination rate — traces back to whether the ingestion layer correctly preserved structure. Happy to go deeper on table handling, OCR confidence gating, or the parent-child chunking strategy."

---

## Pitfalls

- **Mistake:** Describing a pipeline that feeds all document types into a single `pdfplumber.extract_text()` call — **Better:** Explicitly distinguish native PDFs, scanned PDFs, and images; explain OCR routing (Textract/Document AI) and why it's needed for scanned content.
- **Mistake:** Not mentioning table handling — saying "I'll chunk by 512 tokens" — **Better:** Explain that tables must be kept as single chunks (or row-group split), because splitting mid-table loses column headers and makes LLM responses semantically wrong.
- **Mistake:** Treating emails as plain text without stripping signatures, threading context, or metadata — **Better:** Parse email MIME structure, strip boilerplate, store `thread_id`/`sender`/`date` as filterable metadata so users can ask "find emails from Legal in Q3 2025."
- **Mistake:** Not addressing re-indexing on document updates — **Better:** Describe versioned chunk storage with `doc_id`-based delete-and-reingest to keep the index in sync with source of truth.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q6: System processing huge PDF reports — how handle context when splitting](02-006-system-processing-huge-pdf-reports-how-handle-context-when-s.md) | Follow-up: deep dive on PDF-specific chunking edge cases |
| [Q14: How does chunking happen?](../answers/01-014-how-does-chunking-happen.md) | Prerequisite: chunking strategy foundations |
| [Q29: Bad chunking (fixed-size vs semantic)](02-029-bad-chunking-fixed-size-vs-semantic.md) | Same concept: chunking failure modes in production |

---

## One-liner recall

> Route each document type to a specialized parser (PyMuPDF for native PDFs, Textract for scanned, MIME parsing for emails), extract and preserve structure (headings, tables, metadata), then apply structure-aware parent-child chunking before embedding — because parsing quality is the upstream determinant of all downstream retrieval and faithfulness metrics.
