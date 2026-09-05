# Agents collaborating on research reports with citations

**Category:** 03-agents-tool-use
**Question #:** 037
**Source section:** §3 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
This is a multi-agent system design question. The interviewer wants to see whether you can decompose a compound research task into parallel agent roles, coordinate their outputs with attribution integrity, and handle the production challenges: source deduplication, citation validation, conflicting claims, cost/latency, and coherent final synthesis. It tests architectural thinking beyond single-agent RAG.

### Trigger phrases
- "Design a system where multiple agents collaborate to produce a research report."
- "How would you build an AI research assistant that generates cited reports?"
- "Walk me through a multi-agent pipeline for research synthesis with source attribution."

### What it tests
Ability to decompose a complex document-generation workflow into coordinated multi-agent roles with reliable citation provenance, deduplication, conflict resolution, and quality gates.

---

## Answer

### Concept
A multi-agent research pipeline assigns specialized roles — Planner, parallel Researcher agents, a Synthesizer, and a Citation Validator — where each Researcher searches a distinct source domain and returns structured findings with source metadata, then the Synthesizer merges and narrativizes them, and an independent Citation Validator verifies every claim traces back to a retrieved chunk before the report is finalized.

### Mechanism

**Agent roles and responsibilities:**

```
[Planner agent]
  Input: user research question
  Output: structured outline {sections[], search_queries_per_section[], source_domains[]}
  Model: a frontier model, T=0.3 (some creativity in decomposition)

[Researcher agents — run in parallel, one per section or domain]
  Input: sub-query + assigned source domain (web, internal docs, arXiv, SEC filings)
  Tools: web_search, doc_retrieval (Pinecone/hybrid BM25+dense), pdf_extract
  Output: [{claim, supporting_chunk, source_url, source_title, confidence}]
  Model: a small fast model, T=0 (factual extraction)

[Dedup + Merge step — orchestrator code, not an agent]
  Cosine-dedup retrieved chunks (threshold > 0.92 → keep highest-confidence version)
  Group claims by section from the outline

[Synthesizer agent]
  Input: outline + deduplicated claim-evidence pairs per section
  Output: prose report draft with inline [n] citation markers, structured bibliography
  Model: a frontier model, T=0.3

[Citation Validator agent]
  Input: report draft + source chunks
  Per [n] citation: NLI entailment check — does the source chunk entail the cited claim?
  Output: {citation_id, valid: bool, entailment_score, suggested_fix}
  Model: DeBERTa-v3-large fine-tuned for NLI, or a small fast model as LLM judge
  Threshold: entailment_score < 0.75 → flag for revision or removal

[Revision loop — max 2 iterations]
  Flagged claims → route back to Synthesizer with validator feedback
  OR remove claim if no supporting evidence exists in retrieved set

[Final report] → rendered with citation footnotes, bibliography, confidence annotations
```

**Orchestration pattern:** Supervisor (LangGraph) dispatches Researcher agents in parallel fan-out, awaits all completions, runs the orchestrator-code dedup step, then sequences Synthesizer → Validator in serial. No choreography here — visibility into all partial results is needed before synthesis.

**Memory and state:**
- **Working memory:** each Researcher holds its retrieved chunks in context only
- **Shared state (Postgres/Redis):** section → claim list, persisted after each Researcher completes (checkpoint for resumability on partial failure)
- **Citation index:** source_url → {title, retrieved_at, chunk_text} — built incrementally, deduplicated by URL+content hash

**Tool schemas (Researcher tools, abbreviated):**
```json
web_search(query, max_results=10) → [{title, url, snippet, full_text}]
doc_retrieval(query, collection, top_k=5) → [{chunk, source_id, score}]
extract_claim(text, query) → [{claim, supporting_text, confidence}]
```

**Citation format in output:**
```
"Transformer models scale predictably with data and parameters [1], though
recent evidence suggests a data-compute optimum [2]."

[1] Kaplan et al. 2020, "Scaling Laws for Neural Language Models", arXiv:2001.08361
[2] Hoffmann et al. 2022, "Training Compute-Optimal LLMs (Chinchilla)", arXiv:2203.15556
```

### Example / Tradeoff

**Concrete stack:** LangGraph for supervisor/parallel dispatch, a frontier model for Planner + Synthesizer, a small fast model for Researcher extraction, DeBERTa-v3-large NLI model for Citation Validator (faster + cheaper than a frontier model at high citation volume), Pinecone hybrid BM25+dense for internal doc retrieval, Tavily or Bing API for web search, Postgres for shared claim state.

**Cost math (one 10-section report, 3 Researcher agents per section):**
- 30 Researcher calls × ~2K tokens avg = 60K tokens at a small fast model → ~$0.024
- 1 Synthesizer call × ~8K tokens = $0.04 at a frontier model
- 1 Validator pass × 50 citations × ~300 tokens NLI = 15K tokens → DeBERTa inference ~$0.002
- Total: ~$0.07/report at this scope; scales to ~$70/1K reports

**Key tradeoffs:**
| Dimension | Choice | Tradeoff |
|-----------|--------|----------|
| Orchestration | Supervisor (LangGraph) | Full visibility for dedup; SPOF vs choreography resilience |
| Citation validation | NLI model (DeBERTa) vs LLM judge | DeBERTa: 5× cheaper, 10× faster, but binary; LLM judge: nuanced but costly |
| Parallel Researchers | Fan-out per section | Wall-clock = slowest researcher; requires shared state for merge |
| Revision loops | Max 2 iterations | Prevents runaway cost; 2 passes resolves >90% of NLI-flagged claims in practice |

