# Section 5 — Performance & Scalability

Interview-prep answers for Claude-style AI chat frontends. Each heading matches a question from the design doc.

---

## Core

### How do you virtualize a conversation list with 500 messages?

Use **windowed rendering**: only mount DOM nodes for messages in or near the viewport (typically 15–25 visible rows plus overscan). Libraries like **TanStack Virtual** or **react-window** pair well with a scroll container on the message column; each row is a `MessageRow` keyed by stable `messageId`, not array index.

**Data model:** Keep the full 500-message array in memory (or a normalized store keyed by id) but pass the virtualizer only `count`, `estimateSize`, and `getScrollElement`. Variable-height messages are the norm in chat—use `measureElement` after mount and cache heights in a `Map<messageId, number>` so remeasure happens only when content changes (edit, expand code block, image load).

**UX constraints:** Pin the **active streaming message** outside the virtual window logic or mark it `sticky` at the bottom so token updates never unmount mid-stream. Overscan 2–3 screens above/below reduces blank flashes on fast flick-scroll. For 500 messages this drops initial paint from hundreds of layout passes to ~20; main-thread cost scales with viewport, not history length.

**Interview signal:** Mention **reverse** virtual lists if you anchor scroll at bottom (chat default)—some libraries virtualize top-down; chat often needs `flex-direction: column-reverse` or inverted scroll math so "scroll up for history" stays natural.

---

### How do you measure and optimize Time to First Token (TTFT)?

**Define TTFT end-to-end:** `t_first_token_visible − t_send_click` (or `t_request_start`). Split into **client** (auth refresh, JSON serialize, connection setup), **network** (TLS, TTFB on SSE), and **server** (queue wait, prompt assembly, model prefill). Log each segment with `performance.mark` / `measure` and a `trace_id` on the request so backend spans align with RUM.

**Client optimizations:** Reuse HTTP/2 or HTTP/3 connections; avoid blocking the send path on unrelated re-renders; start SSE before heavy UI work; prefetch auth and model routing config on app load. **Server optimizations:** Trim prompt building (cached system prompt, parallel retrieval); right-size model/route; stream headers early (`event: ping`) so the browser opens the stream before first model token—careful not to confuse with real content.

**Metrics:** Track TTFT p50/p95/p99 by model, region, and conversation length; SLO example: p95 TTFT &lt; 800 ms for short chats. Dashboard **server TTFT** (first byte from model) vs **client TTFT** (first token painted)—a gap implicates network or render, not inference. Regressions often come from cold starts, retrieval added to path, or connection pool exhaustion.

---

### How do you lazy-load older conversation history as the user scrolls up?

Treat history as **paginated cursor API**: `GET /conversations/:id/messages?before=<oldestId>&limit=50`. When scroll position crosses a threshold near the top (e.g. within 400 px of `scrollTop === 0`), fire fetch; show a slim **loading older messages** row at the top, not a full-page spinner.

**Scroll preservation:** Before prepending, record `scrollHeight` and `scrollTop`; after prepend, set `scrollTop = newScrollHeight - oldScrollHeight + oldScrollTop` so the user's viewport doesn't jump. Deduplicate by `messageId` when merging pages. Cancel in-flight requests if the user switches conversations (AbortController).

**State:** Store pages in normalized cache (React Query / Zustand); `hasMore` from API `nextCursor`. Optionally prefetch page 2 when opening a long thread if metadata says `messageCount > 100`. Virtualization still applies: after prepend, virtualizer `count` increases and cached heights for new ids get measured on first enter viewport.

---

### How do you avoid re-rendering the entire message list on every new token?

**Isolate streaming state:** Hold the in-flight assistant text in a ref or a tiny context consumed only by `StreamingMessageBubble`, not the parent list. Completed messages are immutable snapshots; only the last row subscribes to token deltas.

**React patterns:** `React.memo` on `MessageRow` with custom compare on `messageId` + `contentHash` / `status`; stable callbacks via `useCallback` keyed by id. **Split context**—never put `streamingText` in the same context as the 499 archived messages. Prefer a store (Zustand/Jotai) with selectors so components subscribe to `messages[id]` slices.

