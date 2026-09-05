# What is reflection in the context of LLM agents?

**Category:** 01-llm-fundamentals
**Question #:** 017
**Source section:** §1 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
Interviewers ask this to probe whether you understand the self-improvement loop that distinguishes modern agentic systems from simple LLM chains. It tests awareness of how agents critique their own outputs, catch errors, and iteratively improve — a key pattern in production agent design (ReAct, Reflexion, self-consistency). It also reveals whether you know *when* reflection adds value vs. when it wastes tokens and latency.

### Trigger phrases
- "How does an agent know when its answer is wrong?"
- "What is Reflexion / self-critique in agent systems?"
- "How do agents improve their own outputs without human feedback?"
- "Walk me through how a ReAct agent corrects itself."

### What it tests
Whether you understand the self-evaluation feedback loop that enables agents to detect and fix their own errors without external supervision.

---

## Answer

### Concept
Reflection (also called self-critique or self-revision) is a pattern where an LLM agent evaluates its own previous output — identifying errors, gaps, or quality issues — and then generates a revised response or plan. It's the agentic equivalent of "check your work before submitting." The agent produces a critique, then conditions its next generation on that critique to produce a better result.

### Mechanism
The reflection loop has three stages:

1. **Generate** — The agent produces an initial response or plan (e.g., a code solution, a research summary, a tool-call sequence).
2. **Critique** — The same (or a separate critic) LLM evaluates the output against an explicit rubric: "Is this answer factually grounded? Did I use the right tool? Does the code pass the test cases?" The critique is itself a natural-language string.
3. **Revise** — The agent is called again with the original prompt + initial output + critique appended to its context, and produces an improved response.

This loop can repeat for N iterations or until a stopping criterion is met (e.g., "no further critique", test suite passes, judge LLM scores above threshold).

**Reflexion (Shinn et al., 2023)** is the canonical formalization: the agent stores critiques in an episodic memory buffer and uses them in subsequent episodes — so the agent learns from failure *across tasks*, not just within a single generation.

**Self-consistency** is a related but distinct pattern: run the same prompt N times with temperature > 0, then take a majority vote. This exploits variance to find more reliable answers but does not involve self-critique.

### Example / Tradeoff
**Code generation agent (LangChain / LangGraph):** A coding agent generates a Python function, runs unit tests via a tool call, and receives a test failure message. It appends the failure + traceback to the conversation context and regenerates, fixing the bug. This is reflection driven by external tool feedback rather than a purely introspective critique.

**A frontier model benchmark:** On HumanEval (code generation), a simple Reflexion loop (generate → critique → revise, up to 3 iterations) improved pass@1 from ~67% to ~88%, demonstrating that reflection can substitute for a larger model in some tasks.

**Tradeoff:** Each reflection iteration adds 1–3 LLM calls and 2–5× the token cost of a single pass. For cheap, fast tasks (simple Q&A, classification), reflection is overkill — better to use temperature=0 and accept the first output. For high-stakes, multi-step tasks (code, research synthesis, long-form writing), reflection can reduce error rates significantly. A common production pattern is *conditional reflection*: trigger the critic only when confidence is low (low log-probability of the output) or when an external tool returns an error signal.

---

## Verbal script

**Opening (30s):**
"Reflection in agent systems is the ability of an LLM to evaluate and revise its own prior output — essentially 'checking its work.' It's distinct from just calling the LLM again; the key is that the evaluation is explicit and fed back into the next generation as context."

**Core explanation (2–3 min):**
"The basic loop is three steps: generate, critique, revise. The agent first produces an initial response. A critic — which can be the same model with a different system prompt, or a separate cheaper model — evaluates it against a rubric: is the reasoning sound? did it use the right tools? does it meet the task requirements? That critique is natural-language text, and it's appended to the context for the next generation.

The key paper here is Reflexion by Shinn et al. in 2023. They added one important upgrade: the agent stores critiques in an episodic memory buffer, so it doesn't just improve within a single run — it learns from failure across multiple task attempts. On HumanEval, a 3-iteration Reflexion loop pushed a small fast model pass@1 from ~48% to ~68%, which is otherwise only achievable by jumping to a much larger model.

In production, I've seen two common variants: *introspective reflection*, where the model critiques its own reasoning — useful for research agents and long-form writing — and *tool-feedback reflection*, where the critique comes from an external signal like a test suite, a search result that contradicts the claim, or a downstream validator. The tool-feedback variant is more reliable because the critique is grounded in objective evidence rather than the model's potentially flawed self-assessment."

**Tradeoff / production angle (1 min):**
"The main cost is latency and tokens: each reflection pass adds at least one extra LLM call. For a task that already takes 2 seconds, three reflection rounds can push you to 6–8 seconds — a real UX problem. So in production, I'd make reflection conditional: trigger it only when there's a concrete failure signal (test failure, low confidence score, factual contradiction from retrieval) rather than always running N rounds. You can also use a smaller, cheaper model as the critic — say, Haiku critiquing Sonnet's output — to reduce cost while preserving most of the quality benefit."

**Wrap-up (30s):**
"So the one-liner: reflection is a generate → critique → revise loop that lets agents catch and fix their own errors, and Reflexion extends this across episodes via memory. It's powerful for code and research tasks but needs cost and latency guardrails in production. Happy to go deeper on how to implement a conditional reflection trigger or the episodic memory design."

---

## Pitfalls

- **Mistake:** Confusing reflection with simply re-prompting the same question — **Better:** Emphasize that reflection requires an *explicit critique* appended to context; just retrying without a critique is random sampling, not self-improvement.
- **Mistake:** Saying "reflection always improves output" without mentioning compounding cost — **Better:** Quantify: each reflection pass ≈ 1 extra LLM call; 3 passes = 3× token cost; recommend conditional triggering (on tool error or low confidence) rather than unconditional N rounds.
- **Mistake:** Not distinguishing introspective reflection (self-critique) from tool-feedback reflection (external error signal) — **Better:** Explain both variants; note that tool-feedback is more reliable because the critique is grounded in objective evidence rather than the model's potentially hallucinated self-assessment.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q6: Agent vs. simple LLM chain — what makes a system truly agentic?](03-006-when-is-agentic-architecture-the-wrong-solution.md) | Reflection is one of the core patterns that distinguishes true agents from chains |
| [Q8: Explain few-shot learning and chain-of-thought prompting](01-008-explain-few-shot-learning-and-chain-of-thought-prompting.md) | Self-consistency (related pattern) and CoT are both precursors to reflection |
| [Q11: How do you ensure LLM outputs are consistent and accurate in multi-step workflows?](01-011-how-do-you-ensure-llm-outputs-are-consistent-and-accurate-in.md) | Reflection is one of the production strategies for consistency in multi-step pipelines |

---

## One-liner recall

> Reflection is a generate → critique → revise loop where an LLM evaluates its own prior output and conditions the next generation on that critique; Reflexion (Shinn 2023) extends this across tasks via episodic memory, but requires conditional triggering in production to avoid 3× token cost.
