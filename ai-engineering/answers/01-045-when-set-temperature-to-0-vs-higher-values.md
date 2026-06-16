# When set temperature to 0 vs higher values?

**Category:** 01-llm-fundamentals
**Question #:** 045
**Source section:** §1 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
Interviewers use this question to check whether you understand sampling mechanics well enough to make deliberate, defensible production decisions — not just copy default configs. It reveals whether you think about correctness vs creativity, determinism vs diversity, and how those tradeoffs map to specific use cases like RAG answer generation, code synthesis, or creative writing.

### Trigger phrases
- "When would you set temperature to 0 vs something higher?"
- "What temperature do you use for factual/code/creative tasks?"
- "How do you control randomness in LLM outputs?"
- "Why did you choose that temperature in your system?"

### What it tests
Ability to map sampling parameters to production requirements (correctness, reproducibility, diversity) and articulate the underlying mechanism.

---

## Answer

### Concept
Temperature controls the "sharpness" of the next-token probability distribution: **T=0** collapses it to a deterministic argmax (greedy decoding), while **T>1** flattens it toward uniform randomness. The right value depends on whether the task rewards precision (RAG, code, SQL) or variety (brainstorming, creative writing, persona chat).

### Mechanism
Before sampling, each logit `z_i` is divided by the temperature T:

```
p_i = softmax(z_i / T)
```

- **T → 0**: the highest-logit token dominates; output is deterministic and reproducible (same prompt → same output every time).  
- **T = 1**: raw model probabilities used as-is (default training distribution).  
- **T > 1**: distribution flattened — lower-probability tokens become more likely, increasing diversity but also incoherence risk.  
- **T < 1** (e.g. 0.2–0.5): distribution sharpened — favors the model's top choices, reducing variance without full determinism.

In practice, `temperature=0` is implemented as **greedy decoding** (argmax) rather than literal division-by-zero. Most inference engines (vLLM, TGI, OpenAI API) treat `temperature=0` as an alias for greedy sampling.

### Example / Tradeoff

| Use case | Recommended T | Reason |
|----------|---------------|--------|
| RAG answer generation | 0 – 0.2 | Faithfulness to retrieved context; reproducibility for regression testing |
| Code generation (function bodies) | 0 – 0.1 | Correctness > creativity; pass@1 is key |
| SQL / structured output | 0 | One right answer; JSON schema validation easier at T=0 |
| Chat / customer support | 0.5 – 0.7 | Natural but not wild; consistent enough for evaluation |
| Creative writing / marketing copy | 0.8 – 1.2 | Diversity matters; multiple generations compared |
| Brainstorming / ideation | 1.0 – 1.5 | Intentional exploration of long-tail ideas |

**Production note:** OpenAI's API defaults to `temperature=1`; vLLM defaults to `temperature=0` for batch inference. Always set explicitly. For self-consistency prompting (multiple samples → majority vote), use T=0.5–0.7 to get meaningful diversity across samples.

**Interaction with top-p:** Temperature and top-p (nucleus sampling) are often used together. A common production config for factual RAG: `temperature=0.1, top_p=0.95` — the top-p cap prevents rare-token hallucinations even when a slightly elevated temperature is used for minor naturalness. Never combine T=0 with top-p filtering — they conflict (greedy ignores sampling).

---

## Verbal script

**Opening (30s):**
"Temperature controls how sharp or flat the model's probability distribution is when sampling the next token. The decision really comes down to: does this task have a single correct answer, or do we want diversity? I think about it as a precision-vs-creativity dial."

**Core explanation (2–3 min):**
"Mechanically, every logit gets divided by T before the softmax. At T=0 — which the API treats as greedy, argmax decoding — the highest-probability token always wins. Same prompt gives the same output every time. That's what you want for RAG answer generation, SQL synthesis, or structured JSON output, because reproducibility matters and hallucinating an alternative phrasing is a risk.

As T goes up toward 1, you're using the model's raw training distribution — the defaults. Above 1, you're flattening the distribution, making surprising tokens more likely. That's useful for brainstorming or creative writing but harmful for factual tasks.

In my systems I use three tiers: zero or near-zero for anything where correctness is the metric (code, SQL, RAG grounding), 0.5–0.7 for conversational responses that need to feel natural, and 0.8–1.2 for intentional creative diversity. I also always set this explicitly — OpenAI defaults to 1, vLLM defaults to 0, so leaving it unset causes inconsistency between environments."

**Tradeoff / production angle (1 min):**
"The one nuance is self-consistency prompting — where you generate N samples and take the majority answer. There you actually want T around 0.5–0.7 to get meaningful sample diversity, otherwise at T=0 you get N identical answers. And you need to be careful combining temperature with top-p: at T=0 you're doing greedy, so top-p filtering is ignored. I set them consistently and document both in the system config so there are no surprises when switching inference backends."

**Wrap-up (30s):**
"So the short answer: T=0 for anything requiring correctness or regression-testable determinism; higher values when diversity or naturalness is the goal. Happy to go deeper on top-p, top-k, or how speculative decoding interacts with temperature."

---

## Pitfalls

- **Mistake:** Saying "I use temperature=1 by default because that's the standard" — **Better:** Explain that T=1 is the raw training distribution and is rarely optimal for production; most factual/code tasks benefit from T=0 or T<0.5.
- **Mistake:** Conflating temperature with top-p — e.g. "I set both to 0 for determinism" — **Better:** Clarify that T=0 means greedy decoding (top-p becomes irrelevant); and that top-p and temperature serve complementary roles when T>0.
- **Mistake:** Not mentioning reproducibility implications — **Better:** Point out that T=0 enables deterministic regression testing (same prompt → same output across runs), which is critical for golden-dataset evaluation.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q7: What is temperature and top-p sampling? How do they affect outputs?](01-007-what-is-temperature-and-top-p-sampling-how-do-they-affect-ou.md) | Deeper mechanism; this note focuses on the decision of *when* to use each value |
| [Q32: Beam search, top-k, top-p — when use each?](01-032-beam-search-top-k-top-p-when-use-each.md) | Sibling question covering other decoding strategies |
| [Q43: How do you reduce hallucinations in LLM outputs?](01-043-how-do-you-reduce-hallucinations-in-llm-outputs.md) | Temperature=0 is one layer in the hallucination mitigation stack |

---

## One-liner recall

> Set T=0 for correctness and reproducibility (RAG, code, SQL); increase toward 0.7–1.2 only when diversity or naturalness is the goal, and always set it explicitly since defaults differ across inference engines.
