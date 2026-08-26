# Rate limiting

### Two distinct purposes

- **Protection** — stop any one client from exhausting shared capacity. Inward-facing.
- **Compliance** — respect a downstream provider's limits so you don't get throttled or banned. Outward-facing.

These need different designs. Protection is per-client and can reject. Compliance is global across your whole fleet and usually needs to **queue** rather than reject, because the work still has to happen.

### Algorithms

**Token bucket** — a bucket holds up to B tokens, refilled at R per second. Each request takes a token; no token, no service. **Allows bursts up to B while enforcing an average of R.** The most common choice and usually the right default, because real traffic is bursty and pure smoothing is unnecessarily harsh.

**Leaky bucket** — requests enter a queue and drain at a fixed rate. Output is perfectly smooth. Good when the downstream genuinely cannot tolerate bursts. Adds latency by design.

**Fixed window** — count requests per calendar minute, reset at the boundary. Trivial to implement, but has the **boundary problem**: a client can send the full limit at 11:59:59 and again at 12:00:00, achieving 2x the intended rate.

**Sliding window log** — store a timestamp per request, count those within the trailing window. Exact, but memory scales with request volume.

**Sliding window counter** — interpolate between the previous and current fixed windows. Approximates the sliding window with fixed-window memory cost. The usual production compromise.

### Distributed rate limiting

The hard part. With N instances, a naive per-instance limit of `limit/N` breaks under uneven load balancing and wastes capacity.

- **Centralised counter** (Redis) — accurate, but adds a network hop to every request and makes Redis a dependency on the hot path. Use atomic operations or a Lua script; a read-then-write is a race.
- **Local buckets with periodic sync** — each instance holds a portion and reconciles periodically. Fast, approximate, can overshoot briefly.
- **Gossip / lease-based** — instances lease portions of the global budget from a coordinator, returning unused capacity. More complex, better utilisation.

**In an interview, the honest answer is that approximate distributed rate limiting is usually fine** — you're protecting against 10x, not enforcing an exact count. Say that; over-engineering exactness is a common trap.

### Design decisions to state

- **What's the key?** Per user, per API key, per IP, per tenant, per endpoint, or a combination. Per-IP alone is weak (NAT, proxies) and can punish shared networks.
- **Reject or queue?** Rejecting returns 429 and is honest. Queueing preserves the work but converts a throughput problem into a latency problem — and needs its own bound (see backpressure).
- **Tiered limits** — different quotas per plan, or per priority class.
- **Cost-based limiting** — not all requests are equal. An LLM call costing 50k tokens shouldn't count the same as a health check. Rate limit on estimated cost rather than request count where the variance is large.

### Client-side behaviour

When you're on the receiving end of a 429: **respect `Retry-After` if present**, back off exponentially with **jitter**, and cap total retries with a budget. Retrying a rate limit aggressively is how a throttle becomes a ban.

### Communicating limits

Return `X-RateLimit-Limit`, `X-RateLimit-Remaining`, `X-RateLimit-Reset` headers, and `429 Too Many Requests` with `Retry-After` when limited. Clients can only behave well if you tell them the rules.

### In the room

> "The limiter has to be shared across the fleet, not per-instance, because the vendor's limit is global. I'd use a token bucket in Redis with an atomic decrement — it allows bursts up to the bucket size, which matches real traffic, while holding the average. And for LLM calls I'd rate limit on estimated tokens rather than request count, because a 50k-token investigation and a health check aren't the same load."
