# Partial observability or missing information?

**Category:** 03-agents-tool-use
**Question #:** 015
**Source section:** §3 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
Interviewers probe whether you understand that real-world agent environments are rarely fully observable — the agent can't see the full state of the world, tool outputs can be incomplete, APIs can fail silently, and users give ambiguous instructions. Strong candidates know how to architect agents that degrade gracefully, ask clarifying questions, and make principled decisions under uncertainty rather than hallucinating or crashing.

### Trigger phrases
- "What happens when your agent can't find the information it needs?"
- "How does your agent handle incomplete or missing context?"
- "What if a tool returns no results or an error?"
- "How do you handle ambiguous user instructions in an agent?"

### What it tests
Whether the candidate can design agents that behave safely and predictably when the environment is incomplete — distinguishing between recoverable uncertainty (query again, reframe) and unrecoverable uncertainty (escalate to human or abstain).

---

## Answer

### Concept
Partial observability means the agent's current state representation does not capture the full world state — tool results may be missing, truncated, or contradictory; user intent may be ambiguous; prior conversation context may be absent. An agent designed only for the happy path will hallucinate, loop, or crash when this occurs. The solution is a layered uncertainty-handling architecture: detect the gap → classify severity → respond with the appropriate mitigation (retry, clarify, escalate, or abstain).

### Mechanism
**1. Classify the missing-information scenario:**

| Type | Example | Mitigation |
|------|---------|------------|
| **Ambiguous user intent** | "Process the report" — which one? | Clarifying question before tool calls |
| **Empty tool result** | Vector DB returns 0 hits | Lower similarity threshold → retry; or abstain |
| **Tool error / timeout** | API returns 500 | Retry with exponential backoff (max 3); mark step failed |
| **Conflicting tool outputs** | Two sources give contradictory facts | Surface both with source attribution; don't synthesize |
| **Incomplete observation** | Agent only sees page 1 of a 50-page doc | Pagination loop or chunked tool calls |
| **Stale context / lost history** | Multi-turn session, prior turns dropped | Redis session store with rolling summary |

**2. Detect uncertainty at each step:**
- Structured tool output schemas (JSON with `status: success | empty | error` field) let the orchestrator branch on outcome rather than rely on the LLM parsing failure prose.
- Confidence signals: cosine similarity score from retrieval, HTTP status codes, empty list detection.

**3. Respond proportionally:**
- **Low severity (empty result):** retry with query rewriting (HyDE, synonym expansion), then fall back to BM25 keyword search.
- **Medium severity (ambiguous intent):** emit a structured clarifying question from the orchestrator before proceeding; limit to one clarification per turn to avoid interrogation loops.
- **High severity (critical data missing):** halt the agent, surface the gap to the user/HITL reviewer with a structured explanation — `"I need X to proceed; here's what I have so far"`.
- **Unrecoverable (persistent tool failure):** write checkpoint state to Redis/Postgres, escalate to HITL via LangGraph `interrupt_before`, allow human to supply missing data or abort.

**4. Prompt-level signaling:**
Instruct the LLM to use a structured `MISSING_INFO` action type in its ReAct output rather than guessing:
```
Thought: I need the user's account ID but it wasn't provided.
Action: MISSING_INFO
Action Input: {"missing": "account_id", "reason": "required for billing lookup"}
```
The orchestrator catches `MISSING_INFO` actions, routes to clarification, and resumes after the human responds.

### Example / Tradeoff
**Support-ticket agent (LangGraph):** When the agent calls `lookup_order(order_id)` and the CRM returns `{"status": "not_found"}`, the orchestrator checks the action result, increments a `missing_count` counter, and:
1. Tries `lookup_order_by_email(customer_email)` as fallback.
2. If that also fails, emits `interrupt_before` with a message to the human queue: "Order not found by ID or email — please verify the order number with the customer."

Without this, a naive agent might hallucinate an order status or loop indefinitely retrying the same failed call.

