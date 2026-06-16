# Tool failures, retries, idempotency?

**Category:** 03-agents-tool-use
**Question #:** 024
**Source section:** §3 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
The interviewer is probing production engineering depth: can you build a reliable agent that recovers gracefully when tools fail, without causing double-writes, infinite retry loops, or cascading cost explosions? This is a senior-level safety question that separates candidates who have shipped agentic systems from those who only demo them.

### Trigger phrases
- "What happens when a tool call fails in your agent?"
- "How do you handle retries without duplicating side effects?"
- "Walk me through your error handling strategy for tool-using agents."

### What it tests
Whether the candidate understands idempotency as the foundational property that makes retries safe, and can design a layered retry + circuit-breaker strategy for production agent reliability.

---

## Answer

### Concept
In agentic systems, tool calls can fail transiently (network timeout, rate limit) or permanently (bad input, downstream service down). Safe recovery requires two properties working together: **retries** to handle transient failures, and **idempotency** to ensure retrying a side-effectful tool doesn't produce duplicate effects (double-charged payments, duplicate DB writes, duplicate emails sent).

### Mechanism

**Idempotency by design:**
- Assign every tool call a stable `tool_call_id` (e.g., `sha256(run_id + step_id + tool_name + args)`).
- Pass this ID as an idempotency key to downstream APIs (Stripe, Twilio, most REST APIs support `Idempotency-Key` headers).
- For internal tools (DB writes, file writes), use upsert semantics rather than insert: `INSERT ... ON CONFLICT (tool_call_id) DO NOTHING`.
- For non-idempotent tools (e.g., send-email), enforce HITL gating or deduplication via a Redis `SETNX` lock on the idempotency key with a TTL.

**Retry strategy (layered):**
1. **Per-tool retry with exponential backoff + jitter:** `base_delay * 2^attempt + random(0, base_delay)`. Typical: 3 retries, 1s/2s/4s base, max 30s.
2. **Classify errors before retrying:**
   - `429 / 503 / network timeout` → retryable (transient)
   - `400 / 422 / schema validation error` → not retryable (bad input — surface to orchestrator immediately to avoid burning retries)
   - `500` → conditionally retryable (check if idempotent; if not, escalate)
3. **Circuit breaker:** After N consecutive failures (e.g., 5), stop calling that tool for T seconds (e.g., 60s) and raise a structured `TOOL_CIRCUIT_OPEN` signal to the orchestrator. The orchestrator can then reroute (use fallback tool) or HITL.
4. **Max retry budget at orchestrator level:** Even if each tool allows 3 retries, cap total retries per agent run (e.g., 10 total tool retries) to prevent cost explosion.

**Tool result schema with error types:**
```python
{
  "status": "success" | "retryable_error" | "permanent_error" | "circuit_open",
  "data": {...},
  "error_code": "RATE_LIMITED" | "INVALID_INPUT" | "DOWNSTREAM_DOWN" | None,
  "tool_call_id": "sha256-...",
  "attempt": 2
}
```
The orchestrator routes on `status`, not raw exceptions — this keeps error handling deterministic and testable.

### Example / Tradeoff

**Concrete example — payment tool in a billing agent:**
- Tool: `charge_customer(customer_id, amount, tool_call_id)`
- Stripe's idempotency key ensures that even if the network drops after Stripe processes the charge but before the agent receives the 200 OK, a retry with the same `tool_call_id` returns the original charge rather than creating a second one.
- Without this: network partition → agent retries → customer charged twice → production incident.

**Tradeoffs:**
| Strategy | Benefit | Cost |
|----------|---------|------|
| Exponential backoff + jitter | Avoids thundering herd | Adds latency on transient failures |
| Circuit breaker | Prevents cascade failures | Requires fallback logic; adds complexity |
| Idempotency keys | Safe retries for side-effectful tools | Requires downstream API support or dedup store |
| Immediate permanent-error escalation | Avoids wasting retry budget | Requires robust error classification |

**LangGraph pattern:** Use `interrupt_before` to pause on permanent errors and surface them to HITL rather than retrying forever. Checkpoint state before each tool call so the agent can resume from the last successful step.

