# LLM confidently wrong — debug RAG giving confident wrong answers?

**Category:** 05-evaluation-metrics
**Question #:** 006
**Source section:** §5 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
Interviewers probe whether you can systematically diagnose a production failure in a RAG system rather than just retrain or swap the model. Confident wrong answers are the most dangerous hallucination pattern because they erode user trust while the system shows no obvious error signal. The question tests production debugging instinct: can you isolate retrieval failures from generation failures, and do you have concrete tools and metrics to do so?

### Trigger phrases
- "Your RAG chatbot is giving confident but wrong answers — what do you do?"
- "LLM is confidently wrong, not just hallucinating empty context — how do you debug?"
- "Users say the system gives wrong answers with high confidence — walk me through your investigation."

### What it tests
Whether the candidate can split retrieval failure from generation failure using RAGAS metrics and systematic layer-by-layer debugging, rather than reflexively blaming the model or calling for fine-tuning.

---

## Answer

### Concept
Confident wrong answers in a RAG system arise from one of two root causes: **retrieval failure** (the wrong chunks are surfaced and the LLM faithfully synthesizes from bad evidence) or **generation failure** (the right chunks are retrieved but the LLM confabulates beyond or against them). These require completely different fixes, so the first diagnostic goal is to isolate which layer is broken.

### Mechanism

**Step 1 — Split retrieval from generation using RAGAS**

Run RAGAS on a sample of failure cases:
- **`context_recall`** low (< 0.7) → retrieval is the problem; retrieved chunks don't contain the answer.
- **`faithfulness`** low (< 0.8) but `context_recall` high → generation is the problem; model is confabulating beyond the retrieved context.
- Both high but `answer_relevancy` low → query understanding / synthesis layer is the problem.

**Step 2 — Debug retrieval failures (context_recall low)**

Check in order:
1. **Chunking** — Is the answer split across chunk boundaries? Log the chunk IDs for failing queries and inspect. If the answer straddles two chunks, add overlap or switch to parent-child chunking (1024 parent / 256 child).
2. **Vocabulary mismatch** — Dense-only retrieval failing on exact keywords (SKU numbers, legal citations, model names). Fix: add BM25 hybrid with RRF fusion. Run `Recall@5` before/after; expect +15–20 pts.
3. **Top-k too low** — The answer is in position 8 but `top_k=5`. Temporarily raise `k` on the failing queries to confirm, then add a cross-encoder reranker (Cohere Rerank / BGE-Reranker) rather than just raising `k` blindly (context window cost).
4. **Stale index** — The answer is correct in the source document but the index hasn't updated. Check `index_lag_seconds` monitoring; add CDC-driven incremental ingestion.

**Step 3 — Debug generation failures (faithfulness low)**

1. **Temperature too high** — LLM is sampling creatively and drifting from the retrieved context. Set `temperature=0` for factual RAG.
2. **Lost in the middle** — Correct chunk is retrieved but placed in position 3–6 of a 7-chunk context; the LLM underweights it. Reorder chunks: most relevant first and last (sandwich placement).
3. **Prompt not grounding** — System prompt doesn't instruct the model to stay within retrieved context. Add explicit grounding instruction: `"Answer only using the context below. If the answer is not in the context, say so."`
4. **Context pollution** — Irrelevant chunks in the context confuse the model. Reduce `top_k`, apply cross-encoder reranker to filter, or raise the cosine similarity threshold for retrieval.

**Step 4 — Add a confidence gate**
Post-generation: run DeBERTa NLI entailment between the answer and each retrieved chunk. If max entailment score < 0.80, replace the answer with a canned abstention (`"I'm not confident I have the right information for this — here's what I found: [sources]"`). This caps the confident-wrong rate at the NLI model's precision.

### Example / Tradeoff

**Concrete incident pattern:** A support bot answered billing questions incorrectly with high confidence. RAGAS `context_recall = 0.91` (retrieval fine), `faithfulness = 0.54` (generation broken). Investigation revealed `temperature=0.7` was set globally; the LLM was blending retrieved policy text with its pre-training knowledge of similar policies. Fix: `temperature=0` + explicit grounding prompt. Faithfulness rose to 0.93, confident-wrong rate dropped from 4.2% to 0.6%.

