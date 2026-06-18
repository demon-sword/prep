# Measure accuracy in generative systems?

**Category:** 05-evaluation-metrics
**Question #:** 011
**Source section:** §5 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
Generative systems have no single "correct" output — a customer support answer, a legal summary, and a code completion can each be right in dozens of ways. Interviewers ask this to see whether you understand that traditional classification accuracy is meaningless here and whether you can build a layered evaluation framework that ties offline metrics to production business outcomes.

### Trigger phrases
- "How do you measure accuracy in a generative model?"
- "What metrics do you use to validate your LLM outputs?"
- "How do you know your RAG pipeline is giving correct answers?"
- "How do you evaluate quality in a chatbot without ground truth?"

### What it tests
Whether the candidate can design a multi-layer eval stack — property checks → semantic similarity → LLM-as-judge → business metrics — and explain why each layer is necessary.

---

## Answer

### Concept
"Accuracy" in generative systems is not a single number but a **stack of complementary signals**: structural correctness (is the format right?), semantic faithfulness (does it say something true?), relevance (does it answer the question?), and downstream impact (did the user succeed?). No single metric captures all of these; strong candidates instrument all four layers.

### Mechanism

**Layer 1 — Structural / property checks (automated, 100% coverage)**
- Schema validation: does the output match the expected JSON schema, length bounds, or citation format?
- Regex / rule checks: are required fields present, no PII leaking, stop tokens respected?
- Tools: `pydantic`, `instructor`, `jsonschema`

**Layer 2 — Semantic accuracy (sample or golden-dataset-driven)**
- **RAGAS Faithfulness** — does every claim in the answer entail at least one retrieved passage? (0–1; production SLO ≥ 0.85)
- **RAGAS Answer Relevancy** — does the answer address the question? (cosine similarity of generated answer embeddings to question)
- **NLI entailment** — DeBERTa-large-NLI as a cheaper, synchronous gate; confidence > 0.75 = supported
- **Golden dataset recall** — 200–500 human-annotated (question, reference answer) pairs; score with Exact Match on extractive sub-fields or BERTScore F1 for fluent comparison

**Layer 3 — LLM-as-judge (sample, 5–10% of traffic)**
- GPT-4o judges each answer on 1–5 rubrics (correctness, completeness, tone); inter-rater agreement calibration with human baseline
- Self-consistency check: same prompt × 3 at T=0.7 → majority vote as accuracy proxy for reasoning tasks
- Tools: `promptfoo`, `deepeval`, `RAGAS` judge mode

**Layer 4 — Business / downstream accuracy (production)**
- **Deflection rate** — fraction of queries resolved without human escalation (proxy for end-to-end accuracy)
- **Task completion rate** — did the user click "that solved it" or abandon?
- **Edit distance / acceptance rate** — for copilot-style tools: how often is the generated output used as-is vs edited heavily?
- **CSAT / thumbs-down rate** — direct user signal; segment by topic, retrieval score, and model version

### Example / Tradeoff
A customer support RAG system: Layer 1 catches format errors (JSON missing `ticket_id`). Layer 2 gates each response against the retrieved chunks — RAGAS Faithfulness < 0.80 triggers a fallback canned response. Layer 3 LLM judge runs on 5% of resolved tickets overnight and flags systematic accuracy regressions by topic cluster. Layer 4 deflection rate is the north-star: 78% → 85% after hybrid retrieval fix confirmed that retrieval accuracy was the root cause, not generation.

**BLEU/ROUGE pitfall:** both are n-gram metrics designed for translation/summarisation — they penalise valid paraphrases, reward lexical overlap regardless of factual correctness, and correlate poorly with human judgement on generative tasks (Reiter 2018, EMNLP 2020 findings). Use them only as sanity checks, not primary SLOs.

---

## Verbal script

**Opening (30s):**
"Great question — accuracy in generative systems is genuinely harder than in classification because there's rarely one right answer. I think about it as a four-layer stack: structural checks that run on every response, semantic accuracy on a golden dataset and sampled traffic, an LLM-as-judge layer for nuanced quality, and then downstream business metrics as the north star."

**Core explanation (2–3 min):**
"The first layer is fast and cheap: schema validation, length checks, citation presence — anything that can be asserted without an LLM. These run synchronously on 100% of traffic and catch the obvious failures. The second layer is semantic accuracy. I use RAGAS Faithfulness to check whether every claim in the answer is grounded in the retrieved context — a score below 0.85 triggers a fallback. For extractive fields, I'll also have a golden dataset of 200–500 annotated examples and score exact match or BERTScore F1. Third, I run an LLM-as-judge on a 5% sample — GPT-4o scoring correctness, completeness, and tone on a 1–5 rubric. I calibrate it with human ratings first so I know where it diverges. Finally, the business layer: deflection rate, task completion, and thumbs-down rate. These are the metrics that actually tell you whether accuracy translates to value."

**Tradeoff / production angle (1 min):**
"The honest tradeoff is cost and latency. Running RAGAS synchronously on every response adds ~200ms and real API cost. So I gate: Layer 1 is synchronous, Layer 2 faithfulness runs async after delivery (alerts on 1-hour rolling average), Layer 3 judge is nightly batch. The other trap is over-trusting BLEU or ROUGE — they look like accuracy but they penalise valid paraphrases and miss factual errors entirely. In production I replaced BLEU with faithfulness + answer_relevancy as primary eval SLOs."

**Wrap-up (30s):**
"So the short answer: structural checks for format, RAGAS Faithfulness and a golden dataset for semantic accuracy, LLM-judge for quality at scale, and business metrics for downstream truth. Happy to go deeper on any layer."

---

## Pitfalls

- **Mistake:** Saying "I use BLEU/ROUGE to measure accuracy" without caveats — **Better:** Acknowledge that n-gram metrics don't capture factual correctness or paraphrase validity; explain what you use instead (RAGAS Faithfulness, LLM-judge, golden dataset BERTScore F1).
- **Mistake:** Describing only offline golden-dataset eval and treating it as sufficient — **Better:** Add the production layer (deflection rate, task completion, CSAT) and explain why offline metrics can hide distribution shift and prompt injection failures.
- **Mistake:** Using a single metric (e.g., "faithfulness score") as the accuracy number — **Better:** Explain that faithfulness measures grounding but not relevance or completeness; the stack covers all dimensions.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q1: What metrics for benchmarking LLM performance?](05-001-what-metrics-for-benchmarking-llm-performance.md) | Broader metric taxonomy this answer specialises |
| [Q9: Perplexity, ROUGE, BLEU — pitfalls of n-gram metrics?](05-009-perplexity-rouge-bleu-pitfalls-of-n-gram-metrics.md) | Why BLEU/ROUGE fail for generative accuracy |
| [Q21: How evaluate a RAG pipeline?](02-021-how-evaluate-a-rag-pipeline.md) | RAG-specific accuracy evaluation with RAGAS |

---

## One-liner recall

> Generative accuracy = four-layer stack: structural property checks (100%) → semantic RAGAS Faithfulness + golden-dataset BERTScore F1 → LLM-as-judge 5% sample → production deflection rate / CSAT as north star; never use BLEU/ROUGE as primary SLOs.
