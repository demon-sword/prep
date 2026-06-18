# Perplexity, ROUGE, BLEU — pitfalls of n-gram metrics?

**Category:** 05-evaluation-metrics
**Question #:** 009
**Source section:** §5 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
Interviewers ask this to check whether you know the standard academic metrics well enough to critique them. The trap is candidates who recite the formulas confidently but then apply BLEU or perplexity to a production LLM task without recognising why those numbers will mislead them. Strong candidates know when *not* to use a metric as much as when to use it.

### Trigger phrases
- "How do you measure the quality of generated text?"
- "What metrics do you use to evaluate LLM outputs?"
- "Is BLEU a good metric for your use case?"
- "What's wrong with n-gram-based metrics for GenAI?"

### What it tests
Whether the candidate can critically evaluate the limits of classic NLP metrics and articulate why production LLM eval requires a layered approach beyond n-gram overlap.

---

## Answer

### Concept
**Perplexity** measures how well a language model's probability distribution predicts a held-out text corpus — lower is better, but it's internal to a specific model. **BLEU** and **ROUGE** count n-gram overlaps between a generated output and one or more reference strings. All three predate the generative AI era and share a core flaw: they measure surface-form similarity to a reference, not semantic correctness, factual accuracy, or user utility.

### Mechanism

**Perplexity:**
- Defined as `exp(-1/N · Σ log p_model(token_i))` over N tokens.
- Measures how "surprised" a model is by a test corpus — lower PPL means the model assigns higher probability to real text.
- **Pitfall 1:** Not comparable across models with different tokenizers or vocabularies. GPT-4's PPL on a dataset cannot be compared to Llama 3's PPL on the same dataset because token boundaries differ.
- **Pitfall 2:** Low perplexity doesn't mean high-quality output. A model trained to be verbose and hedge everything can achieve low PPL while producing unhelpful answers.
- **Pitfall 3:** Perplexity has no concept of factual accuracy — a model that confidently hallucinates plausible-sounding text can still have low PPL.

**BLEU (Bilingual Evaluation Understudy):**
- Computes modified n-gram precision (n=1–4) between hypothesis and reference translations, with a brevity penalty.
- Originally designed for machine translation with many reference translations.
- **Pitfall 1:** Requires exact reference strings. For open-ended generation (chat, summarization, QA), there is no single correct answer — a semantically perfect paraphrase scores 0 if it shares no n-grams with the reference.
- **Pitfall 2:** Rewards n-gram copying over semantic paraphrase. A hallucinated sentence that borrows words from context can score higher than a factually correct restatement.
- **Pitfall 3:** Sensitive to tokenization and case normalisation — scores can differ significantly between implementations (sacrebleu vs custom scripts).

**ROUGE (Recall-Oriented Understudy for Gisting Evaluation):**
- Measures n-gram recall (and F1) between a system summary and reference summaries. ROUGE-1 (unigrams), ROUGE-2 (bigrams), ROUGE-L (longest common subsequence).
- Better than BLEU for summarization because recall matters more (you want to cover key points).
- **Pitfall 1:** Still surface-form — a factually correct, well-worded summary of different length or lexical choice can score low.
- **Pitfall 2:** ROUGE-L penalises paraphrase heavily even when the LCS correctly captures the key idea.
- **Pitfall 3:** Multi-reference ROUGE is needed but rarely available in production datasets; single-reference ROUGE underestimates quality when many valid summaries exist.

### Example / Tradeoff

**Production example — customer support chatbot evaluation:**

| Metric | Score | Reality |
|--------|-------|---------|
| ROUGE-L vs template reference | 0.42 | Bot's answer was correct but used different phrasing |
| BLEU-4 | 0.21 | Seemed poor; human raters gave 4.2/5 |
| RAGAS Faithfulness | 0.94 | Correctly grounded in retrieved context |
| RAGAS Answer Relevancy | 0.89 | Directly addressed the user question |
| Deflection rate | 68% | Business metric: 68% of tickets resolved without human |

BLEU and ROUGE signalled a "bad" model; RAGAS and the business metric revealed a strong one.

**When each metric is still useful:**
- **Perplexity:** Useful for comparing pre-training data quality or checkpoint selection *within the same model family and tokenizer* (not cross-model).
- **BLEU:** Still standard for machine translation benchmarks (WMT, FLORES) where multiple reference translations exist and fluency is the goal.
- **ROUGE:** Useful for summarization regression testing when you have stable human-written reference summaries and want to catch catastrophic degradation — not for fine-grained quality.

