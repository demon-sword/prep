# Section 3 — MCP & Tool Use UI (Interview Answers)

Answers for Claude-style AI chat frontends: framing, implementation, tradeoffs, Anthropic API specifics, and security.

---

## Core

### How do you render a tool call pill — loading, success, and error states?

**Framing:** The pill is the user’s mental model for “Claude did something outside the chat box.” It must be scannable in a fast token stream, stateful without stealing focus from the assistant reply, and faithful to what actually happened on the server (not just what the model *said* it did).

**Approach:** Treat each `tool_use` block as a first-class UI entity keyed by `tool_use_id` (from the streamed assistant message). On first `tool_use` delta, mount a pill in **loading**: tool display name, optional icon for the MCP server, truncated args (PII-redacted), and an indeterminate progress indicator. Args can stream in; debounce re-layout so the pill doesn’t resize every token. When your backend finishes the MCP round-trip and you have a `tool_result`, transition to **success**: checkmark, duration, expandable JSON/text result (syntax-highlighted, max height + scroll). On MCP/HTTP failure, validation error, or `is_error: true` in the result block, show **error**: distinct color, human-readable message, “Retry” and “Details” (stack trace only in dev). Persist final state in the message store so scroll-back and reload match history.

**Tradeoffs:** Inline pills vs a collapsible “Tools used (3)” summary — inline is clearer for one-off actions; summary scales for agentic chains. Showing full args builds trust but leaks sensitive inputs; default to summarized args with expand-on-demand. Optimistic “success” before MCP returns feels fast but lies if the call fails — only use optimistic UI for read-only tools you’ve allowlisted.

**Anthropic API specifics:** Assistant content includes `{ type: "tool_use", id, name, input }`. The pill’s lifecycle ends when you append the matching `{ type: "tool_result", tool_use_id, content }` (and optional `is_error`) in the **next** user message before the next model turn. Stream parsing must handle `tool_use` split across chunks; buffer until `input` JSON is complete or show “Preparing…” until parseable.

**Security:** Never render secrets from args/results raw in the DOM if logs/screenshots matter — mask tokens, emails, and free-text PII. Error details shown to end users should be sanitized; full errors belong in server logs tied to `tool_use_id`.

---

### How does a confirm button in the UI map to the backend API call?

**Framing:** Confirm is **human-in-the-loop (HITL)** execution: the model may *propose* a destructive or sensitive tool call, but the client must not run MCP until the user explicitly approves. The UI button is not “another chat message” — it’s a gated side effect with its own idempotency and audit trail.

**Approach:** When the assistant stream completes a `tool_use` that requires approval, pause the agent loop client-side (or server-side): store `pending_tool_executions[tool_use_id] = { conversation_id, name, input, mcp_server_id, created_at }` and render Confirm / Cancel. **Confirm** triggers `POST /conversations/:id/tools/execute` (or equivalent) with body `{ tool_use_id, approved: true, client_request_id }`. The backend validates the pending record, user/org auth, and tool policy, runs MCP, then **appends** to the transcript the user message containing `tool_result`, and resumes the model with `messages` + `tools` unchanged except for the new result. **Cancel** sends `approved: false` or a synthetic `tool_result` with `is_error: true` and content like `"User declined"` so the model can recover gracefully. The frontend should not call Anthropic directly for execution — MCP credentials and OAuth tokens live server-side.

**Tradeoffs:** Pausing on the server (conversation state `awaiting_approval`) vs only on the client — server pause survives refresh and multi-tab; client-only is simpler but fragile. Letting the user edit args before confirm increases flexibility but complicates validation and audit (“approved input” must be what was executed).

**Anthropic API specifics:** You still owe the API a proper alternating structure: assistant message with `tool_use`(s), then user message with matching `tool_result`(s). Confirm does not replace that — it only authorizes your backend to produce the `tool_result` block. For streaming continuations, use the same `tool_use_id` the model emitted; mismatched IDs cause 400s from the API.

**Security:** Bind `tool_use_id` to the authenticated user and conversation; reject execute if the pending record is expired, already executed, or belongs to another org. Rate-limit execute endpoints. Log `approved_by`, timestamp, and hash of `input` for compliance.

---

### Why does `tool_result` go in as `role: "user"` in the Anthropic API?

**Framing:** Candidates often think this means a human typed the result. In API design, **`user` means “content supplied to the model from outside the assistant’s own generation”** — including tool observations, client metadata, and programmatic feedback.

**Approach:** Anthropic’s Messages API models a turn-based conversation: the **assistant** role carries model-generated text and `tool_use` blocks (the model’s decision to act). The **user** role carries everything the runtime feeds back as environment observation — including `tool_result` content blocks. That keeps a clean invariant: assistant = model output; user channel = inputs the model must condition on next. Your orchestration layer constructs that user message after MCP returns; the end user never types it, but the API contract requires `role: "user"` with `content: [{ type: "tool_result", tool_use_id, content }]`. Multiple results from parallel tools belong in one user message as multiple blocks, each `tool_use_id` matching a prior assistant `tool_use`.

