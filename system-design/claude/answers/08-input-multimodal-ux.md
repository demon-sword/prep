# Section 8 — Input & Multimodal UX

Interview-prep answers for Claude-style AI chat frontends: composable input, attachments, and multimodal send paths.

---

## Core

### How do you implement a textarea that grows with content but caps at a max height?

Use a **controlled or semi-controlled** `<textarea>` (or `contenteditable` only if you need rich inline formatting) and drive height from **scroll height**, not line-count heuristics. On every input event (and when value is set programmatically, e.g. voice or slash-command insertion), set `style.height = 'auto'`, read `scrollHeight`, then set `height = min(scrollHeight, maxPx)` and toggle `overflow-y: auto` once you hit the cap. Debounce is usually unnecessary at human typing speeds; batch with `requestAnimationFrame` if you also resize on window resize or font load.

The **max height** should be a product constant (e.g. 200px on mobile, 280px desktop) tied to layout: the composer stays above the keyboard/safe area and does not push the message list off-screen. When capped, internal scroll preserves caret visibility via `scrollTop` adjustment on selection change. For accessibility, expose the same behavior with `resize: none` and ensure focus ring and contrast are not clipped by a parent `overflow: hidden`.

**Send vs grow:** Enter-to-send and Shift+Enter-for-newline are orthogonal; growing height should not change keyboard handling. If you mirror ChatGPT/Claude, the send button enables when `trim(value).length > 0` or attachments exist, independent of height. Test edge cases: pasted multi-line blocks, IME composition (do not resize mid-composition on some browsers—listen to `compositionend`), and programmatic clears after send (reset height to one line).

---

### How do you handle large file uploads — chunking, progress, cancellation?

Treat uploads as **first-class async jobs** with their own state machine: `queued → uploading → processing → ready | failed | cancelled`. For files above a threshold (e.g. 5–10 MB), use **multipart upload** to object storage (S3 multipart, GCS resumable, or tus protocol) from the browser via presigned URLs from your API—never stream huge blobs through your app server if you can avoid it. The client splits into fixed-size chunks (5–8 MB is common), uploads parts in parallel with a small concurrency limit (3–4), and reports aggregate progress as `sum(bytesUploaded) / file.size`.

**Progress UI** binds to the job: per-file bar in the composer chip list, optional throughput and ETA for slow networks. **Cancellation** uses `AbortController` on in-flight `fetch`/XHR and calls a backend `abortMultipart(uploadId)` to delete incomplete parts so you do not leak storage. On success, persist only a **stable attachment reference** (`fileId`, `mime`, `size`, optional `sha256`) in the message payload—not the raw bytes in conversation JSON.

**Retries:** idempotent `uploadId` + part ETags let you resume after tab refresh if you store upload session metadata in IndexedDB. Server-side virus scan, MIME sniffing, and size quotas run in a worker after upload completes; the UI shows “Processing…” until the attachment is `ready` or surfaces a typed error (quota, unsupported type, scan failed). Never attach to the model until `ready`; sending should queue or block with clear copy.

---

### How do you render an image uploaded by the user inline in the conversation?

Model a user message as **ordered content blocks**: `{ type: 'text', text }` and `{ type: 'image', source: { type: 'url' | 'base64', ... } }` aligned with your provider’s multimodal schema (Anthropic image blocks, OpenAI `image_url`, etc.). In the thread UI, render user bubbles with a **thumbnail strip** above or beside text: `object-fit: cover`, max dimensions (e.g. 240×240 preview, click to lightbox), and `loading="lazy"` for history.

For **immediate preview** before upload finishes, use `URL.createObjectURL(file)` in the composer and revoke on unmount or after CDN URL replaces it. After upload, store and display the **CDN/signed URL** only; avoid embedding multi-MB base64 in React state or localStorage. Alt text can default to filename; optional user-editable alt for accessibility.

**Layout:** flex column inside the bubble—images first, then text—so streaming assistant replies do not reflow oddly. When the model echoes or analyzes the image, the assistant message stays text; the user message remains the source of truth for what was sent. If an image fails moderation or upload, show an inline error chip on that block without deleting the rest of the message draft.

