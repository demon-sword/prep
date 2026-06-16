# What is temperature and top-p sampling? How do they affect outputs?

**Category:** 01-llm-fundamentals
**Question #:** 007
**Source section:** §1 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
The interviewer is probing whether you understand how LLM inference works beyond just calling an API. Temperature and top-p are the two most commonly mis-set parameters in production — getting them wrong causes hallucinations, repetitive outputs, or outputs that are too random for the task. A strong candidate knows not just what these parameters do but when to set each one and why, with concrete examples from real use cases.

### Trigger phrases
- "How do you control randomness in LLM outputs?"
- "When would you set temperature to 0 vs a higher value?"
- "What sampling strategy would you use for a coding assistant vs a creative writing tool?"
- "Why does your chatbot sometimes give wildly different answers to the same question?"

### What it tests
Understanding of autoregressive decoding mechanics and ability to map sampling parameters to production requirements (determinism vs creativity, hallucination risk, cost implications).

---

## Answer

### Concept
Temperature and top-p (nucleus sampling) are two hyperparameters that control how an LLM selects the next token from the probability distribution computed by the softmax layer. Temperature controls the sharpness of that distribution; top-p controls how many tokens are even considered as candidates. Together they govern the creativity/randomness vs determinism/safety tradeoff.

### Mechanism

