# Section 9 — API Design & Provider Abstraction

Interview-prep answers for building Claude-style chat frontends on top of multiple LLM providers. Each question is self-contained; comparison tables appear where provider differences matter.

---

## Core

### Why does Anthropic use strict alternating turns while OpenAI allows a `tool` role?

Anthropic’s Messages API enforces a **strict user ↔ assistant alternation** in the `messages` array. Tool interaction is modeled *inside* those turns: the assistant turn contains `tool_use` content blocks, and the **next** turn must be `role: "user"` carrying matching `tool_result` blocks—not a third role. OpenAI’s Chat Completions API evolved a separate **`tool` role** (and earlier `function`) so each tool output is its own message between assistant `tool_calls` and the following assistant reply.

The design difference is mostly **schema philosophy and history**, not capability. Anthropic optimizes for a single conversational transcript where tools are typed content blocks in an otherwise normal dialogue—easier to validate (“every `tool_use` id has a `tool_result` in the next user message”) and closer to how the model was trained to interleave reasoning and actions. OpenAI’s array-of-roles model maps cleanly to older chat templates and to clients that want to grep for `role === "tool"` without parsing nested blocks.

| Aspect | Anthropic | OpenAI |
|--------|-----------|--------|
| Turn rule | Strict `user` / `assistant` alternation | Multiple roles in sequence (`system`, `user`, `assistant`, `tool`) |
| Tool call location | `tool_use` blocks inside `assistant` | `tool_calls` on `assistant` message |
| Tool output location | `tool_result` blocks inside next `user` | Dedicated `role: "tool"` message per call |
| Invalid pattern | Two `user` turns in a row | Often allowed: `assistant` → several `tool` → `assistant` |

In a multi-provider product, your **canonical message graph** should not mirror either API literally. Store assistant tool calls and tool results as first-class edges (parent message → tool call → tool result), then **compile** to Anthropic (merge results into one user turn) or OpenAI (expand into `tool` messages) at the adapter boundary. Failing to do this is a common source of 400 errors when porting tool-using agents between providers.

---

### How do you normalize message history across Anthropic, OpenAI, and Gemini formats?

Define an **internal representation (IR)**—provider-neutral message types and content blocks—and treat Anthropic, OpenAI, and Gemini as **write adapters** (IR → provider request) and **read adapters** (provider response/stream → IR). The UI, persistence, branching, and token accounting all speak IR only.

A practical IR for a chat product includes: `message_id`, `parent_id` (for branches), `role` (`system` | `user` | `assistant`), `content[]` where each block is `text` | `image` | `tool_call` | `tool_result` | `thinking` (optional), plus metadata (`created_at`, `model`, `provider`, `stop_reason`). Tool calls carry stable `call_id`, `name`, and `arguments` (JSON). Tool results carry the same `call_id`, payload, and `is_error`.

**Compilation rules** differ per provider:

| IR concept | Anthropic | OpenAI | Gemini (generateContent) |
|------------|-----------|--------|-------------------------|
| System prompt | Top-level `system` param (string or blocks) | `system` / `developer` message in array | `systemInstruction` field |
| User text + images | `user` content blocks | `user` with string or `content[]` | `user` role, `parts[]` |
| Assistant text | `assistant` blocks | `assistant` message | `model` role |
| Tool call | `tool_use` in assistant | `tool_calls` on assistant | `functionCall` in model parts |
| Tool result | `tool_result` in **next** `user` | `role: "tool"` messages | `functionResponse` in user parts |
| Multi-tool turn | One `user` with N results | N `tool` messages | Batch into one user turn |

Normalization also handles **ordering and orphans**: merge consecutive user messages where a provider forbids gaps; split one IR user message into Anthropic’s “tool results only” user turn; coalesce OpenAI’s multiple `tool` rows back into IR. Run validation before every outbound call: unmatched `call_id`, assistant tail without user follow-up for pending tools, and image blocks without supported MIME types.

Persist IR in the database; cache compiled provider payloads only ephemerally (they change when SDKs or prompt formats change). Version the IR schema (`ir_version: 2`) so migrations can rewrite history when you add features like extended thinking or cached system blocks.

---

### How do you handle provider-specific features (e.g. Anthropic extended thinking) without breaking abstraction?

Use a **capability matrix + optional extensions** pattern instead of leaking provider types through your public API. The abstraction exposes portable concepts (`sendMessage`, `stream`, `tools`, `maxOutputTokens`); provider-only behavior rides in **typed optional fields** that default to no-ops on other providers.

For extended thinking: in IR, add an optional `thinking` block on assistant messages (redacted or summarizable for UI). The Anthropic adapter maps it to `thinking` / `redacted_thinking` parameters and stream events; the OpenAI adapter might map to nothing, or to a vendor-specific reasoning model flag if you support one; Gemini might use a thinking budget field when available. The **UI layer** checks `capabilities.extendedThinking` to show a “reasoning” expander—not `if (provider === 'anthropic')`.

