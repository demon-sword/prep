# Claude Frontend System Design — Interview Questions

A comprehensive reference of deep questions across all segments, organized by theme and difficulty.

---

## 1. Streaming & Real-Time Rendering

> Very common. Every AI-first company asks about this.

### Core
- How do you render incomplete Markdown mid-stream without layout thrash?
- How do you throttle token appends so the DOM doesn't repaint 50×/sec?
- How do you implement a stop-generation button that actually stops the stream?
- What is the difference between SSE and WebSockets — when would you pick each?
- How do you handle a stream that drops midway — reconnect, retry, or resume?

### Deep
- How do you buffer tokens before flushing to the DOM — what's the right interval?
- How do you handle a code block that opens with ` ``` ` but the closing fence hasn't arrived yet?
- How do you render a streaming table where rows arrive one token at a time?
- How do you show a "typing indicator" that transitions seamlessly into real content?
- How do you handle backpressure if the client is rendering slower than tokens arrive?

---

## 2. Conversation State Management

> Very common. Core to any chat product.

### Core
- Where does conversation state live — client, server, or both?
- How do you handle editing a previous message and regenerating from that point?
- How do you implement branching conversations (retry gives a different response path)?
- How do you sync conversation state across two open tabs on the same conversation?
- What is your strategy when the context window fills up — truncate, summarize, or paginate?

### Deep
- How do you model a branched conversation as a data structure — tree vs linear array?
- How do you reassemble the messages array after a mid-conversation edit?
- How do you handle optimistic UI rollback if a regenerated message fails?
- How do you implement "undo" for a sent message?
- How do you persist draft messages across page refreshes?

---

## 3. MCP & Tool Use UI

> Emerging hot topic. Most candidates haven't thought this through.

### Core
- How do you render a tool call pill — loading, success, and error states?
- How does a confirm button in the UI map to the backend API call?
- Why does `tool_result` go in as `role: "user"` in the Anthropic API?
- How do you prevent a double-booking from a confirm button being clicked twice?
- How do you communicate the trust boundary — data leaving Claude to a third-party MCP server?

### Deep
- How do you implement idempotency keys for destructive MCP actions like bookings or emails?
- How do you render multi-step tool chains — 3 tool calls in one assistant turn?
- How do you handle a tool call that times out after 30 seconds?
- How do you diff the Anthropic vs OpenAI tool use protocol — `tool_use`/`tool_result` vs `tool_calls`/`tool` role?
- How do you handle a partial tool result — MCP server returns incomplete data?
- How do you show the user which external services were called and what data was shared?

---

## 4. Artifacts & Sandboxed Rendering

> Common at companies building AI coding or document tools.

### Core
- How do you safely render Claude-generated HTML or React in the browser?
- Why use an iframe sandbox — what attacks does it prevent?
- How do you stream code into a live-reloading preview panel?
- How does `postMessage` work between the host page and the sandboxed iframe?
- How do you version artifacts — user edits vs Claude regenerates?

### Deep
- What CSP headers do you set on the sandboxed iframe and why?
- How do you handle an artifact that imports an external CDN library — allow or block?
- How do you diff two versions of an artifact and show a visual changelog?
- How do you sync scroll position between the code editor and the rendered preview?
- How do you handle an infinite loop inside a sandboxed React component?
- How do you implement a "revert to version N" for an artifact?

---

## 5. Performance & Scalability

> Senior-level signal. Shows production experience.

### Core
- How do you virtualize a conversation list with 500 messages?
- How do you measure and optimize Time to First Token (TTFT)?
- How do you lazy-load older conversation history as the user scrolls up?
- How do you avoid re-rendering the entire message list on every new token?
- How do you handle slow networks — skeleton states, progressive rendering?

### Deep
- How do you implement scroll anchoring so new tokens don't jump the viewport?
- How do you calculate the dynamic height of a message before it has rendered (needed for virtualization)?
- How do you debounce Markdown re-parsing during a fast token stream?
- How do you measure token-per-second render rate on the client and alert on degradation?
- How do you preload the next conversation in the sidebar so it feels instant?
- What is your caching strategy for conversation history — memory, IndexedDB, server?

---

## 6. Auth, Security & Multitenancy

> Senior-level. Differentiates engineers who've built multi-user systems.

### Core
- How do you scope conversations to a user — JWT claims, row-level security?
- How do you implement org-level conversation isolation in a Team plan?
- How do you prevent prompt injection through user-uploaded files?
- How do you handle OAuth token refresh for MCP servers mid-conversation?

### Deep
- How do you invalidate all sessions for a user on password change without breaking active streams?
- How do you implement conversation sharing with a public link — what's the permission model?
- How do you audit-log every MCP action for enterprise compliance?
- How do you prevent a malicious MCP server from exfiltrating conversation history?
- How do you scope API keys so a developer key can't access another org's conversations?
- How do you handle a user who belongs to multiple orgs — context switching mid-session?

---

## 7. Offline, Resilience & Error Handling

> Differentiator. Shows you think beyond the happy path.

### Core
- What do you show if the SSE stream disconnects at token 200 of 800?
- How do you queue a user message sent while offline and replay it on reconnect?
- How do you distinguish a rate-limit error from a model error from a network error?
- How do you implement exponential backoff on the SSE reconnect?

### Deep
- How do you implement a "resume stream" — continue generation from where it dropped?
- How do you handle a partial message that was persisted to the DB mid-stream before disconnect?
- How do you show a degraded-mode UI when the inference cluster is slow (p99 > 10s)?
- What is your retry strategy for a failed MCP tool call — retry immediately, after delay, or ask user?
- How do you surface rate limit information (e.g. requests remaining) to the user without alarming them?

---

## 8. Input & Multimodal UX

> Common at companies with file upload, voice, or image features.

### Core
- How do you implement a textarea that grows with content but caps at a max height?
- How do you handle large file uploads — chunking, progress, cancellation?
- How do you render an image uploaded by the user inline in the conversation?
- How do you implement slash commands (e.g. `/search`, `/summarize`) in the input box?

### Deep
- How do you implement voice input with live transcription feeding into the chat input?
- How do you handle a PDF upload — extract text client-side or send the raw file?
- How do you show a token count estimate for the current input before the user sends?
- How do you implement drag-and-drop file attachment with paste-from-clipboard support?
- How do you handle mixed multimodal input — image + text + file in one message?

---

## 9. API Design & Provider Abstraction

> Relevant if building on top of multiple LLM providers.

### Core
- Why does Anthropic use strict alternating turns while OpenAI allows a `tool` role?
- How do you normalize message history across Anthropic, OpenAI, and Gemini formats?
- How do you handle provider-specific features (e.g. Anthropic extended thinking) without breaking abstraction?
- What is the difference between `system` as a top-level field (Anthropic) vs a system message in the array (OpenAI)?

### Deep
- How do you build a provider-agnostic streaming adapter — same interface for SSE and WebSocket backends?
- How do you handle model versioning — what happens when `claude-sonnet-4` is deprecated mid-product?
- How do you implement automatic model fallback if the primary model returns a 529 overloaded error?
- How do you estimate cost before sending a request — token counting per provider?

---

## 10. The "Killer" Questions

> Questions that separate good candidates from great ones. Each forces multi-system thinking.

1. **Edit message N in a 20-message conversation.** Forces you to think about branching history, context window re-assembly, optimistic UI rollback, and server-side state — all at once.

2. **The confirm button is clicked twice in 200ms.** How do you guarantee exactly one booking? Covers button locking, idempotency keys, backend deduplication, and UX rollback.

3. **The stream drops at token 400 of 1000.** What does the user see, what's in the DB, and how do you recover? Covers partial persistence, resume logic, and error UX.

4. **Design the conversation sidebar for a user with 10,000 conversations.** Covers virtualization, search indexing, pagination, and optimistic rename/delete.

5. **A Claude-generated React component has an infinite loop. How do you detect and handle it?** Covers sandboxing, timeout/heartbeat in the iframe, and graceful error rendering.

6. **The MCP OAuth token expires mid-conversation during a multi-step agentic task.** Covers token refresh, mid-stream pause, user re-auth UX, and task resumption.

---

*Use the segmentation above to time-box your prep. Streaming + conversation state first, then MCP/artifacts, then the rest.*