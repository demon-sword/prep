# Section 7 — Offline, Resilience & Error Handling

Interview-prep answers for Claude-style AI chat frontends. Each question is self-contained; together they describe a coherent resilience layer.

---

## Core

### What do you show if the SSE stream disconnects at token 200 of 800?

Keep the **250 tokens already rendered** on screen — never wipe the partial assistant message. Append a lightweight **inline status** on that message: e.g. “Connection interrupted” with actions **Retry**, **Continue** (if resume is supported), and **Dismiss**. Visually distinguish *incomplete* from *complete*: a subtle left border, pulsing dot, or “still generating” affordance that stops animating on disconnect.

Do **not** block the composer unless the last turn is still logically “in flight” on the server. If the user can send another message, allow it, but show a banner that the previous reply may still be finishing server-side. On retry, default to **resume** when the backend exposes `stream_id` + `offset`; otherwise **regenerate from the same user turn** with an idempotency key so you do not double-charge or duplicate rows.

Persist client state immediately: `message_id`, `accumulated_text`, `token_count` or last `event_id`, `status: interrupted`. That makes refresh-safe UX and powers “Continue” without guessing. If the product policy is “all or nothing,” mark the DB row `partial: true` and offer “Regenerate” instead of presenting a truncated answer as final — but still show the partial text so the user is not staring at a blank bubble.

---

### How do you queue a user message sent while offline and replay it on reconnect?

Treat outbound sends as **durable jobs** in an outbox, not fire-and-forget fetches. On send while offline: (1) optimistically append the user message to local state with `client_message_id` (UUID), `status: pending`; (2) enqueue `{ client_message_id, conversation_id, payload, created_at, retry_count }` in **IndexedDB** (survives refresh) with a memory mirror for the current session; (3) disable only actions that require live inference (e.g. “Stop”) until online.

On `online` / `visibilitychange` / successful health check: drain the outbox **FIFO per conversation** (parallel across conversations is fine). Each replay uses `Idempotency-Key: client_message_id` so the API returns the existing assistant message if the first attempt actually succeeded. Update UI: `pending → sending → streaming | failed`. Failed items stay in the outbox with error copy and **Retry** / **Discard**; cap retries and surface a dead-letter state after N attempts.

Conflict rules: if the user edited the conversation while offline, re-validate `conversation_revision` or `parent_message_id` before replay — stale jobs should prompt “Send anyway?” or auto-attach to the latest leaf. For multi-tab, use `BroadcastChannel` or `storage` events so one tab’s drain does not duplicate sends; leader election or a single “sync worker” tab is enough at scale.

---

### How do you distinguish a rate-limit error from a model error from a network error?

Use a **single error taxonomy** at the HTTP + application layer, then map to user-facing copy and retry policy.

| Signal | Rate limit | Model / provider | Network |
|--------|------------|------------------|---------|
| HTTP | `429`, sometimes `503` with `Retry-After` | `400`, `422`, `500`, `502`, provider `529` overloaded | No response, `502`/`504`, browser `TypeError`, SSE `error` without JSON body |
| Headers | `Retry-After`, `X-RateLimit-Remaining`, `X-RateLimit-Reset` | Provider `request-id`, error `type` in JSON (`invalid_request_error`, `overloaded`) | — |
| Body | `error: rate_limit_exceeded`, `limit`, `reset_at` | Structured `message`, `param`, `code` | Often empty or HTML from proxy |

Normalize in a client `parseApiError(response, event)` → `{ category, retryable, retryAfterMs, requestId, raw }`. **Rate limit**: retryable after delay; never auto-retry in a tight loop. **Model**: usually not retryable for the same payload (fix input); retry only for `529`/overload with backoff. **Network**: retryable with backoff; distinguish “failed to connect” (offline) from “stream reset mid-flight” (resume path).

SSE adds nuance: a clean `event: error` with JSON is model/rate-limit; an abrupt TCP close without terminal event is **network/interrupted stream**. Log `category` + `request_id` to analytics; never show raw provider stacks in the UI.

---

### How do you implement exponential backoff on the SSE reconnect?

