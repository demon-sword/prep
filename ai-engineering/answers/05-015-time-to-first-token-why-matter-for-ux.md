# Time to first token — why matter for UX?

**Category:** 05-evaluation-metrics
**Question #:** 015
**Source section:** §5 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
The interviewer is probing whether you understand the production latency landscape of LLM systems at a user-experience level. TTFT is the dominant UX lever in streaming GenAI products — users perceive a responsive system the moment the first token appears, even if total generation time is long. A candidate who conflates TTFT with total latency, or who can't name the architectural knobs that control it, signals they haven't shipped a real streaming LLM product.

### Trigger phrases
- "How do you reduce latency in GenAI applications?"
- "What latency metric matters most for UX in a streaming chatbot?"
- "Walk me through how you'd improve perceived responsiveness in an LLM product."
- "Why is time to first token different from total generation time?"

### What it tests
Understanding of the prefill/decode split in LLM inference and how to optimise the user-perceived responsiveness of streaming LLM applications in production.

---

## Answer

### Concept
**Time to first token (TTFT)** is the wall-clock duration from when the API request is sent to when the first output token is streamed back to the client. It is distinct from **total generation latency** (time to last token, TTLT) and **throughput** (tokens/second). TTFT governs perceived responsiveness: users tolerate long total generation times if the UI starts rendering within ~200–500 ms, but a blank screen for 2+ seconds triggers frustration and abandonment.

### Mechanism
LLM inference has two phases:

| Phase | What happens | Latency characteristic |
|-------|-------------|------------------------|
| **Prefill** | All input tokens processed in one forward pass; KV cache populated | Scales with prompt length (more tokens → longer prefill) |
| **Decode** | One token generated per forward pass; memory-bandwidth-bound | Scales with output length (number of tokens generated) |

TTFT = **network round-trip + prefill time**. The decode phase does not contribute to TTFT — it is post-first-token.

Key drivers of high TTFT:
1. **Long prompts** — each token in the prompt must be processed in the prefill pass. A 10K-token RAG context prefills 5–10× slower than a 1K prompt.
2. **Queuing / batching** — shared inference servers (vLLM, TGI) batch requests to maximise GPU utilisation; a request may wait for the current batch to finish before its prefill starts.
3. **Cold starts** — serverless deployments (Lambda, Cloud Run) can add 1–5 s for container warm-up.
4. **Model size** — a 70B model has more prefill FLOP than a 7B model for the same prompt.

**Mitigations (in order of impact):**

1. **Prompt compression** — LLMLingua, selective context, or semantic caching reduces prefill length and thus TTFT. Cutting a 4K prompt to 1.5K can halve prefill time.
2. **Streaming responses** — enable streaming in the API call so the client renders tokens as they arrive; TTFT feels faster even if TTLT is unchanged.
3. **Model tiering / speculative decoding** — route simple queries to a smaller model (GPT-4o-mini, Llama 3 8B) with faster prefill; use speculative decoding on the large model to parallelise decode.
4. **Semantic caching** — exact cache hit (GPTCache, Redis) returns the full response in <10 ms, eliminating prefill entirely.
5. **Continuous batching + priority queues** — vLLM's PagedAttention + continuous batching lets new requests interleave with in-flight decodes rather than waiting for full-batch completion, reducing queue wait.
6. **Compute-optimised infrastructure** — H100s prefill ~2× faster than A100s for identical models; TPU v5e gives high prefill throughput for long documents.

### Example / Tradeoff
At a customer-support chatbot serving 500K queries/day with an average 2.5K-token RAG context:

| Configuration | TTFT (p50) | TTFT (p95) | Total latency (p50) |
|--------------|-----------|-----------|---------------------|
| GPT-4o, no caching | 1.8 s | 4.2 s | 8.5 s |
| GPT-4o-mini, no caching | 0.7 s | 1.9 s | 4.2 s |
| GPT-4o + semantic cache (30% hit) | 0.6 s effective | 1.4 s effective | 3.1 s effective |
| GPT-4o-mini + LLMLingua (40% compression) | 0.4 s | 1.1 s | 2.8 s |

**Key tradeoff:** Reducing TTFT via model downtiering (GPT-4o → GPT-4o-mini) also reduces cost ~15× but may reduce answer quality. Validate quality regression with RAGAS faithfulness and golden-dataset accuracy before switching. Semantic caching achieves both TTFT reduction and cost savings without quality loss, but only for repeated queries.

**Streaming vs TTLT tradeoff:** Streaming does not reduce TTLT — it only improves perceived latency. For use cases where the full response must be post-processed (e.g., NLI faithfulness check, JSON parsing), you may not be able to stream, and TTFT becomes less important than TTLT.

