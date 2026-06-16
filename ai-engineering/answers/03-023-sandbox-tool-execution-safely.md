# Sandbox tool execution safely?

**Category:** 03-agents-tool-use
**Question #:** 023
**Source section:** §3 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
Interviewers ask this because tool-calling agents that execute code, run shell commands, or make write API calls are a significant production risk surface. The question probes whether you understand that security and safety are architectural concerns built into the agent loop — not afterthoughts. Strong candidates differentiate between sandboxing strategies by risk level, understand the performance cost of isolation, and know which off-the-shelf tooling to reach for.

### Trigger phrases
- "How do you safely run code an agent generates?"
- "What happens if an agent calls a destructive tool?"
- "How do you prevent an agent from doing something irreversible?"

### What it tests
Whether you can design a layered execution sandbox that balances agent autonomy against containment — with concrete tooling choices and risk-tier reasoning.

---

## Answer

### Concept
Sandboxing tool execution means running agent-issued tool calls in an isolated environment where the blast radius of a bad action (malicious code, runaway process, destructive write) is bounded and reversible. It is not a single technique — it is a **risk-tier framework**: read-only APIs need no sandbox, shell/code execution needs a container, financial/irreversible actions need a HITL gate regardless of sandbox.

### Mechanism

**Three-tier risk model:**

| Tier | Tool type | Sandbox approach |
|------|-----------|-----------------|
| **Low** | Read-only: web search, DB SELECT, knowledge base lookup | No container — validate inputs with jsonschema, enforce timeouts only |
| **Medium** | Stateful writes: DB INSERT/UPDATE, email send, file write | Docker container with network egress blocklist, filesystem mount limited to temp dir, timeout 30s |
| **High** | Code execution, shell commands, payment/delete operations | E2B / Modal ephemeral microVM, no persistent storage, CPU/memory limits, HITL confirmation before execution, result inspection before commit |

**Execution flow (medium/high tier):**
1. **Input sanitization** — validate tool args against JSON schema (required fields, allowed patterns); reject args containing SQL metacharacters, path traversal (`../`), shell metacharacters (`; |`).
2. **Container/VM spin-up** — E2B (`from e2b import Sandbox`) or Docker (`docker run --rm --network=none --memory=512m --cpus=0.5`). E2B cold-starts in ~200ms; Docker in ~500ms.
3. **Execute with timeout** — wall-clock cap (e.g., 30s). Kill on timeout; return structured `{"status": "timeout"}` to agent loop.
4. **Output capture + inspection** — capture stdout/stderr; strip secrets/PII from output before returning to the LLM context. Flag large outputs (>50KB) as potentially problematic.
5. **Idempotency check** — for write tools, record a `tool_call_id` + hash before execution; on retry, check if side-effect already committed before re-running.
6. **Audit log** — append `{run_id, tool, args_hash, result_summary, duration_ms}` to append-only log (S3/Postgres) for forensics.

### Example / Tradeoff

**E2B for code execution (GitHub Copilot Workspace pattern):**
```python
from e2b import Sandbox

async def run_code_safely(code: str, timeout: int = 30) -> dict:
    async with Sandbox(timeout=timeout) as sbx:
        execution = sbx.run_code(code)
        return {
            "stdout": execution.logs.stdout[:4096],  # cap output size
            "stderr": execution.logs.stderr[:2048],
            "exit_code": execution.exit_code,
        }
```
E2B spins up a gVisor-backed microVM per call, isolating filesystem, network, and process tree. Cost: ~$0.000225/min per VM. For 10K code executions/day at avg 5s each, cost is ~$0.19/day — negligible vs LLM token cost.

**Docker alternative (self-hosted):**
```bash
docker run --rm \
  --network=none \
  --memory=512m --memory-swap=512m \
  --cpus=0.5 \
  --read-only \
  --tmpfs /tmp:size=64m \
  my-sandbox-image python -c "$CODE"
```
`--network=none` blocks exfiltration. `--read-only` prevents filesystem persistence. Cold-start is ~500ms; acceptable if tool use is infrequent.

