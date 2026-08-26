# How these primitives connect

Worth surfacing in any concept's theory or takeaways where relevant, because interviewers reward seeing the relationships rather than reciting a list:

- **At-least-once delivery** (queues) is *why* **idempotency** is mandatory
- **Idempotency** is what makes **retries** safe, which is what makes **circuit breakers** useful rather than lossy
- **Backpressure** and **rate limiting** are the same instinct applied at different boundaries — one internal, one external
- **CDC** exists because **dual writes** aren't atomic, which is a **consistency** problem
- **Sharding** creates the **hot partition** problem, which **consistent hashing** and fixed-partition-count rebalancing address
- **Caching** is a deliberate **consistency** trade, and its failure modes (stampede) are solved with the same tools as **rate limiting** (single-flight, jitter)
- **Distributed locking** without fencing tokens is a correctness bug wearing a mutual-exclusion costume — it needs the same "who do you trust and for how long" thinking as **consensus**
- **Event sourcing/CQRS** is CDC's logical endpoint taken further: instead of deriving events from row changes, the events *are* the source of truth
- **Distributed transactions** (2PC) and **consensus** (Raft/Paxos) share a mechanism — both need a majority/quorum to agree before committing — which is why 2PC coordinators are often built on a consensus system for their own availability
- **Load balancing** and **service discovery** are two halves of the same problem: discovery answers "who's alive," load balancing answers "which of them gets this request"

If a concept's theory or takeaways can draw one of these arrows to another concept, do it — it's what separates a senior answer from a definitions recital.
