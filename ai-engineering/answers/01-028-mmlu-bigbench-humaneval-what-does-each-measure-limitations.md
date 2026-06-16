# MMLU, BigBench, HumanEval — what does each measure? Limitations?

**Category:** 01-llm-fundamentals
**Question #:** 028
**Source section:** §1 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
Interviewers ask this to check that you can critically evaluate benchmark claims — a core skill when choosing models, reading vendor leaderboards, or convincing stakeholders that eval numbers are meaningful. A weak candidate recites benchmark names; a strong candidate explains what each actually measures, what it *doesn't* measure, and why headline scores can mislead production decisions.

### Trigger phrases
- "How do you evaluate LLM performance? What benchmarks matter?"
- "GPT-4 scores 90% on MMLU — is that model good enough for our use case?"
- "What are the limitations of standard LLM benchmarks?"
- "Compare MMLU, BigBench, and HumanEval."

### What it tests
Ability to critically interpret benchmark scores rather than accept them as ground truth — plus awareness of data contamination, task diversity gaps, and how to bridge from academic evals to production metrics.

---

## Answer

### Concept
MMLU, BigBench, and HumanEval are the three most commonly cited LLM benchmarks, each targeting a different capability axis: **broad knowledge** (MMLU), **general reasoning diversity** (BigBench), and **code generation** (HumanEval). None fully predicts production performance, and all have known contamination and saturation problems.

### Mechanism

**MMLU — Massive Multitask Language Understanding**
- **What:** 57 subjects × ~16K multiple-choice questions drawn from professional exams (bar, USMLE, GRE, MCAT) and academic curricula (history, math, CS, law, medicine).
- **How scored:** 0-shot or 5-shot accuracy across all subjects; reported as macro-average.
- **What it actually measures:** Factual recall and subject-matter breadth from a Western, English-centric exam corpus.
- **Limitations:**
  - **Data contamination** — many training sets include MMLU questions verbatim. GPT-4's 86% may partly reflect memorization, not reasoning.
  - **Multiple-choice bias** — models can score well by exploiting option distribution or letter-position artifacts without understanding.
  - **Saturation** — frontier models (GPT-4, Claude 3, Gemini Ultra) all score 85–90%+, making it useless for differentiating top-tier models.
  - **No open-ended reasoning** — multiple-choice can't probe multi-step problem-solving or explanation quality.

**BIG-Bench (Beyond the Imitation Game Benchmark)**
- **What:** 214 tasks contributed by 450+ researchers covering reasoning, multilingual NLU, social IQ, math, code, creativity, and adversarial robustness. BIG-Bench Hard (BBH) is a curated 23-task subset of the hardest items where humans outperformed GPT-3.
- **How scored:** Task-specific metrics (exact match, multiple choice, human-rated); reported as normalized preferred metric.
- **What it actually measures:** Breadth of capabilities including tasks LLMs struggle with — logical deduction, causal reasoning, minority language understanding, sycophancy probes.
- **Limitations:**
  - **Heterogeneous difficulty** — averaging across 214 wildly different tasks produces a composite number that's hard to interpret.
  - **Slow to update** — community contribution process means new capability gaps lag real model progress.
  - **Task leakage** — several tasks appeared in public fine-tuning datasets. BBH is now preferred because it focuses on remaining hard cases.
  - **Human baseline inconsistency** — "human performance" on some tasks was measured with limited annotation budgets.

**HumanEval**
- **What:** 164 hand-written Python programming problems (OpenAI, 2021). Each problem has a function signature, docstring, and unit tests. Models generate code; unit tests determine pass/fail.
- **How scored:** `pass@k` — probability at least one of k samples passes all unit tests. `pass@1` (greedy) is the headline metric.
- **What it actually measures:** Python function-level code synthesis on relatively short, self-contained algorithmic tasks.
- **Limitations:**
  - **Scale too small / tasks too narrow** — 164 problems, single-function scope, no multi-file or system-level tasks. Modern models score 85–90%+ (`pass@1`), so it no longer differentiates.
  - **No real-world complexity** — no API calls, dependency management, debugging, or iterative editing, which dominate actual developer workflows.
  - **Python-only** — doesn't capture polyglot ability (TypeScript, Rust, Go) that matters for hiring decisions.
  - **Data contamination** — the problems are public and appear in many training corpora. MBPP, SWE-Bench, and LiveCodeBench are now preferred for less-contaminated signal.

### Example / Tradeoff

| Benchmark | What it measures | Best use | Key limitation |
|-----------|-----------------|----------|----------------|
| MMLU | Broad factual knowledge, 57 subjects | Compare general knowledge breadth | Saturated; contamination risk; multiple-choice only |
| BIG-Bench Hard | Reasoning diversity, hardest 23 tasks | Find model weaknesses on novel reasoning | Composite score hard to interpret; slow updates |
| HumanEval | Python function synthesis | Code capability signal | 164 problems; saturated; no system-level tasks |

