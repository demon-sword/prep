# Generated code gets executed — prevent malicious code?

**Category:** 08-safety-guardrails
**Question #:** 010
**Source section:** §10 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
This is the highest-blast-radius question in the safety category, and the interviewer is checking whether you reach for **isolation** or for **inspection**. Weak candidates answer with a filter — "I'd scan the code for dangerous imports." Strong candidates answer with a sandbox, and treat static analysis as a cheap pre-filter layered on top, never as the control. The question also probes whether you understand that generated code is untrusted *regardless of who prompted it*, because indirect prompt injection means the attacker may be a document in your index rather than the user in front of you.

### Trigger phrases
- "What happens if the model generates code that gets executed?"
- "You're building a data-analysis agent that runs Python — how do you make that safe?"
- "How do you sandbox an LLM's tool calls?"
- "The agent can run shell commands. What's your threat model?"

### What it tests
Whether you default to containment over inspection, and can specify a concrete isolation boundary — network, filesystem, syscalls, resources, identity — rather than gesturing at "we'd sandbox it."

---

## Answer

### Concept
Treat every byte of model-generated code as **untrusted input from a hostile source**, and make the execution environment incapable of causing harm rather than trying to predict which code is harmful. Static inspection of generated code is undecidable in the general case and trivially defeated by obfuscation (`getattr(__builtins__, 'ev'+'al')`), so it can be a cheap pre-filter but never the control. The control is the sandbox boundary. The second half of the concept: the code is untrusted even when the user is trusted, because with indirect prompt injection the effective author of that code may be a poisoned document that your retriever pulled into context.

### Mechanism

**Layer 0 — never execute in-process.** No `eval`, no `exec`, no `subprocess` in the application runtime. An in-process `eval` hands the attacker your service's memory, environment variables, database connections, and cloud credentials in one step. This is the single most common real-world mistake and it is unrecoverable.

**Layer 1 — the isolation boundary.** Ordered by strength:

| Mechanism | Isolation strength | Startup | Notes |
|---|---|---|---|
| In-process `eval` | **None** | 0 ms | Never. Full compromise of the host service. |
| Subprocess + `seccomp` | Weak–medium | ~5 ms | Shares the kernel; syscall filtering only |
| Container (Docker) + hardening | Medium | ~100–500 ms | Shared kernel — a kernel exploit escapes |
| gVisor (userspace kernel) | Strong | ~150–500 ms | Intercepts syscalls; much smaller kernel attack surface |
| Firecracker microVM | Strongest | ~125 ms | Hardware-virtualised; separate kernel |

For anything running third-party or internet-facing workloads, a microVM or gVisor is the defensible answer; a plain container is a shared-kernel boundary and a kernel CVE walks straight through it.

**Layer 2 — harden inside the boundary.** The sandbox type is necessary but not sufficient. Every one of these matters:
- **No network egress by default.** This is the highest-value single control — it converts "attacker exfiltrates your data" into "attacker prints something to a log." Where the workload genuinely needs the network, use a strict destination allowlist through an egress proxy, never a blanket `--net=host`.
- **Block the cloud metadata endpoint** (`169.254.169.254`). On a default cloud VM this is how a sandbox escape becomes an IAM credential theft. It must be blocked explicitly; "no egress" rules that only cover the public internet routinely miss it.
- **Read-only root filesystem** with a small `tmpfs` scratch mount, mounted `noexec` where possible.
- **Non-root user**, `--cap-drop=ALL`, `--security-opt=no-new-privileges`, and a `seccomp` profile.
- **Hard resource limits:** CPU shares, memory ceiling, PID limit (a fork bomb is three characters), and a wall-clock timeout enforced by the *orchestrator*, not by the sandboxed process.
- **One container per request, destroyed after use.** Reuse leaks state between users and turns a single successful injection into a persistent foothold.
- **No secrets in the environment.** The sandbox gets data, never credentials. If the code must reach a service, proxy the call from outside the boundary and inject the credential there.

