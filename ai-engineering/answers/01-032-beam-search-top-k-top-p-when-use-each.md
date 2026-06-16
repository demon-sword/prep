# Beam search, top-k, top-p — when use each?

**Category:** 01-llm-fundamentals
**Question #:** 032
**Source section:** §1 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
This probes whether you understand decoding as a separate, tunable system — not just "the model outputs text." Interviewers expect you to reason about quality/diversity/cost tradeoffs and give concrete production configurations for specific use-cases (code generation, chatbots, creative writing).

### Trigger phrases
- "Walk me through the decoding strategies for LLMs."
- "Why would you pick top-p over top-k in production?"
- "When would you use beam search vs sampling?"
- "What are the different ways to generate text from an LLM?"

### What it tests
Whether you understand the quality-diversity-latency tradeoff space of autoregressive decoding and can prescribe the right strategy per use-case.

---

## Answer

### Concept
After each forward pass, an LLM produces a logit distribution over its vocabulary; the **decoding strategy** decides which token to select next. The three main families are: **beam search** (deterministic, multi-hypothesis), **top-k sampling** (sample from the k most probable tokens), and **top-p / nucleus sampling** (sample from the smallest set of tokens whose cumulative probability ≥ p). They span a spectrum from fully deterministic (beam) to highly stochastic (high top-p + temperature).

### Mechanism

**Beam search:**
- Maintains B parallel "beams" (hypotheses) at every timestep.
- Each beam extends by the top-B tokens from the current distribution; prunes all but the top-B sequences by cumulative log-probability.
- Final output = highest-scoring complete sequence.
- Cost: B× the memory and compute of greedy decoding; unsuitable for long sequences or large B.
- Classic use: machine translation (seq2seq with encoder-decoder like T5, MarianMT). Rarely used for open-ended generation because it produces repetitive, overconfident text ("degeneration problem").

**Top-k sampling:**
- Zeroes out all but the top-k tokens by probability, renormalizes, then samples.
- Fixed k = fixed vocabulary size at each step regardless of the shape of the distribution — if the model is very confident (peaked distribution), k=50 still allows noisy low-prob tokens; if uncertain (flat distribution), k=50 still only covers a fraction of plausible tokens.
- Decent for chatbots and summarization; less principled than top-p.

**Top-p (nucleus) sampling:**
- Sort tokens by descending probability; accumulate until cumulative prob ≥ p; sample from that dynamic set.
- The nucleus adapts to the model's confidence: peaked distribution → small nucleus (near-deterministic); flat distribution → large nucleus (more creative).
- Introduced by Holtzman et al. 2020 ("The Curious Case of Neural Text Degeneration").
- Most commonly used in production chat/creative systems. Typical value: p=0.9–0.95.

**Temperature (orthogonal modifier):**
- Scales all logits by 1/T before softmax. T<1 sharpens (more deterministic), T>1 flattens (more random). Combined with top-p/top-k.
- T=0 → argmax (greedy) regardless of top-k/top-p.

**Production configurations (2025–2026 norms):**
| Use-case | Strategy | Why |
|----------|----------|-----|
| Code generation (Copilot, Codex) | T=0.1–0.2, top-p=0.95 | Correctness > diversity; low noise |
| Customer support chatbot | T=0.7, top-p=0.95 | Coherent but not robotic |
| Creative writing | T=1.0–1.2, top-p=0.95 | Diversity desirable |
| Summarization | T=0.3, top-p=0.9 | Faithful, low hallucination |
| Machine translation | Beam B=4–5 | BLEU-optimal; seq2seq |
| Reasoning / chain-of-thought | T=0 or beam | Determinism for reproducibility |

**Speculative decoding (bonus angle):** uses a small draft model to propose k tokens greedily, then the large model verifies them in parallel — effectively beam-like quality at near-sampling speed. Used in vLLM and TensorRT-LLM for latency reduction.

### Example / Tradeoff
In vLLM, sampling parameters are set per-request via `SamplingParams(temperature=0.7, top_p=0.95, top_k=-1)` — top_k=-1 disables top-k filtering, leaving only nucleus sampling. OpenAI's Chat API exposes the same knobs (`temperature`, `top_p`; note they recommend not setting both simultaneously). For production RAG answer generation, most teams use T=0, top_p=1.0 (greedy) because faithfulness to retrieved context matters more than creative variation — setting T=0 eliminates sampling noise and makes answers reproducible for golden-set evaluation.