**Tradeoffs:** Conceptual confusion in UI copy (“You” avatar on tool results) — use a “System” or “Tool output” label in the product while keeping API roles correct. Some teams mirror results as assistant-visible-only via summarization; that’s an extra model call and drifts from the native tool loop.

**Anthropic API specifics:** Order matters: every `tool_result` must immediately follow the assistant message that contained the corresponding `tool_use`(s). You cannot interleave assistant text after `tool_use` without first closing the loop with results (unless using newer patterns your SDK documents for partial continuation). `is_error: true` on a result tells the model the tool failed without throwing at the HTTP layer.

**Security:** Because `tool_result` is user-role content, anything injected there (malicious MCP, prompt injection in tool output) is treated as high-trust context for the model — sanitize, size-limit, and schema-validate results before appending.

---

### How do you prevent a double-booking from a confirm button being clicked twice?

**Framing:** Double-submit is a classic web problem amplified by agentic UX: users double-click Confirm, two tabs approve the same pending tool, or a slow network causes retry. For bookings/emails, idempotency must be **end-to-end**, not just a disabled button.

**Approach:** **UI layer:** On first click, set `executing=true`, disable Confirm, show spinner; ignore further clicks. **Client idempotency:** Generate `client_request_id` (UUID) per approval attempt; send on every execute request. **Server layer:** Unique constraint on `(conversation_id, tool_use_id)` or status field `pending → executing → completed`; second request with same `tool_use_id` returns the stored outcome (200 with same `tool_result`), not a second MCP call. **MCP/downstream:** Pass `Idempotency-Key: client_request_id` (or hash of `tool_use_id` + user + tool name) to the booking API so the hotel/flight system dedupes. Use short-lived distributed locks (Redis `SET NX` with TTL) around execute for the same `tool_use_id`. Return clear UX if duplicate: “Already booked — view confirmation #123.”

**Tradeoffs:** Strict dedup on `tool_use_id` only vs including normalized args — same id with edited args is rare if server stores canonical pending input. Failing closed (reject duplicate) vs failing open (return cached success) — prefer cached success for payments/bookings to avoid user panic.

**Anthropic API specifics:** Only one `tool_result` per `tool_use_id` should exist in the canonical message history; if duplicate execute races, your message assembler must not append two results for the same id — the API will reject or the model will behave oddly.

**Security:** Idempotency keys must be unguessable and scoped to the user; don’t let one user replay another’s key. Time-bound pending approvals (e.g. 15 minutes) so stale flight prices aren’t booked after delay.

---

### How do you communicate the trust boundary — data leaving Claude to a third-party MCP server?

**Framing:** Users conflate “Claude read my message” with “Claude sent my data to Stripe/Google Calendar.” The product must make **data egress** explicit before execution, especially for enterprise and regulated data.

**Approach:** **Before connect:** OAuth/consent screen listing scopes (“Read calendar events”, “Create events”), org admin allowlist of MCP servers. **Before each sensitive call:** Inline disclosure on the confirm card: “This will send to **Acme Travel MCP** (vendor.com): departure city, dates, passenger name.” Derive the field list from JSON Schema / tool definition, not model prose. **During/after:** Pill footer “Data sent to: …” with link to activity log. **Settings:** “Connected services” page with revoke. For enterprise, label data residency (“Processed in US-East”) if known. Use consistent iconography (external-link, shield) for third-party vs first-party tools.

**Tradeoffs:** Full arg preview vs summary — full builds trust but is noisy; summarize with expand. Blocking until user reads a long policy hurts conversion; use progressive disclosure with sane defaults for low-risk read tools.

**Anthropic API specifics:** The model’s `tool_use.input` is what you’re about to send; don’t rely on the model to self-disclose — your UI should render from structured `input` and server-side policy. System prompts can encourage honesty but aren’t a security boundary.

**Security:** Treat MCP servers as semi-trusted: run them in isolated network paths, strip conversation history from tool context unless necessary, enforce per-tool field allowlists, and warn when a tool requests `*` scopes. SOC2 narrative: egress is logged, revocable, and admin-governed.

---

## Deep

### How do you implement idempotency keys for destructive MCP actions like bookings or emails?

**Framing:** Idempotency protects users and vendors from retries, duplicate tabs, and orchestrator replays. Keys must survive from the confirm click through MCP to the third-party API.