---

### How do you implement slash commands (e.g. `/search`, `/summarize`) in the input box?

Parse the **leading token** of the composer value on change: if input matches `^/(\w*)$` at start of line (or after optional whitespace), enter **command mode** and show a filtered **typeahead menu** (fuzzy match on command names and aliases). Selecting a command replaces or completes the token and may open **parameter UI**—second menu for scope, or a modal for required args—before send.

Architecturally, slash commands are **client-side intents** that map to one of: (1) **prompt templates** injected at send time, (2) **routing** to a different API (`/search` → RAG endpoint), or (3) **tool/MCP invocation** with pre-filled arguments. Keep a registry `{ name, description, argsSchema, handler }` so product can add commands without touching the textarea component. Handlers should return a **normalized outbound message** (text + metadata) so the rest of the pipeline stays unchanged.

**UX details:** keyboard nav (↑↓, Enter, Esc), highlight matched substring, hide menu on blur unless clicking menu (use pointer-down preventDefault on menu items). Do not send on Enter while the menu is open—Enter selects. Optional: only activate when `/` is first character to avoid conflicting with paths in code pastes. Log `commandId` in analytics and in message metadata for debugging. Server should still validate—never trust client-only command side effects for auth or billing.

---

## Deep

### How do you implement voice input with live transcription feeding into the chat input?

Use the **Web Speech API** (`SpeechRecognition` / `webkitSpeechRecognition`) for a zero-backend MVP in Chromium, or **streaming STT** (Deepgram, Whisper API, Google STT) over WebSocket for cross-browser and better accuracy. Flow: mic button → permission prompt → `MediaStream` + recognition session → **partial transcripts** append or replace a “live” segment in the composer while **final** segments commit to the stable textarea value.

Maintain two buffers: **`committedText`** (what the user had before dictation) and **`interimText`** (unstable partial). UI shows `committedText + interimText` with interim styled (gray/italic); on `result` event with `isFinal`, merge into `committedText` and clear interim. **Feeding the chat input** means updating the same controlled state the textarea uses, so slash commands, token count, and attachments still work; stopping mic freezes the final string without clearing attachments.

**Latency and errors:** show a pulsing indicator and “Listening…” state; handle `no-speech`, `network`, and `not-allowed` with toasts. For long dictation, chunk audio to the server every N seconds so a tab crash does not lose everything. Privacy: default to **no retention** of raw audio unless enterprise requires it; disclose in UI when cloud STT is used. Offer **push-to-talk** vs **toggle** modes; on mobile, expect OS-level keyboard dictation as a fallback and avoid fighting for the mic with WebRTC elsewhere in the app.

**Send coupling:** optional voice-complete action (“stop and send”) should run the same `submitMessage()` path as typed send, with deduplication if the user hits send twice. Echo cancellation matters if you ever play TTS while recording—use separate tracks or pause recognition during playback.

---

### How do you handle a PDF upload — extract text client-side or send the raw file?

Use a **hybrid strategy** keyed by page count, file size, and product capabilities. **Small/text-native PDFs** (≤ ~20 pages, ≤ few MB): client-side extraction with `pdf.js` gives fast preview, immediate token estimates, and lets the user see what will be sent; send extracted text in the message (or as a `document` text block) plus optional thumbnail of page 1 for UX. **Large, scanned, or encrypted PDFs**: upload raw file to storage, run **server-side OCR/extraction** (Unstructured, Textract, custom pipeline), and attach a `fileId` the model path resolves when `ready`.

Do **not** rely on client extraction alone for vision models: if the deployment supports **document vision**, you may send pages as images or use the provider’s native PDF support when available—still via upload reference, not base64 in JSON. **Security:** PDFs are a common malware and prompt-injection vector; scan server-side, strip JavaScript/actions, and cap pages/tokens ingested. Show the user **page count and estimated tokens** after extraction; let them select page ranges for long docs.

