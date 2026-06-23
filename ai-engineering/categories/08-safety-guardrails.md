# 08. Safety & Guardrails — AI Engineering Interview Category

Covers how to make LLM-powered systems safe, reliable, and compliant in production — from prompt injection and jailbreak defenses to PII handling, bias mitigation, and red-teaming. A growing priority for senior roles and any regulated-domain position.

---

## Interview signals

| You hear… | This category |
|-----------|---------------|
| "how do you prevent the model from saying harmful things?" | guardrail architecture |
| "what would you do if a user tried to jailbreak your chatbot?" | prompt injection / jailbreak defense |
| "how do you handle PII in prompts and logs?" | data privacy in LLM pipelines |
| "walk me through red-teaming an LLM system" | adversarial evaluation |
| "how do you balance safety with usefulness?" | harm-helpfulness tradeoff |
| "what happens if the model generates code that gets executed?" | code execution safety |

---

## Mental model

Strong candidates understand that safety is **layered defense-in-depth, not a single check**. A production LLM system needs guardrails at every stage: input sanitization before the LLM call, grounding constraints in the prompt, output classifiers after generation, and PII scrubbing in logs. Weak candidates treat safety as a single system prompt instruction ("just say you won't do harmful things") and miss that adversaries actively probe those instructions. The real challenge is maintaining this stack without degrading helpfulness — every guardrail layer adds latency and can create false positives that break legitimate user flows. Strong candidates can articulate the harm-helpfulness tradeoff concretely (e.g., "a 95th-percentile policy threshold blocks 0.3% of legitimate queries — here's how we tune that") and have done red-team exercises to find failure modes before they reach production.

---

## Sub-topics

### 1. Input & Output Guardrails
**When:** "how do you prevent harmful outputs", "guardrails architecture", "how do you detect policy violations"
**What:** Input classifiers screen user messages before the LLM call; output classifiers screen model responses before they reach users; both operate as middleware with configurable thresholds.
**Key questions:**
- [Q1: When and how implement LLM guardrails?](../answers/08-001-when-and-how-implement-llm-guardrails.md)
- [Q2: Minimize harmful outputs while staying useful?](../answers/08-002-minimize-harmful-outputs-while-staying-useful.md)
- [Q3: Detect policy violations / offensive content?](../answers/08-003-detect-policy-violations-offensive-content.md)

### 2. Prompt Injection & Jailbreak Defense
**When:** "what if a user tries to override the system prompt", "prompt injection", "jailbreaking", "adversarial users"
**What:** Prompt injection embeds adversarial instructions in user input or retrieved content to override system behavior; jailbreaking uses crafted prompts to bypass safety training; both require structural defenses beyond system prompt instructions.
**Key questions:**
- [Q4: Protect against prompt injection and jailbreaking?](../answers/08-004-protect-against-prompt-injection-and-jailbreaking.md)
- [Q10: Generated code gets executed — prevent malicious code?](../answers/08-010-generated-code-gets-executed-prevent-malicious-code.md)

### 3. Privacy, PII & Compliance
**When:** "how do you handle sensitive data", "HIPAA/GDPR for LLM apps", "PII in prompts", "data in logs"
**What:** PII must be detected and redacted or pseudonymized at ingestion, query time, and in log pipelines before it reaches the LLM or persists in storage; Constitutional AI and alignment provide the policy framework for what models should and shouldn't do.
**Key questions:**
- [Q7: Data privacy and PII in prompts and logs?](../answers/08-007-data-privacy-and-pii-in-prompts-and-logs.md)
- [Q6: Constitutional AI and alignment?](../answers/08-006-constitutional-ai-and-alignment.md)

### 4. Red-Teaming & Bias
**When:** "how do you find safety failures before launch", "red team", "bias in the model", "responsible AI"
**What:** Red-teaming is structured adversarial evaluation where human or automated probers systematically attempt to elicit harmful outputs; bias audits measure demographic disparities in model outputs and training data.
**Key questions:**
- [Q9: Red-team an LLM system?](../answers/08-009-red-team-an-llm-system.md)
- [Q8: Bias in training data and generated content?](../answers/08-008-bias-in-training-data-and-generated-content.md)

---

## Decision framework

