# How do LLMs generate text? Autoregressive decoding process.

**Category:** 01-llm-fundamentals
**Question #:** 031
**Source section:** §1 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
The interviewer wants to confirm you understand *how* text generation actually works under the hood — not just that "the model predicts the next token." Strong candidates explain the prefill/decode split, the token-by-token loop, the role of sampling, and why this architecture drives the cost and latency profiles you care about in production.

### Trigger phrases
- "Walk me through how an LLM actually generates text."
- "What happens mechanically when I call the OpenAI API?"
- "Why is generation slow compared to the prompt processing?"

### What it tests
Understanding of autoregressive decoding mechanics and their direct production consequences (latency, throughput, KV cache, streaming).

---

## Answer

### Concept
LLMs generate text **one token at a time in a left-to-right loop**: at each step the model takes the full sequence of tokens seen so far (prompt + all previously generated tokens), runs a forward pass through the transformer, and samples the next token from the resulting probability distribution over the vocabulary. This is called **autoregressive** (or **causal**) decoding because each output token is conditioned on all prior tokens.

### Mechanism

**Two phases — prefill and decode:**

| Phase | What happens | Characteristics |
|-------|-------------|-----------------|
| **Prefill** | All prompt tokens are processed in one parallel forward pass; the KV cache is populated for every prompt token. | Compute-bound; fast (batched matrix multiply across all positions simultaneously) |
| **Decode** | One new token is generated per forward pass; the KV cache is extended by one row each step. | Memory-bandwidth-bound; sequential; slow relative to prefill |

**The decode loop in detail:**
1. **Forward pass** — the transformer runs with causal masking: each token can attend only to itself and all preceding tokens. The final hidden state at the last position is projected to a logits vector of size `V` (vocabulary size, e.g. 128 K for Llama 3).
2. **Sampling** — a sampling strategy converts logits to a token: greedy (argmax), top-k, top-p (nucleus), or temperature-scaled. (See Q32 for detail.)
3. **Append and loop** — the sampled token is appended to the sequence, and the loop repeats until a stop token (`<|endoftext|>`, `<|eot_id|>`) or max-length is reached.
4. **KV cache** — rather than recomputing K and V matrices for all previous tokens on every decode step, they are cached. Each decode step only computes Q/K/V for the *new* token, reads cached K/V for all prior tokens, and updates the cache. Memory cost: `2 × layers × heads × d_head × seq_len × dtype_bytes` per sequence.

**Token → text:** after generation, the token IDs are decoded back to text using the tokenizer's vocabulary (e.g. tiktoken BPE for a frontier model, SentencePiece for Llama). Partial UTF-8 characters may be buffered until a full codepoint is assembled — relevant for streaming UX.

### Example / Tradeoff

**Production numbers (a 70B-class open-weight model, A100 80 GB, FP16):**
- Prefill: ~5,000 tokens/s for a 512-token prompt (compute-bound)
- Decode: ~20–30 tokens/s (memory-bandwidth-bound — KV cache reads dominate)
- TTFT (time to first token) ≈ 100–300 ms; heavily influenced by prompt length and batch size

**vLLM's PagedAttention** addresses the memory bottleneck by storing KV cache in non-contiguous "pages" (like OS virtual memory), enabling higher batch sizes and thus higher decode throughput without OOM.

**Streaming:** most production APIs (OpenAI, Anthropic) stream tokens as they are generated via SSE. This improves perceived latency (users see text appearing) even though total generation time is unchanged.

**Autoregressive cost:** generating 1,000 output tokens requires 1,000 sequential forward passes (decode steps). This is why output tokens are typically 3–4× more expensive than input tokens per API pricing — and why long generation tasks (e.g. writing a 5,000-word essay) are costly.

---

## Verbal script

**Opening (30s):**
"LLMs generate text autoregressively — one token at a time in a loop. There are actually two distinct phases: prefill, where the prompt is processed in parallel, and decode, where each new token requires its own sequential forward pass. Understanding this split explains most of the cost and latency behavior you see in production."

**Core explanation (2–3 min):**
"In the prefill phase, all prompt tokens are processed simultaneously in one big matrix multiply — it's compute-bound and fast. The output is the KV cache: stored key-value pairs for every prompt token, so we don't recompute them on every decode step.

Then decode begins. Each step: run a forward pass with causal masking (each token can only see prior tokens), project the last hidden state to a logit vector over the vocabulary — for Llama 3, that's 128K tokens. Apply your sampling strategy: temperature scaling, then maybe top-k or top-p nucleus sampling to cap the distribution. Sample a token, append it to the sequence, extend the KV cache by one row, and repeat.

Stop conditions are: the model emits a special end-of-sequence token like `<|eot_id|>`, you hit a configured stop sequence, or you hit max tokens.

On a 70B-class open-weight model running on an A100, you see prefill at roughly 5,000 tokens per second but decode dropping to 20–30 tokens per second — because decode is memory-bandwidth-bound, reading those growing KV caches on every step. That's why vLLM uses PagedAttention: non-contiguous KV cache blocks that let you pack more sequences per GPU and increase effective throughput."

**Tradeoff / production angle (1 min):**
"The autoregressive nature creates a fundamental cost asymmetry: output tokens cost 3–4× more than input tokens because each one requires a serial decode step. This drives several production decisions — prompt compression to minimize input cost, output length limits to control generation cost, and streaming (SSE) to mask the decode latency with progressive display. For very long outputs, speculative decoding (a smaller draft model proposes multiple tokens; the large model verifies in parallel) can cut wall-clock time by 2–3×."

**Wrap-up (30s):**
"So in short: prefill processes the prompt in one parallel pass and fills the KV cache; decode is a serial token-by-token loop constrained by memory bandwidth. The KV cache is what makes decode tractable, and tools like vLLM's PagedAttention are what make it scalable. Happy to go deeper on sampling strategies, speculative decoding, or the KV cache memory math."

---

## Pitfalls

- **Mistake:** Saying "the model reads the prompt and generates an answer" without distinguishing prefill from decode — **Better:** Explicitly name both phases, explain why decode is sequential and memory-bound, and connect this to why TTFT and throughput are different optimization targets.
- **Mistake:** Treating generation as a single forward pass — **Better:** Clarify that N output tokens require N decode forward passes (each adding one token), which is why output length directly drives latency and cost.
- **Mistake:** Not mentioning the KV cache when asked about generation — **Better:** Explain that without the KV cache, every decode step would recompute attention over the full growing sequence (O(n²) in time and memory), making long generation impractical; the cache is what makes it O(n) per step.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q9: What is KV cache? How does it help in LLM inference?](01-009-what-is-kv-cache-how-does-it-help-in-llm-inference.md) | KV cache is the key mechanism enabling efficient autoregressive decode |
| [Q32: Beam search, top-k, top-p — when use each?](01-032-beam-search-top-k-top-p-when-use-each.md) | Sampling strategies applied at each decode step |
| [Q7: What is temperature and top-p sampling?](01-007-what-is-temperature-and-top-p-sampling-how-do-they-affect-ou.md) | Deep dive into the token selection step within the decode loop |

---

## One-liner recall

> LLMs generate text in two phases — a parallel prefill pass that builds the KV cache, then a sequential token-by-token decode loop where each step is memory-bandwidth-bound and costs one full forward pass.
