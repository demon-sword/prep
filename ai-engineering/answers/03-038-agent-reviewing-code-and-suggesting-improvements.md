# Agent reviewing code and suggesting improvements

**Category:** 03-agents-tool-use
**Question #:** 038
**Source section:** §3 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
This is a design prompt that tests whether you can translate abstract agent concepts into a concrete, production-shaped system. Interviewers want to see: tool selection discipline (which capabilities does the agent actually need?), safety thinking (it touches code — what prevents it from doing damage?), practical awareness of cost/latency (LLM calls per diff can get expensive), and evaluation instincts (how do you know if its suggestions are good?).

### Trigger phrases
- "Design an agent that reviews code and suggests improvements."
- "Walk me through a code-review agent — how would you build and deploy it?"
- "How would you build an AI-powered code reviewer for a GitHub pull request?"
- "We want an agent that catches bugs and style issues in PRs — how would you architect it?"

### What it tests
Ability to scope a realistic multi-tool agent, enforce safety/cost discipline on code-touching systems, and define a concrete eval framework for a non-deterministic output.

---

## Answer

### Concept
A code-review agent is a read-only LLM loop that ingests a diff or file, runs static analysis tools to gather structured signals, then synthesizes human-readable review comments with actionable suggestions — all without modifying files or executing untrusted code. "Read-only" is the key design constraint that keeps it safe.

### Mechanism

**Trigger and scope**
The agent is triggered by a pull-request webhook (GitHub Actions, GitLab CI). It receives the PR diff — not the entire repo — as its primary context. Scope is bounded: it reviews only changed files and their immediate imports.

**Tool layer (all read-only)**
| Tool | Purpose | Schema |
|------|---------|--------|
| `get_diff` | Fetch PR diff as unified patch | `{pr_id, repo}` → `{files: [{path, patch}]}` |
| `get_file` | Read full file for context around a hunk | `{repo, path, sha}` → `{content}` |
| `run_linter` | Run language linter (ruff, eslint) on diff | `{language, code}` → `{violations: [{line, rule, msg}]}` |
| `run_sast` | Static security scan (Bandit, Semgrep) | `{language, code}` → `{findings: [{severity, line, cwe}]}` |
| `search_docs` | Retrieve relevant style-guide / architecture docs | `{query}` → `{chunks}` |

All tool calls are sandboxed: linters run in a Docker container with `--network=none` and read-only bind mounts. No code is executed; only parsed/statically analysed.

**Agent loop (LangGraph ReAct)**
```
1. get_diff → structured file list
2. For each changed file:
   a. get_file (context around hunks)
   b. run_linter + run_sast (parallel)
   c. LLM synthesizes structured comment objects:
      {file, line, severity, category, message, suggestion}
3. Aggregate comments → deduplicate → rank by severity
4. If comment count > threshold → request human reviewer
5. Post comments via GitHub API (write tool, called once at end)
```

The LLM is only reasoning; it cannot push commits. The GitHub post is a single write call, gated after synthesis.

**Model tiering**
- Linter/SAST violations: a small fast model (low cost, format is structured)
- Architectural / design feedback: a frontier model (nuanced reasoning)
- Token budget: diff chunked to ≤4K tokens per file; larger files use sliding window with overlap

**Output format**
```json
{
  "file": "src/auth/token.py",
  "line": 42,
  "severity": "high",
  "category": "security",
  "message": "JWT secret read from env without fallback guard — will panic on missing key.",
  "suggestion": "Use `os.environ.get('JWT_SECRET') or raise ValueError(...)` and validate at startup."
}
```
Structured output enforced via `response_format=json_schema` so the GitHub posting tool can parse reliably.

### Example / Tradeoff

**Production example — GitHub Copilot / CodeRabbit pattern**
CodeRabbit and similar tools use a pipeline close to this: diff → file context → parallel static analysis → LLM summary → PR comment thread. They process ~200–500 files/PR with costs in the $0.05–$0.30/PR range using model tiering.

**Key tradeoffs**

| Axis | Conservative | Aggressive |
|------|-------------|------------|
| Scope | Changed files only | Full repo context |
| LLM call count | 1 call per file | N calls per hunk |
| Cost/PR | $0.10–$0.35 | $2–$10+ |
| False positive rate | Higher (no full-context) | Lower |
| Latency | <60s | 2–5min |

