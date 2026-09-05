# Ralph Backend — Interactive HTML Generator

Generates **self-contained interactive HTML files** for backend / distributed-systems interview concepts, targeting a 7–8 years experienced backend engineer — one file per concept, theory + live visualization + the exact interview-ready sentence. Built on the same base as `ralph-concepts/` and `ralph-machine-learning/`, retargeted at `backend/`.

## What makes this one different

Eight of the 22 concepts (`01`–`08`) are seeded from **hand-written source notes** in `sources/` — real senior-level write-ups already at the target depth and voice ("mechanism → variants → the trade-off that matters → the sentence to say in an interview"). The generating agent reads the relevant source file first and adapts it faithfully rather than inventing theory from scratch; the remaining 14 concepts are written from scratch in the same voice. See `spec.md` § Source material.

Each generated page also carries a dedicated **`#interview-line`** section — a callout with the exact sentence to say when the topic comes up, not just a summary.

## Quick start

```bash
# 1. Scaffold the plan
./ralph-backend/scaffold.sh

# 2a. Generate one concept — next in queue
./ralph-backend/once.sh

# 2b. Generate a specific concept by id
./ralph-backend/once.sh 11-consensus-algorithms

# 3a. Run the full loop (all 22)
./ralph-backend/loop.sh

# 3b. Run a specific concept (useful to retry a failed one)
./ralph-backend/loop.sh 19-indexing-storage-engines

# 4. Validate all generated files
./ralph-backend/validate.sh

# 4b. Validate a single concept
./ralph-backend/validate.sh 19-indexing-storage-engines
```

## See available concept IDs

```bash
./ralph-backend/once.sh --help
```

## What it generates

For each of the 22 concepts in `concepts.json`, one HTML file at:
```
backend/concepts/<id>.html
```

Each file is **fully self-contained** — open directly in a browser, no server needed.

### HTML structure
| Section | Content |
|---------|---------|
| `<header>` | Title, group badge, one-sentence description |
| `#theory` | Deep theory: mechanism, variants, named failure modes, tradeoffs |
| `#visualization` | Interactive JS viz (vanilla JS + Canvas/SVG, no CDN) — prefers simulating the real mechanism over a canned animation |
| `#interview-line` | Callout: the exact sentence to say when this comes up in an interview |
| `#takeaways` | 4–6 senior-level insights |
| `.concept-nav` | Prev/next navigation between concepts |

## Concepts (22 total)

| Group | Concepts |
|-------|---------|
| **Data** | Caching Strategies*, Change Data Capture*, Database Replication, Indexing & Storage Engines (B-tree vs LSM-tree) |
| **Messaging** | Queues & Backpressure*, Event Sourcing & CQRS |
| **Consistency** | Consistency Trade-offs (CAP/PACELC)*, Concurrency Control (Optimistic/Pessimistic/MVCC) |
| **Scaling** | Sharding & Partitioning* |
| **Coordination** | Idempotency*, Consensus Algorithms (Raft/Paxos), Distributed Transactions (2PC & Saga), Distributed Locking & Fencing Tokens |
| **Reliability** | Circuit Breakers & Bulkheads* |
| **Traffic management** | Rate Limiting*, Load Balancing, Service Discovery |
| **Operations** | Observability, Zero-Downtime Deployments, Multi-Region Architecture, Connection Pooling |
| **API design** | API Design & Evolution |

\* = seeded from hand-written source notes in `sources/`

## Scripts

| Script | Purpose |
|--------|---------|
| `scaffold.sh` | Build/refresh `plan.md` from `concepts.json` |
| `once.sh [--model slug]` | Generate ONE concept (pick from plan.md) |
| `loop.sh [max] [--model slug]` | Loop all 22 concepts |
| `validate.sh [concept-id]` | Structural validation of generated HTML files |

## Design system

Matches the dark terminal theme used across the rest of the repo's HTML suite:
- Background: `#0d0f17`
- Accent: `#00d4ff` (cyan)
- Fonts: Inter + JetBrains Mono (Google Fonts CDN)
- No other external dependencies

## Testing

Each concept is tested by the generating agent via **Playwright MCP**:
1. Navigate to the file URL
2. Screenshot to confirm render
3. Check console for JS errors
4. Fix and re-test if needed

## Environment variables

| Var | Default | Description |
|-----|---------|-------------|
| `RALPH_BACKEND_MODEL` | (claude default) | Model slug to use |
| `RALPH_BACKEND_TIMEOUT` | `3600` | Agent timeout in seconds |

## Shared environment

| Var | Default | Effect |
|---|---|---|
| `RALPH_MAX_ATTEMPTS` | 3 | Rejections before the run gives up |
| `RALPH_SKIP_FACTCHECK` | 0 | `1` skips the adversarial fact-check pass |
| `RALPH_FACTCHECK_TIMEOUT` | 900 | Seconds for the fact-check pass |
| `RALPH_LOOP_SLEEP` | 5 | Seconds `loop.sh` pauses between iterations |
| `RALPH_MAX_STALLS` | 3 | Consecutive no-output iterations before the loop stops |
| `RALPH_CORPUS_FINAL` | — | `1` makes `validate-corpus.sh` apply its completeness gate |