---

## Verbal script

**Opening (30s):**
"Tool failure handling is one of the hardest parts of production agent engineering, because the naive approach — just retry — can cause data corruption or cost explosions. The key insight is that retries are only safe when the underlying tool is idempotent, so my answer has two parts: making tools idempotent by design, then layering retries on top."

**Core explanation (2–3 min):**
"I'd start with idempotency. Every tool call gets a stable idempotency key — I typically compute it as a hash of the run ID, step index, tool name, and arguments. For external APIs like Stripe or Twilio, I pass this as the `Idempotency-Key` header, which their servers use to deduplicate. For internal DB writes, I use upsert semantics — `INSERT … ON CONFLICT DO NOTHING`. For tools that genuinely can't be made idempotent, like sending a notification, I gate them behind a Redis `SETNX` lock or a HITL checkpoint.

On top of that, I layer a retry policy. The first thing I do is classify errors: 429s and 503s are retryable transients; 400s and schema validation errors are permanent — retrying those is wasteful and misleading. For retryable errors, I use exponential backoff with jitter to avoid thundering herd: base delay of 1s, doubling each attempt, with a random offset to spread load.

Above the per-tool retry, I add a circuit breaker. After five consecutive failures from the same tool, I stop calling it for 60 seconds and emit a `TOOL_CIRCUIT_OPEN` signal to the orchestrator. The orchestrator can then reroute to a fallback tool or pause for human review. And at the orchestrator level, I cap total retries per run — say, 10 tool retries across the entire agent run — so a flaky downstream service can't burn my token budget."

**Tradeoff / production angle (1 min):**
"The concrete failure case that motivates all of this is payment processing. If a billing agent charges a customer and the network drops before it gets the success response, the agent will retry. Without idempotency keys, the customer gets double-charged — that's a production incident. Stripe's idempotency key design means the retry returns the original charge. The flip side is that not all tools support idempotency keys natively, so for those I need the Redis dedup store or HITL gate. The overhead is worth it for any tool with financial, communication, or irreversible side effects."

**Wrap-up (30s):**
"So in summary: idempotency makes retries safe, error classification makes retries efficient, circuit breakers prevent cascades, and an orchestrator-level retry budget prevents cost explosions. Happy to go deeper on any of the layers — the circuit breaker pattern or the LangGraph checkpoint/resume model in particular."

---

## Pitfalls

- **Mistake:** "I'd just retry failed tool calls a few times with a delay" — **Better:** Explain error classification first (retryable vs permanent), then idempotency keys to make retries safe for side-effectful tools, then backoff + jitter; generic retry without these distinctions causes double-writes and burns token budget on unrecoverable errors.
- **Mistake:** Treating all tool errors as retryable (including 400 bad-input errors) — **Better:** Surface permanent errors (schema validation failures, bad auth) immediately to the orchestrator rather than retrying; distinguish the error class before choosing a recovery path.
- **Mistake:** Ignoring the orchestrator-level retry budget ("each tool handles its own retries") — **Better:** Cap total retries per agent run at the orchestrator level; otherwise a flaky downstream service triggers N-per-tool × M-tools retries and inflates cost unpredictably.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q23: Sandbox tool execution safely?](03-023-sandbox-tool-execution-safely.md) | Prerequisite — sandboxing + idempotency together form the tool safety contract |
| [Q25: Biggest security risks with tool-using agents?](03-025-biggest-security-risks-with-tool-using-agents.md) | Follow-up — unvalidated tool inputs are both a security risk and a source of permanent errors |
| [Q10: Design a safe and debuggable agent loop](03-010-design-a-safe-and-debuggable-agent-loop.md) | Same concept — agent loop safety includes retry/idempotency at the loop level |

---

## One-liner recall

> Assign every tool call a stable idempotency key so retries are safe, classify errors before retrying (transient vs permanent), apply exponential-backoff-with-jitter per tool, add a circuit breaker for cascading failures, and cap total retries at the orchestrator level to bound cost.