**Layer 3 — the LLM-specific controls.** These sit *on top of* the sandbox, never instead of it:
- **Import/call allowlist and lightweight static analysis** before execution — cheap, catches accidental damage and unsophisticated attempts, and gives you a useful audit signal. Treat every hit as telemetry, not as your security boundary.
- **Human approval gate for irreversible actions.** Reading a dataframe is not the same as `DROP TABLE`, sending an email, or moving money. Anything outside the sandbox that has real-world side effects needs an out-of-band confirmation step that the model cannot itself satisfy.
- **Privilege separation on tools.** The orchestrator, not the model, decides which tools exist. An injected instruction to call `delete_account()` is inert if that tool was never in the allowlist for this session.
- **Audit-log every executed program** with its full source, the session and trace ID, and its output. When something goes wrong this is the only artifact that lets you reconstruct what ran.

### Example / Tradeoff

**Concrete incident pattern:** a data-analysis agent let users upload a CSV and asked the model to write pandas code to answer questions about it. The CSV's column *headers* contained an injection payload. The generated code — which passed an import allowlist, because it imported only `pandas` and `os` — read `os.environ` and wrote the contents into the "analysis result" that was returned to the user. Two failures compounded: secrets were present in the sandbox environment at all, and the *output* path was trusted. The fix was environment scrubbing plus treating tool output as untrusted data on the way back, not just on the way in.

**The core tradeoff is isolation strength versus latency and cost.** A Firecracker microVM per request costs roughly 125 ms of startup and real infrastructure complexity; a hardened container is faster to build and operate but shares the kernel. For an internal tool run by authenticated employees against trusted data, a hardened container with no egress is usually a defensible risk decision. For anything public-facing or handling untrusted documents, the microVM is the answer — and at that point the honest engineering question is **build versus buy**, since the major providers now ship hosted code-execution sandboxes with this hardening already done. Building your own sandbox is a security-engineering project, not a feature; unless isolation is your differentiator, using a managed one is usually the better call.

**Real tools:** gVisor, Firecracker, Docker with `seccomp`/`cap-drop`, `nsjail`, E2B, Modal, and the hosted code-execution tools offered by the major model providers.

---

## Verbal script

**Opening (30s):**
"My first move is to reframe it: I don't try to detect malicious code, I make the execution environment incapable of doing damage. Static analysis of generated code is undecidable in general and trivially beaten by string obfuscation, so it's a useful cheap pre-filter and a good audit signal, but it can never be the control. The control is the sandbox boundary. And I treat the code as untrusted even when I trust the user — because with indirect prompt injection, the real author might be a poisoned document my retriever pulled in."

**Core explanation (2–3 min):**
"Layer zero is the non-negotiable one: never `eval` or `exec` in the application process. That hands an attacker your environment variables, your DB connections and your cloud credentials in a single step, and there's no recovering from it.

Then the isolation boundary. A plain Docker container shares the host kernel, so a kernel CVE escapes it. For untrusted workloads I want either gVisor, which puts a userspace kernel in front of the syscall interface, or a Firecracker microVM, which gives you hardware virtualisation and a separate kernel at around 125 milliseconds of startup. That's the defensible answer for anything internet-facing.

Inside the boundary, the highest-value single control is no network egress by default — that turns 'attacker exfiltrates your customer data' into 'attacker prints something to a log.' If the workload genuinely needs network access I put a destination allowlist behind an egress proxy. I also explicitly block the cloud metadata endpoint at 169.254.169.254, because that's the path that turns a sandbox escape into stolen IAM credentials, and generic egress rules often miss it. Beyond that: read-only root filesystem with a small tmpfs scratch, non-root user, drop all capabilities, no-new-privileges, a seccomp profile, and hard CPU, memory, PID and wall-clock limits enforced by the orchestrator rather than inside the sandbox. One container per request, destroyed afterwards — reuse leaks state between users. And critically, no secrets in the environment: the sandbox gets data, never credentials. If the code needs to reach a service, I proxy that call from outside the boundary.

