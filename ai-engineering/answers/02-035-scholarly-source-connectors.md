# How do you connect scholarly sources (arXiv, Semantic Scholar, PubMed) into a RAG pipeline?

**Category:** 02-rag-systems
**Question #:** 035
**Source section:** §2 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
Generic web-search RAG falls apart on scientific literature: papers have versions, citations form a graph, metadata (venue, authors, identifiers) matters as much as text, and each source API has different rate limits and coverage. Interviewers ask this to test whether you can design a source-connector layer — fetching, normalizing, deduping, and keeping fresh — rather than treating "retrieve papers" as a single API call.

### Trigger phrases
- "Design a literature-review assistant over arXiv and PubMed."
- "How would you build RAG over scientific papers instead of web pages?"
- "How do you handle arXiv rate limits and paper versions?"
- "We need citations to real papers — how do you guarantee the sources exist?"
- "How do you keep a paper index fresh as new preprints appear?"

### What it tests
Whether you can compare scholarly APIs concretely (coverage, identifiers, limits), normalize them into one record shape, and handle the paper-specific problems: versions, dedup across sources, and citation-graph traversal.

---

## Answer

### Concept
A scholarly source connector is an ingestion adapter per API — arXiv, OpenAlex, Semantic Scholar, PubMed/Europe PMC — that normalizes each source's records into one canonical paper schema (identifiers, version, metadata, full-text link), dedupes across sources on shared identifiers, and refreshes incrementally. The design centers on identifier discipline: DOI, arXiv ID, PMID, and OpenAlex Work ID are the join keys that make multi-source retrieval coherent.

### Mechanism

**Source comparison (what each API gives you):**

| Source | Coverage | Identifiers | Full text | Notes |
|--------|----------|-------------|-----------|-------|
| arXiv API (Atom feed) | CS/physics/math preprints | arXiv ID, DOI (when published) | PDF + sometimes source | Asks for at most one request per ~3 seconds; versions (v1, v2) are first-class — always record which version you indexed |
| OpenAlex | Cross-disciplinary (~250M works), aggregates Crossref, PubMed, arXiv | OpenAlex Work ID, DOI, PMID, arXiv ID | Links out, no hosting | Best crosswalk between identifier systems; generous limits with identification (polite pool); the default spine for dedup |
| Semantic Scholar API | CS-heavy + biomed, citation graph | S2 paper ID, DOI, arXiv ID | Open-access PDF links where available | Citation and reference endpoints enable graph traversal; unauthenticated use is heavily throttled — request an API key for production |
| PubMed E-utilities / Europe PMC | Biomedicine (PubMed ~35M records) | PMID, PMCID, DOI | Abstracts (PubMed); full-text OA subset (PMC/Europe PMC) | NCBI documents ~3 requests/second without a key, ~10/second with one; Europe PMC REST is the friendlier full-text route for OA articles |

**Connector design:**

1. **Canonical record:** `{work_id, doi, arxiv_id, pmid, title, authors, venue, year, version, abstract, pdf_url, license, source, fetched_at}`. Every connector maps into this shape; missing fields stay null rather than guessed. The license field drives downstream behavior — closed-access papers contribute metadata + abstract only, never scraped full text.
2. **Dedup and identity:** normalize DOIs to lowercase (strip resolver prefixes), strip arXiv version suffixes for identity but keep the version in the record. Join order: DOI first, then arXiv ID, then PMID; OpenAlex as the crosswalk when a record carries only one identifier. Same paper from arXiv and PubMed must collapse to one chunk set, or retrieval double-counts it and citations look inflated.
3. **Version policy:** index the latest version by default but record the version string; for reproducibility-sensitive use (replication notes, audits), pin the exact version cited. A v2 that retracts a v1 claim under the same arXiv ID is a real failure mode.
4. **Citation-graph traversal:** one hop of references + citations via Semantic Scholar or OpenAlex expands recall beyond keyword match — this is how you find the prior work a preprint builds on and the follow-ups that supersede it. Cap the fan-out (top-N by citation count) or the corpus explodes.
5. **Refresh:** poll arXiv/OAI-PMH and OpenAlex incrementally by date; re-fetch metadata for cited papers on a schedule (retractions and version bumps change answers). Full re-crawls are wasteful — date-filtered deltas plus on-demand backfill.

**Grounding guarantee:** every generated claim links to a record in the index, and the citation renderer emits the identifier (DOI or arXiv ID), not just a title string. Titles hallucinate convincingly; identifiers resolve or they don't — validate each cited identifier against the index before rendering.

### Example / Tradeoff

**A concrete pipeline:** literature-review RAG over ML + bio papers.
- Ingest: nightly OpenAlex delta (new works in the target topics) joined against arXiv versions for CS papers and Europe PMC full text for OA bio papers; Semantic Scholar one-hop citation expansion at query time for depth.
- Chunking follows the document-processing pipeline (abstract + section-aware splits), with section headers preserved so "results" chunks outrank "related work" chunks for factual claims.
- Generation carries inline citations with DOI/arXiv IDs, gated by the citation validator from the citations note.

