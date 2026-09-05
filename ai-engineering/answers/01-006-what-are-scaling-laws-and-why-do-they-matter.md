# What are scaling laws and why do they matter?

**Category:** 01-llm-fundamentals
**Question #:** 006
**Source section:** §1 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
The interviewer is probing whether you understand how the field decides to invest in bigger models, larger datasets, and more compute — and whether you can translate that theoretical framework into practical decisions (model selection, budget allocation, when to stop scaling). It also tests whether you know the Chinchilla correction: that most models were undertrained, not underparameterized.

### Trigger phrases
- "How did OpenAI/DeepMind decide to train such large models?"
- "Why are scaling laws important for AI engineering?"
- "What's the Chinchilla result and why does it matter?"
- "How do you decide how much compute to spend on a new model?"

### What it tests
Understanding of empirical power-law relationships between compute, data, model size, and loss — and the ability to use those relationships to make resource allocation decisions.

---

## Answer

### Concept
Scaling laws are empirical power-law relationships that predict how a language model's loss decreases as you increase compute (FLOPs), model parameters (N), and training tokens (D). First published by OpenAI (Kaplan et al. 2020) and refined by DeepMind (Hoffmann et al. 2022, "Chinchilla"), they show that loss follows predictable curves: L ∝ N^{-α} and L ∝ D^{-β}, with roughly equal returns from model size and data size.

### Mechanism
**Kaplan et al. (2020) — original OpenAI paper:**
- For a fixed compute budget C, optimal model size N_opt ∝ C^{0.73}
- This led to the prevailing wisdom: "make the model bigger, train it less"
- GPT-3 (175B params, ~300B tokens) was designed under this regime

**Chinchilla correction (DeepMind 2022):**
- Hoffmann et al. showed the Kaplan allocation was wrong: both N and D should scale proportionally — roughly 20 tokens per parameter is optimal
- Chinchilla (70B params, 1.4T tokens) outperformed Gopher (280B, 300B tokens) despite being 4× smaller
- Implication: most large models (GPT-3, PaLM, LLaMA-1) were *undertrained*, not underparameterized

**Practical formula:** For a compute budget of C FLOPs, optimal N ≈ √(C / 6) and D ≈ 20 × N. Every doubling of compute should be split ~50/50 between model size and data.

**The three laws in practice:**
1. **Loss vs. compute:** smooth power law — predictable returns on each dollar
2. **Loss vs. model size:** diminishing returns if you under-train a large model
3. **Loss vs. data:** bottleneck once you exhaust high-quality data (the "data wall")

### Example / Tradeoff
- **LLaMA 2 (Meta, 2023):** 70B params trained on 2T tokens — Chinchilla-optimal ratio, demonstrating that a smaller, well-trained model beats a larger undertrained one
- **Practical implication for engineers:** When choosing a model for a task, don't default to "biggest." A 7B model trained on 140B tokens may outperform a 70B model trained on 100B tokens on the same task if the smaller model is better trained
- **Data wall:** Scaling laws break when high-quality data runs out. After ~3–5T tokens of filtered internet text, returns on more data flatten. This is why synthetic data (frontier-model-generated) and data curation matter increasingly at frontier scale
- **The irreducible loss:** Every scaling law has an asymptote — the Bayes-optimal loss for the task. No amount of scale eliminates this floor; it reflects the inherent unpredictability of language

---

## Verbal script

**Opening (30s):**
"Scaling laws are one of the most practically important ideas in LLM engineering. The core insight is that model loss follows predictable power-law curves as you increase compute, model size, and data — which means you can plan training runs and model selection with empirical precision rather than guessing."

**Core explanation (2–3 min):**
"The original Kaplan et al. 2020 paper from OpenAI established that, for a fixed compute budget, you should bias toward larger models and train them less. That drove the GPT-3 era — 175 billion parameters, 300 billion tokens. But in 2022, DeepMind published the Chinchilla paper and showed that was wrong. Their key finding: model size and training tokens should scale proportionally — roughly 20 tokens per parameter is optimal.

To make this concrete: Chinchilla was 70 billion parameters trained on 1.4 trillion tokens — four times smaller than Gopher but also four times better trained. Chinchilla outperformed Gopher across almost every benchmark, at a fraction of the inference cost. This is the Chinchilla correction, and it reframed how the whole field sizes models.

For an engineer, the practical takeaway is: when you have a fixed compute budget C, split it roughly equally between growing the model and growing the dataset. A 7B model trained on 140B tokens will beat a 70B model trained on 100B tokens on the same task, because the smaller model is in its optimal training regime while the large one is undertrained."

**Tradeoff / production angle (1 min):**
"The main place scaling laws break down is the data wall. The power-law holds while you have abundant high-quality data. Once you've exhausted filtered internet text — which at frontier scale is roughly 3–5 trillion tokens — adding more data gives diminishing returns, and you start hitting data quality ceilings. That's why synthetic data generation and careful curation matter so much today. The other limit is the irreducible loss: there's a floor set by the inherent entropy of language that no scaling can eliminate."

**Wrap-up (30s):**
"So scaling laws matter because they turn model training from art into engineering — predictable budgeting, optimal size/data allocation, and the Chinchilla insight that smaller, better-trained models often win. Happy to go deeper on the data wall or how this connects to model selection in practice."

---

## Pitfalls

- **Mistake:** Citing only the Kaplan paper and saying "bigger models always perform better" — **Better:** Mention the Chinchilla correction and explain that optimal performance requires proportional scaling of both model size and data (≈20 tokens/param), not just growing parameters
- **Mistake:** Treating scaling laws as theoretical only, with no production implication — **Better:** Connect to real decisions: model selection (7B well-trained vs. 70B undertrained), training budget allocation, and why LLaMA 2 / Mistral outperform larger but undertrained predecessors
- **Mistake:** Not mentioning the data wall or irreducible loss — **Better:** Acknowledge that scaling laws have limits: data availability caps returns, and Bayes-optimal loss provides a floor that no scale can breach

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q1: How do LLMs work?](01-001-how-do-llms-work.md) | Prerequisite — scaling laws describe the training dynamics of the architecture |
| [Q4: What is the difference between pre-training and fine-tuning?](01-004-what-is-the-difference-between-pre-training-and-fine-tuning.md) | Related — Chinchilla optimal compute allocation is a pre-training concept |
| [Q30: What is Mixture of Experts (MoE)? How does it improve efficiency?](01-030-what-is-mixture-of-experts-moe-how-does-it-improve-efficienc.md) | Follow-up — MoE is one architectural response to scaling laws (more params, same active compute) |

---

## One-liner recall

> Scaling laws (Kaplan 2020, Chinchilla 2022) show that loss follows predictable power curves with compute, size, and data — and the key Chinchilla insight is that model size and training tokens must scale proportionally (~20 tokens/param), meaning smaller well-trained models beat larger undertrained ones.