**Approach:** Generate `client_request_id` at approval time (UUIDv4). Persist a row: `{ id, tool_use_id, user_id, status, request_hash, response_snapshot, created_at }`. On execute: (1) if `id` exists with `status=completed`, return cached `tool_result`; (2) if `status=processing` and started &lt; N seconds ago, return 409 or poll; (3) else set `processing`, call MCP with header `Idempotency-Key: client_request_id` and body including stable business idempotency (e.g. `booking_key = hash(user, offer_id, slot)`). MCP adapter forwards to provider APIs (Stripe, etc.). On success, store provider id in `response_snapshot`, set `completed`, append `tool_result` to history once. On failure, set `failed` with retriable flag; only allow retry with **new** `client_request_id` if business logic requires a fresh attempt, or same key if the failure was transport-level before provider ack.

**Tradeoffs:** Key scoped to `tool_use_id` (one approval → one effect) vs scoped to business operation (same flight search retried) — combine both: UI approval dedupes on `tool_use_id`, provider dedupes on business key. TTL on idempotency records (24–72h) vs forever storage for audit — keep audit log longer than dedup cache.

**Anthropic API specifics:** The `tool_result` content should include provider confirmation ids so the model doesn’t re-invoke the same booking on the next turn; optionally add a system hint “booking already created: id …”.

**Security:** Keys must not be enumerable; bind to auth session. Reject execute if `request_hash` of stored pending input ≠ incoming body (tamper detection).

---

### How do you render multi-step tool chains — 3 tool calls in one assistant turn?

**Framing:** Modern models often emit parallel or sequential `tool_use` blocks in a single assistant message before any final natural-language answer. The UI must show **progression** without three identical pills fighting for attention.

**Approach:** Parse one assistant message into an ordered list of `tool_use` blocks. Render a **tool run group**: header “Used 3 tools” with a vertical stepper or stacked pills, each with its own state machine (loading → success/error). Execute order: respect server orchestration — often parallel for independent reads, sequential when tool B needs result A (your backend enforces DAG). Update pills independently as results arrive; only collapse the group to a summary when all terminal. If the model later adds text in the same assistant message after tools in the API payload, show tools first, then streamed prose (API ordering of content blocks matters — render in block order). For streaming, tools may appear before `stop_reason: tool_use`; keep the assistant bubble in “thinking/tools” mode until results are injected and the follow-up model stream starts.

**Tradeoffs:** One combined card vs three pills — combined reduces noise; separate pills clarify which step failed. Auto-collapse on success keeps chat clean; expand-on-error aids debugging.

**Anthropic API specifics:** One user message should contain **all** `tool_result` blocks for that assistant message’s `tool_use` ids before calling the model again. Partial completion (2 of 3 done) should not trigger the next API call unless you intentionally support partial loops with `is_error` on the missing one.

**Security:** Show per-tool egress in the group; a read tool beside a write tool shouldn’t imply only read data left the system.

---

### How do you handle a tool call that times out after 30 seconds?

**Framing:** MCP servers, OAuth refresh, and network hops routinely exceed user patience. Hard caps (e.g. 30s) protect worker pools and UX; you must fail gracefully without corrupting the message graph.

**Approach:** **Server:** Wrap MCP invoke with `AbortController` / context deadline at 30s (configurable per tool). On timeout, do not leave conversation in `processing` forever — mark idempotency row `failed` with `retriable: true` if no provider ack. **API to model:** Append `tool_result` with `is_error: true` and content: `{ "error": "timeout", "message": "Tool X did not respond in 30s" }` so the model can apologize, retry, or suggest alternatives. **UI:** Pill → error state with “Timed out” and actions **Retry** (new execute with same `tool_use_id` only if your policy allows one retry slot) and **Cancel task**. If work may continue async (long report), switch to async pattern: return immediate `tool_result` “job_id: …”, pill shows “Running in background” with webhook/poll updating a job panel — don’t block the 30s-bound synchronous path for that tool class.

**Tradeoffs:** 30s universal vs per-tool SLA — bookings might need 60s with explicit “still working” UI. Cutting the HTTP stream to the client while server continues is possible but confuses users unless you have job ids.

**Anthropic API specifics:** Never omit a result for a `tool_use` the model already emitted — timeout must still produce a `tool_result` or the next `messages.create` fails validation. Don’t fire the next model turn until every `tool_use_id` in that turn is resolved or explicitly errored.

**Security:** Timeouts shouldn’t retry blindly on destructive tools without the same idempotency key. Log timeout with server identity for vendor SLA discussions.

---

### How do you diff the Anthropic vs OpenAI tool use protocol — `tool_use`/`tool_result` vs `tool_calls`/`tool` role?

**Framing:** Multi-provider frontends need a **canonical internal model** and adapters at the orchestration boundary, not in React components.

