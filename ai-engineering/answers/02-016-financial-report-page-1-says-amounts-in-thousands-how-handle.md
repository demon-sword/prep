# Financial report: page 1 says "amounts in thousands" — how handle doc-wide context when chunking

**Category:** 02-rag-systems
**Question #:** 016
**Source section:** §2 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
This is a precision retrieval trap. Fixed-size chunking discards doc-wide context — a chunk saying "revenue: 42,500" is meaningless without knowing the unit of measure declared on page 1. Interviewers use this scenario to probe whether you understand **metadata propagation**, **parent-child chunking**, and the real-world consequence of treating a document as an independent bag of text fragments.

### Trigger phrases
- "How would you chunk a financial report where page 1 declares 'all amounts in thousands'?"
- "How do you preserve document-level context that isn't repeated on every page?"
- "What happens to chunk accuracy when a unit-of-measure header only appears once?"

### What it tests
Whether you know to propagate doc-global metadata (unit declarations, currency, date scope, entity name) into every child chunk — not just extract text sequentially.

---

## Answer

### Concept
Fixed-size chunking destroys **document-scope context** — information that applies to the entire document but only appears once (page 1 header, cover page, introductory disclaimer). The unit declaration "amounts in thousands" is a canonical example: every numeric chunk is ambiguous without it. The fix is to extract these global signals at the document level and inject them as **chunk metadata** and optionally as a **preamble** prepended to each chunk.

### Mechanism

**Step 1 — Document-level extraction pass**
Before chunking, run a structured extraction step over the first 1–2 pages (or the entire document for short files) to pull doc-global metadata:
- Unit of measure: `amounts_unit: "thousands USD"`
- Reporting period: `period: "FY2024"`
- Entity name: `entity: "Acme Corp"`
- Currency: `currency: "USD"`

Tools: PyMuPDF for native PDFs, AWS Textract for scanned documents. A lightweight LLM call (a small fast model) can reliably extract structured JSON from the cover/first page.

**Step 2 — Parent-child chunking with metadata inheritance**
Structure the document as parent nodes (sections/pages, ~1024 tokens) and child nodes (paragraphs, ~256 tokens). Every child chunk inherits the doc-global metadata fields extracted in Step 1.

```
Chunk schema:
{
  "text": "Revenue for Q3 was 42,500.",
  "doc_id": "annual-report-fy2024",
  "page": 7,
  "section": "Income Statement",
  "amounts_unit": "thousands USD",   ← injected at index time
  "period": "FY2024",
  "entity": "Acme Corp",
  "currency": "USD"
}
```

**Step 3 — Generation preamble injection**
At generation time, prepend a one-line preamble before the retrieved chunks in the prompt:

```
[Context: Acme Corp Annual Report FY2024. All monetary amounts are in thousands of USD unless otherwise noted.]

Retrieved passages:
<chunk>Revenue for Q3 was 42,500.</chunk>
```

This ensures the LLM interprets "42,500" as $42.5M, not $42,500.

**Step 4 — Overlap windows for cross-page continuity**
Use a 10–15% token overlap between adjacent chunks so that a unit declaration near the bottom of page 1 naturally bleeds into the top of page 2's chunk, providing a fallback even if metadata extraction missed it.

### Example / Tradeoff

**Before:** A RAG system chunked a 10-K filing into fixed 512-token blocks. Retrieved chunk: *"Total liabilities: 8,200"* — LLM answered "$8,200" when the correct answer was "$8.2 billion."

**After:** Metadata extraction pass added `amounts_unit: "billions USD"` to every chunk. Generation preamble injected the unit. LLM answered correctly across all financial queries.

**Tradeoff:** The metadata extraction LLM call adds ~200ms and ~$0.001/document at a small fast model pricing. For a corpus of 300K legal/financial documents, that's ~$300 total — negligible compared to re-embedding costs from a botched chunking strategy. The right call is always to pay the extraction cost upfront.