**Temperature (`T`):**
- The raw logits from the model are divided by `T` before softmax: `softmax(logits / T)`
- `T = 1.0` → unchanged distribution (model's default)
- `T < 1.0` (e.g., 0.1–0.3) → sharpens distribution; high-probability tokens become even more dominant; output is more deterministic and repetitive
- `T = 0` → greedy decoding; always pick the argmax token; fully deterministic
- `T > 1.0` (e.g., 1.5–2.0) → flattens distribution; lower-probability tokens get more weight; output is more diverse but risks incoherence

**Top-p (nucleus sampling):**
- Sort all tokens by probability descending; take the smallest set whose cumulative probability ≥ `p`; sample from that nucleus only
- `top_p = 1.0` → consider all tokens (no filtering)
- `top_p = 0.9` → take the top tokens summing to 90% probability mass; cut the long tail of unlikely tokens
- Dynamically adjusts the candidate pool: when the model is confident (one token has 0.95 prob), nucleus is tiny; when uncertain, nucleus is wider

**Interaction:** Both parameters are usually applied together. A typical production config: `temperature=0.7, top_p=0.9`. Setting `temperature=0` makes `top_p` irrelevant (greedy wins).

**Top-k (related):** A simpler alternative — sample from the top-k tokens only. Less adaptive than top-p because k is fixed regardless of the model's confidence.

### Example / Tradeoff

| Use case | Temperature | Top-p | Rationale |
|----------|-------------|-------|-----------|
| SQL generation / code | 0 or 0.1 | 1.0 | Correctness critical; determinism preferred |
| Customer support FAQ | 0.2–0.4 | 0.9 | Consistent, factual, low hallucination risk |
| General chat assistant | 0.7 | 0.9 | Natural variation without wild outputs |
| Creative writing / brainstorming | 1.0–1.2 | 0.95 | Diversity and surprise valued |
| Embedding generation | N/A | N/A | Embeddings don't use sampling |

**Production gotcha:** Setting `temperature=0` in a RAG pipeline dramatically reduces hallucination risk but can cause the model to get "stuck" in repetitive loops on edge cases. A small temperature like 0.1 is often safer than exactly 0 for long-form generation.

In frameworks like vLLM, sampling parameters are per-request — you can serve different temperature profiles for different endpoint paths (e.g., `/api/code` vs `/api/chat`) from the same model instance.

---

## Verbal script

**Opening (30s):**
"Temperature and top-p are the two main knobs for controlling randomness in LLM outputs. I think of them as operating at different levels: temperature reshapes the entire probability distribution, while top-p acts as a filter on which tokens are even eligible before sampling. Let me walk through each one and then talk about how I'd choose settings for different production use cases."

**Core explanation (2–3 min):**
"Starting with temperature — when the model computes its next-token probabilities via softmax, it divides the underlying logits by the temperature value first. At temperature 1, you get the model's natural distribution. Drop it below 1 — say to 0.2 — and you're effectively squeezing the distribution: the already-high-probability tokens get even more weight, so outputs become more deterministic and repetitive. Temperature 0 is pure greedy decoding — always pick the single most likely token. Go above 1 and you're flattening the distribution, giving unlikely tokens more of a chance, which creates more diverse or surprising outputs, but at the cost of coherence and factual accuracy.

Top-p, or nucleus sampling, works differently. You sort all tokens by probability, high to low, and keep adding them until their cumulative probability reaches your threshold — say 0.9 or 90%. You sample only from that nucleus. The key insight is that this is dynamic: if the model is very confident about the next word — like 'Paris' after 'The capital of France is' — the nucleus might be just 2–3 tokens. If the model is uncertain, the nucleus expands to hundreds of tokens. This is more adaptive than top-k, which always uses a fixed number of candidates regardless of model confidence.

In practice I'll set both together. For a coding assistant at my last company, we ran temperature 0.1, top-p 0.95 — we wanted near-deterministic output for code correctness but a tiny bit of variance to avoid infinite loops on degenerate inputs. For a creative marketing copy tool, we used temperature 1.0 to get real variety."

**Tradeoff / production angle (1 min):**
"The key production tension is determinism vs quality. Temperature 0 sounds ideal for factual tasks, but it can cause repetition loops in long-form generation, and it makes A/B testing harder because all outputs are identical. A small temperature like 0.1 often gives most of the determinism benefits while avoiding edge cases. Also, higher temperatures increase token count and therefore cost — a temperature-1.5 response can be 30–40% longer than a temperature-0.3 response for the same prompt. In vLLM or TGI, you can configure different sampling profiles per request, so your coding endpoint and chat endpoint can use different settings from the same serving instance."

**Wrap-up (30s):**
"The bottom line: temperature reshapes the distribution, top-p prunes the candidate set. For factual/code tasks, low temperature (0–0.3). For conversational tasks, moderate temperature (0.5–0.8). For creative tasks, higher temperature (0.9–1.2) with a top-p safety net around 0.9–0.95. Happy to go deeper into how these interact with beam search or how they affect hallucination rates."

---

## Pitfalls

- **Mistake:** Saying "just set temperature to 0 for accuracy" without noting that deterministic outputs can still hallucinate if the model's top token is wrong, and that exact-zero can cause repetition loops — **Better:** Explain that temperature 0 reduces variance but doesn't eliminate hallucination; the fix for hallucination is RAG or faithfulness checking, not just low temperature.
- **Mistake:** Conflating top-p and top-k, or saying "top-p keeps the top 90% of tokens" (implying a fixed count) — **Better:** Explain that top-p is dynamic: it keeps the smallest set of tokens whose cumulative probability reaches the threshold, so the actual number of candidates varies with model confidence.
- **Mistake:** Not knowing what temperature > 1.0 does, or saying "you can't go above 1" — **Better:** Explain that temperature > 1 is valid and useful for creative tasks; it flattens the distribution, giving low-probability tokens more relative weight, increasing output diversity at the cost of coherence.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q32: Beam search, top-k, top-p — when use each?](01-032-beam-search-top-k-top-p-when-use-each.md) | Deeper dive into all decoding strategies including beam search |
| [Q45: When set temperature to 0 vs higher values?](01-045-when-set-temperature-to-0-vs-higher-values.md) | Same concept, decision-framework framing |
| [Q31: How do LLMs generate text? Autoregressive decoding process.](01-031-how-do-llms-generate-text-autoregressive-decoding-process.md) | Prerequisite — the autoregressive loop that temperature/top-p plug into |

---

## One-liner recall

> Temperature scales the softmax logits to sharpen or flatten the token distribution (0 = greedy, >1 = creative); top-p dynamically prunes the candidate set to the smallest nucleus summing to probability p — together they trade off determinism against diversity, and in production you pick low temperature for code/facts and moderate-to-high for creative or conversational tasks.