```text
Client request
    → CapabilityResolver (per org / per model alias)
    → IR + ExtensionBag { thinking?: { enabled, budget } }
    → ProviderAdapter.compile()
    → Provider SDK
```

Keep extensions **explicit and serializable** in stored messages so replay and audit work. When exporting a conversation to a provider that lacks a feature, **strip or summarize** unsupported blocks (e.g. collapse thinking to “[reasoning omitted]”) rather than failing the whole request. Document degradation in product copy when users pick a portable model vs a provider-enhanced model.

Avoid `#ifdef` sprawl in business logic: one `ProviderPort` interface per provider implementation, feature detection at **model registration** time (`ModelDescriptor.capabilities`), and integration tests that assert the same user story (tool loop, streaming stop, image attach) across all adapters. Provider-specific prompts (XML tool formats vs JSON schema) belong in the adapter’s **prompt compiler**, not in React components.

---

### What is the difference between `system` as a top-level field (Anthropic) vs a system message in the array (OpenAI)?

**Anthropic** treats `system` as a **separate request field**, not part of the alternating `messages` list. It can be a string or an array of content blocks (including cache breakpoints for prompt caching). The messages array is only `user` and `assistant` turns. **OpenAI** typically embeds instructions as the first message(s) with `role: "system"` or `"developer"` inside the same array you send on every turn.

| | Anthropic | OpenAI |
|---|-----------|--------|
| Placement | `system: "..."` sibling to `messages` | `messages[0]` with `role: "system"` |
| Editable per turn | Replace `system` param each request | Mutate or prepend system message |
| Alternation rules | Does not consume a turn slot | Occupies array position; affects some fine-tunes |
| Caching | `cache_control` on system blocks | Prompt caching on prefix (model-dependent) |
| Multi-segment system | Multiple blocks in `system[]` | Multiple system messages (usually merged) |

Product implications: if your app lets users edit “project instructions,” store **one system document in IR** and compile it per provider—do not store two divergent truths. For **token counting**, Anthropic often bills system separately from messages; OpenAI counts system messages as input tokens in the array—your cost estimator must include system in both cases but via different code paths.

When re-sending history, OpenAI may **re-include** system on every call unless you use APIs that support storing instructions server-side; Anthropic re-attaches the same `system` field while `messages` grow. For branching conversations, pin the **system snapshot** at branch creation so regenerating an old branch does not pick up today’s global system prompt by accident.

---

## Deep

### How do you build a provider-agnostic streaming adapter — same interface for SSE and WebSocket backends?

Expose one **async iterable (or Observable) of normalized stream events** to the frontend; hide wire format behind `StreamTransport` + `StreamDecoder` per provider.

**Normalized event types** (stable contract):

| Event | Payload | UI use |
|-------|---------|--------|
| `message_start` | `message_id`, `model` | Placeholder bubble |
| `content_delta` | `block_index`, `text` | Append tokens |
| `tool_call_delta` | `call_id`, `name`, `arguments_fragment` | Build tool pill |
| `thinking_delta` | `text` (if capability) | Reasoning panel |
| `content_block_stop` | `block_index`, `type` | Finalize block |
| `message_delta` | `usage_partial` | Token meter |
| `message_stop` | `stop_reason`, `usage` | Enable send, save |
| `error` | `code`, `retryable` | Toast / retry |

**SSE path:** browser `EventSource` or `fetch` + `ReadableStream` parser; decoders handle `data: {...}\n\n`, Anthropic’s `event: content_block_delta`, and OpenAI’s `choices[0].delta`. **WebSocket path:** same decoders after framing (JSON lines, or binary envelope with `type`). The adapter reads bytes → frames → provider events → **normalize** → enqueue on a shared async queue with backpressure (`highWaterMark`); if the UI is slow, drop/coalesce `content_delta` to 60fps batches.

```text
Provider wire (SSE | WebSocket)
    → Transport (connect, headers, auth, heartbeat)
    → FrameParser
    → ProviderEventDecoder
    → NormalizedStreamEvent*
    → Client chat reducer
```

Implement **one cancellation contract**: `AbortSignal` aborts fetch, closes WebSocket, and sends provider-specific cancel if supported. Reconnection policy lives in transport (idempotent `message_start` or resume token if the provider offers it—not assumed portable). Integration tests feed **fixture byte streams** per provider and assert identical normalized event sequences for the same golden completion.

---

### How do you handle model versioning — what happens when `claude-sonnet-4` is deprecated mid-product?

Never expose raw provider model IDs as your only product identifier. Introduce **model aliases** (`smart`, `fast`, `reasoning`) mapped through configuration to `provider + model_id + min/max tokens + capabilities`. Store the **resolved `model_id` on each message** at write time for reproducibility, billing, and support.

