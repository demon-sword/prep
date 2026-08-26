# Consistency trade-offs

### CAP, stated correctly

Under a **network partition**, you must choose between **consistency** and **availability**. That's the whole theorem, and the framing people get wrong is treating it as a permanent three-way choice. Partitions are rare; the interesting trade-off most of the time is **latency vs consistency**, which is what PACELC adds:

> **PACELC**: if there's a **P**artition, choose **A**vailability or **C**onsistency; **E**lse (normal operation), choose **L**atency or **C**onsistency.

PACELC is the more useful model and mentioning it lands well.

### The consistency spectrum

- **Strong / linearizable** — every read sees the most recent write. The system behaves as if there's one copy. Expensive: requires coordination, so latency scales with the distance between replicas.
- **Sequential** — all operations appear in *some* consistent order that every node agrees on, but not necessarily real-time order.
- **Causal** — operations that are causally related appear in order everywhere; concurrent operations may be seen in different orders. Often the sweet spot: it prevents the anomalies users actually notice (seeing a reply before the comment it replies to).
- **Eventual** — replicas converge if writes stop. Says nothing about when. Cheap and highly available.

### Session guarantees — the practical middle ground

Full strong consistency is usually overkill; full eventual consistency produces baffling user experiences. Session guarantees split the difference:

- **Read-your-writes** — a user always sees their own updates. The single most important one. Without it, a user edits their profile, reloads, and sees the old value.
- **Monotonic reads** — you never see time go backwards (read a value, then read an older value).
- **Monotonic writes** — your writes apply in the order you made them.

These are cheap to implement (route a session to the same replica, or track a version token) and eliminate most user-visible weirdness.

### Isolation levels (the database-local cousin)

Don't confuse consistency (across replicas) with isolation (across concurrent transactions). Know the anomalies:

- **Read uncommitted** → dirty reads
- **Read committed** → no dirty reads, but non-repeatable reads
- **Repeatable read** → no non-repeatable reads, but phantoms possible
- **Serializable** → transactions behave as if run one at a time

**Snapshot isolation** (what Postgres calls repeatable read) is common and has a specific failure mode: **write skew**, where two transactions each read a consistent snapshot, each make a decision that's valid alone, and together violate an invariant. Classic example: two doctors both go off-call simultaneously because each sees the other is still on.

### Quorums

With N replicas, W write acknowledgements, R read responses: if **W + R > N**, reads and writes overlap on at least one node, so reads see the latest write. Common: N=3, W=2, R=2. Tuning W and R trades write latency against read latency against fault tolerance.

### In the room

The move is to identify *which data* needs *which* consistency, rather than picking one for the whole system.

> "Verdicts need strong consistency and an audit trail — a regulator asking what we knew in January can't get a stale answer. But the dedup cache is fine eventually consistent; a duplicate investigation costs money, not correctness. I'd rather be precise about which is which than pick one level for everything."