**What to use instead for LLM eval:**
- **RAGAS** (Faithfulness, Answer Relevancy, Context Recall, Context Precision) for RAG pipelines.
- **LLM-as-Judge** (GPT-4o or Claude sampling 5–10% of outputs, scoring on rubric dimensions: correctness, helpfulness, groundedness).
- **Golden dataset with human labels** for regression gating (≥N% on held-out set before deploy).
- **Production business metrics:** deflection rate, CSAT, p95 latency, thumbs-down rate.

---

## Verbal script

**Opening (30s):**
"I'd start by saying that perplexity, BLEU, and ROUGE were designed for a pre-LLM era — they're surface-form metrics that measure token or n-gram overlap against a reference string. They can still be useful in narrow contexts, but for modern generative AI evaluation they mislead more than they reveal. Let me walk through each and its specific failure mode, then explain what I use instead."

**Core explanation (2–3 min):**
"Perplexity measures how surprised a model is by held-out text — lower is better. The key pitfall is that it's not comparable across models with different tokenizers, so you can't use it to compare GPT-4 to Llama. And low perplexity doesn't mean high quality — a model that outputs fluent, plausible-sounding hallucinations can have low PPL.

BLEU counts n-gram precision between your output and a reference, with a brevity penalty. It was designed for machine translation where multiple references exist. The fatal flaw for generative tasks: if the model produces a semantically correct answer in different words, BLEU scores it near zero. I've seen BLEU scores under 0.25 for answers that human raters scored 4.2 out of 5.

ROUGE is similar but measures recall — designed for summarization, where you care that key points are covered. It's slightly more useful because recall matters for summarization, but it still penalises paraphrase and requires stable reference summaries, which are expensive to maintain.

The deeper issue is none of these metrics measure what actually matters: factual correctness, groundedness in retrieved context, or user utility."

**Tradeoff / production angle (1 min):**
"In production I use a layered eval stack. For RAG systems: RAGAS Faithfulness and Answer Relevancy on a golden dataset — these are model-based evals that check whether the answer is grounded in the retrieved context and actually answers the question. For regression gating: a golden dataset with human labels. For ongoing monitoring: LLM-as-judge sampling 5–10% of traffic with a rubric, plus business metrics like deflection rate and CSAT. I'll still use ROUGE for summarization regression testing when I have stable references and just want to catch catastrophic drops — but never as a primary quality signal."

**Wrap-up (30s):**
"So the short answer: BLEU and ROUGE are reasonable for machine translation and summarization regression respectively, but for open-ended LLM output quality they're misleading. Perplexity is useful for within-family checkpoint selection. For production LLM eval, I rely on RAGAS, LLM-as-judge, golden datasets, and business metrics. Happy to go deeper on any of these."

---

## Pitfalls

- **Mistake:** Using BLEU score as the primary quality metric for a chatbot or QA system and reporting numbers without mentioning that many valid phrasings score near zero — **Better:** Acknowledge that BLEU was designed for MT with multiple references; explain that for generative tasks you need semantic metrics (RAGAS, LLM-judge) and only use BLEU for regression testing catastrophic degradation.
- **Mistake:** Saying "perplexity is how good the model is" without noting it's not comparable across different tokenizers/models, and that it doesn't measure factual accuracy — **Better:** Clarify PPL is useful for within-family checkpoint selection or data quality comparison; explain it cannot be compared across GPT-4 vs Llama 3 because tokenization differs and a model can hallucinate with low PPL.
- **Mistake:** Treating ROUGE-L as sufficient for summarization quality evaluation and not mentioning that a factually correct paraphrase can score poorly — **Better:** Use ROUGE for regression catch on stable reference summaries, pair with RAGAS Faithfulness or an NLI entailment check for factual correctness.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q1: What metrics for benchmarking LLM performance?](05-001-what-metrics-for-benchmarking-llm-performance.md) | Broader framework that contextualises where BLEU/ROUGE fit |
| [Q8: Measure hallucination rate in production?](05-008-measure-hallucination-rate-in-production.md) | Production eval stack that replaces n-gram metrics |
| [Q17: Golden dataset for evaluation and regression testing?](05-017-golden-dataset-for-evaluation-and-regression-testing.md) | How to build the reference set that makes regression testing meaningful |

---

## One-liner recall

> BLEU/ROUGE measure n-gram overlap against a fixed reference — they penalise correct paraphrases, can't detect hallucinations, and mislead on open-ended LLM tasks; use RAGAS, LLM-as-judge, and business metrics instead, reserving ROUGE for summarization regression and BLEU only for MT.