**Tradeoff:** Adding a synchronous DeBERTa NLI gate adds ~80–120ms per query. For latency-sensitive paths, run it async with a fallback: serve the answer immediately, flag for review if NLI < threshold, and surface the correction to the user asynchronously (email / next session). For regulated domains (healthcare, finance), the synchronous gate is non-negotiable.

---

## Verbal script

**Opening (30s):**
"Confident wrong answers are the hardest RAG failure because there's no obvious error signal — the system looks like it's working. My first instinct is not to retrain or swap the model. Instead, I split the problem into two layers: retrieval and generation. They fail for different reasons and need different fixes."

**Core explanation (2–3 min):**
"I'd start by running RAGAS on a sample of the failing queries — specifically `context_recall` and `faithfulness`. These two metrics together act as a diagnostic crosshair.

If `context_recall` is low — say below 0.70 — the retrieved chunks simply don't contain the answer. The LLM is doing its best with bad evidence. I'd look at three culprits: chunking boundaries splitting the answer, vocabulary mismatch where dense retrieval misses exact keywords like SKU numbers or legal citations, and stale indexes where the source was updated but the vector index wasn't. The vocabulary mismatch is really common — switching to BM25 hybrid search with RRF fusion usually fixes it and I'd expect Recall@5 to jump 15–20 points.

If `context_recall` is high but `faithfulness` is low — the right chunks are there but the LLM is generating beyond them — then I look at temperature first. Even a temperature of 0.7 on a factual task causes the model to blend retrieved context with its pre-training priors. Setting temperature to zero is often the single highest-ROI fix. I'd also add an explicit grounding instruction in the system prompt and check for lost-in-the-middle: if the correct chunk is in position 4 of 7, the model systematically underweights it, so reordering with the most relevant chunk first and last often helps."

**Tradeoff / production angle (1 min):**
"Once the root cause is fixed, I'd add a long-term confidence gate: async DeBERTa NLI entailment between the answer and retrieved chunks. If the entailment score is below 0.80, the system falls back to a canned abstention rather than serving the wrong answer confidently. The tradeoff is ~80–100ms latency. For a support bot that's usually fine to run synchronously. For a real-time product, I'd run it async and surface a correction in the next interaction. For a healthcare chatbot, the sync gate is non-negotiable."

**Wrap-up (30s):**
"So the structured approach is: RAGAS to split retrieval from generation, layer-by-layer debug starting with the cheapest fixes (temperature, grounding prompt, chunking), and a NLI gate as the production safety net. Happy to go deeper on any of those layers."

---

## Pitfalls

- **Mistake:** Saying "we should fine-tune the model to fix hallucinations" — **Better:** Fine-tuning doesn't fix retrieval failures and rarely fixes generation-layer confident-wrong answers; start with RAGAS to diagnose the layer, fix retrieval with hybrid search or chunking changes, fix generation with `temperature=0` and grounding prompts — fine-tune is the last resort.
- **Mistake:** Saying "just lower the temperature to 0" without first checking whether retrieval is the root cause — **Better:** Temperature=0 helps only when good context is retrieved; if `context_recall` is low, the model is faithfully summarizing bad evidence, and temperature changes don't help — you need to fix retrieval first.
- **Mistake:** Treating confident wrong answers as a single phenomenon — **Better:** Distinguish intrinsic hallucination (model invents facts absent from context) from retrieval-grounded confabulation (model extends beyond retrieved context) from retrieval failure (wrong context → wrong answer) — each has a different fix.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q3: Detect and mitigate hallucinations in production](05-003-detect-and-mitigate-hallucinations-in-production.md) | prerequisite — broader hallucination framework this question drills into |
| [Q8: Measure hallucination rate in production](05-008-measure-hallucination-rate-in-production.md) | follow-up — how to track the metric this debugging process targets |
| [Q13: Common RAG failure points — how debug them?](../answers/02-013-common-rag-failure-points-how-debug-them.md) | same concept from RAG category — retrieval-layer debug taxonomy |

---

## One-liner recall

> Run RAGAS: low `context_recall` → fix retrieval (hybrid search, chunking, freshness); low `faithfulness` → fix generation (temperature=0, grounding prompt, sandwich placement); add async DeBERTa NLI gate to cap confident-wrong rate in production.
