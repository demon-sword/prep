# System Design Prep

Frontend system design interview prep. Each topic gets its own folder with question banks, answers, and interactive study pages.

## Interview format (45–60 min)

Use this structure for a full system design answer. Total time: roughly **45–60 minutes**.

### ① Requirements — 5–10 min

Clarify the problem before drawing boxes.

- **Functional requirements** — what the product must do; confirm with the interviewer
- **Non-functional requirements** — latency, scale, availability, security, cost
- **Metrics & constraints** — numbers you can design against (e.g. p95 latency, concurrent users)
- **Assumptions** — what you are and are not building
- **Scope** — explicitly call out what is in vs out of scope for this session

### ② Architecture — 10–15 min

High-level design and how the frontend is organized.

- **Framework / stack** — why this stack fits the problem
- **High-level architecture** — major layers and data flow (client → BFF → services → storage)
- **Component / module tree** — UI breakdown (shell, views, shared widgets)
- **State management** — where state lives and why:

  | Layer | Examples |
  |-------|----------|
  | Ephemeral / in-memory | UI toggles, form drafts, stream buffers |
  | Client persistence | localStorage, IndexedDB, cookies |
  | Server / cache | Redis, CDN, query cache |
  | Source of truth | Postgres, object storage |

### ③ Data model — ~5 min

Core entities the system operates on.

- Name each entity and its key fields
- Note relationships (one-to-many, graph, etc.)
- Mention important methods or invariants where relevant  
  e.g. `User { id, orgId, getStatus() }`

Keep it conceptual — not a full schema dump.

### ④ API design / BFF — ~10 min

How the frontend talks to the backend.

- **Protocol choice** — REST, GraphQL, gRPC (and why)
- **Real-time patterns** — long polling, WebSockets, SSE (when each fits)
- **Key endpoints / operations** — grouped by domain, not a exhaustive list
- **Network lifecycle** — request → response, streaming, cancel, reconnect, retry
- **Edge & caching** — CDN, stale-while-revalidate, cache invalidation
- **Storage tradeoffs** — when to use ACID vs BASE, hot vs cold data

### ⑤ Deep dive — ~10 min

Pick **1–2 areas** the interviewer cares about most. Common options:

- Performance (virtualization, bundle size, Core Web Vitals)
- Security (auth boundary, sandboxing, CSP, tenant isolation)
- Observability (logging, tracing, error reporting, stream health)
- Testing (unit, integration, E2E, streaming mocks)
- Accessibility & i18n
- Build / CI / deployment

Close with a short synthesis: what you'd build first, what you'd defer, and the main tradeoff you made.

---

**Background knowledge** (protocol stack, URL → render pipeline, browser APIs) supports your answer but is not a separate timed section — weave it in where relevant.

## Per-question answer format

For individual questions within a topic, use three parts:

1. **Problem framing** — restate the question and why it matters
2. **Approach** — your solution, mechanisms, and diagram if helpful
3. **Tradeoffs** — alternatives considered and why you chose this path

## Folder layout

Each system design **topic** gets its own folder. Every topic includes an **interactive architecture map** — a standalone HTML file that ties the whole question set together.

```
system-design/
├── README.md                              # this file — interview format & conventions
└── <topic>/                               # e.g. claude/, slack/, figma/
    ├── <topic>-design-doc.md              # question bank
    ├── <topic>-frontend-architecture.html # interactive system diagram (required)
    ├── <topic>-system-design-interview.html # full 45–60m interview walkthrough
    ├── answers/                           # markdown answers
    ├── answers-html/                      # interactive HTML study pages
    │   ├── index.html
    │   ├── assets/                        # shared CSS/JS for study UI
    │   └── …                              # one page per section
    └── scripts/                           # generators, tooling
```

New topics are added as sibling folders under `system-design/`.

### Interactive architecture map

One per topic — e.g. [`claude/claude-frontend-architecture.html`](./claude/claude-frontend-architecture.html).

This is the **big-picture view** for that problem space. It should:

- Map **layers and components** (UI → client state → transport → API/BFF → providers → data)
- **Tag nodes** to answer sections so you can filter while studying
- Support **flow walkthroughs** — click through key paths (send message, tool call, reconnect, etc.)
- Link each node to the **relevant section answers** in `answers-html/`

The section index (`answers-html/index.html`) and interview template should both link to this file. When adding a new topic, create its architecture map before or alongside the section answers so every question has a system context to sit in.

## Previewing HTML

- **Browser** — `open path/to/file.html`
- **Live Preview** — Cmd+Shift+P → “Live Preview: Show Preview” (Cursor / VS Code)
- **Simple Browser** — Cmd+Shift+P → “Simple Browser: Show”, paste a `file://` URL
- **Live Server** — when pages need a local server (fetch, modules, etc.)
