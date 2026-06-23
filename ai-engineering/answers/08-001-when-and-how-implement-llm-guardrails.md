# When and how implement LLM guardrails?

**Category:** 08-safety-guardrails
**Question #:** 001
**Source section:** §10 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
Interviewers want to know whether you treat safety as a checkbox ("add a system prompt") or as a **production engineering discipline**. This question probes your ability to design defense-in-depth middleware, articulate the harm-helpfulness tradeoff, and tune guardrail thresholds against real traffic data.

### Trigger phrases
- "When and how would you implement guardrails for an LLM application?"
- "How do you prevent the model from producing harmful or off-policy outputs?"
- "Walk me through your guardrail architecture."

### What it tests
Ability to design layered, production-grade safety middleware that balances harm prevention with user experience — not just reciting "system prompt + content filter."

---

## Answer

### Concept
LLM guardrails are **middleware layers that enforce behavioral policy** on model inputs and outputs. They are triggered whenever the LLM can produce outputs that violate safety, regulatory, or business policy constraints — which is virtually every user-facing deployment. A guardrail is not a single check but a stack: input classifier → prompt-level constraints → output classifier → async audit.

### Mechanism
**When to implement:** Add guardrails before launch whenever (a) users interact directly with the model, (b) the model has access to tools or executes code, or (c) outputs carry legal, reputational, or health-and-safety risk. The earlier in the pipeline you add guardrails, the cheaper they are — blocking at input costs one classifier call; blocking after generation wastes the full LLM call.

**Four-layer stack:**

1. **Input guardrail (pre-LLM, synchronous)**
   - Run a lightweight classifier on every user message before the LLM call.
   - Tools: **Llama Guard 3** (Meta, open-source, <50ms on GPU), **Perspective API** (Google, toxicity), or a fine-tuned DistilBERT on your policy taxonomy.
   - On block: return a canned refusal and skip the LLM call entirely — saves both latency and cost.
   - Threshold tuning: start at p95 confidence → measure false positive rate on 1,000 representative real queries → lower threshold until FP rate < 0.5%.

2. **Prompt-level constraints (in-prompt, zero latency overhead)**
   - System prompt: explicit behavior rules ("You are a customer support agent. Never discuss competitors. If asked for medical advice, say you cannot help and provide a helpline number.").
   - Role and scope restriction, persona anchoring, abstention instructions for out-of-scope queries.
   - **Not sufficient alone** — system prompts can be overridden by injection; they are a baseline, not a boundary.

3. **Output guardrail (post-LLM)**
   - Synchronous: blocks the response before it reaches the user — use for high-risk domains (healthcare, finance, legal). Adds 50–150ms for a fast classifier.
   - Asynchronous: logs the response and flags for human review — use for medium-risk deployments where latency budget is tight (<200ms p95). A small percentage of flagged responses reach users but are caught within seconds.
   - Tools: **Llama Guard 3** (reuse for output), **NeMo Guardrails** (NVIDIA, dialog-level policy enforcement with LLM-backed classifiers), **Guardrails AI** (output schema + semantic validators), custom fine-tuned classifiers.
   - For regulated domains: add a **DeBERTa NLI entailment check** — response must be entailed by retrieved context, else block.

4. **PII and data layer (cross-cutting)**
   - Strip PII from inputs before the LLM call and from outputs before logging using **Microsoft Presidio** (entity recognition + anonymization).
   - Never log raw user messages — redact first, then write to your log store.

**Architecture pattern:**
```
User message
    │
    ▼
[Input classifier: Llama Guard 3]  ←— block + log if policy violation
    │
    ▼
[Prompt builder: system prompt + sanitized context]
    │
    ▼
[LLM call: GPT-4o / Llama 3]
    │
    ▼
[Output classifier: Llama Guard 3 / NeMo Guardrails]  ←— block if violation
    │
    ▼
[PII scrub: Presidio]
    │
    ▼
User response  +  Async audit log (Kafka → monitoring dashboard)
```

