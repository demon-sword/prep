# RAG returns relevant docs but users can't find the answer — search engine vs answer engine

**Category:** 02-rag-systems
**Question #:** 020
**Source section:** §2 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
The interviewer is probing whether you understand the fundamental product design distinction between *retrieval* (surface the right document) and *generation* (synthesize a direct answer). Many RAG systems are built by ML engineers thinking about retrieval quality, but users think in terms of answers — "tell me what to do," not "here's a document that might help." This question tests debugging instinct and user-centric product thinking in AI systems.

### Trigger phrases
- "Our retrieval metrics look great but user satisfaction is low — what's happening?"
- "Users say they can't find what they're looking for even when the right docs are returned."
- "How do you tell when you have a retrieval problem vs a generation problem?"
- "Search engine vs answer engine — what's the difference?"

### What it tests
Whether you can diagnose the retrieval-vs-generation gap and redesign the answer synthesis layer to close it.

---

## Answer

### Concept
A **search engine** returns a ranked list of relevant documents — the user's job is to read and extract the answer themselves. An **answer engine** (what RAG should be) synthesizes a direct, grounded answer from those documents. When retrieval succeeds but users still can't find answers, the pipeline has retrieved well but generated poorly: the generation layer is acting like a search engine (quoting passages) rather than an answer engine (synthesizing conclusions).

### Mechanism
The gap typically manifests in one or more of these failure patterns:

1. **Context dumping** — the LLM returns verbatim passages instead of synthesizing a concise answer. Fix: strengthen the system prompt — explicitly instruct `"Synthesize a direct answer in 2–3 sentences. Do NOT copy-paste the source. Cite the source doc by title."`.

2. **Answer buried in long context** — the LLM receives 5–10 chunks and the user-relevant fact is in chunk 4 of 8; the LLM either buries it or hedges. Fix: reduce top-k (3 instead of 8), and use cross-encoder reranking to put the best chunk first. Also apply the "lost in the middle" placement heuristic — most relevant chunk first or last, never in the middle.

3. **Reformulation gap** — the retrieved doc answers a slightly different question than the user asked (vocabulary mismatch in question framing). Fix: add query rewriting (HyDE or LLM-generated sub-questions) before retrieval so the query better matches how the documents are phrased.

4. **Missing explicit abstention** — when retrieved context is partially relevant, the LLM hedges with "this might be related…" rather than telling the user what it doesn't know. Fix: prompt with explicit abstention instructions (`"If the context doesn't directly answer the question, say so and suggest what the user should look for."`).

5. **No answer consolidation for multi-doc questions** — the answer spans multiple chunks from different docs; without consolidation the LLM writes a disjointed response. Fix: Map-Reduce synthesis or a dedicated consolidation pass over top-N retrieved chunks.

