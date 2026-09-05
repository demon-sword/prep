# Can you describe the difference between GenAI and traditional programming for a real-world problem?

**Category:** 01-llm-fundamentals
**Question #:** 010
**Source section:** §1 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
This is a calibration question asked early in screens — interviewers want to confirm you can articulate the paradigm shift clearly to non-technical stakeholders and that you understand *when* GenAI is the right tool vs. overkill. It also probes whether you grasp the operational tradeoffs (stochastic outputs, cost, latency, hallucination risk) that come with the shift.

### Trigger phrases
- "Can you explain GenAI vs traditional programming for someone who isn't technical?"
- "When would you reach for an LLM vs a rule-based system?"
- "What's fundamentally different about building with LLMs vs writing deterministic code?"

### What it tests
Ability to articulate the paradigm difference (rule-specification → example-demonstration) and reason about when each approach is appropriate in production.

---

## Answer

### Concept
Traditional programming is **explicit logic**: a human writes rules, conditionals, and algorithms that deterministically map inputs to outputs. GenAI (specifically LLMs) is **learned behavior**: the model generalizes from billions of training examples to handle inputs no rule explicitly covers, producing outputs that are probabilistic rather than deterministic.

### Mechanism
| Dimension | Traditional programming | GenAI / LLM |
|-----------|------------------------|-------------|
| How behavior is specified | Code: `if/else`, regex, SQL, APIs | Training data + prompts |
| Output type | Deterministic, typed | Probabilistic, natural language |
| Handles novel input | Fails or returns error | Generalizes (sometimes hallucinates) |
| Debugging | Stack trace, unit tests | Eval datasets, prompt ablation, tracing |
| Latency | Sub-millisecond | 200ms–5s (TTFT + generation) |
| Cost per call | Near zero | ~$0.001–$0.025+ per 1K tokens |
| Best for | Structured logic, exact rules, high-throughput | Understanding intent, generating text, handling ambiguity |

**When traditional programming wins:** deterministic lookups (tax calculation, routing rules), high-throughput structured data (SQL aggregations), safety-critical systems where auditability is required.

**When GenAI wins:** understanding free-form user intent, synthesizing unstructured documents, generating natural-language summaries, tasks where exhaustive rule enumeration is impractical.

### Example / Tradeoff
**Customer support triage (real-world):** A rule-based system can route tickets by keyword matching ("billing" → billing queue). It breaks the moment a user writes "my card got charged twice and now I can't afford rent" — the rule misses it. An LLM with a prompt like "classify the intent of this support message" handles the paraphrase but costs ~$0.002/call and may occasionally misclassify. The production answer is often **both**: LLM for intent classification, traditional code for routing logic and SLA enforcement.

A concrete stack: LangChain or LlamaIndex for LLM orchestration, a deterministic rule engine downstream, OpenTelemetry tracing to observe where each fails. At 1M tickets/day you'd also add semantic caching (GPTCache or Redis) to avoid re-classifying identical phrasings.

---

## Verbal script

**Opening (30s):**
"I'd frame this as a shift in how you specify behavior. In traditional programming, I write the rules — every `if/else`, every regex, every lookup. In GenAI, I can't enumerate all the rules, so I show the model examples and it learns to generalize. That's powerful, but it comes with a completely different set of production tradeoffs."

**Core explanation (2–3 min):**
"Take a concrete example: a customer support ticket classifier. The traditional approach is a rule engine — keyword lists, maybe a decision tree. It's fast, cheap, fully auditable. But it fails the moment someone writes the same thing in a way the rules didn't anticipate. You end up with a maintenance nightmare as you add more and more edge-case rules.

The GenAI approach: you prompt an LLM like Claude or a frontier model with 'classify the intent of this message' and a rubric. It handles novel phrasings, typos, multiple languages. But now I'm spending $0.002 per call, latency jumps from microseconds to 500ms, and outputs are stochastic — the model might occasionally misclassify, and I can't just read a stack trace to understand why.

The key insight is that these aren't competitors — they're complements. In production I'd use the LLM for the hard part (understanding intent) and traditional code for the downstream logic (routing rules, SLA timers, database writes). That's what teams at Intercom, Zendesk, and Notion actually do."

**Tradeoff / production angle (1 min):**
"The hardest operational challenge is evaluation. Traditional code has unit tests — pass/fail. GenAI needs golden datasets, LLM-as-judge setups, and continuous regression monitoring because the model can drift as you change prompts. Frameworks like RAGAS and DeepEval help, but it's fundamentally a different debugging discipline. And cost control matters at scale — at 1M calls/day, semantic caching (reusing LLM responses for similar queries) can cut spend 30–40%."

**Wrap-up (30s):**
"So the short answer: traditional programming = deterministic, auditable, cheap, brittle at the edges. GenAI = flexible, generalizes, probabilistic, expensive, needs eval infrastructure. In real systems you use both — GenAI at the understanding layer, traditional code at the execution layer."

---

## Pitfalls

- **Mistake:** Saying "GenAI replaces traditional programming" without qualification — **Better:** Explain that GenAI excels at understanding/generation tasks where rule enumeration is impractical, while traditional code remains better for deterministic logic, low-latency operations, and auditable systems; the best architectures use both.
- **Mistake:** Treating GenAI outputs as deterministic — e.g., "we'll just check if the response contains the word 'billing'" — **Better:** Acknowledge stochasticity upfront, describe how you'd set temperature=0 for classification tasks, and explain evaluation infrastructure (golden sets, regression suites) needed to catch output drift.
- **Mistake:** Ignoring cost and latency — describing GenAI as a drop-in upgrade without mentioning that a 500ms LLM call can't replace a 1ms rule lookup in a hot path — **Better:** Articulate where LLM latency is acceptable (async classification, report generation) vs. unacceptable (autocomplete, real-time routing), and name mitigation strategies like caching and model tiering.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q1: How do LLMs work?](01-001-how-do-llms-work.md) | Prerequisite — understanding LLM mechanics underpins why GenAI behaves differently |
| [Q40: What is the difference between prompt engineering, RAG, and fine-tuning?](01-040-what-is-the-difference-between-prompt-engineering-rag-and-fi.md) | Follow-up — once GenAI is chosen, this is the next decision |
| [Q11: How do you ensure LLM outputs are consistent and accurate in multi-step workflows?](01-011-how-do-you-ensure-llm-outputs-are-consistent-and-accurate-in.md) | Follow-up — addresses the stochasticity problem raised in this answer |

---

## One-liner recall

> GenAI shifts from **writing rules** to **demonstrating examples** — trading determinism and sub-millisecond cost for generalization and flexible handling of ambiguity, requiring eval infrastructure and hybrid architectures where LLMs handle understanding and traditional code handles execution.
