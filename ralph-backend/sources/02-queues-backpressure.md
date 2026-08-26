# Queues and backpressure

### Why queues exist

A queue **decouples the rate of production from the rate of consumption**. That's it. Everything else — durability, ordering, fan-out — is a feature built on top of that one property.

Two distinct uses, often conflated:

- **Work queue** — distribute tasks across workers. One message, one consumer. SQS, Celery, RabbitMQ work queues.
- **Event log / stream** — durable ordered record, many independent consumers reading at their own pace. Kafka, Kinesis, Pulsar. Consumers track their own offset; the log doesn't delete on read.

The distinction matters: a work queue forgets a message once acknowledged; a log retains it, so a new consumer can replay history. If someone asks "can we reprocess the last week?" the answer depends entirely on which one you built.

### Delivery guarantees

- **At-most-once** — fire and forget. Messages can be lost. Rare in practice.
- **At-least-once** — the default almost everywhere. Messages can be **duplicated**. This is why idempotency (section 5) is non-negotiable in queue-based systems.
- **Exactly-once** — the marketing term. Real end-to-end exactly-once requires either transactional coordination between broker and consumer state, or at-least-once delivery plus idempotent processing. In an interview, say: **"exactly-once delivery is effectively at-least-once delivery plus idempotent consumers."** That one sentence signals you've actually built this.

### Ordering

Global ordering across a distributed queue is expensive and usually unnecessary. What you normally want is **per-key ordering**: all events for the same entity land in the same partition and are processed in order, while different entities proceed in parallel. Kafka gives you this via the partition key. The cost: a hot key becomes a hot partition, and you can't parallelise within it.

### Backpressure

**The concept:** when a consumer can't keep up, the system must signal upstream to slow down rather than silently accumulating work until something breaks.

Without backpressure, a queue absorbing 5x load doesn't fail — it grows. Latency climbs, memory fills, and you discover the problem when the oldest message is two hours old and every SLA is blown. **A queue that never applies backpressure is a queue that converts a throughput problem into a latency problem and hides it.**

Mechanisms:

- **Bounded queues** — a fixed capacity. When full, producers block, or get an error, or the system sheds load. The bound *is* the backpressure.
- **Pull-based consumption** — consumers request work at their own rate rather than having it pushed. Kafka is pull-based; this is a large part of why it degrades gracefully.
- **Rate limiting at the producer** — cap intake at what the system can actually process (see section 8).
- **Load shedding** — deliberately drop or reject low-priority work to protect the rest. Better to reject 10% explicitly than to degrade 100% silently.

### The metric that matters

**Consumer lag** — how far behind the head of the queue your consumers are, measured in messages or (better) in time. Queue depth alone is misleading; lag in seconds tells you whether you're meeting your SLA. Alert on lag, not depth.

### Dead letter queues

Messages that fail repeatedly go to a DLQ instead of blocking the main queue or retrying forever. Two things people forget: **someone must monitor the DLQ** (an unmonitored DLQ is a data loss mechanism with extra steps), and you need a **replay path** to reprocess them after the bug is fixed.

### In the room

> "I'd use a partitioned log rather than a work queue here, keyed by tenant, so we get per-tenant ordering and can replay. Backpressure comes from the bounded consumer pool and pull-based consumption — under a 5x burst, lag grows but nothing falls over, and I'd alert on lag in seconds rather than queue depth."