On top of all that I add the LLM-specific layer: an import allowlist and lightweight static analysis as a pre-filter and telemetry source, privilege separation so the orchestrator decides which tools exist rather than the model, a human approval gate for anything irreversible, and audit logging of every program that ran with its full source and trace ID."

**Tradeoff / production angle (1 min):**
"The tradeoff is isolation strength against latency and operational cost. A microVM per request is roughly 125 milliseconds of cold start plus real infrastructure work. For an internal tool used by authenticated employees on trusted data, a hardened container with no egress is a reasonable risk decision. For anything public-facing or touching untrusted documents, I want the microVM.

At that point the honest question is build versus buy. The major providers now ship hosted code-execution sandboxes with this hardening already done. Building your own is a security-engineering project with a long tail of CVEs, not a feature — so unless sandboxing is your differentiator, I'd use a managed one and spend the team's time on the application."

**Wrap-up (30s):**
"So the short version: never execute in-process, isolate in gVisor or a microVM, default to zero network egress and block the metadata endpoint, no credentials inside the boundary, one disposable container per request, and layer allowlisting plus a human gate for irreversible actions on top. Detection is a pre-filter and an audit signal — containment is the control. Happy to go deeper on the egress proxy design or on how I'd handle tool output as untrusted data on the way back."

---

## Pitfalls

- **Mistake:** "I'd scan the generated code for dangerous functions like `os.system` and `eval` before running it" — **Better:** Lead with containment, not inspection. Static detection is undecidable in general and defeated by trivial obfuscation like `getattr(__builtins__, 'ev'+'al')`. An allowlist is a cheap pre-filter and a useful audit signal layered *on top of* a sandbox; it is never the security boundary.
- **Mistake:** Saying "I'd run it in a Docker container" and stopping there — **Better:** Specify what the boundary actually enforces: containers share the host kernel, so name gVisor or Firecracker for untrusted workloads, and enumerate the hardening — no network egress, blocked metadata endpoint, read-only rootfs, non-root, dropped capabilities, seccomp, CPU/memory/PID/wall-clock limits, one disposable container per request.
- **Mistake:** Leaving credentials in the sandbox environment because "the code is only doing data analysis" — **Better:** The sandbox receives data, never secrets. Any call needing a credential is proxied from outside the boundary. Environment variables are the first thing an injected payload reads, and a single successful injection turns into full credential theft.
- **Mistake:** Assuming the risk only exists when the user is untrusted — **Better:** Indirect prompt injection means generated code may be authored by a poisoned document in your RAG index, not by the person typing. Treat generated code as hostile regardless of who prompted it, and treat the sandbox's *output* as untrusted data too, since exfiltration usually rides back out on the result path.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q4: Protect against prompt injection and jailbreaking?](08-004-protect-against-prompt-injection-and-jailbreaking.md) | prerequisite — injection is how hostile code gets authored in the first place |
| [Q9: Red-team an LLM system?](08-009-red-team-an-llm-system.md) | related — tool abuse and excessive agency are a core red-team attack class |
| [Q25: Biggest security risks with tool-using agents?](03-025-biggest-security-risks-with-tool-using-agents.md) | related — code execution is the highest-blast-radius tool an agent can hold |

---

## One-liner recall

> Contain, don't detect: never `eval` in-process, isolate in gVisor or a Firecracker microVM, default to zero network egress with the cloud metadata endpoint explicitly blocked, keep all credentials outside the boundary, use one disposable container per request with hard CPU/memory/PID/wall-clock limits, and layer an import allowlist, orchestrator-side tool privilege separation, a human gate for irreversible actions, and full audit logging on top — because generated code is untrusted even when the user is trusted.