---

## Verbal script

**Opening (30s):**
"I'd design this as a supervisor-worker multi-agent system: a Planner decomposes the research question into sections and sub-queries, parallel Researcher agents retrieve and extract claims with source metadata, a Synthesizer produces the narrative draft with inline citation markers, and a Citation Validator does an NLI entailment pass to confirm every claim is actually supported by the retrieved source. Let me walk through each layer."

**Core explanation (2–3 min):**
"The Planner uses a frontier model to produce a structured JSON outline — sections, search sub-queries per section, and which source domains to search. That decomposition is the most important step: a badly scoped sub-query means Researchers bring back irrelevant evidence, and the Synthesizer hallucinates to fill the gap.

Researcher agents run in parallel — one per section or one per source domain depending on the task. Each one searches its domain (web via Tavily, internal docs via Pinecone hybrid BM25+dense, PDFs via a parser), extracts structured claim-evidence pairs, and returns them with source metadata: URL, title, the exact supporting chunk. This structured output is critical — if you let Researchers return free-form prose, you lose provenance and the Citation Validator can't verify anything.

Before synthesis, I run an orchestrator-code dedup step: cosine similarity on retrieved chunks above 0.92 → keep the highest-confidence version. This prevents the Synthesizer from citing the same underlying fact with two different sources, which makes reports look sloppy.

The Synthesizer then gets the deduplicated claim-evidence pairs grouped by section. It writes prose and places inline [n] markers referencing the citation index. Temperature 0.3 here — factual accuracy matters more than creativity, but some fluency is needed.

Then the Citation Validator — I'd use DeBERTa-v3-large fine-tuned for NLI rather than a small fast model because it's 5× faster and 10× cheaper at scale, and citation validation is a binary entailment task, not a generation task. Any citation with entailment score below 0.75 gets flagged: the Synthesizer revises the claim or removes it if no supporting evidence exists. I cap this at 2 revision loops to control cost."

**Tradeoff / production angle (1 min):**
"The hardest production problem is conflicting claims across Researchers — two agents find sources that say opposite things. I handle this by surfacing the conflict explicitly in the Synthesizer's prompt: 'Source A says X, Source B says Y — acknowledge the disagreement and cite both.' Suppressing conflicts produces a confident-but-wrong report, which is worse than an uncertain one.

The other issue is cost creep: parallel Researchers each making multiple web search + retrieval calls can hit $0.50–1.00/report if not bounded. I limit each Researcher to max_results=10 web hits and top_k=5 RAG chunks, and gate Researcher calls through a budget tracker in the orchestrator."

**Wrap-up (30s):**
"So the key architectural decisions are: structured claim-evidence output from Researchers (not prose), orchestrator-code dedup before synthesis, NLI-based Citation Validation as a separate agent rather than trusting the Synthesizer's self-assessment, and max 2 revision loops. Happy to go deeper on the NLI validation layer or the conflict-resolution strategy."

---

## Pitfalls

- **Mistake:** Having Researchers return free-form summaries instead of structured claim-evidence pairs with source metadata — **Better:** Require structured JSON output `{claim, supporting_chunk, source_url, confidence}` from every Researcher; without this the Citation Validator has nothing to check against and the Synthesizer fabricates citations from memory.
- **Mistake:** Trusting the Synthesizer to self-verify citations ("just prompt it to be accurate") — **Better:** Run an independent Citation Validator agent (NLI model or LLM judge) after synthesis; the Synthesizer's job is fluent narrative, not entailment verification — conflating the two roles degrades both.
- **Mistake:** Not handling conflicting claims across Researchers — acknowledging only one source when sources disagree — **Better:** Surface conflicts explicitly in the Synthesizer prompt and instruct it to cite both and note the disagreement; confident synthesis of conflicting evidence is the #1 hallucination mode in multi-agent research pipelines.
- **Mistake:** Skipping the orchestrator-code dedup step and letting the Synthesizer see the same fact from two slightly different chunks — **Better:** Cosine dedup (threshold ~0.92) before synthesis prevents redundant citations and duplicate-source bibliography entries that undermine report credibility.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q32: Orchestration vs choreography for multi-agent systems](03-032-orchestration-vs-choreography-for-multi-agent-systems.md) | Supervisor pattern used here — why orchestration over choreography for this workflow |
| [Q22: Tool schemas that reduce hallucinated actions](03-022-tool-schemas-that-reduce-hallucinated-actions.md) | Structured Researcher output schemas prevent citation fabrication |
| [Q22: Citations and source attribution in RAG](../answers/02-022-citations-and-source-attribution-in-rag.md) | Single-agent citation mechanics — same NLI validation pattern applied here |

---

## One-liner recall

> A multi-agent research pipeline uses a Planner to decompose the question, parallel Researcher agents to retrieve structured claim-evidence pairs with source metadata, an orchestrator dedup step, a Synthesizer for narrative with inline citation markers, and an NLI Citation Validator to verify every claim before finalizing — with at most 2 revision loops to bound cost.