When `claude-sonnet-4` is announced deprecated: (1) add the replacement ID to the alias map with a **cutover date**; (2) run shadow traffic or A/B on new conversations only; (3) keep serving old threads with the pinned ID until the hard sunset, or offer “continue on legacy” vs “upgrade thread” (upgrade may change behavior—disclose in UI); (4) update **token pricing tables** and capability flags in the same config deploy.

| Layer | Responsibility |
|-------|----------------|
| Product alias | What user selects in UI |
| Config service | `alias → [{ provider, model_id, weight, until }]` |
| Conversation metadata | `pinned_model` per thread or per branch |
| Message metadata | `model_id` actually used for that completion |
| Deprecation job | Warn, block new threads, migrate defaults |

Breaking changes (context window size, tool schema, vision limits) require **capability checks** before send—not just string replacement. Feature flags can route `% of traffic` to the new model. Maintain a **compatibility matrix** in docs and in code so support knows “Team plan alias `smart` after 2026-06-01 = claude-sonnet-4-5.” Automated alerts when provider APIs return `model_not_found` trigger paging and automatic alias failover only if the substitute is marked equivalent.

---

### How do you implement automatic model fallback if the primary model returns a 529 overloaded error?

Treat **529 / 503 / explicit `overloaded`** as **transient provider capacity errors**, distinct from 429 rate limits (your quota) and 400 validation failures. A small **routing policy engine** in the API gateway or inference BFF executes:

1. **Retry primary** with full jitter exponential backoff (e.g. 250ms → 2s, max 2–3 attempts) if the request is idempotent or you have not yet streamed bytes to the client.
2. On exhaustion, **fallback chain** from config: same provider different region/model → cross-provider equivalent alias (only if capabilities match: tools, vision, context length).
3. **Circuit breaker** per `(provider, model_id)`; when open, skip straight to fallback for N minutes.
4. **Stream-aware behavior**: if failure happens before `message_start`, retry/fallback is invisible; if mid-stream, surface “interrupted—retry?” and do not silently stitch two models in one assistant message without marking metadata.

| Error class | Typical action |
|-------------|----------------|
| 529 overloaded | Backoff → fallback model |
| 429 rate limit | Queue, slower retry, show “busy” |
| 401 / 403 | No fallback; fix credentials |
| 400 invalid_request | No fallback; fix adapter bug |
| Timeout | Retry once, then fallback |

Log `primary_model`, `fallback_model`, `latency`, `attempt` for cost and quality review. **Sticky quality**: some products prefer failing visibly over silently switching to a weaker model—make fallback configurable per tier. Guardrails: fallback model must support the same **tool definitions** and max output; truncate context if the fallback window is smaller (explicit truncation policy, never silent chop of the latest user message). Charge accounting uses the model that actually served the request.

---

### How do you estimate cost before sending a request — token counting per provider?

Pre-send estimation drives **input budget warnings**, org spend caps, and “~$0.02 this message” UI. Split **input tokens** (history + system + tools + attachments) and **expected output tokens** (user-configured `max_tokens` or historical p90 for similar prompts).

| Provider | Input counting approach | Caveats |
|----------|-------------------------|---------|
| Anthropic | `messages.count_tokens` API or official tokenizer | Images billed separately; cache read/write tokens |
| OpenAI | `tiktoken` for text; API `usage` for ground truth | `o*` / reasoning models differ; tools add schema tokens |
| Gemini | `countTokens` API | Multimodal parts need per-modality rules |

**Pipeline:** (1) serialize IR to the **same compiled shape** the adapter will send (compilation affects tokens); (2) run provider counter or local tokenizer; (3) add tool-definition overhead (JSON schema size is often underestimated); (4) add image tokens from resolution tiers per provider docs; (5) multiply by **price table** keyed by `model_id` including cached-input discounts.

Output estimate is inherently uncertain—use `min(max_tokens, user_slider)` for upper bound and show a range (“0.01–0.08”) or single number with disclaimer. **Do not block send** on exact equality with provider billing; block only on hard org limits (`projected_input + max_output > remaining_quota`).

Cache Anthropic/OpenAI counts for unchanged prefixes (hash of system + messages up to last assistant) to keep the input box snappy. Re-count on every keystroke is expensive—debounce 300ms and diff against previous hash. After the real completion, reconcile with **`usage` from the response** and store actuals for analytics; tune heuristics when estimate/error ratio drifts. For multi-provider products, centralize **PricingService** (model_id → $/1M input/output, cache rates) so finance can update prices without shipping a mobile app release.

---

## Quick reference — adapter layer checklist

| Concern | Pattern |
|---------|---------|
| Message shape | Internal IR + compile per provider |
| Tools | Graph of call → result; compile to blocks or `tool` role |
| System prompt | IR `system` document; map to field vs message |
| Streaming | Normalized events; SSE and WS share decoder output |
| Models | Product aliases + per-message `model_id` pin |
| Outages | 529 backoff + circuit breaker + capability-matched fallback |
| Cost | Pre-count compiled payload; post-hoc `usage` reconciliation |