Reconnect only for **retryable** disconnects (network, `502`/`504`, optional `529`), not for `401`/`403`/`400`. Track `attempt` per `stream_id` (or per `generation_job_id`), capped (e.g. 5–8 attempts). Delay: `baseMs * 2^attempt + jitter`, with jitter uniform in `[0, 0.3 * delay]` to avoid thundering herd; honor `Retry-After` when present (use `max(computed, retryAfter)`).

Flow: on `EventSource` `error` or fetch stream abort → set message status `reconnecting` → `scheduleReconnect(attempt + 1)`. **Full jitter** variant: pick random delay in `[0, cap]` for large fleets. Reset `attempt` to 0 after any successful `event: message_start` or terminal `event: done`. Use **AbortController** so a user “Stop” or navigation cancels pending timers.

Pass resume context on reconnect: `Last-Event-ID` header or query `?cursor=<last_event_id>` if the server supports it; otherwise backoff applies to **starting a new stream** bound to the same `generation_id`. Expose attempt in devtools; in UI show “Reconnecting (3/5)…” not raw milliseconds. Combine with **circuit breaker**: if the health endpoint fails for 30s, stop reconnect loops and switch to offline/degraded mode.

---

## Deep

### How do you implement a "resume stream" — continue generation from where it dropped?

Resume needs a **server-side generation lease**, not only client hope. When streaming starts, return `generation_id` (and optionally `stream_id`) in the first SSE event or response headers. The model runtime checkpoints incrementally: append deltas to a buffer (Redis/DB) keyed by `generation_id`, with monotonic `event_id` or byte `offset`. Client stores `last_event_id` from each SSE `id:` field or explicit `event: chunk` payload.

On disconnect, client calls `GET /v1/generations/{id}/stream?after={last_event_id}` or `POST .../resume` with the same idempotency key. Server reads from checkpoint and **replays** already-produced tokens (fast) then continues inference if the worker is still alive; if the worker died, either resume from last KV checkpoint (provider permitting) or return `409` with `resume_unavailable` and fall back to regenerate. Anthropic/OpenAI often cannot truly continue arbitrary mid-generation token streams — product honesty: “resume” may mean **replay cached output + complete from truncated context** via a server-side prompt that includes partial assistant text and asks to continue, which is not bitwise-identical but is good UX.

Contract sketch: events include `id`, `generation_id`, `done: false`; terminal `event: done` seals the generation. Idempotent resume: duplicate resume requests attach to the same subscriber fan-out or return the same chunk sequence. Cap resume window (e.g. 15 minutes) then force regenerate. Security: resume requires same session/auth as the original stream.

---

### How do you handle a partial message that was persisted to the DB mid-stream before disconnect?

Split **persistence** from **presentation**. While streaming, upsert an assistant row early: `id`, `conversation_id`, `role: assistant`, `content: ''`, `status: streaming`, `generation_id`. Append text on a debounced schedule (e.g. every 300–500ms or every N tokens) or on each chunk server-side — tradeoff: more DB writes vs fresher recovery.

On disconnect: set `status: interrupted` (or keep `streaming` until TTL if resume is likely). **Do not** mark `status: complete` without a terminal `done` event. Client merges DB fetch on reload: if `interrupted`, show partial body + recovery actions. If resume succeeds, flip `status: complete` and set `content` to final canonical text (overwrite duplicates idempotently by `generation_id`).

Edge cases: (1) **Duplicate partials** — use `generation_id` unique constraint, one row per generation. (2) **User deletes message while streaming** — tombstone wins; cancel server job. (3) **Branching** — partial belongs to a specific `parent_message_id`; resume must not attach to wrong branch. (4) **Billing** — charge on completed tokens or provider usage record, not on partial row save. For search/indexing, exclude `interrupted` from embeddings until complete or explicitly marked abandoned.

---

### How do you show a degraded-mode UI when the inference cluster is slow (p99 > 10s)?