**Tradeoff:** Aggressive clarification (ask before every ambiguity) kills UX — users hate being interrogated. Set a confidence threshold: only ask when the agent's tool results have a cosine score < 0.65 *and* the action is irreversible (e.g., send email, update record). For low-stakes actions, allow the agent to proceed with the best available information and log the uncertainty.

---

## Verbal script

**Opening (30s):**
"Partial observability is one of the core challenges that separates toy agents from production ones. In the real world, the agent never has perfect information — tools return empty results, users give ambiguous instructions, APIs time out. My approach is to classify the type of missing information and respond proportionally, rather than letting the LLM guess or loop."

**Core explanation (2–3 min):**
"I'd start by categorizing the gap. Ambiguous user intent is different from an empty tool result, which is different from a hard API failure. For each type, I use a different mitigation.

For ambiguous intent, I have the orchestrator emit a single structured clarifying question before any tool calls — not the LLM free-forming a question, but the orchestrator detecting that a required parameter is missing from the parsed intent.

For empty tool results, I retry with query rewriting — synonyms, HyDE-style hypothesis expansion, or falling back from dense to BM25 hybrid search. If the retry also fails, I escalate rather than proceed.

For tool errors or timeouts, I use exponential backoff with a max of three retries in the orchestrator code, then checkpoint state and route to HITL via something like LangGraph's `interrupt_before`.

The key pattern across all of these is structured tool output schemas — I want the orchestrator to branch on a `status` field, not have the LLM parse failure prose. And I give the LLM a `MISSING_INFO` action type in its ReAct format so it can signal uncertainty explicitly rather than hallucinating a plausible answer."

**Tradeoff / production angle (1 min):**
"The main tension is between user experience and safety. If you ask for clarification too aggressively — every time the agent is less than 90% confident — users feel interrogated and abandon the session. So I tune the threshold: only trigger clarification when the action is irreversible *and* confidence is below a defined threshold, like cosine < 0.65 on retrieval. For low-stakes, reversible actions, I let the agent proceed and log the uncertainty for offline review. And I always preserve checkpoint state before any irreversible action so a human can resume from the last safe point."

**Wrap-up (30s):**
"In short: classify the gap, respond proportionally — retry for empty results, clarify for ambiguous intent, escalate for critical missing data — and use structured orchestrator control rather than hoping the LLM handles uncertainty gracefully on its own. Happy to go deeper on any of the specific patterns."

---

## Pitfalls

- **Mistake:** Saying "the agent will ask the user if it doesn't know" without specifying how or when — **Better:** Describe the concrete trigger (structured missing parameter detection, cosine threshold, `MISSING_INFO` action type) and limit to one clarification per turn to avoid interrogation loops.
- **Mistake:** Treating all missing-information scenarios identically (always retry, or always escalate) — **Better:** Classify by severity and reversibility: empty retrieval result → retry with query rewriting; ambiguous intent on irreversible action → clarify; persistent tool failure → checkpoint + HITL escalation.
- **Mistake:** Letting the LLM parse tool error prose and decide what to do — **Better:** Enforce structured tool output schemas with a `status` field so the orchestrator branches deterministically on success/empty/error, not based on the LLM's interpretation of an error message.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q10: Design a safe and debuggable agent loop](03-010-design-a-safe-and-debuggable-agent-loop.md) | Safe loop design includes partial observability handling |
| [Q11: Termination conditions in long-running agents](03-011-termination-conditions-in-long-running-agents.md) | Missing information can trigger a stuck-detection termination path |
| [Q29: Human-in-the-loop patterns — when trigger human review](03-029-human-in-the-loop-patterns-when-trigger-human-review.md) | HITL is the escalation path for unrecoverable missing information |

---

## One-liner recall

> Classify missing information by type (ambiguous intent / empty result / tool failure / stale context), respond proportionally (clarify once / retry with rewriting / checkpoint + HITL), and enforce this in the orchestrator via structured tool schemas and a `MISSING_INFO` action type — never let the LLM guess when the data is absent.