---

## Verbal script

**Opening (30s):**
"There are three main decoding strategies — beam search, top-k, and top-p — and the right choice depends entirely on whether you're optimizing for quality, diversity, or speed. Let me walk through each and then give you the production configs I'd actually use."

**Core explanation (2–3 min):**
"I'd start with beam search. It keeps B parallel hypotheses alive at each step, always choosing the highest cumulative log-probability path. It's great for translation or structured generation where there's a clear best answer — models like MarianMT use beam width of 4–5. But for open-ended generation it causes degeneration: repetitive, overconfident text, because it over-exploits the probability distribution. Also, B× compute makes it expensive at scale.

"Top-k sampling is simpler — you zero out everything outside the top k tokens and sample. The problem is k is fixed, which is unprincipled: when the model is very confident, even k=50 lets in noisy tokens; when the model is uncertain, k=50 misses plausible options.

"Top-p, or nucleus sampling, solves that by adapting dynamically. You accumulate tokens in descending probability order until you hit cumulative prob ≥ p — that's the nucleus — then sample from it. When the model is confident the nucleus is tiny; when uncertain it's large. This is the default for most production chat systems. OpenAI recommends top-p=0.95 for chatbot use-cases, and vLLM exposes it as a first-class parameter.

"Temperature is orthogonal: it scales logits before softmax. T=0 is greedy; T=0.2 is near-greedy for code; T=1.0+ for creative writing. I'd never set temperature and top-p both to non-default simultaneously — they interact in unintuitive ways and OpenAI explicitly warns against it."

**Tradeoff / production angle (1 min):**
"The key insight is that for RAG answer generation, I default to T=0 (greedy / top-p=1.0) because faithfulness to retrieved context is the goal — sampling variance just introduces hallucination risk. For conversational chat I use T=0.7, top-p=0.95. For creative tasks I push to T=1.0–1.2. And if latency is critical, speculative decoding with a draft model is effectively beam-like quality at sampling speed — vLLM supports it natively."

**Wrap-up (30s):**
"The decision tree is: beam search for structured seq2seq tasks with clear ground truth; top-p (nucleus) for chat and creative open-ended generation; greedy/T=0 for factual RAG pipelines where reproducibility and faithfulness matter. Happy to go deeper on speculative decoding or the interaction with temperature if useful."

---

## Pitfalls

- **Mistake:** Treating "top-p" and "temperature" as interchangeable or saying "just set temperature high for variety" — **Better:** Explain that temperature reshapes the full distribution while top-p truncates the tail; they're orthogonal controls, and high temperature without top-p truncation can produce incoherent text.
- **Mistake:** Recommending beam search for all LLM generation tasks because it "finds the best answer" — **Better:** Explain that beam search causes degeneration on open-ended generation (Holtzman et al. 2020) and is only appropriate for constrained seq2seq tasks like translation; for chat or RAG, greedy or nucleus sampling is superior.
- **Mistake:** Not knowing any concrete production values (just saying "adjust as needed") — **Better:** Cite real configs: T=0.1 for code, T=0.7 + top-p=0.95 for chat, T=0 for factual RAG; shows production experience rather than textbook knowledge.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q7: What is temperature and top-p sampling? How do they affect outputs?](01-007-what-is-temperature-and-top-p-sampling-how-do-they-affect-ou.md) | Direct prerequisite — temperature mechanics |
| [Q31: How do LLMs generate text? Autoregressive decoding process.](01-031-how-do-llms-generate-text-autoregressive-decoding-process.md) | Parent concept — the loop within which decoding strategies operate |
| [Q9: What is KV cache? How does it help in LLM inference?](01-009-what-is-kv-cache-how-does-it-help-in-llm-inference.md) | Related production angle — KV cache enables efficient multi-step decoding |

---

## One-liner recall

> Use beam search for seq2seq (translation), top-p (nucleus, p=0.95) for chat/creative, and greedy (T=0) for factual RAG — because each optimizes a different point in the quality/diversity/faithfulness tradeoff space.
