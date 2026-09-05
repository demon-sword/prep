# Speculative decoding — speed up inference?

**Category:** 04-fine-tuning-training
**Question #:** 010
**Source section:** §4 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
Interviewers want to know whether you understand *why* LLM decode is slow (memory-bandwidth-bound, one-token-at-a-time) and whether you know advanced inference optimization techniques beyond "just use quantization." Speculative decoding is a favourite because it exploits architectural insight (the verify pass is cheap) rather than raw hardware.

### Trigger phrases
- "How do you speed up LLM inference beyond quantization?"
- "Speculative decoding — how does it work?"
- "How would you reduce time-to-first-token / decode latency at scale?"
- "Walk me through how vLLM achieves high throughput."

### What it tests
Understanding of the memory-bandwidth bottleneck in autoregressive decode and the ability to trade compute for reduced wall-clock latency through draft-verify speculation.

---

## Answer

### Concept
Speculative decoding speeds up autoregressive LLM inference by using a small, cheap **draft model** to generate multiple candidate tokens in parallel, then having the large **target model** verify all of them in a *single forward pass*. Accepted tokens are kept; the first rejected token triggers a rollback. Because the target model's forward pass is nearly constant-cost regardless of how many tokens it evaluates in parallel (it is memory-bandwidth-bound, not compute-bound during decode), this dramatically increases effective throughput and reduces wall-clock latency without changing model outputs.

### Mechanism

**Why autoregressive decode is slow:**
- Each decode step loads the full model weights from HBM into the compute units — for a 70B model at BF16 that is ~140 GB per step.
- Arithmetic intensity ≈ 2 FLOPs/byte during decode (vs. 156 FLOPs/byte theoretical peak on A100): the GPU sits mostly idle waiting for memory transfers, not computing.
- One token per forward pass → O(N) sequential steps for N output tokens.

**Speculative decoding algorithm:**

```
1. Draft:  small model M_q (e.g. 7B) generates K draft tokens
           autoregressively (fast — K sequential M_q passes).
2. Verify: target model M_p (e.g. 70B) runs ONE forward pass over
           all K draft tokens in parallel (token-parallel batch).
3. Accept: compare draft token distribution q(x) vs target p(x).
           - Accept token i with probability min(1, p(x_i)/q(x_i)).
           - On first rejection: sample a corrected token from
             p(x) - q(x) (residual distribution).
4. Result: 1–K+1 tokens produced per M_p forward pass.
```

**Key properties:**
- **Lossless:** mathematically equivalent to sampling from the target model — no quality degradation.
- **Throughput gain:** If acceptance rate α ≈ 0.7 and K = 4, expected tokens per M_p pass ≈ 1 + 4·0.7 = 3.8×. Real-world gains: 2–4× on coding/structured tasks with aligned draft/target distributions.
- **Tradeoff:** Works best when draft and target agree often (aligned distribution → high α). Domain mismatch or creative/diverse sampling degrades α and may produce negative speedup (extra M_q overhead).

**Draft model choices:**
| Draft strategy | Examples | Notes |
|---|---|---|
| Dedicated small model | Gemma 2B drafts Gemma 9B | Same family → high α |
| Self-drafting (Medusa) | Adds parallel "heads" to target | No separate model; slightly lower α |
| n-gram / retrieval | Prompt Cache draft | Works for repetitive outputs (code, boilerplate) |

### Example / Tradeoff

**Production usage:**
- **vLLM** supports speculative decoding natively (`--speculative-model`, `--num-speculative-tokens`): using a small open-weight model (7–8B class) as draft for a 70B-class open-weight model yields ~2.8× throughput improvement on HumanEval code tasks.
- **Google's 2023 paper** (Leviathan et al.) demonstrated 2–3× wall-clock speedup on Chinchilla, lossless.
- **Medusa** (Cai et al. 2024) adds 4–5 parallel heads to the target model itself, eliminating the need for a draft model; effective for serving a single model family.

**When speculative decoding helps vs. hurts:**
| Scenario | Α (acceptance rate) | Recommendation |
|---|---|---|
| Code generation (structured, predictable) | 0.75–0.85 | Strong use case |
| Summarisation (moderate diversity) | 0.60–0.70 | Moderate gain |
| Creative / high-temperature chat | 0.30–0.50 | Marginal — may hurt |
| Short outputs (<20 tokens) | N/A | Overhead dominates |