**When the agent should NOT auto-post**
- Security findings with CVE severity ≥ HIGH → route to HITL (security team Slack alert)
- Comment count > 20 → collapse to summary + link to full report (avoids notification flood)
- Draft PRs → skip entirely

**Eval framework**
- Precision@k: of the top-k comments, how many are correct? (Manual label 50 PRs/week)
- False negative rate: run on PRs where bugs were later reported in production
- Developer acceptance rate: % of suggestions acted upon (accept/apply vs dismiss)
- Regression: golden diff set with known bugs — verify agent flags them across model versions

---

## Verbal script

**Opening (30s):**
"I'd approach this as a read-only ReAct agent that combines static analysis tools with LLM synthesis — the key design principle is that the LLM never executes code or writes to the repo; it only reasons. Let me walk through the architecture."

**Core explanation (2–3 min):**
"The trigger is a PR webhook from GitHub Actions. The agent gets the unified diff, not the whole repo — that's important for cost and latency. It has four tools: `get_diff`, `get_file` for surrounding context, `run_linter` for structured violations like ruff or eslint, and `run_sast` for security patterns via Semgrep or Bandit. Both linters run in Docker containers with `--network=none` — read-only, sandboxed, no code execution.

The LLM loop works per file: fetch the file, run linter and SAST in parallel, then ask the LLM to synthesize structured comment objects — file, line, severity, category, message, suggestion. I'd enforce JSON schema output so the downstream GitHub posting tool can parse reliably without fragile string parsing.

For model tiering: I'd use a small fast model for reformatting linter output, and a frontier model only for architectural or design-level feedback that requires real reasoning. That keeps cost in the $0.05–$0.15/PR range."

**Tradeoff / production angle (1 min):**
"The main tradeoffs are scope versus cost. If I only review changed files, I miss cross-file issues — a function signature change that breaks callers elsewhere. If I load full repo context, costs spike to $1–5/PR and latency blows out. The pragmatic middle is changed files plus their direct imports. I'd also add an auto-suppress rule: if the agent generates more than 20 comments, collapse them into a summary rather than flooding the PR thread — that's a real developer experience failure I've seen with noisy tools.

On safety: security findings with CVE severity HIGH or above should route to HITL — a Slack alert to the security team — rather than auto-posting. And I'd skip draft PRs entirely.

For eval, I'd track developer acceptance rate (what % of suggestions are applied), false negative rate against bugs that reached production, and run a golden diff set regression on every model update."

**Wrap-up (30s):**
"So the architecture is: PR webhook → read-only tool loop → LLM synthesis with structured output → single gated write to GitHub. The discipline is: the LLM reasons, the orchestrator enforces limits, and nothing executes untrusted code. Happy to go deeper on the sandboxing, eval framework, or multi-language support."

---

## Pitfalls

- **Mistake:** Designing the agent to also apply fixes automatically (auto-commit) — **Better:** Explain that auto-applying changes on untrusted code is a serious security and correctness risk; the agent should only suggest, and a human (or a separate opt-in "apply fix" flow with HITL confirmation) makes the change.
- **Mistake:** Sending the entire repository as context to reduce false negatives, without discussing cost or latency impact — **Better:** Start with diff + direct imports; quantify cost at $0.05 vs $1–5/PR and discuss the scope/cost/FN-rate triangle explicitly.
- **Mistake:** Treating the agent's output as always correct and auto-posting every comment — **Better:** Add a confidence gate and comment-count cap; describe the developer acceptance rate metric and the noise problem with over-eager review bots.
- **Mistake:** Skipping the eval framework entirely — **Better:** Immediately mention precision@k, developer acceptance rate, and a golden diff regression set; reviewers know non-deterministic outputs are hard to eval and want to see you've thought about it.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q8: Walk through a production-ready agent architecture](03-008-walk-through-a-production-ready-agent-architecture.md) | Core architecture pattern this design extends |
| [Q23: Sandbox tool execution safely](03-023-sandbox-tool-execution-safely.md) | Sandboxing linters/SAST in Docker — the safety layer |
| [Q22: Tool schemas that reduce hallucinated actions](03-022-tool-schemas-that-reduce-hallucinated-actions.md) | Structured output schema discipline for review comments |

---

## One-liner recall

> A code-review agent is a read-only ReAct loop — diff in, linter+SAST tools run in Docker, LLM synthesizes structured comment objects, single gated write to GitHub — with model tiering, comment-count caps, HITL for high-severity findings, and dev acceptance rate as the primary eval metric.
