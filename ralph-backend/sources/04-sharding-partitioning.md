# Sharding and partitioning

### Terminology

**Partitioning** splits data into subsets. **Sharding** usually means partitioning across separate machines. **Vertical partitioning** splits by column or feature (users here, orders there); **horizontal partitioning** splits rows by key. Sharding almost always means horizontal.

You shard when a single node can't hold the data, can't serve the throughput, or can't meet the latency target. **Not before** — sharding costs you cross-shard joins, distributed transactions, and operational complexity forever.

### Strategies

**Range partitioning** — shard by key ranges (A–F, G–M…) or by time. Range scans are efficient. **Hotspots are the danger**: time-based partitioning means all writes hit the newest partition. Common and often acceptable for time-series, disastrous for a general workload.

**Hash partitioning** — hash the key, mod by shard count. Even distribution, no hotspots on a good hash. **Range queries become scatter-gather** across every shard, and resharding is painful because changing the shard count remaps almost every key.

**Consistent hashing** — map both keys and nodes onto a ring; a key belongs to the next node clockwise. Adding or removing a node only remaps the keys between it and its neighbour, roughly K/N keys, instead of nearly all of them. **Virtual nodes** (each physical node occupying many ring positions) fix the uneven distribution you'd otherwise get with few nodes. This is the answer when someone asks how to reshard without a full migration.

**Directory / lookup-based** — a lookup service maps key to shard. Maximum flexibility, easy rebalancing, but the directory is a dependency and a potential bottleneck. Often the pragmatic choice for multi-tenant systems where tenants vary wildly in size.

### Choosing a shard key

The single highest-leverage decision, and hard to change later. Criteria:

- **High cardinality** — enough distinct values to spread across shards
- **Even distribution** — no single value dominating
- **Query alignment** — most queries should hit one shard. If your common query needs data from every shard, the key is wrong.

**Multi-tenant systems** usually shard by tenant, which aligns beautifully with queries and isolation but produces the **noisy neighbour** problem: one huge tenant overwhelms its shard. Fixes: dedicated shards for the largest tenants, or a composite key (tenant + sub-key) for those tenants specifically.

### Rebalancing

**Fixed partition count** — create far more partitions than nodes (say 1024 partitions across 8 nodes), and rebalance by moving whole partitions. The number of partitions never changes; the mapping to nodes does. This is what Kafka and Elasticsearch do, and it's the cleanest answer to "how do you add capacity."

### Secondary indexes

The subtle part. Two options:

- **Local (document-partitioned)** — each shard indexes its own data. Writes are cheap and local. Reads by the secondary key must **scatter-gather** across all shards.
- **Global (term-partitioned)** — the index itself is partitioned by the indexed term. Reads hit one shard. Writes must update an index on a *different* shard, so writes become distributed and often asynchronous.

### In the room

> "I'd shard by tenant, because it aligns with both query patterns and the isolation requirement. The risk is noisy neighbours — one enterprise tenant generating 100x the volume — so I'd use a fixed large partition count and pin the biggest tenants to dedicated partitions rather than resharding the whole cluster."
