# Caching strategies

### The core idea

A cache trades **freshness for latency and load**. Everything about caching is downstream of that trade — every strategy is a different answer to "how stale am I willing to be, and who pays when I'm wrong?"

### Where caches live

- **Client-side** — browser, mobile app. Fastest, least controllable, hardest to invalidate.
- **CDN / edge** — static assets, sometimes API responses. Geographic.
- **Application-level** — in-process memory (fast, per-instance, doesn't scale horizontally, cold on deploy).
- **Distributed cache** — Redis, Memcached. Shared across instances. This is what people usually mean.
- **Database-level** — query cache, buffer pool. Mostly out of your hands.

### Read patterns

**Cache-aside (lazy loading)** — the default, and what you should assume unless told otherwise.

```
value = cache.get(key)
if value is None:
    value = db.read(key)
    cache.set(key, value, ttl)
return value
```

Application owns the logic. Only requested data is cached. Downside: every cache miss is a full round trip, and the first request after expiry always pays. Also vulnerable to the thundering herd (below).

**Read-through** — the cache itself knows how to fetch from the source. Application just asks the cache. Cleaner code, but you need a cache that supports it, and you've moved logic into infrastructure.

### Write patterns

**Write-through** — write to cache and DB synchronously, in one operation. Cache is never stale. Writes are slower because you pay both. Good when reads massively outnumber writes and staleness is unacceptable.

**Write-behind (write-back)** — write to cache, acknowledge immediately, flush to DB asynchronously. Fast writes, absorbs bursts. **You can lose data if the cache dies before the flush.** Only acceptable when the data is reconstructible or the loss is tolerable.

**Write-around** — write straight to the DB, bypass the cache, let the next read populate it. Avoids polluting the cache with write-once data that's never read. Common for logs and events.

### Invalidation

The famous hard problem. Three approaches:

- **TTL** — simplest, and usually right. Data is stale for at most N seconds by design. Pick the TTL from how much staleness the business can tolerate, not from a gut feeling.
- **Explicit invalidation** — delete the key on write. Correct but fragile: every write path must remember, and distributed caches can race (invalidate then repopulate with stale data from an in-flight read).
- **Versioned keys** — include a version or a hash in the key (`user:123:v7`). Old entries become unreachable and age out naturally. No invalidation race, at the cost of key churn.

### The three failure modes to name

**Thundering herd (cache stampede)** — a hot key expires and a thousand concurrent requests all miss and all hit the DB simultaneously. Fixes: a lock/mutex so only one request repopulates while others wait; probabilistic early expiry (refresh slightly before TTL, randomised per request); or serving stale-while-revalidate.

**Cache penetration** — requests for keys that don't exist anywhere, so they always miss and always hit the DB. Often malicious. Fix: cache the negative result (with a short TTL), or use a Bloom filter to reject known-absent keys cheaply.

**Cache avalanche** — a large number of keys expire at the same moment (e.g. everything was populated at deploy time with the same TTL). Fix: jitter the TTLs.

### Eviction policies

**LRU** (least recently used) is the default and usually fine. **LFU** (least frequently used) is better when access frequency is stable and you don't want a burst of one-off requests to evict your hot set. **FIFO** is rarely what you want. Know that Redis offers several `maxmemory-policy` options and that `allkeys-lru` vs `volatile-lru` (only keys with a TTL) is a real choice.

### In the room

> "I'd cache with a TTL rather than explicit invalidation here, because the staleness budget is N seconds and TTL removes a whole class of invalidation races. The risk is a stampede on hot keys, so I'd add jitter and a single-flight lock on repopulation."

**Where this appeared in the Simbian design:** the dedup layer is a cache with a deliberately chosen TTL, and the LLM gateway uses prompt caching to cut cost on repeated context.