**Cost note:** The draft model M_q adds VRAM and compute. Typical budget: M_q is ≈10% of M_p parameters (e.g. 7B draft for 70B target). If serving at low concurrency, prefer quantization (GPTQ/AWQ) over speculative decoding; at high concurrency and long outputs, speculative decoding wins.

---

## Verbal script

**Opening (30s):**
"I'd frame speculative decoding around why autoregressive decode is slow in the first place. Each token generation requires a full weight load from GPU HBM — it's memory-bandwidth-bound, not compute-bound. So the GPU is mostly idle waiting for data, and we generate one token per pass. Speculative decoding exploits that the *verify* pass is almost free relative to the memory transfer cost."

**Core explanation (2–3 min):**
"The algorithm has two phases. First, a small draft model — say a small open-weight model (7–8B class) — generates K candidate tokens autoregressively; that's fast because the model is tiny. Then the large target model — say a 70B-class open-weight model — runs a single forward pass over all K tokens in parallel. Because a forward pass that processes K tokens costs roughly the same memory bandwidth as processing 1 token at peak decode batch size 1, we get K evaluations almost for free.

We accept draft token i with probability min(1, p_target / p_draft). If the draft was right, we keep it; if it was wrong, we sample a corrected token from the residual distribution and throw away everything after. The result is mathematically identical to sampling directly from the target model — it's lossless.

The efficiency gain scales with the acceptance rate α. For coding tasks where draft and target strongly agree, α ≈ 0.75–0.85 and we get 2.8–3.5× throughput. For creative high-temperature outputs where distributions diverge, α drops to 0.3–0.5 and the overhead of running the draft model can actually hurt."

**Tradeoff / production angle (1 min):**
"In production with vLLM, you pass `--speculative-model llama3-8b` and `--num-speculative-tokens 5`. The main gotcha is memory: the draft model lives in VRAM alongside the target, so you need to size your server accordingly. For a 70B target at BF16 (140 GB), adding an 8B draft (16 GB) requires at least 2 A100s just for weights, before KV cache. Alternatives like Medusa add parallel prediction heads to the target itself — no extra model — which is cleaner operationally. n-gram drafting works without any draft model for highly repetitive outputs like boilerplate code."

**Wrap-up (30s):**
"So the punchline is: speculative decoding converts a sequential memory-bandwidth bottleneck into a parallel verification problem, giving 2–4× latency improvement on structured tasks with no quality loss. It's most powerful when draft and target are from the same model family. Happy to go deeper on Medusa, continuous batching interactions, or how speculative decoding interacts with PagedAttention."

---

## Pitfalls

- **Mistake:** Describing speculative decoding as "approximate" or saying it sacrifices quality — **Better:** It is provably lossless — the acceptance criterion (min(1, p/q)) ensures the marginal token distribution is exactly the target model's distribution.
- **Mistake:** Saying "just use a smaller model for all requests" instead of discussing the draft-verify architecture — **Better:** Speculative decoding keeps the target model in the loop for quality; the draft just proposes, the target decides, so you get small-model speed with large-model quality.
- **Mistake:** Claiming speculative decoding always gives a speedup regardless of task — **Better:** On high-temperature or highly diverse outputs, the acceptance rate drops and the draft overhead may exceed the gain; you should profile acceptance rate per workload and fall back to standard decode if α < ~0.5.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q34: Why is LLM inference memory-bounded?](01-034-why-is-llm-inference-memory-bounded.md) | Root cause that speculative decoding exploits |
| [Q9: What is KV cache? How does it help in LLM inference?](01-009-what-is-kv-cache-how-does-it-help-in-llm-inference.md) | Prerequisite — KV cache is the baseline inference optimization |
| [Q12: Quantization — tradeoffs between size, speed, accuracy?](04-012-quantization-tradeoffs-between-size-speed-accuracy.md) | Complementary inference optimization; choose based on concurrency and output length |

---

## One-liner recall

> Speculative decoding uses a cheap draft model to propose K tokens, then verifies all K in one parallel target-model pass — losslessly achieving 2–4× throughput on structured tasks by converting sequential memory-bandwidth trips into a single batch verify.