**Tradeoff:** E2B is managed and fast (~200ms cold-start) but is a vendor dependency and costs per minute. Docker is self-hosted and free but requires container management and has higher cold-start. For very high-frequency code execution (>1M/day), a warm pool of pre-started containers amortizes cold-start cost.

---

## Verbal script

**Opening (30s):**
"Sandboxing tool execution is one of those things that's easy to skip in a demo and catastrophic to skip in production. I think of it as a risk-tier problem: the right sandbox depends entirely on what damage a bad tool call can do — read-only lookups need only input validation, but any code execution or write operation needs real isolation."

**Core explanation (2–3 min):**
"I'd design three tiers. Tier one is read-only tools — web search, vector DB queries, SELECT statements. Here I just validate tool args against a strict JSON schema and enforce a timeout. No container needed; the blast radius is zero.

Tier two is stateful writes — INSERT/UPDATE, email sends, file writes. These get a Docker container with `--network=none` to block egress, a readonly filesystem except for a tmpfs at `/tmp`, and memory/CPU limits. The key detail is idempotency: I record a `tool_call_id` hash before execution, and on any retry I check whether the side-effect was already committed before re-running.

Tier three is the high-risk category: code execution, shell commands, payments, deletes. Here I use E2B or Modal — managed ephemeral microVMs that give me filesystem, network, and process isolation in about 200 milliseconds. Before the VM even starts, I apply input sanitization to reject path traversal, shell injection metacharacters, and SQL metacharacters. After execution, I cap stdout size, strip PII from the output, and write an append-only audit log entry before passing results back to the agent.

For truly irreversible actions — deleting records, sending external communications — I also require a HITL gate regardless of tier. The sandbox limits technical damage; HITL is the human check on logical errors."

**Tradeoff / production angle (1 min):**
"The main tension is latency vs isolation. E2B's 200ms cold-start is fine for background tasks but painful for interactive agents where users see each step. Warm container pools solve this at the cost of infrastructure complexity. The other tension is output size — a code execution might return megabytes of data; I always cap stdout and have the agent work with summaries, not raw output. And sandboxing doesn't eliminate prompt injection: a malicious document could inject instructions into the code the agent writes. Input sanitization and output inspection are both needed."

**Wrap-up (30s):**
"So the pattern is: classify tool risk tier → apply appropriate isolation → add idempotency for writes → HITL gate for irreversibles → audit log everything. Happy to go deeper on any tier or talk through how this integrates with the agent loop controller."

---

## Pitfalls

- **Mistake:** "I'd just run it in a subprocess with `subprocess.run()`" without mentioning network isolation, filesystem limits, or timeouts — **Better:** Explain that subprocess isolation on the host shares the same network and filesystem as the agent process; use Docker `--network=none` or E2B for real isolation, and always enforce a wall-clock timeout to prevent runaway processes.
- **Mistake:** Treating sandboxing as the only safety layer and ignoring input sanitization — **Better:** Explain that sandbox escapes are possible (gVisor is not impenetrable); input sanitization (schema validation, metacharacter rejection) is a defense-in-depth first layer that stops most attacks before code ever runs.
- **Mistake:** Forgetting idempotency on tool retries — **Better:** If the agent retries a write tool after a timeout, it may double-commit. Always record a `tool_call_id` hash before execution and check for existing side-effects before re-running.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q25: Biggest security risks with tool-using agents?](03-025-biggest-security-risks-with-tool-using-agents.md) | Follow-up — sandboxing is one mitigation layer in the broader security threat model |
| [Q24: Tool failures, retries, idempotency?](03-024-tool-failures-retries-idempotency.md) | Companion — retry safety depends on idempotency patterns built alongside sandboxing |
| [Q10: Design a safe and debuggable agent loop?](03-010-design-a-safe-and-debuggable-agent-loop.md) | Parent architecture — sandboxed tool execution is one component of the overall safe agent loop |

---

## One-liner recall

> Sandbox tool execution with a three-tier risk model: read-only tools need only schema validation + timeout; stateful writes get Docker with `--network=none` + idempotency checks; code/shell execution uses E2B ephemeral microVMs with input sanitization, output capping, and an append-only audit log — plus HITL gates for all irreversible actions.