**Production reality:** For a customer support chatbot, none of these benchmarks predicts deflection rate, faithfulness, or p95 latency. The right eval is a **golden dataset** of 200–500 real support queries with human-graded answers, measured via RAGAS (faithfulness, answer relevancy) and business metrics (CSAT, escalation rate). Benchmark scores are a starting shortlist filter, not a deployment gate.

---

## Verbal script

**Opening (30s):**
"These three benchmarks are the ones you'll see on every model leaderboard, and they're worth knowing cold — not just what they measure, but what their scores *don't* tell you. Let me walk through each and then explain why I'd almost never use any of them as my primary production eval."

**Core explanation (2–3 min):**
"MMLU — Massive Multitask Language Understanding — is 57-subject multiple choice: bar exam, MCAT, GRE, history, law, you name it, ~16,000 questions total. It measures broad factual knowledge. The problem is, frontier models are all scoring 85–90%, so it no longer differentiates. And there's a well-documented contamination problem — many of the questions showed up verbatim in training data, so a high score might be retrieval, not reasoning.

BIG-Bench, and specifically BIG-Bench Hard, is a community benchmark of 214 tasks, narrowed to 23 hard cases where early models failed badly. It's the most diverse of the three — covers causal reasoning, social IQ, minority languages, adversarial probes. The limitation is that averaging across wildly different tasks makes the composite hard to interpret. When I see 'BBH score: 72%,' I want to know *which* tasks failed, not the average.

HumanEval is OpenAI's 164-problem Python coding benchmark. Pass at 1 — probability a single sample passes all unit tests — is the headline number. Modern models hit 85–90% here too. The real limitation is scope: 164 single-function problems tells you very little about multi-file refactoring, debugging, or TypeScript/Rust ability. SWE-Bench is the more realistic replacement — it has real GitHub issues and test suites — but it's harder to run.

**Tradeoff / production angle (1 min):**
"In practice, I use benchmarks to narrow a shortlist — if a model scores 60% on MMLU, I'm not deploying it in a knowledge-heavy domain. But the real production eval is always a domain-specific golden dataset. For RAG systems I care about RAGAS faithfulness and context precision. For code generation I care about pass rates on *my* test suite, not HumanEval. One concrete gotcha: I've seen teams pick model A over model B based on MMLU, but model B's latency was 40% lower and faithfulness on their golden set was 5 points higher. The benchmark was noise for their actual use case."

**Wrap-up (30s):**
"So: MMLU = knowledge breadth, BIG-Bench Hard = reasoning diversity, HumanEval = Python function synthesis. All three are saturated for frontier models and have contamination issues. They're a starting filter, not a deployment gate. The real eval is always a task-specific golden dataset with production-relevant metrics."

---

## Pitfalls

- **Mistake:** Treating benchmark scores as ground truth for model selection ("GPT-4 scored 90% on MMLU so it's the best for our use case") without asking what the task actually requires — **Better:** Acknowledge that MMLU measures knowledge breadth on multiple-choice academic questions, which may have little overlap with your production task; propose a domain-specific golden set with metrics tied to business outcomes (deflection rate, CSAT, faithfulness).
- **Mistake:** Not mentioning data contamination — frontier models have almost certainly seen MMLU and HumanEval questions during pre-training, inflating scores — **Better:** Explicitly flag contamination as a reason benchmark scores overstate real generalization; prefer newer, less-contaminated benchmarks (LiveCodeBench, MMLU-Pro) or private evals for high-stakes decisions.
- **Mistake:** Conflating `pass@1` with `pass@k` on HumanEval — `pass@100` can be 99% while `pass@1` is 60%, making the benchmark headline metric choice matter hugely — **Better:** Clarify which k is being reported; for production coding assistants, `pass@1` is the relevant metric since users typically see one completion.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q5: Explain context windows and their limitations](01-005-explain-context-windows-and-their-limitations.md) | Related limitation discussion — both benchmarks and context windows require knowing what capability is actually being measured |
| [Q29: RLHF vs DPO — when prefer one over the other?](01-029-rlhf-vs-dpo-when-prefer-one-over-the-other.md) | Follow-up — RLHF/DPO alignment is often tuned to improve benchmark scores; knowing benchmark limitations helps evaluate alignment claims |
| [Q8: Explain few-shot learning and chain-of-thought prompting](01-008-explain-few-shot-learning-and-chain-of-thought-prompting.md) | Mechanism link — MMLU is typically evaluated 5-shot; CoT prompting dramatically changes model performance on BIG-Bench Hard reasoning tasks |

---

## One-liner recall

> MMLU measures broad factual knowledge (57-subject multiple choice, saturated at 85–90% for frontier models), BIG-Bench Hard measures reasoning diversity across novel hard tasks, and HumanEval measures Python function synthesis (pass@1, also saturated) — all three have data contamination and saturation problems, making task-specific golden datasets the real production eval signal.
