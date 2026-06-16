# Planning failures hardest to detect in production?

**Category:** 03-agents-tool-use
**Question #:** 017
**Source section:** §3 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
This question probes whether you have shipped agentic systems and lived with their failure modes beyond the demo. Planning failures are uniquely insidious because the agent often appears to be working — it's calling tools, emitting logs, and returning outputs — while silently doing the wrong thing. Interviewers want to see that you can distinguish superficial operational health from actual goal fidelity.

### Trigger phrases
- "What goes wrong with agents in production that your tests didn't catch?"
- "What planning failures are hardest to observe or debug?"
- "How do you know your agent is actually making progress?"
- "Walk me through a time an agent looked healthy but was producing bad results."

### What it tests
Production observability depth: whether you instrument agents to detect semantic drift, not just operational errors.

---

## Answer

### Concept
The hardest planning failures to detect are those where the agent is **operationally healthy but semantically stuck or wrong**: it emits no exceptions, calls real tools, and produces plausible output — yet it is not advancing toward the actual goal. These are distinct from crashes or timeouts, which surface immediately in logs.

### Mechanism
Four failure classes that consistently evade naive monitoring:

| Failure class | Why it's invisible | Detection signal |
|---|---|---|
| **Goal drift** | Agent re-interprets the original goal across turns; each individual step looks locally reasonable | Compare current sub-goal embedding to original goal embedding every N steps; cosine drift > 0.15 → alert |
| **Sycophantic looping** | Agent rephrases the same failed action after tool returns an error, fooling itself the plan changed | Fingerprint (hash) each (action, tool, args) tuple; identical hash twice → stuck |
| **Silent tool success / semantic failure** | Tool returns HTTP 200, DB write succeeds, but the retrieved data is stale or wrong domain — agent treats it as ground truth | Validate tool output schema + spot-check a sample (e.g. embedding similarity of returned doc to query) |
| **Over-decomposition with local optimality** | Agent decomposes a 2-step task into 12 steps; achieves all 12 — but the high-level goal remains unmet because decomposition was wrong | End-to-end acceptance check on the final state, not just step-level completion |

**Production instrumentation pattern (LangSmith / OpenTelemetry):**
```
per_step_span:
  - step_index, action_type, tool_name, args_hash
  - goal_embedding_cosine_to_original        ← semantic drift
  - unique_action_fingerprints_last_5_steps  ← repetition loop
  - tool_output_schema_valid                 ← silent bad data
  - time_since_last_state_change             ← progress proxy
```
Set alert thresholds:
- `cosine_drift > 0.15` → warn + HITL gate
- `repeated_fingerprint` within 3 steps → hard stop + escalate
- `no_new_db_state_changed` for 5+ steps → mark as stuck

### Example / Tradeoff
**Real pattern — support ticket agent:** The agent was tasked with "resolve ticket #4821 — customer can't log in." It correctly retrieved the user record, correctly called `check_auth_service`, got a 200 OK with `{"healthy": true}` (which was the auth service health check, not a per-user auth check — wrong tool interpretation), then synthesized "Auth service is healthy, ticket resolved" and closed the ticket. No exception, no alert. Detection: end-to-end acceptance test that actually attempted a login after the agent closed the ticket.

**Cost vs. detection coverage tradeoff:**
- Step-level hash fingerprinting: near-zero cost, catches ~60% of planning loops
- Goal embedding drift check per step: ~$0.001/step (1K tokens), catches semantic drift but not wrong tool selection
- End-to-end acceptance test on final state: most reliable but adds latency + cost; appropriate for high-stakes workflows (ticket closure, financial writes) not high-volume cheap tasks

---

## Verbal script

**Opening (30s):**
"I'd split planning failures into two buckets: operational failures — crashes, timeouts, tool errors — which are easy to detect, and semantic failures — where the agent is running fine but not actually achieving the goal. The second bucket is what makes production agents genuinely hard to operate, so I'll focus there."

**Core explanation (2–3 min):**
"There are four failure classes I've seen consistently slip through monitoring. First is **goal drift**: across many reasoning turns, the agent gradually re-interprets what it's solving for. Each individual step looks locally correct, but the overall trajectory diverges. You catch this by embedding the original goal and comparing it to the agent's current stated sub-goal every N steps — a cosine distance above ~0.15 is a red flag.

Second is **sycophantic looping** — the agent calls a tool, gets an error, rewords the exact same call with slightly different phrasing, and repeats. It looks like progress because actions are being taken, but it's spinning. I handle this by hashing `(action, tool, args)` tuples and short-circuiting if I see an identical fingerprint within the last 3–5 steps.

Third is **silent tool success with semantic failure**: the tool call returns HTTP 200 and writes to the DB, but it retrieved the wrong data — stale, wrong tenant, wrong schema field. The agent treats this as ground truth. This one requires output validation — schema checks minimum, spot-sample embedding similarity for high-stakes pipelines.

Fourth is **over-decomposition with local optimality**: the agent decomposes a two-step goal into twelve steps, achieves all twelve — but the original high-level goal is unmet because the decomposition was wrong from the start. The only reliable detection is an end-to-end acceptance test on the final state, not step-level completion."

**Tradeoff / production angle (1 min):**
"The tradeoff is instrumentation cost. Hash fingerprinting is cheap and catches a lot of loops. Goal drift embedding checks cost a small amount per step — worth it for long-running agents. End-to-end acceptance testing is the most reliable but adds latency, so I gate it on workflow type: anything that writes to an external system or closes a customer ticket gets a post-completion verification step."

**Wrap-up (30s):**
"The key principle is: don't just monitor for operational health — instrument for semantic progress. If your observability stack can only tell you 'no exceptions raised,' you'll miss the hardest failures. I'd add goal-drift checks and action fingerprinting as table stakes for any production agent."

---

## Pitfalls

- **Mistake:** Describing only operational failures (crashes, timeouts, tool 4xx/5xx errors) as "hard to detect" — **Better:** Distinguish operational health (easy to monitor) from semantic progress (hard to monitor); the hardest failures are when the agent is operationally healthy but goal-divergent.
- **Mistake:** Saying "just add logging at each step" without specifying *what* to log or how to detect stuck/drifting patterns — **Better:** Name specific signals: action fingerprint hashing for loop detection, goal-embedding cosine drift for semantic drift, end-to-end acceptance tests for over-decomposition failures.
- **Mistake:** Not mentioning the "silent tool success / semantic failure" class — **Better:** Call out that a 200 OK from a tool doesn't mean the agent got the right data; output schema validation and spot-sampling are necessary defenses.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q14: Detect and stop infinite planning loops?](03-014-detect-and-stop-infinite-planning-loops.md) | Same action-fingerprinting mechanism; Q14 focuses on the stop logic, Q17 on the detection taxonomy |
| [Q10: Design a safe and debuggable agent loop](03-010-design-a-safe-and-debuggable-agent-loop.md) | The observability layer (LangSmith spans, structured traces) is the foundation for detecting all four failure classes |
| [Q30: Monitor autonomous agent behavior in production](03-030-monitor-autonomous-agent-behavior-in-production.md) | Broader production monitoring; Q17 focuses specifically on planning-level semantic failures |

---

## One-liner recall

> The hardest planning failures are operationally silent: goal drift (embed the original goal, track cosine distance per step), sycophantic loops (hash action+args, short-circuit on repeat), silent bad data from tools (validate output schema), and over-decomposition (end-to-end acceptance test on final state, not step count).
