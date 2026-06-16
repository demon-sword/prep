# How do stop sequences work?

**Category:** 01-llm-fundamentals
**Question #:** 035
**Source section:** §1 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
Interviewers probe whether you understand the token-generation loop at a mechanical level — not just API surface knowledge. Stop sequences are a small but operationally critical control knob: getting them wrong causes truncated responses, runaway generation, or wasted tokens. This question also surfaces practical API fluency (did you actually build with these models, or just read about them?).

### Trigger phrases
- "How does the model know when to stop generating?"
- "How do you prevent a model from generating extra tokens after the answer?"
- "What's the difference between a stop sequence and `max_tokens`?"

### What it tests
Mechanical understanding of the autoregressive decode loop and practical ability to control generation boundaries in production.

---

## Answer

### Concept
Stop sequences are one or more strings that, when produced by the model during decoding, cause generation to halt immediately — the matching tokens are typically excluded from the returned output. They give the caller explicit control over *when* the model stops, separate from the token-budget control of `max_tokens`.

### Mechanism
During autoregressive decoding, at each step the model samples or greedily selects the next token. After appending that token to the buffer, the inference engine checks whether the current output suffix matches any stop sequence string. If it matches, generation terminates. The engine does this check at the **string level** (after detokenizing), not at the token level — because a stop sequence like `"\n\n"` may span multiple tokens.

Key behaviors:
- **Multiple stop sequences** — you can pass a list; generation halts at the first match (OpenAI: up to 4; Anthropic: array).
- **Stop tokens vs stop strings** — some engines expose a lower-level `stop_token_ids` list; the string form is more portable across tokenizers.
- **Inclusive vs exclusive** — most APIs exclude the stop sequence from the returned text (OpenAI, Anthropic). The `finish_reason` field (`"stop"` vs `"length"`) tells you which termination path fired.
- **EOS token** — the model also has a built-in end-of-sequence token (e.g., `<|endoftext|>` for GPT, `<|eot_id|>` for Llama 3). Stop sequences are caller-defined overrides on top of this.
- **Streaming** — in streaming mode the engine buffers the last `max(len(stop_seq))` bytes before emitting, so it can withhold a match that's still arriving mid-token.

### Example / Tradeoff
**Function-call extraction:** When prompting a model to produce JSON inside `<tool_call>...</tool_call>` XML tags, you'd set `stop=["</tool_call>"]`. This prevents the model from continuing to generate prose after the JSON ends, cuts token cost, and makes parsing deterministic.

**Code generation (Copilot-style):** GitHub Copilot uses stop sequences like `"\n\n\n"` or the next function definition marker to avoid generating multiple functions when only one completion is wanted.

**Tradeoff:** Stop sequences assume the model will *actually produce* the sentinel string. If the model is inconsistent (e.g., sometimes uses `</tool>` instead of `</tool_call>`), generation runs to `max_tokens`. Robust systems combine stop sequences with a `max_tokens` safety cap and parse-validate the output regardless.

---

## Verbal script

**Opening (30s):**
"Stop sequences are a generation control mechanism — they let you tell the model 'halt as soon as you produce this string.' I think of them as a complement to `max_tokens`: max_tokens is a hard token budget, while stop sequences are semantic termination conditions the caller defines. Let me walk through how they work mechanically."

**Core explanation (2–3 min):**
"During autoregressive decoding, the model generates one token at a time. After each token, the inference engine detokenizes the current output buffer and checks whether the end of that buffer matches any stop sequence you specified. If yes, it stops — the stop sequence itself is usually excluded from the returned text.

A few nuances matter in practice. First, the check happens at the string level, not the token level, because a sequence like double newline spans two tokens. Second, most APIs let you pass multiple stop sequences — the OpenAI API takes up to four. Third, the `finish_reason` field in the response tells you why generation stopped: `'stop'` means a stop sequence or EOS fired; `'length'` means `max_tokens` was hit. You should always inspect this in production, because a truncated response due to `'length'` often means your prompt is too long or your token cap is too tight.

In streaming mode there's a subtle nuance: the engine has to buffer the last few bytes before emitting them, since a partial stop sequence may still be arriving. vLLM and TGI both implement this correctly, but it's something to be aware of when building low-latency streaming endpoints."

**Tradeoff / production angle (1 min):**
"The main failure mode is relying solely on stop sequences when the model is inconsistent about producing the sentinel. If you're doing structured output extraction — say, JSON inside XML tags — and the model occasionally uses a slightly different closing tag, generation runs to `max_tokens` and your parser gets garbage. The robust pattern is: stop sequences for the happy path, `max_tokens` as a safety net, and defensive parsing that handles truncation. I also always log `finish_reason` as a production metric — a spike in `'length'` finishes is often the first signal that something upstream changed."

**Wrap-up (30s):**
"So stop sequences are a simple but important primitive: they give you semantic control over where generation ends, reduce wasted tokens, and make output parsing more predictable. The key is pairing them with `max_tokens` and always checking `finish_reason` in production. Happy to go deeper on structured output patterns or streaming behavior."

---

## Pitfalls

- **Mistake:** Treating stop sequences and `max_tokens` as equivalent controls — **Better:** Explain they serve different purposes: `max_tokens` is a hard budget cap; stop sequences are semantic terminators. A model that never produces the stop string will run to `max_tokens`, so both must be set.
- **Mistake:** Assuming the stop sequence is included in the returned output — **Better:** State clearly that most APIs (OpenAI, Anthropic) exclude the matched stop sequence from the response, and always parse accordingly; explain the `finish_reason` field to distinguish stop vs length termination.
- **Mistake:** Not checking `finish_reason` in production and silently accepting truncated outputs — **Better:** Log `finish_reason` as a metric; a `'length'` result means downstream parsing received an incomplete response and the token budget or prompt needs adjustment.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q31: How do LLMs generate text? Autoregressive decoding process.](01-031-how-do-llms-generate-text-autoregressive-decoding-process.md) | Prerequisite — stop sequences are a control layer on top of the decode loop |
| [Q32: Beam search, top-k, top-p — when use each?](01-032-beam-search-top-k-top-p-when-use-each.md) | Same layer — decoding strategies that interact with stop sequences |
| [Q7: What is temperature and top-p sampling?](01-007-what-is-temperature-and-top-p-sampling-how-do-they-affect-ou.md) | Related sampling controls at the same API surface |

---

## One-liner recall

> Stop sequences are caller-defined strings that halt autoregressive generation the moment they appear in the output buffer (string-level check, exclusive of the match); pair with `max_tokens` as a safety net and always inspect `finish_reason` in production.