**Diagnostic split using RAGAS:**
- High `context_recall` + low `answer_relevancy` → generation problem (retrieved docs have the info but the answer doesn't use it)
- Low `context_recall` → retrieval problem (wrong docs returned)
- Low `faithfulness` → hallucination (answer invents facts not in retrieved context)

### Example / Tradeoff
In a customer support RAG at a fintech company, retrieval NDCG@5 was 0.82 (excellent) but CSAT was 55%. Post-mortem: the LLM was returning paragraphs starting with "According to our policy document…" followed by 200-word excerpts. Users wanted a one-line answer like "Yes, you can dispute charges within 60 days by calling 1-800-XXX." Fix:
1. Reduced top-k from 8→3, added Cohere Rerank to sharpen the single best chunk.
2. Rewrote system prompt: `"Answer in 1–3 sentences, first person ('You can…'), cite the source title, offer next steps."`.
3. Added answer_relevancy RAGAS check — gated answers below 0.75 to a "I found these related articles: [link1] [link2]" fallback (graceful search-engine degradation).

Result: CSAT improved from 55% to 71% within 2 weeks with no retrieval changes.

**Key tradeoff:** Shorter, synthesized answers feel confident but increase hallucination risk; longer, quoted answers are safer but frustrating. The right balance is: synthesize the answer, cite the source, offer to show the full document. This gives users a direct answer with a trust escape hatch.

---

## Verbal script

**Opening (30s):**
"This is a really common failure mode I've seen in production RAG — the retrieval is working fine, but users still feel like they're not getting answers. The root cause is usually a product design gap: we built a search engine but users expected an answer engine. Let me walk through how I'd diagnose and fix it."

**Core explanation (2–3 min):**
"I'd start by splitting the RAGAS metrics. If `context_recall` is high — meaning the right documents are being retrieved — but `answer_relevancy` is low — meaning the generated answer doesn't actually address the user's question — that's a clear signal the problem is in the generation layer, not retrieval.

The most common generation failure is what I call 'context dumping' — the LLM copies chunks verbatim instead of synthesizing a direct answer. The fix is prompt engineering: explicitly tell the model to answer in 2–3 sentences, synthesize rather than quote, cite the source by title.

The second failure is the 'lost in the middle' problem — with 8 retrieved chunks, the relevant fact ends up in chunk 4, and the LLM either buries or ignores it. Fix: reduce top-k from 8 to 3, use cross-encoder reranking to promote the best chunk, and place it first in the context.

Third: query reformulation gaps. If the user says 'can I get a refund?' but the doc says 'return policy states…', the vocabulary mismatch means even a semantically-retrieved doc isn't phrased in a way the LLM uses to answer directly. Fix: add query rewriting before retrieval — HyDE or an LLM-generated sub-question expansion."

**Tradeoff / production angle (1 min):**
"The tradeoff here is directness vs safety. A highly synthesized answer sounds confident but risks hallucination if the retrieved chunks are partially relevant. My production pattern: synthesize the answer (satisfy the 'answer engine' expectation), cite the source doc title, and add a graceful fallback — if answer_relevancy < 0.75, return 'Here are the most relevant articles' links instead of a synthesized answer. This gives you answer-engine UX on confident cases, search-engine UX when uncertain."

**Wrap-up (30s):**
"So the core insight is: retrieval quality and answer quality are separate problems. RAGAS gives you the diagnostic split — context_recall tells you if retrieval is working, answer_relevancy tells you if generation is working. Fix the right layer. Happy to go deeper on any of the specific fixes."

---

## Pitfalls

- **Mistake:** Assuming "users can't find the answer" means retrieval is broken and immediately retuning embeddings or increasing top-k — **Better:** First split the RAGAS metrics (context_recall vs answer_relevancy vs faithfulness) to determine which layer is failing before touching retrieval; most of the time it's a generation/prompt problem.

- **Mistake:** Increasing top-k to "give the LLM more context" as a fix — **Better:** More context exacerbates lost-in-the-middle and context pollution; the fix is usually reducing top-k and reranking better, plus improving the synthesis prompt.

- **Mistake:** Not distinguishing between the retrieval SLO and the user-facing answer SLO — **Better:** Articulate that retrieval metrics (NDCG, MRR, Recall@k) and user-experience metrics (CSAT, task completion, answer_relevancy) are distinct, and production monitoring needs both.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q13: Common RAG failure points — how debug them?](02-013-common-rag-failure-points-how-debug-them.md) | broader failure taxonomy including retrieval vs generation split |
| [Q21: How evaluate a RAG pipeline? NDCG, MRR, precision@k, recall?](02-021-how-evaluate-a-rag-pipeline-ndcg-mrr-precisionk-recall.md) | evaluation metrics used to diagnose the search-vs-answer gap |
| [Q44: What is the 'lost in the middle' problem?](../answers/01-044-what-is-the-lost-in-the-middle-problem.md) | core mechanism behind context-position failures in generation |

---

## One-liner recall

> When retrieval succeeds but users can't find answers, the generation layer is acting like a search engine (quoting passages) rather than an answer engine (synthesizing conclusions) — diagnose with RAGAS `context_recall` vs `answer_relevancy`, then fix the synthesis prompt, reduce top-k, and rerank.