**Tradeoff:** OpenAlex-as-spine plus on-demand expansion minimizes storage and stays fresh, but adds query-time latency and external dependency. A fully mirrored local corpus (all PDFs parsed and embedded) is fast and offline-capable but expensive to store, parse (GROBID/ScienceParse pass), and keep current. Most production systems land in the middle: metadata spine mirrored locally, full text fetched and cached on demand. The failure mode to avoid is identifier-free retrieval — title/author matching without DOI or arXiv-ID validation produces plausible-looking citations to papers that don't exist.

---

## Verbal script

**Opening (30s):**
"I'd structure this as a connector layer: one adapter per scholarly API normalizing into a canonical paper record, deduped on shared identifiers with OpenAlex as the crosswalk, plus citation-graph expansion at query time. The core discipline is identifiers — DOI, arXiv ID, PMID — because that's what makes multi-source retrieval coherent and citations verifiable."

**Core explanation (2–3 min):**
"The key insight is that each source covers a different slice. arXiv is the preprint firehose for CS and physics with first-class versions — I'd record exactly which version I indexed, because a v2 can retract a v1 claim under the same ID. OpenAlex is the cross-disciplinary spine that lets me join a DOI to a PMID to an arXiv ID, so the same paper arriving from two sources collapses to one record. Semantic Scholar gives me the citation graph — references and follow-ups — which expands recall beyond keyword matching. PubMed and Europe PMC cover biomedicine, with full text only for the open-access subset.

Every connector maps into one canonical schema with identifiers, version, license, and fetch timestamp. Dedup joins on DOI first, then arXiv ID, then PMID. The license field matters downstream: closed-access papers contribute metadata and abstracts only.

For freshness I'd poll incrementally by date rather than re-crawling, and re-fetch metadata for anything we've cited — retractions and version bumps change answers. And the grounding guarantee: citations render as resolvable identifiers, validated against the index before display, because titles hallucinate convincingly but a DOI either resolves or it doesn't."

**Tradeoff / production angle (1 min):**
"The tradeoff is mirrored corpus versus spine-plus-fetch. Mirroring everything locally is fast but expensive to store, parse, and keep current. Spine-plus-on-demand-fetch stays fresh and cheap but adds latency and an external dependency at query time — so I'd cache fetched full text aggressively. On limits: arXiv asks for roughly one request per three seconds, NCBI throttles to a few requests per second without a key, and Semantic Scholar needs an API key for production volume — so all fetching goes through a rate-limited queue with backoff, never inline in the request path."

**Wrap-up (30s):**
"Short version: normalize every source into one identifier-keyed record, dedupe across sources, expand via the citation graph, refresh incrementally, and cite identifiers not titles. Happy to go deeper on any of the APIs or the dedup logic."

---

## Pitfalls

- **Mistake:** Citing paper titles or author-year strings without validating identifiers — **Better:** Render DOI or arXiv IDs checked against the index; titles hallucinate fluently, identifiers resolve or they don't.
- **Mistake:** Treating arXiv IDs as versionless ("we indexed arXiv:2401.12345") — **Better:** Record the exact version indexed and default to latest; version bumps can retract claims, and reproducibility requires the pinned version.
- **Mistake:** Indexing the same paper twice from different sources and double-counting it in retrieval — **Better:** Dedupe on DOI → arXiv ID → PMID with OpenAlex as crosswalk so one paper yields one chunk set.
- **Mistake:** Calling source APIs inline in the query path with no rate limiting — **Better:** Put all fetching behind a rate-limited queue with backoff and cache (arXiv ~3s guidance, NCBI per-second caps, S2 key requirement); the request path reads the local spine and cache.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q1: Design a RAG system for a customer support chatbot](02-001-design-a-rag-system-for-a-customer-support-chatbot-how-do-yo.md) | The end-to-end RAG architecture this connector layer plugs into — retrieval, rerank, generate |
| [Q22: Citations and source attribution in RAG?](02-022-citations-and-source-attribution-in-rag.md) | The citation-validation gate that consumes the identifiers this layer guarantees |
| [Q3: Design a GenAI document processing pipeline for unstructured documents](02-003-design-a-genai-document-processing-pipeline-for-unstructured.md) | PDF parsing and section-aware chunking for fetched papers — the stage after the connector delivers records |

---

## One-liner recall

> Scholarly connectors normalize arXiv, OpenAlex, Semantic Scholar, and PubMed into one identifier-keyed record (DOI/arXiv ID/PMID), dedupe across sources, expand via the citation graph, refresh incrementally — and cite resolvable identifiers, never bare titles.