```
Need to add safety to an LLM system:

Step 1 — Scope the threat model
  Is user input adversarial? → add input classifier (Llama Guard / Perspective API)
  Does the model use tools or execute code? → add sandboxed execution + output schema validation
  Is PII in scope? → add Presidio redaction at ingestion + query + log layers

Step 2 — Choose guardrail placement
  If latency SLO is tight (<200ms) AND risk is medium:
    → async output classifier (non-blocking, flag for review)
  If domain is regulated (healthcare, finance, legal) OR risk is high:
    → synchronous blocking guardrail (add ~50–150ms latency)
  If volume is very high (>10K RPS):
    → lightweight rule-based pre-filter first, classifier only on uncertain cases

Step 3 — Tune the harm-helpfulness tradeoff
  Start conservative (high threshold → low FP rate)
  Measure false positive rate on representative traffic
  Lower threshold until FP rate < 0.5% on legitimate queries
  Monitor separately: block rate, bypass rate (red-team periodic checks)

Step 4 — Prompt injection defense
  RAG pipeline? → sanitize retrieved content before context injection
  Tool-using agent? → allowlist tools + validate tool outputs as data not instructions
  User-facing? → delimiter fencing + injection classifier on input

Step 5 — Red-team before launch
  Automated: PyRIT / Garak / Promptbench for scale
  Human: domain expert red-teamers for nuanced failures
  Iterate until zero critical failures on taxonomy; re-test after every model update
```

---

## Common mistakes

| Mistake | What to say instead |
|---------|---------------------|
| "We added a system prompt saying 'don't do harmful things'" | System prompts are easily overridden; use layered middleware classifiers (Llama Guard, Perspective API) on top of prompt-level instructions |
| "We use content filtering — the API provider handles it" | Provider filters catch egregious content; domain-specific policy violations (brand risk, competitive mentions, regulatory) require custom classifiers tuned on your data |
| "Prompt injection just means checking for keywords like 'ignore previous instructions'" | Keyword filtering misses encoded, paraphrased, and indirect injection; use an injection classifier + structural prompt delimiters + treat all retrieved content as untrusted data |
| "We log all conversations for debugging" | Raw conversation logs may contain PII — Presidio redaction must run before logs are written to any store; retention policy and access controls must be documented for GDPR/HIPAA |
| "Red-teaming is just asking the model to do bad things" | Production red-teaming is structured: build a taxonomy of harm categories, use automated tools (PyRIT, Garak) for scale, human experts for nuanced cases, and track coverage across the taxonomy |
| "Bias is a training problem, not a deployment problem" | Bias manifests in outputs regardless of training — measure subgroup performance on your specific task and domain, monitor for drift, and implement threshold adjustment or re-weighting per segment |

---

## Question checklist

| # | Question | Difficulty signal | Status |
|---|----------|-------------------|--------|
| 1 | When and how implement LLM guardrails? | M | `todo` |
| 2 | Minimize harmful outputs while staying useful? | M | `todo` |
| 3 | Detect policy violations / offensive content? | M | `todo` |
| 4 | Protect against prompt injection and jailbreaking? | S | `todo` |
| 5 | Handle exceptions in GenAI applications? | E | `todo` |
| 6 | Constitutional AI and alignment? | S | `todo` |
| 7 | Data privacy and PII in prompts and logs? | M | `todo` |
| 8 | Bias in training data and generated content? | M | `todo` |
| 9 | Red-team an LLM system? | S | `todo` |
| 10 | Generated code gets executed — prevent malicious code? | S | `todo` |

---

## One-page summary

- **Defense-in-depth:** Safety requires layers — input classifier → grounding prompt → output classifier → async faithfulness check → PII-scrubbed logs. No single layer is sufficient.
- **Prompt injection is structural, not lexical:** Delimiter fencing + treating retrieved content as untrusted data + a dedicated injection classifier beats keyword blocklists.
- **Harm-helpfulness tradeoff is tunable:** Measure FP rate on representative traffic; tune thresholds so < 0.5% of legitimate queries are blocked; monitor bypass rate separately via periodic red-team checks.
- **PII must be scrubbed at every boundary:** Presidio (or equivalent) runs at ingestion, at query time, and before logs are written — not just at one point.
- **Red-teaming is structured evaluation:** Build a harm taxonomy, use automated tools (PyRIT, Garak) for coverage, human experts for nuance, re-test after every model or prompt update — not a one-time exercise.
