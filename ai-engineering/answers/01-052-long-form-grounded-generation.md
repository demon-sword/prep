# How do you generate long-form grounded documents (reports, papers) with an LLM?

**Category:** 01-llm-fundamentals
**Question #:** 052
**Source section:** §1 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
Single-pass generation works for short answers but collapses on long documents: coherence drifts, citations detach from claims, and later sections contradict earlier ones. Interviewers ask this to test whether you understand why long-form grounded generation is a pipeline (plan → draft per section → verify) rather than a longer prompt — and how retrieval and citation checks plug into each stage.

### Trigger phrases
- "How would you generate a 20-page report with citations?"
- "Our model writes good paragraphs but incoherent documents — how do you fix that?"
- "How do you keep citations accurate in long generated documents?"
- "Design an AI paper-writing assistant."
- "How do you prevent contradictions across sections of a long output?"

### What it tests
Whether you can decompose long-form generation into outline planning, section-scoped drafting with retrieval, and claim-level verification — naming the failure mode each stage addresses.

---

## Answer

### Concept
Long-form grounded generation produces multi-section documents where every factual claim traces to a retrieved source. The core technique is hierarchical decomposition: generate a global outline first, then draft each section against its own retrieved context with the outline and prior sections as constraints, then verify citations and cross-section consistency in a separate pass. No single context window holds the whole job at once.

### Mechanism

**1. Outline planning (global coherence):**
- Generate the document outline — sections, per-section key claims, and intended length — before any prose. The outline is the coherence contract: every later stage is constrained by it.
- Retrieve once per planned section (not once for the whole document) so each section's context is dense with relevant material instead of diluted across the full topic.
- Get the outline reviewed — by the user or a critic pass — because structural errors (missing section, wrong emphasis) are cheapest to fix before drafting.

**2. Section-scoped drafting (grounding):**
- Draft one section at a time. Each drafting call receives: the global outline, summaries of already-drafted sections (not full text — compressed context), and fresh retrieved chunks for this section only.
- Instruct the model to attach a source pointer to every factual claim inline during drafting. Claims without pointers are flagged in the next stage, not silently accepted.
- Control length per section explicitly (target tokens or key points to cover); without a budget, sections bloat and the document loses proportion.

**3. Verification pass (separate from drafting):**
- Run the citation check from the RAG citations pattern over the full draft: each claim must be entailed by its cited chunk (NLI gate), and each cited identifier must resolve in the index. Long documents amplify citation drift — a section drafted against one context gets edited later until the citation no longer supports the sentence.
- Cross-section consistency check: collect the document's factual assertions and test for contradictions (dates, numbers, names, positions taken). A single Model call over extracted claim-summaries — not full text — suffices.
- Revision loop is bounded: fix flagged claims (re-retrieve or soften the claim), re-verify once. Unbounded polish loops burn budget for diminishing returns.

**Why not one pass:** a single generation call spreads attention across the full context (the lost-in-the-middle effect degrades recall of mid-context sources), mixes planning with prose (structure suffers), and produces citations after the fact (rationalized, not grounded). Decomposition trades latency and cost for quality at each stage.

### Example / Tradeoff

**A concrete pipeline:** survey-style technical report with citations.
- Outline call: 8 sections with 3–5 key claims each, reviewed by the user.
- Per section: retrieve top chunks for that section's claims, draft with inline source pointers, prior-section summaries in context.
- Verify: citation entailment gate over all claims, identifier resolution, contradiction scan over extracted assertions, one bounded revision round.
- Tooling: the retrieval stages reuse the standard RAG stack (hybrid retrieval, rerank); the drafting and verification stages are the same planner-plus-verifier shape as the research-report agent pattern.

**Tradeoff:** section-by-section drafting with verification costs several times a single pass (more calls, more retrieval, a full verification sweep) and adds latency — wrong for chat or short answers. It pays off when the output is long, factual, and cited: reports, survey drafts, paper sections. The failure mode to avoid is verifying with the same call that drafted — self-review without fresh retrieval or an independent check passes most drift. Separate the verifier's context from the drafter's.

---

## Verbal script

**Opening (30s):**
"I'd never generate a long grounded document in one pass. I'd decompose it: outline first as the coherence contract, draft section by section with per-section retrieval, then verify citations and cross-section consistency in a separate pass. Each stage fixes a specific failure mode of single-pass generation."

**Core explanation (2–3 min):**
"The key insight is that single-pass generation fails three ways on long documents. Attention dilutes across a huge context so mid-document sources get lost. Planning and prose get mixed so the structure suffers. And citations get rationalized after the fact instead of grounded during writing.

So stage one is the outline: sections, key claims per section, length budgets — reviewed before any prose, because structural fixes are cheapest there. I retrieve once per section so each drafting context is dense, not diluted.

Stage two drafts one section at a time, with the outline plus compressed summaries of prior sections in context — summaries, not full text, to control context size. The model attaches source pointers to claims as it writes.

Stage three is verification with fresh eyes: every claim checked against its cited chunk with an entailment gate, identifiers resolved against the index, and a contradiction scan over extracted assertions across sections. Then one bounded revision round — re-retrieve or soften flagged claims — not open-ended polishing."

**Tradeoff / production angle (1 min):**
"This costs several times a single pass, so I'd scope it to outputs worth it: reports, survey drafts, cited documents — never chat. And the verifier must be independent of the drafter: same-call self-review passes most drift. Length budgets per section matter too — without them sections bloat and the document loses proportion."

**Wrap-up (30s):**
"Short version: outline as contract, section-scoped drafting with per-section retrieval, independent verification pass — latency and cost traded for coherence and grounding. Happy to go deeper on the verification design."

---

## Pitfalls

- **Mistake:** Generating the whole document in one long call and adding citations afterward — **Better:** Draft per section with retrieval in context and inline source pointers during writing; post-hoc citations rationalize rather than ground.
- **Mistake:** Verifying with the same call or context that drafted the text — **Better:** Run verification independently with fresh retrieval; self-review without an independent check passes most citation drift and contradictions.
- **Mistake:** Retrieving once for the whole document and sharing that context across all sections — **Better:** Retrieve per section so each drafting context is dense with relevant material; whole-document retrieval dilutes and triggers lost-in-the-middle recall loss.
- **Mistake:** Letting sections bloat with no length budget or outline review — **Better:** Fix the outline and per-section budgets before drafting; structural disproportion is cheapest to correct before prose exists.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q20: Describe text summarization techniques and when you'd use each](01-020-describe-text-summarization-techniques-and-when-youd-use-eac.md) | Companion: prior-section summaries use the same map-reduce compression as long-document summarization |
| [Q22: Citations and source attribution in RAG?](02-022-citations-and-source-attribution-in-rag.md) | The citation entailment gate the verification pass applies to every claim |
| [Q43: How do you reduce hallucinations in LLM outputs?](01-043-how-do-you-reduce-hallucinations-in-llm-outputs.md) | Grounding and verification techniques generalized from single answers to full documents |

---

## One-liner recall

> Long-form grounded generation drafts from a reviewed outline section by section with per-section retrieval, then verifies citations and cross-section consistency independently — never one pass, never self-review.
