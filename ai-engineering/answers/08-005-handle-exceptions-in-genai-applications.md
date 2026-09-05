# Handle exceptions in GenAI applications?

**Category:** 08-safety-guardrails
**Question #:** 005
**Source section:** §10 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
GenAI apps fail in ways that traditional software doesn't: the LLM call itself can time out, return malformed JSON, exceed context limits, produce content that trips guardrails mid-stream, or drift into hallucination on a perfectly valid request. Interviewers use this question to probe whether you understand **the unique failure modes of LLM-backed systems** — non-determinism, latency variance, provider rate limits, and schema violations — and whether you build the retry, fallback, and observability infrastructure to handle them gracefully rather than surfacing raw stack traces to users.

### Trigger phrases
- "How do you handle exceptions or errors in a GenAI application?"
- "What happens when the LLM call fails or returns garbage?"
- "How do you make an AI feature resilient to provider outages or rate limits?"

### What it tests
Production engineering maturity: ability to classify LLM failure modes and implement layered resilience (retry policies, fallback chains, graceful degradation, circuit breakers, structured observability) without treating the LLM as a black box that always returns valid text.

---

## Answer

### Concept
Exception handling in GenAI applications is a **multi-class problem**. Unlike a deterministic API that either returns 200 OK or throws a typed exception, an LLM call can fail in six distinct ways: (1) provider errors (rate limits, timeouts, outages), (2) schema violations (expected JSON but got prose), (3) context-limit overflows, (4) guardrail rejections (input or output blocked), (5) hallucinations (valid response, wrong facts), and (6) tool-call failures in agentic loops. Each class requires a different recovery strategy.

### Mechanism

**Class 1 — Provider errors (429, 500, 503, timeout)**

- **Retry with exponential backoff + jitter**: `tenacity` or `httpx` retry logic, 3 attempts, base 1s, cap 30s, ±25% jitter to avoid thundering herd. Only retry idempotent calls (read, generation); do not retry payment or state-mutating tool calls without idempotency keys.
- **Circuit breaker**: after 5 consecutive failures in a 60s window, open the circuit and route to the fallback model. Use `pybreaker` or a Redis-backed counter. Close the circuit after a 30s probe interval.
- **Model fallback chain**: `claude-sonnet-5` → `claude-haiku-4-5` → cached response → static fallback string. Surface model-tier in logs for post-incident analysis.

**Class 2 — Schema violations (malformed or missing structured output)**

- Use **Instructor** (wraps OpenAI/Anthropic SDK) or `response_format={"type": "json_schema", ...}` with a Pydantic model. On `ValidationError`, retry the call up to 2 times with the error message appended to the prompt: `"Your previous response was invalid: {error}. Return valid JSON matching the schema."` 
- After 2 retries, raise to a human review queue or return a safe default (e.g., empty list, `null` fields) rather than propagating the raw string.
- Log the raw LLM output alongside the validation error for pattern analysis — recurring schema failures indicate prompt or model drift.

**Class 3 — Context-limit overflows (`context_length_exceeded`)**

- Catch `ContextLengthExceeded` (OpenAI) or equivalent and trigger the **truncation cascade**: (a) reduce retrieved chunk count top-k by 50%, (b) compress conversation history via `ConversationSummaryBufferMemory`, (c) switch to a model with a larger context window (e.g., `claude-3-5-sonnet` 200K), (d) if still over limit, chunk the input and run Map-Reduce summarization.
- Surface a user-facing message ("I'm working with a large document — let me summarise the key parts") rather than a raw API error.

**Class 4 — Guardrail rejections (input or output blocked)**

- Input block: return a canned policy response immediately. Do not retry — the content itself is the problem, not the infrastructure.
- Output block: retry the generation once with a stricter grounding prompt and `temperature=0`. If still blocked, fall back to a human-escalation message.
- Log blocked query category (harm class, confidence score) separately from infrastructure errors — guardrail metrics and retry metrics need different dashboards.

**Class 5 — Hallucinations (valid response, wrong facts)**

- Post-generation: async RAGAS faithfulness check or DeBERTa NLI entailment gate. On failure (faithfulness < 0.80), replace the response with a safe fallback ("I couldn't find a reliable answer — here are the sources for you to review") rather than retrying the LLM, which would just produce another hallucination from the same bad retrieval.
- Hallucination handling is distinct from exception handling — it requires a verification layer, not a retry.

**Class 6 — Tool-call failures in agentic loops**

- Classify tool errors as retryable (network timeout, 429) vs permanent (schema mismatch, permission denied). Apply exponential backoff for retryable errors.
- **Idempotency keys**: hash `(run_id, step_idx, tool_name, args)` → use as an idempotency header (Stripe-style) to prevent duplicate side effects on retry.
- After N retries, escalate to HITL or terminate the agent loop with a structured error report rather than running indefinitely.

**Observability:**

```python
import structlog
log = structlog.get_logger()

try:
    response = llm_call(prompt, model="claude-sonnet-5")
except RateLimitError as e:
    log.warning("llm.rate_limit", model="claude-sonnet-5", retry_attempt=attempt)
    # trigger backoff + fallback
except ValidationError as e:
    log.error("llm.schema_violation", raw_output=response.text, error=str(e))
    # retry with error in prompt
except ContextLengthExceededError:
    log.warning("llm.context_overflow", tokens=estimated_tokens)
    # truncation cascade
```

Every exception class should emit a structured log event with: `model`, `error_class`, `retry_attempt`, `latency_ms`, `prompt_tokens`. Aggregate into dashboards: error rate by class, retry rate, fallback rate, circuit-breaker open events.

### Example / Tradeoff