**State machine:** `uploaded → extracting → preview ready → (user confirms) included in message`. If extraction fails, offer “send original to backend anyway” only when policy allows. Cache extraction by `contentHash` so re-upload in another thread does not re-OCR. For interview framing: optimize **time-to-preview** client-side, optimize **correctness and scale** server-side, and never block the UI thread on OCR for 100-page files.

---

### How do you show a token count estimate for the current input before the user sends?

Run a **client-side tokenizer** that matches the deployment model family: `tiktoken` wasm port, `@anthropic-ai/tokenizer`, or a small WASM build per provider. On composer `input`, debounce 150–300ms and compute `count = encode(text).length + attachmentTokens`. Display a subtle **footer counter** (“~1,240 tokens”) and optional **context budget bar** when the thread already has history—`remaining = contextWindow - threadTokens - draftTokens`.

**Attachments:** images use provider-specific rules (tiles, patches, or fixed cost per image); PDFs use extracted text length; unknown files show “—” until processing completes. **Performance:** worker thread for tokenize so typing stays smooth; cache encodings for unchanged prefixes when only appending (incremental count). **Accuracy disclaimer:** label as estimate; server does final count before billing.

**Product hooks:** warn soft threshold at 80% of context, hard disable send at 100% with “shorten or start new chat.” For team plans, optionally show **cost estimate** (`tokens * pricePerM`) on hover. Do not block IME or voice on every keystroke—debounce is mandatory. If you support multiple models, re-run count when model picker changes because tokenizers differ.

---

### How do you implement drag-and-drop file attachment with paste-from-clipboard support?

Centralize on one **`AttachmentController`** that accepts `File[]` from any source: `<input type="file" multiple>`, drag-and-drop, and paste. For drag-and-drop, register `dragenter`/`dragover`/`drop` on the composer **drop zone** (whole card or dedicated overlay); `preventDefault` on dragover to allow drop; validate `dataTransfer.types` includes `Files`. Show a **drop highlight** state and reject non-file drags (e.g. text URLs can be a separate path).

**Paste:** listen to `paste` on the textarea. If `clipboardData.files.length > 0`, treat as attachment (screenshots, copied files); else if plain text, insert at caret. Images from screenshot tools often arrive as a single anonymous `image.png`—good default. Normalize each `File` through the same pipeline: type allowlist, max size, virus scan queue, preview generation.

**UX:** dedupe by name+size+lastModified; show chips with remove (×); support **multi-file** drop. **Accessibility:** file picker button is keyboard-reachable; do not rely on drag-only. **Mobile:** paste from clipboard is primary; drag-and-drop often N/A. **Edge cases:** dragging from browser address bar may be a URL string, not a file—detect `text/uri-list` and offer “Attach link” vs “Fetch preview.” Prevent browser navigating away on drop by always calling `preventDefault` on the document during active drag if the drop target is global.

---

### How do you handle mixed multimodal input — image + text + file in one message?

Define a **single user message schema** with an ordered `content: ContentBlock[]` array: e.g. `[image, image, text, documentRef]`. The composer is a **unified attachment strip** (thumbnails + file chips) plus one text field; send is enabled when any block is non-empty. On submit, atomically build one API payload—providers expect one `user` turn with multiple parts, not parallel messages.

**Ordering policy:** typically **visuals first, then text, then documents** so prompt structure matches model training (“here are images, here is the question”). **Upload gating:** wait for all blobs to reach `ready` or let user send with partials only if product allows (usually block with “Uploading 2/3…”). **Token budgeting:** sum estimates across blocks; truncate or warn when over limit, with per-block removal.

**Rendering:** user bubble composes sub-renderers per block type; assistant streaming stays unchanged. **Editing/regenerate:** store enough metadata to rebuild the same multipart request. **Failure isolation:** if one image fails scan, mark that block failed but keep others in the draft. **Analytics:** one `messageId` with `attachmentTypes: ['image','pdf']` for funnel analysis.

**API normalization layer:** map internal blocks to Anthropic/OpenAI/Gemini shapes in one adapter so the UI does not branch per provider. For interview depth: the hard part is not UI layout but **consistent lifecycle**—upload, extract, tokenize, send, and retry—across heterogeneous types in one atomic user action.
