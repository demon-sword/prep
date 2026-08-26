# Circuit breakers and bulkheads

Both are **failure isolation** patterns. They answer: when one dependency is broken, how do we stop it from taking down everything else?

### Circuit breaker

Wraps a call to a dependency and tracks its failure rate. Three states:

- **Closed** — normal. Calls pass through. Failures are counted.
- **Open** — the failure threshold was crossed. Calls **fail immediately without attempting the dependency**. This is the whole point: you stop wasting threads, connections, and time on something you know is broken.
- **Half-open** — after a cooldown, allow a small number of trial calls. If they succeed, close. If not, open again and extend the cooldown.

**Why it matters more than retries:** retrying a struggling service makes it worse. A circuit breaker is the mechanism that stops a slow dependency from becoming a total outage — without it, every request thread blocks waiting on the failing call, the thread pool exhausts, and a single broken downstream takes out an unrelated endpoint on the same service.

**What to configure:** failure threshold (rate, not absolute count), the window over which it's measured, cooldown duration, and — most importantly — **the fallback**. An open circuit needs a defined behaviour: cached value, default, degraded response, or explicit error. A circuit breaker with no fallback just fails faster.

**Timeouts are the prerequisite.** A call with no timeout can't be detected as failed — it just hangs. Every remote call needs a timeout, and the timeout should be shorter than the caller's own deadline.

### Bulkhead

Named after ship compartments: a hull breach floods one compartment, not the vessel. In software, you **partition resources so that exhaustion in one area can't starve another**.

Forms:

- **Separate thread pools / connection pools per dependency.** If the slow service has its own pool of 10 threads, it can exhaust those 10 and nothing else.
- **Separate pools per tenant or per priority class.** One tenant's burst can't consume all capacity.
- **Separate instances entirely** for critical paths.

The relationship: **the bulkhead limits the blast radius, the circuit breaker shortens the duration.** They're complementary, and naming both shows depth.

### Related patterns worth knowing

- **Timeout** — the foundation. Nothing else works without it.
- **Retry with exponential backoff and jitter** — jitter is essential. Without it, all failed clients retry in lockstep and produce synchronised load spikes.
- **Retry budget** — cap retries as a percentage of total traffic, so retries can't amplify a partial outage into a full one.
- **Graceful degradation** — complete the operation without the failed component, and say so. Better than failing entirely, provided the degradation is *visible*.
- **Fail fast vs fail safe** — decide which is right for each dependency. Some failures should abort; some should be absorbed.

### In the room

> "Threat intel gets a circuit breaker with a defined fallback: when it's open, the investigation completes without reputation data and the verdict is marked degraded with the missing evidence named. Silently omitting it would be dangerous — a lowered-confidence verdict is honest, a confident one built on partial evidence isn't."