---

## Verbal script

**Opening (30s):**
"TTFT — time to first token — is the latency metric that most directly controls perceived responsiveness in a streaming LLM product. It's the time from when I send the request to when the first output token appears on the user's screen. I think of it as the 'blank screen' metric — users tolerate long generation if they see *something* fast, but a blank screen over 500ms starts feeling broken."

**Core explanation (2–3 min):**
"The reason TTFT is a distinct metric comes from how LLM inference works. There are two phases: prefill and decode. In prefill, all input tokens are processed in one forward pass and the KV cache is populated — this phase scales with prompt length and is the main driver of TTFT. Once prefill is done, the model decodes one token per forward pass, which is memory-bandwidth-bound. So TTFT is basically: network round trip plus prefill time. The decode phase doesn't contribute to TTFT at all.

The biggest enemy of TTFT in production is a long prompt. A 10K-token RAG context with all retrieved documents takes 5–10× longer to prefill than a 1K prompt. So my first lever is prompt compression — tools like LLMLingua or aggressive context selection can cut prompts by 40–60%, cutting TTFT in half.

The second lever is streaming. If I enable token streaming on the API call, the client starts rendering as soon as the first decode token arrives. That doesn't reduce TTFT in the strict sense — prefill still happens before any token is emitted — but it makes the product feel responsive and cuts perceived latency dramatically.

The third lever is model tiering. A 7B or 8B model like GPT-4o-mini or Llama 3 8B has a much smaller prefill footprint than GPT-4 70B for the same prompt, so TTFT is 2–3× faster. The tradeoff is answer quality, which I'd validate with a golden dataset before switching.

And the fourth lever — semantic caching — is the nuclear option: if the query is a near-duplicate of something cached (GPTCache with cosine similarity ≥ 0.93), I return the full response in under 10 ms, bypassing prefill entirely."

**Tradeoff / production angle (1 min):**
"The subtle tradeoff is that reducing TTFT can conflict with post-processing requirements. If I need to run a RAGAS faithfulness check or parse the output as structured JSON before showing it to the user, I can't stream, and TTFT becomes irrelevant — what matters is TTLT. So the right metric depends on the product architecture. For chat UIs, stream and optimise TTFT. For batch pipelines or API responses that require the full output before processing, optimise TTLT instead. I'd always instrument both separately in my monitoring stack."

**Wrap-up (30s):**
"So TTFT matters because it controls the 'blank screen' moment in streaming AI products. The levers are prompt compression, streaming, model tiering, and semantic caching — in that order of implementation difficulty. I'd track TTFT separately from TTLT and total cost in production dashboards, with a p95 SLO of around 500ms–1s for a chatbot use case."

---

## Pitfalls

- **Mistake:** Treating TTFT and total latency as the same thing, saying "just stream the response" without explaining that TTFT still depends on prefill time — **Better:** Distinguish the prefill (TTFT driver) from decode (TTLT driver), explain streaming only helps perceived latency not actual TTFT, and name concrete levers like prompt compression and model tiering that actually reduce prefill time.
- **Mistake:** Recommending semantic caching as the only TTFT solution without discussing cache hit rate, TTL invalidation, or the staleness tradeoff — **Better:** Explain that semantic caching only helps for repeated/near-duplicate queries (30–40% hit rate typical), requires a similarity threshold (0.92–0.97), and needs TTL tied to knowledge-base freshness; for novel queries, you need other levers.
- **Mistake:** Ignoring the streaming-vs-post-processing conflict — saying "always stream" without noting that structured output, NLI checks, or citation validation require the full response before rendering — **Better:** Clarify that streaming is only viable when the client can render partial text; for JSON-mode or faithfulness-gated responses, optimise TTLT instead.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q11: How do you reduce latency in GenAI applications?](../answers/07-003-how-reduce-latency-in-genai-applications.md) | Broader latency framework of which TTFT is one dimension |
| [Q9: What is KV cache? How does it help in LLM inference?](../answers/01-009-what-is-kv-cache-how-does-it-help-in-llm-inference.md) | KV cache is the mechanism that prefill populates; understanding it explains TTFT |
| [Q12: Operational/business metrics: win rate, deflection rate, p95 latency?](05-012-operationalbusiness-metrics-win-rate-deflection-rate-p95-lat.md) | TTFT p95 is one of the production SLOs in the business metrics stack |

---

## One-liner recall

> TTFT = network + prefill time (not decode); reduce it via prompt compression, streaming, model tiering, and semantic caching, and monitor p95 separately from total generation latency.