**DOM strategy:** Append tokens via **text node** or `contenteditable` inner update inside one row, or throttle to 60–100 ms batches (see Section 1) so React reconciliation runs ~10×/sec not 50×/sec. List virtualization ensures off-screen rows don't reconcile at all. In DevTools Profiler, verify parent `ConversationView` render count stays flat during stream.

---

### How do you handle slow networks — skeleton states, progressive rendering?

**Perceived performance** matters more than raw bandwidth: on send, immediately show the user message (optimistic) plus an **assistant skeleton** (shimmer lines, pulsing avatar) so layout doesn't collapse waiting for SSE. If TTFT exceeds ~300 ms, escalate copy ("Still thinking…") at 2 s and 5 s tiers—avoid alarmist errors until a hard timeout.

**Progressive rendering:** Stream plain text first; defer expensive Markdown AST + syntax highlight until paragraph boundaries or 150 ms idle. Images and tool cards get **placeholder aspect-ratio boxes** then swap on load. Code blocks can show monospace plain text, then highlight in `requestIdleCallback`.

**Network-aware:** `navigator.connection.effectiveType` (with fallback) can reduce animation, shrink prefetch, or suggest retry. Queue outbound messages offline (IndexedDB) with replay on reconnect. Cache static assets aggressively; conversation bodies are dynamic—use stale-while-revalidate for sidebar list, not for active stream.

---

## Deep

### How do you implement scroll anchoring so new tokens don't jump the viewport?

Chat has two modes: **user reading history** (viewport must not move when content above/below changes) and **user pinned to bottom** (new tokens should follow). Track `isPinnedToBottom` with a threshold, e.g. `scrollHeight - scrollTop - clientHeight < 80px`, updated on scroll and after programmatic scroll.

When **pinned**, on each token append set `scrollTop = scrollHeight` (or `scrollIntoView` on a sentinel anchor div at the end). Use **CSS `overflow-anchor: auto`** on the scroll container as a browser fallback—it reduces jump when heights change above the viewport. When **not pinned**, do not auto-scroll; optionally show a "New messages ↓" chip.

For **virtualized** lists, anchoring is harder: prefer `scrollToIndex` on the last item with `align: 'end'` only when pinned. If the user scrolled up mid-stream, freeze scroll position using the scroll-height delta technique when the streaming bubble grows. Test with DevTools CPU throttle + long code blocks—layout growth without anchoring is a common production bug.

---

### How do you calculate the dynamic height of a message before it has rendered (needed for virtualization)?

Use a **tiered estimator**, then correct on mount:

1. **Estimate:** `basePadding + lineCount * lineHeight` where `lineCount ≈ ceil(charCount / charsPerLine)`; bump for attachments, tool pills, or `message.role === 'assistant' && hasCodeFence`. Store per-role averages learned from last N measured rows (EWMA).
2. **Measure:** On first paint, `ResizeObserver` or `getBoundingClientRect` writes true height into `heightCache.set(id, h)`; call `virtualizer.measureElement(el)`.
3. **Invalidate:** On stream end, edit, expand/collapse, or image `onLoad`, remeasure once.

For **unseen** prepended history, estimates may be wrong—overscan and `scrollMargin` prevent white gaps; wrong estimates cause brief jitter corrected in one frame after measure. Optional **offscreen probe**: render clone in `visibility: hidden; position: absolute` for one frame—expensive, use only for high-value rows. Markdown-heavy messages: estimate from raw string length, not rendered height; code blocks need higher multiplier.

Interview tip: fixed `itemSize={120}` fails interviews—always discuss variable size + cache + remeasure on stream complete.

---

### How do you debounce Markdown re-parsing during a fast token stream?

Split **display buffer** from **parse buffer**. Tokens append to a ref-backed string; UI shows plain text or a **lightweight incremental** renderer (split by newlines, parse only the last incomplete block). Full Markdown (remark/unified, GFM, KaTeX) runs on a **debounced schedule**—e.g. `leading: false, trailing: true, 100–200 ms` via `requestAnimationFrame` + `setTimeout`, cancelled and rescheduled on each token burst.