Treat slowness as a **first-class mode**, not a spinner that never ends. Signals: client-side TTFB > 3s, server `X-Queue-Depth`, synthetic health `p99_latency_ms`, or explicit `503`/`529` with `degraded: true`. UI layers: (1) **Expectation** — replace generic “Thinking…” with “High demand — responses may take up to 30s.” (2) **Progress** — staged status from SSE (`queued`, `routing`, `tokens`) or indeterminate progress with elapsed time. (3) **Escape hatches** — “Cancel”, “Try faster model” (haiku/mini), “Notify me when done” (email/push via job id).

System behavior: enable **request shedding** at the gateway (queue cap), route to fallback model, or return `Retry-After`. Client-side **adaptive timeout**: after 10s, offer continue waiting vs switch model vs draft-only mode (compose without inference). Avoid alarm red banners; use neutral tone and amber only if user-initiated actions fail. Cache **recent** successful health in `sessionStorage` to pre-warm copy: “We’re experiencing slower responses” on next send without waiting 10s again.

Optional: degrade features — disable image gen, MCP tools, or long context when `degraded` flag is set. Metrics: track abandonment rate vs degraded banner shown to tune thresholds.

---

### What is your retry strategy for a failed MCP tool call — retry immediately, after delay, or ask user?

Default: **do not** blindly retry in the agent loop; classify the failure first.

| Failure type | Strategy |
|--------------|----------|
| Transient network / `502` / timeout to MCP host | 1–2 automatic retries with short exponential backoff (e.g. 500ms, 2s), same tool + same args if idempotent |
| Rate limit / `429` on tool server | Backoff per `Retry-After`; surface “Tool busy, retrying…” |
| Auth / `401` / `403` | No retry; prompt user to reconnect integration |
| Validation / `400` / schema mismatch | No retry; show tool error to user/model for corrected args |
| Unknown / `500` from tool | **Ask user** after one safe retry: “Jira failed — Retry / Skip / Edit args” |

Idempotency: pass `tool_call_id` to MCP; for mutating tools (create ticket, charge card), require **explicit user confirm** on retry or use idempotency keys on the tool side. In the UI, show tool rows as `running → failed` with expandable stderr; “Retry” button sends a new `tool_call` with `retry_of: id` so audit logs stay clear. Agent policy: cap total automatic tool retries per turn (e.g. 3) to prevent runaway loops; then halt with a summary message.

Long-running tools: heartbeat SSE + cancel; retry only if the server reports `status: unknown` (job may still be running) — use **poll job status** before re-executing.

---

### How do you surface rate limit information (e.g. requests remaining) to the user without alarming them?

Ingest limits from headers on **every** successful API response: `X-RateLimit-Limit`, `Remaining`, `Reset` (or OAuth-style `RateLimit-*`). Store in a small client quota store keyed by `scope` (user, org, model tier). Display in **low-salience** chrome: settings footer, account menu, or a slim usage pill — not a modal on every send.

Copy rules: green/neutral when remaining > 20%; subtle text when 10–20% (“Daily messages: 8 left”); only when < 5% or after a soft `429` use inline composer hint: “You’re nearing today’s limit.” After hard limit: disable send with clear reset time in local timezone (“Resets today at 6:00 PM IST”) and one upgrade/help link — no red error chrome unless they actually hit the wall.

Avoid countdown timers that tick every second (anxiety). Prefer **bucket reset time** over live RPM. For team plans, show org pool separately from personal. Never expose raw header names; map to product language (“messages”, “files”, “priority requests”). Optional: progressive disclosure — hover “?” on usage pill for breakdown by feature. Post-limit, preserve read/history access; only block new inference.

---

## Quick reference — policies at a glance

| Scenario | User sees | Retry | Persist |
|----------|-----------|-------|---------|
| SSE drop mid-stream | Partial text + Continue/Retry | Backoff + resume if available | `interrupted` assistant row |
| Offline send | Optimistic user bubble + pending | Outbox on reconnect | IndexedDB outbox |
| 429 | Soft limit copy / reset time | After `Retry-After` | — |
| Model 400 | Actionable error, no spin | Fix input | — |
| MCP tool fail | Tool row failed + actions | 1–2 if idempotent, else ask | Audit `tool_call_id` |
| Slow cluster (p99 > 10s) | Degraded banner + staged status | Fallback model / queue | — |