**Customer support RAG chatbot (production, 50K queries/day):** Error breakdown in month 1:
- Rate limit (429): 1.2% of calls → resolved with exponential backoff + circuit breaker (< 0.05% user-visible errors after fix)
- Schema validation failures: 0.8% → Instructor retry-with-error reduced to 0.03%
- Context overflow: 0.3% → truncation cascade transparent to users
- Guardrail blocks: 0.6% input, 0.1% output → all handled with canned responses; zero raw errors to users

Total user-visible error rate: **0.12%** (down from 2.4% without structured exception handling).

**Tradeoff:** Retry-on-schema-failure adds 1–3s latency. For latency-sensitive paths (autocomplete, streaming), skip retry and return a graceful degradation response immediately, logging for async repair rather than blocking the user.

---

## Verbal script

**Opening (30s):**
"GenAI apps fail in fundamentally different ways than traditional APIs — you get non-deterministic responses, rate limits, context overflows, schema violations, and guardrail rejections all at once. I think of exception handling here as a six-class problem, and each class needs a different recovery strategy. Let me walk through how I'd structure it."

**Core explanation (2–3 min):**
"The first class is **provider errors** — 429 rate limits, 503 outages, and timeouts. For these I use exponential backoff with jitter: three attempts, starting at one second, capped at thirty, with ±25% jitter to avoid thundering herd. On top of backoff I add a circuit breaker — if I see five consecutive failures in a 60-second window, I open the circuit and route to a fallback model, say from a frontier model down to a small fast model, or to a cached response.

Second class is **schema violations** — you asked for JSON and got prose. I solve this with Instructor or OpenAI's `response_format` with a Pydantic schema. On `ValidationError`, I retry the call up to twice with the error message appended to the prompt. After two retries I don't keep spinning — I return a safe default or escalate to a human review queue.

Third is **context overflow** — you hit the model's token limit. I have a truncation cascade: first reduce retrieved chunks by half, then compress conversation history with a summarization buffer, then switch to a model with a larger context window. If you're still over, fall back to Map-Reduce.

Fourth is **guardrail rejections** — input or output blocked. For input blocks I don't retry — the content itself is the problem. For output blocks I retry once with a stricter grounding prompt and temperature zero. Either way, these go to a separate dashboard from infrastructure errors.

Fifth is **hallucinations** — and here the key insight is that a hallucination is not a retryable error. The LLM will just produce another hallucination from the same bad retrieval context. Instead, I run a RAGAS faithfulness check or DeBERTa NLI gate post-generation; if faithfulness is below 0.8, I replace the response with a safe fallback rather than retrying.

Sixth is **tool-call failures in agents** — I classify tool errors as retryable versus permanent, apply backoff for the retryable ones with idempotency keys to prevent duplicate side effects, and after N retries terminate the loop with a structured error report rather than running indefinitely.

Across all of these, structured logging is critical: every exception emits a log event with the error class, model, retry attempt, latency, and token count. I aggregate those into dashboards so I can see error rate by class and spot regressions on model updates."

**Tradeoff / production angle (1 min):**
"The main tension is between resilience and latency. Retrying schema failures adds one to three seconds — for an autocomplete or streaming flow, that's too expensive. So on latency-sensitive paths I skip retry and return graceful degradation immediately, logging the failure for async review. The other gotcha is mixing exception classes in one catch block — when you treat a guardrail block the same as a network timeout, you lose the signal you need to fix the root cause. Separate handling, separate metrics, separate alerting."

**Wrap-up (30s):**
"So the TL;DR: six failure classes, each with its own recovery — backoff+circuit-breaker for provider errors, Instructor retry for schema violations, truncation cascade for context overflow, canned response for guardrail blocks, faithfulness gate for hallucinations, and idempotent loop termination for tool failures. And structured per-class observability throughout. Happy to go deeper on any of these."

---

## Pitfalls

- **Mistake:** Catching all LLM errors in one generic `except Exception` block with a single retry — **Better:** Classify errors into retryable (429, 503, timeout) vs non-retryable (guardrail block, context overflow, permanent schema failure) and apply class-specific recovery. Retrying a guardrail-blocked query wastes cost and is never correct; retrying a network timeout is exactly right.

- **Mistake:** "We retry schema failures up to 10 times" without mentioning the latency cost or the alternative of graceful degradation — **Better:** Cap schema retries at 2 (with the validation error in the prompt), then return a safe default rather than blocking the user for 10+ seconds. Distinguish between latency-sensitive paths (skip retry, degrade gracefully) and async/batch paths (aggressive retry is fine).

- **Mistake:** Treating hallucinations as a retryable exception — **Better:** A hallucination is not an infrastructure error; retrying from the same bad retrieval context just produces another hallucination. The fix is a post-generation faithfulness verification gate (RAGAS, DeBERTa NLI) that replaces the response with a fallback, not a retry loop.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q1: When and how implement LLM guardrails?](08-001-when-and-how-implement-llm-guardrails.md) | Prerequisite — guardrail rejection is one of the six failure classes |
| [Q4: Protect against prompt injection and jailbreaking?](08-004-protect-against-prompt-injection-and-jailbreaking.md) | Related — prompt injection can cause guardrail blocks that need exception-handling |
| [Q3: Detect and mitigate hallucinations in production?](../answers/05-003-detect-and-mitigate-hallucinations-in-production.md) | Cross-category — faithfulness gate as hallucination exception handler |

---

## One-liner recall

> GenAI exceptions fall into six classes — provider errors (backoff+circuit-breaker), schema violations (Instructor retry-with-error, cap at 2), context overflow (truncation cascade), guardrail blocks (canned response, no retry), hallucinations (faithfulness gate + fallback, not retry), and tool failures (idempotent backoff + loop termination) — each with separate handling and separate observability metrics.
