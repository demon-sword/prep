# Explain few-shot learning and chain-of-thought prompting

**Category:** 01-llm-fundamentals
**Question #:** 008
**Source section:** §1 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
The interviewer is probing whether you understand how to elicit better behavior from LLMs without retraining — a core skill for applied AI engineers. It tests whether you know when to reach for prompt engineering techniques vs more expensive alternatives (fine-tuning, RAG), and whether you understand *why* these techniques work mechanically, not just that they do.

### Trigger phrases
- "How do you improve LLM reasoning without fine-tuning?"
- "What is few-shot prompting and when do you use it?"
- "How do you get the model to follow a complex multi-step task?"
- "Explain chain-of-thought — when does it help and when doesn't it?"

### What it tests
Practical prompt engineering judgment: knowing the mechanics of in-context learning, when CoT is worth the token cost, and when it fails.

---

## Answer

### Concept
**Few-shot learning** is providing 2–8 labeled input/output examples in the prompt so the model infers the task pattern without any weight updates. **Chain-of-thought (CoT) prompting** is eliciting intermediate reasoning steps — either via examples that show reasoning ("Let's think step by step…") or via a zero-shot trigger phrase — so the model externalizes its reasoning before producing a final answer. Both exploit in-context learning: the transformer's ability to adapt behavior purely from context.

### Mechanism
**Few-shot learning:**
1. Prepend k labeled examples to the prompt: `Input: X → Output: Y`
2. The model attends to the examples and generalizes the pattern to the new input
3. Works because pre-training exposed the model to countless task formats; examples activate the right "mode"
4. Typical sweet spot: 2–8 examples (diminishing returns beyond 8 for most tasks; budget for token cost)
5. Example selection matters: diverse, representative, correctly formatted — bad examples hurt more than help

**Chain-of-thought prompting:**
1. **Zero-shot CoT**: append `"Let's think step by step."` — triggers reasoning without examples (works on GPT-4-class models)
2. **Few-shot CoT**: include examples that show full reasoning traces: `Q: … A: First, … Then, … Therefore, …`
3. Mechanism: model generates intermediate tokens that serve as a scratch-pad; the answer token is conditioned on correct intermediate steps rather than jumping from question to answer
4. Most effective on tasks requiring multi-step arithmetic, symbolic reasoning, commonsense chains, and planning
5. **Self-consistency** extension: sample N reasoning paths with temperature > 0, majority-vote the final answers — reduces variance for hard reasoning tasks (Google 2022, +10–20 pp on GSM8K)

### Example / Tradeoff
**Few-shot CoT in production at Anthropic/OpenAI:** GPT-4 on GSM8K (grade-school math) jumps from ~56% (zero-shot) to ~92% (8-shot CoT). The cost is proportional: 8 examples × ~200 tokens = ~1,600 extra input tokens per request. At 1M daily queries and $0.003/1k input tokens, that's ~$4,800/day added cost — worth it for high-value tasks (legal reasoning, clinical decision support), not for simple FAQ retrieval.

**When CoT fails:** Tasks that are not reasoning-based (e.g., style transfer, tone matching, simple classification). On smaller models (< 7B params), CoT often produces fluent-sounding but incorrect reasoning chains — the model generates plausible-looking steps that lead to wrong answers. At that scale, fine-tuning beats CoT.

**Real tool:** LangChain's `FewShotPromptTemplate` manages example selection from a store; `ExampleSelector` picks semantically similar examples using a FAISS index — prevents irrelevant examples from polluting context.

---

## Verbal script

**Opening (30s):**
"Few-shot learning and chain-of-thought are the two most powerful prompt engineering techniques for improving LLM output quality without any model retraining. They're complementary: few-shot teaches the model the task format by example, while chain-of-thought teaches it to reason step-by-step before answering. I'll walk through how each works mechanically, when to use them, and where they break down."

**Core explanation (2–3 min):**
"Few-shot works by prepending k labeled input/output examples to the prompt. The model sees the pattern and generalizes — this works because pre-training exposed it to countless formats, so examples just activate the right mode. The typical sweet spot is 2–8 examples. Beyond 8, you get diminishing returns but pay linearly more tokens.

Chain-of-thought is a different idea: instead of just giving examples of inputs and outputs, you give examples that include the full reasoning trace. Or in zero-shot mode, you just append 'Let's think step by step.' The key mechanism is that the model generates intermediate tokens as a scratch-pad — the answer token is conditioned on those intermediate steps rather than jumping straight from question to answer. This makes a massive difference on multi-step arithmetic, planning, and symbolic reasoning.

A concrete example: GPT-4 on GSM8K math benchmarks goes from ~56% accuracy zero-shot to ~92% with 8-shot chain-of-thought. But that's 8 examples × ~200 tokens = 1,600 extra input tokens per request. At 1M daily queries, that's real cost, so you'd use it selectively for high-value tasks."

**Tradeoff / production angle (1 min):**
"The failure modes matter. CoT degrades on small models — a 7B-parameter model will generate confident-sounding reasoning that's wrong. In production, I'd pair CoT with self-consistency: sample 5–10 reasoning paths at temperature ~0.7 and majority-vote the final answers. That adds cost but dramatically reduces variance. Also: few-shot example quality is critical — a couple of bad examples can hurt more than no examples at all, so I'd maintain a curated example set and run regression tests when updating it."

**Wrap-up (30s):**
"The core insight is that both techniques exploit in-context learning — no weight changes, just better use of the model's pre-trained representations. Few-shot for task format, CoT for reasoning depth. Happy to go deeper on self-consistency, automatic CoT generation, or how this compares to fine-tuning for complex tasks."

---

## Pitfalls

- **Mistake:** Treating few-shot as always better than zero-shot — "just add more examples" — **Better:** Explain the cost tradeoff (k examples × tokens = extra cost/latency per request), and that bad examples actively hurt; example quality and diversity matters more than quantity beyond 4–6.
- **Mistake:** Claiming CoT works universally — "chain-of-thought always improves accuracy" — **Better:** Clarify it degrades on small models (< 7B params) and non-reasoning tasks like classification or style transfer; CoT helps when intermediate steps are actually causally relevant to the correct answer.
- **Mistake:** Conflating few-shot learning (in-context, no gradient) with fine-tuning — **Better:** Be explicit that few-shot is purely inference-time; no weights are updated, which means results don't persist across conversations and the model isn't actually "learning."

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q7: What is temperature and top-p sampling? How do they affect outputs?](01-007-what-is-temperature-and-top-p-sampling-how-do-they-affect-ou.md) | Self-consistency uses temperature > 0 to sample diverse CoT paths |
| [Q4: What is the difference between pre-training and fine-tuning?](01-004-what-is-the-difference-between-pre-training-and-fine-tuning.md) | Few-shot is an alternative to fine-tuning; understanding when each is appropriate |
| [Q9: What is KV cache? How does it help in LLM inference?](01-009-what-is-kv-cache-how-does-it-help-in-llm-inference.md) | KV cache amortizes the cost of repeated few-shot prefixes across requests |

---

## One-liner recall

> Few-shot injects labeled examples so the model pattern-matches the task format; chain-of-thought appends intermediate reasoning steps so the model's answer is conditioned on correct logic rather than a direct jump — both exploit in-context learning with no weight updates, and CoT works best on multi-step reasoning tasks with models ≥ 7B parameters.
