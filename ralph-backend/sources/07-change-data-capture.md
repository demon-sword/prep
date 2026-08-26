# Change data capture (CDC)

### The problem it solves

You have data in a database. Something else needs to know when it changes — a search index, a cache, an analytics warehouse, another service. The naive options are all bad:

- **Dual writes** (write to DB and publish an event) — not atomic. The process can die between the two, leaving them permanently inconsistent. **This is the anti-pattern CDC exists to replace, and naming it is a strong signal.**
- **Polling for changes** — high latency, high load, misses deletes, misses intermediate states.

**CDC reads the database's own replication log** — the WAL in Postgres, the binlog in MySQL, the oplog in MongoDB — and turns committed changes into a stream of events. Because it reads the log the database already writes for its own replication, the events are exactly the committed changes, in commit order, with no extra write path to get out of sync.

### Log-based vs the alternatives

- **Log-based** — Debezium is the standard tool. Low overhead, no schema changes, captures deletes, preserves ordering. Requires access to the replication stream and some operational care.
- **Trigger-based** — database triggers write to an audit table which is then polled. Works anywhere, but adds write-path overhead and can affect transaction latency.
- **Query-based** — poll `WHERE updated_at > last_seen`. Simple, but misses deletes, misses intermediate updates, needs a reliable timestamp column, and has a race at the boundary.

### The transactional outbox

The pattern to know when log-based CDC isn't available or you want explicit control over the event schema:

1. In the **same transaction** as the business write, insert a row into an `outbox` table
2. A separate relay process reads the outbox and publishes to the message broker
3. Mark published (or let CDC read the outbox table itself)

Because the business write and the outbox insert share a transaction, they're atomic. The relay is at-least-once, so consumers need idempotency — which loops back to idempotency.

### Semantics

CDC events are usually **at-least-once** and ordered per key. Consumers must be idempotent. Many CDC events are naturally idempotent if you treat them as **upserts of the full row state** rather than deltas — another instance of "derive state rather than mutate it."

Two more things worth knowing:

- **Snapshot plus stream** — a new consumer needs the current state before it can meaningfully apply the change stream. Tools handle this with an initial snapshot followed by streaming from the corresponding log position.
- **Schema evolution** — the source table's schema will change. Consumers must tolerate added columns; a schema registry helps.

### Where it's used

Cache invalidation, search index maintenance, materialised views, data warehouse replication, the strangler-fig migration pattern (dual-running old and new systems), and event-driven architectures generally.

### In the room

> "Rather than dual-writing to the DB and the event bus — which isn't atomic and drifts permanently the first time a process dies between the two — I'd use CDC off the replication log, or a transactional outbox if I need control over the event schema. Consumers are idempotent because CDC is at-least-once."