**Fence-aware debouncing:** If inside an unclosed ` ``` `, delay AST rebuild until close or 300 ms idle—avoids flickering partial code blocks. **Incremental AST:** Patch the tree for the tail paragraph only when possible; fall back to full reparse on structural change (heading, list, table). Cap work: skip highlight.js on partial fences; run highlighter once on close.

**Priority:** While `isStreaming`, prefer speed over perfect MD; on `stream.end`, flush immediately (cancel debounce, parse once). Pair with **throttled React setState** so reconciliation and MD parse don't align on the same 16 ms frame. Profiling: MD parse should stay &lt; 5 ms p95 for typical paragraphs; full-doc reparse on 4k tokens is a perf bug.

---

### How do you measure token-per-second render rate on the client and alert on degradation?

Define **render TPS** = tokens applied to visible UI per second, and **stream TPS** = tokens received from SSE—the gap indicates render backlog. Instrument in the streaming hook:

```ts
// Every token or batch:
metrics.histogram('chat.stream.tokens_received', 1);
metrics.histogram('chat.render.tokens_painted', batchLen);
metrics.timing('chat.render.batch_duration_ms', paintMs);
```

Use a sliding 1 s window in-memory for dev overlay; ship aggregates via OpenTelemetry/Datadog RUM. **Degradation alerts:** render TPS &lt; 0.5 × stream TPS for &gt; 2 s, or `requestAnimationFrame` gap p95 &gt; 50 ms during stream, or `Long Task` &gt; 100 ms (PerformanceObserver). Segment by device (`navigator.hardwareConcurrency`), message type (code vs prose), and virtualized vs not.

**User-facing:** No alert—toast; **engineering:** page when p95 render TPS drops 30% week-over-week. Reproduce with Chrome Performance panel + React Profiler; common causes: full-list re-render, sync MD parse, syntax highlight on every token, layout thrash from unbatched DOM writes.

---

### How do you preload the next conversation in the sidebar so it feels instant?

**Predict intent:** On sidebar `mouseEnter` / `focus` / `touchstart` (not merely hover on desktop—use 50–100 ms delay to avoid storm), prefetch `GET /conversations/:id` summary + first page of messages. **Viewport prefetch:** When conversation N is active, prefetch N−1 and N+1 in the list order after idle (`requestIdleCallback`).

**Data warming:** Hydrate React Query cache with `staleTime: 30_000` so click reads cache synchronously; background `refetch` for freshness. **Code-split** route chunks on sidebar mount so navigation doesn't pay JS parse on click. **SSE not prefetched** for inactive threads—only REST history and metadata.

**Instant switch UX:** On click, render from cache immediately (previous messages + title); show subtle stale indicator if refetch in flight. **Priority:** `fetch(..., { priority: 'low' })` for preload vs `high` for active send. Cap concurrent preloads (max 2) and cancel on rapid hover scrub. Metrics: `sidebar.open.latency_ms` p95 &lt; 100 ms when preload hit rate &gt; 70%.

---

### What is your caching strategy for conversation history — memory, IndexedDB, server?

Use a **three-tier ladder** with explicit eviction:

| Tier | Contents | TTL / size |
|------|----------|------------|
| **Memory** (React Query / normalized store) | Active conversation + sidebar page; streaming buffer | LRU ~20 threads or 50 MB cap |
| **IndexedDB** (Dexie/idb-keyval) | Message pages, drafts, offline queue | Days–weeks; keyed by `userId:conversationId` |
| **Server** (source of truth) | Full history, branches, ACL | Paginated; CDN only for static assets |

**Read path:** Open thread → memory hit → else IndexedDB page 1 → parallel network refetch; merge by `updatedAt` / version. **Write path:** Optimistic append to memory; persist completed messages to IndexedDB async; server confirms with id assignment. **Invalidation:** On edit/regenerate/delete, bump conversation `version` and wipe memory + IDB keys for that id; BroadcastChannel syncs tabs.

**Security:** Encrypt sensitive IDB at rest for enterprise; never cache other users' rows. **Server cache** (Redis) for hot prompts is backend—not duplicated in client for full transcripts. **Eviction:** On logout, clear IDB namespace; memory clears on refresh. Prefetch and sidebar hover populate memory without promoting every thread to IDB—only opened or recently used threads get disk write.

Interview close: "Server owns truth; client cache is disposable acceleration"—aligns with multitenancy and GDPR delete (server purge + client wipe).