### Example / Tradeoff
**Customer support chatbot (healthcare insurance):** Implemented a 3-layer stack — Llama Guard 3 input classifier (60ms, GPU), system-prompt scope restriction with abstention for medical advice, synchronous Llama Guard 3 output check (55ms). Total guardrail overhead: ~115ms on top of LLM call. False positive rate after threshold tuning: 0.4% of legitimate queries blocked. Bypass rate (measured via weekly automated red-team with PyRIT): < 0.2% on harm taxonomy. Business impact: zero policy violations in 6 months of production; CSAT unaffected (users don't notice 115ms at this level).

**Key tradeoff:** Synchronous vs async output classifier. Synchronous is safer but adds latency — use it when harm is irreversible (medical advice, financial transactions). Async is faster but some harmful responses slip through momentarily — acceptable for medium-risk consumer apps with human review queues.

---

## Verbal script

**Opening (30s):**
"I think about LLM guardrails as a layered defense system — not a single check. The analogy I use is airport security: there's a ticket check at the door, a scanner in the middle, and a gate agent at boarding. No single layer is sufficient on its own. Let me walk through when I'd add each layer and what I'd actually implement."

**Core explanation (2–3 min):**
"The first question is *when* to add guardrails. The short answer is: before you ship any user-facing LLM feature. The earlier in the pipeline you place them, the cheaper they are. Blocking at input with a classifier costs one fast model call. Blocking after generation wastes the full LLM call plus the latency.

My standard stack has four layers. First, an **input classifier** — I'd use Llama Guard 3, which is open-source from Meta, runs in under 60ms on a GPU, and classifies inputs against a configurable harm taxonomy. It sits in front of the LLM call and returns a SAFE/UNSAFE decision. If UNSAFE, I return a canned refusal immediately and skip the LLM entirely.

Second, **prompt-level constraints** in the system prompt — scope restriction, persona anchoring, abstention instructions. This is the cheapest layer, but it's not sufficient alone. Adversarial users can override system prompts through injection, so I treat this as a default behavior baseline, not a hard boundary.

Third, an **output classifier** — I run another Llama Guard call on the generated response. For high-stakes domains like healthcare or finance, this is synchronous — it blocks the response before it reaches the user, at the cost of 50–150ms of latency. For lower-risk consumer apps with a tight latency budget, I'll run it async: the response goes to the user, but it's simultaneously streamed to a review queue. Any flagged response triggers a human review within minutes.

Fourth, cross-cutting **PII scrubbing** with Microsoft Presidio — it runs on inputs before the LLM and on outputs before they hit the log store. Raw user messages never touch our logging infrastructure.

A critical implementation detail: threshold tuning. I start the classifier at a conservative confidence threshold, then measure the false positive rate on 1,000 representative production queries. I tune down until FP rate is under 0.5% — because over-blocking legitimate queries erodes trust just as much as under-blocking harmful ones."

**Tradeoff / production angle (1 min):**
"The main tradeoff is synchronous vs asynchronous for the output classifier. Synchronous is the right choice whenever the harm is irreversible — if a medical chatbot gives dangerous advice, you can't un-deliver that. Async is viable for medium-risk apps where a small percentage of flagged responses reaching users is acceptable and human reviewers can act quickly. The other gotcha is model updates — every time you swap the underlying LLM or change the system prompt, you need to re-run your red-team suite. Guardrails calibrated for one model don't necessarily transfer."

**Wrap-up (30s):**
"So the TL;DR: guardrails go in before launch, at every boundary — input, prompt, output, and logging. The stack is Llama Guard input → system prompt constraints → synchronous or async Llama Guard output → Presidio PII scrub. Threshold tuning and periodic red-teaming keep the harm-helpfulness balance calibrated over time. Happy to go deeper on any layer."

---

## Pitfalls

- **Mistake:** "We added a system prompt that says 'never discuss harmful topics' — that's our guardrail." — **Better:** System prompts are easily overridden by prompt injection; they're a baseline behavior default, not a security boundary. Describe input/output classifiers (Llama Guard, NeMo Guardrails) as the actual enforcement layer, with the system prompt as a complementary signal.

- **Mistake:** "We block anything above a 0.5 confidence threshold" without mentioning false positive rate measurement. — **Better:** Explain the FP rate tuning process: measure on 1,000+ representative real queries, tune until FP < 0.5%, monitor bypass rate via periodic red-team — treating threshold as a fixed number rather than a calibrated parameter signals inexperience with production deployments.

- **Mistake:** "We use the provider's built-in content filter." — **Better:** Provider filters catch egregious content but miss domain-specific policy violations (competitive mentions, regulatory constraints, brand risk). Custom classifiers fine-tuned on your policy taxonomy and representative examples are required for production-grade enforcement.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q2: Minimize harmful outputs while staying useful?](08-002-minimize-harmful-outputs-while-staying-useful.md) | Follow-up — harm-helpfulness tradeoff in detail |
| [Q4: Protect against prompt injection and jailbreaking?](08-004-protect-against-prompt-injection-and-jailbreaking.md) | Related — adversarial bypass of guardrails |
| [Q3: Detect policy violations / offensive content?](08-003-detect-policy-violations-offensive-content.md) | Same layer — output classifier implementation specifics |

---

## One-liner recall

> Guardrails are a four-layer stack — input classifier (Llama Guard 3) → system-prompt constraints → synchronous or async output classifier → Presidio PII scrub — with FP rate tuned below 0.5% on real traffic and bypass rate verified via periodic red-team.