**Approach:** **Anthropic:** Assistant message `content` array mixes `text` and `tool_use` objects (`id`, `name`, `input`). Results go in **`role: user`** as `tool_result` blocks referencing `tool_use_id`. Stop reason `tool_use` ends the turn until results are supplied. **OpenAI Chat Completions:** Assistant message may include `tool_calls[]` with `id`, `function.name`, `function.arguments` (string JSON). Results are separate messages with **`role: tool`**, `tool_call_id`, and `content` string. **OpenAI Responses API** converges closer to block-structured content — know which API you target. **Adapter layer:** Normalize to `ToolInvocation { id, name, args, status, result, isError }` and `TranscriptEvent` sequencing; on export to Anthropic, pack results into one user message; on export to OpenAI, fan out one `tool` role message per call (order preserved). **Streaming:** Anthropic streams `input_json_delta`; OpenAI streams `tool_calls[].function.arguments` deltas — unify in the pill’s arg preview buffer.

**Tradeoffs:** Lowest-common-denominator model may lose Anthropic parallel block nuance — acceptable for UI, not for exact token replay. Storing raw provider payloads alongside canonical form helps debugging and re-play.

**Anthropic API specifics:** `tool_use_id` naming vs OpenAI’s `tool_call_id` — map explicitly in persistence. Anthropic allows multiple tools in one assistant message; classic OpenAI often uses one assistant message with multiple `tool_calls` — similar UI, different serialization.

**Security:** Provider adapters must not leak OpenAI keys to Anthropic paths; tool results from either provider get the same sanitization pipeline before re-display and re-send.

---

### How do you handle a partial tool result — MCP server returns incomplete data?

**Framing:** “Partial” spans truncated JSON, pagination cursors, streaming MCP chunks, and schema validation failures where some fields are present.

**Approach:** **Validation:** JSON Schema validate MCP output server-side; on partial schema match, mark `validation_level: partial` in your internal record. **To the model:** Prefer honest `tool_result` over silent fixup — include `is_error: true` if required fields are missing for the model to proceed safely, or include structured partial payload plus metadata: `{ "data": { ... }, "_meta": { "partial": true, "missing": ["price"], "cursor": "abc" } }` so the model can call a follow-up tool. **UI:** Pill shows warning state (amber): “Partial result — some fields unavailable” with expand to see what arrived vs expected. **Recovery:** Offer “Continue fetching” if MCP supports pagination; orchestrator issues a second tool call with cursor, not a fake complete result. **Persistence:** Store raw MCP bytes before truncation for support; store redacted version in the transcript.

**Tradeoffs:** Passing partial data with `is_error: false` reduces false failures but increases hallucination risk if the model invents missing fields — bias toward `is_error` for safety-critical tools (payments, medical). Truncating huge results for context window is necessary; summarize server-side with a trusted summarizer rather than hard cut mid-JSON.

**Anthropic API specifics:** `content` in `tool_result` can be string or structured blocks per API version; keep structured partials as valid JSON strings the model can parse. Size limits may force truncation — document truncation in the result so the model knows.

**Security:** Partial errors must not expose internal stack traces; missing data shouldn’t bypass confirm policies on a subsequent “complete” call.

---

### How do you show the user which external services were called and what data was shared?

**Framing:** Post-hoc transparency reduces support load and meets enterprise audit expectations. This is distinct from the pre-confirm disclosure — it’s an **activity trail** grounded in server logs, not model narration.

**Approach:** **Per-turn:** Under the assistant reply, “Connections used this turn” chips: server name, tool names, timestamp. Click opens a drawer with each call: request fields (allowlisted keys), response size, status, duration, idempotency id. **Conversation-level:** “Data sharing” or “Integrations activity” in sidebar filters by date and service. **Enterprise:** Export CSV/SIEM mapping `{ user_id, conversation_id, tool_use_id, mcp_server, tool_name, fields_sent[], status, ip }`. Derive `fields_sent` from structured `input` at execute time, not from LLM paraphrase. If results contain PII from third parties, mark “data received from X” separately from “data sent.”

**Tradeoffs:** Full payload replay vs field labels — replay helps power users; labels help privacy. Real-time updates vs batch — real-time needs websocket from execute pipeline. Showing every read tool in a 10-step chain is noisy — aggregate “Calendar (3 reads, 1 write)” with drill-down.

**Anthropic API specifics:** The transcript’s `tool_use`/`tool_result` pair is your source of truth for replay; sync UI activity log when you append to `messages`, not when the model merely streams a `tool_use` that was never approved/executed.

**Security:** RBAC on activity logs (only conversation owner + org admin). Redact secrets in drawer; hash stable identifiers for support tickets. Retention policy aligned with GDPR — right to delete must purge execute logs and individual `tool_result` payloads where required.

---

*Section 3 complete. Aligns with Anthropic Messages API tool-use loop; adapt OpenAI paths via orchestration adapter.*