**Edge case — conflicting unit declarations:** Some reports switch units by section (e.g., "segment revenues in millions, per-share amounts in dollars"). The metadata extraction prompt must capture these per-section overrides, or the parent chunk must carry its own `amounts_unit` override distinct from the doc-level default.

---

## Verbal script

**Opening (30s):**
"This is a great question because it's about a failure mode that's easy to miss: fixed-size chunking assumes each chunk is self-contained, but financial documents aren't — they have document-scope context that's declared once and applies everywhere. The unit declaration on page 1 is the classic example. I'd solve this with a two-part approach: metadata extraction before chunking, and preamble injection at generation time."

**Core explanation (2–3 min):**
"I'd start with a document-level extraction pass over the cover page and first section. Using PyMuPDF for native PDFs or Textract for scanned documents, I'd run a structured extraction — either a regex pattern for common financial headers, or a cheap a small fast model call — to pull out global metadata: `amounts_unit`, `period`, `entity`, `currency`. This takes maybe 200ms per document and costs fractions of a cent.

Then I'd use parent-child chunking — parent nodes at the section or page level (~1024 tokens), child nodes at the paragraph level (~256 tokens). Every child chunk gets the doc-global metadata fields injected into its index record. So when a chunk says 'Revenue: 42,500,' the vector DB record also stores `amounts_unit: thousands USD`.

At retrieval time, the metadata travels with the chunk. At generation time, I prepend a one-line preamble to the LLM prompt: 'All monetary amounts in this document are in thousands of USD.' The LLM then correctly interprets every number. I also add 10–15% overlap between adjacent chunks as a fallback — if the unit appears at the bottom of page 1, it bleeds into the top of page 2's chunk naturally."

**Tradeoff / production angle (1 min):**
"The main complexity is conflicting unit declarations. Some 10-Ks report segment revenues in millions but per-share amounts in dollars. A flat doc-level `amounts_unit` field breaks here. The fix is to make unit metadata per-section, not just per-document — the parent chunk carries an override that takes precedence over the doc default. It's more schema complexity but it's essential for accurate financial QA. I'd validate this with a golden dataset of known-unit questions before shipping to production."

**Wrap-up (30s):**
"The key insight is that document-scope context has to be explicitly extracted and propagated — it doesn't survive naive chunking. Metadata injection at index time plus preamble injection at generation time is the production pattern. Happy to go deeper on the extraction prompt design or the schema for handling conflicting unit declarations."

---

## Pitfalls

- **Mistake:** Saying "I'd include overlap so the unit declaration appears in later chunks" — **Better:** Overlap is a fragile fallback for short windows; it fails entirely when the declaration is on page 1 and the chunk is on page 40. The primary fix is explicit metadata extraction and injection — overlap is just a safety net.
- **Mistake:** Extracting unit metadata but only storing it in a sidecar file, not in the vector DB record — **Better:** The metadata must be stored as a field on every chunk in the vector index so it travels with retrieved results and can be injected into the generation prompt automatically.
- **Mistake:** Ignoring per-section unit overrides (treating the document as having one unit throughout) — **Better:** For financial filings, some sections switch units (e.g., per-share figures are always in dollars even when aggregate figures are in thousands). The schema needs to support section-level overrides, and the extraction step should check for phrases like "except per share amounts."

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q6: System processing huge PDF reports — how handle context when splitting documents](02-006-system-processing-huge-pdf-reports-how-handle-context-when-s.md) | same parent topic — PDF splitting and context preservation |
| [Q3: Design a GenAI document-processing pipeline for unstructured data](02-003-design-a-genai-document-processing-pipeline-for-unstructured.md) | broader pipeline this chunk design fits into |
| [Q29: Bad chunking — fixed-size vs semantic](02-029-bad-chunking-fixed-size-vs-semantic.md) | root cause: fixed-size chunking destroys doc-scope context |

---

## One-liner recall

> Extract doc-global metadata (unit declarations, period, entity) before chunking, inject it as structured fields on every child chunk in the vector index, and prepend a one-line preamble at generation time — overlap is a fallback, not the fix.
