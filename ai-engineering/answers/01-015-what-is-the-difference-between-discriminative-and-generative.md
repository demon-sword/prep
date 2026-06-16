# What is the difference between discriminative and generative models?

**Category:** 01-llm-fundamentals
**Question #:** 015
**Source section:** §1 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
The interviewer is probing whether you understand the fundamental probabilistic distinction that separates classical ML models (discriminative) from LLMs and diffusion models (generative). Strong candidates connect the math to practical consequences: why generative models can hallucinate, why they can produce novel content, and when you'd actually reach for each.

### Trigger phrases
- "What's the difference between generative and discriminative models?"
- "Why can LLMs generate text but a classifier can't?"
- "Is BERT generative or discriminative?"
- "When would you use a generative model vs a discriminative one?"

### What it tests
Whether you can anchor an LLM-centric answer in the underlying probabilistic framework and translate that into real engineering tradeoffs.

---

## Answer

### Concept
**Discriminative models** learn the conditional distribution P(y | x) — given input x, what is the label y? They draw a decision boundary between classes. **Generative models** learn the joint distribution P(x, y) — or, for unconditional generation, P(x) — and can therefore *synthesize* new examples of x, not just classify them. Modern LLMs are autoregressive generative models: they learn P(token_t | token_1, …, token_{t-1}) and generate by sampling from that distribution one token at a time.

### Mechanism
| Model type | What it learns | Inference | Example |
|---|---|---|---|
| Discriminative | P(y \| x) | forward pass → class label / score | Logistic regression, BERT for classification, SVM |
| Generative (joint) | P(x, y) | sample x from P(x \| y) | Naïve Bayes, GMM, VAE |
| Generative (autoregressive) | P(x) = ∏ P(x_t \| x_{<t}) | sequential token sampling | GPT-4, Claude, LLaMA 3 |
| Generative (diffusion) | P(x) via denoising score | iterative denoising from Gaussian noise | Stable Diffusion, DALL·E 3 |

Discriminative models are typically **more accurate on their target task** given the same data because they don't waste capacity modeling the input distribution. Generative models pay for their ability to synthesize with higher complexity and higher hallucination risk.

### Example / Tradeoff
**BERT vs GPT** is the canonical contrast: BERT is encoder-only, trained with masked language modeling (predicting masked tokens given full context), which makes it discriminative in the sense that it produces representations used for classification tasks — it doesn't generate free text. GPT is decoder-only, autoregressive, truly generative. In practice:

- **Sentiment analysis, NER, intent classification** → BERT-style discriminative fine-tune: faster, more accurate, less likely to hallucinate an irrelevant label.
- **Text generation, summarization, Q&A with open-ended output** → GPT-style generative model required.
- **Hybrid** (RAG): a generative LLM produces the final answer, but a discriminative retrieval model (bi-encoder embedding + approximate nearest neighbor) selects which documents to provide.

The production trap: because LLMs are generative they sample from a probability distribution over tokens — even at temperature=0 (greedy decoding) they can "hallucinate" because the model assigns nonzero probability to false tokens if those patterns appeared in training. Discriminative classifiers don't hallucinate; they only misclassify.

---

## Verbal script

**Opening (30s):**
"The distinction is really a probabilistic one. Discriminative models learn the conditional — P(y given x) — the boundary between classes. Generative models learn the joint distribution over inputs and outputs, which means they can *synthesize* new inputs, not just classify them. For LLMs specifically, the generative model is autoregressive: it learns P of the next token given all prior tokens and generates text by sampling from that distribution one token at a time."

**Core explanation (2–3 min):**
"The clearest real-world contrast is BERT versus GPT. BERT is encoder-only — it sees the whole sequence with masked tokens and predicts what the masks should be. That masking objective makes it excellent at downstream discriminative tasks like classification and NER, but it doesn't generate free text. GPT is decoder-only with causal masking — each token can only attend to prior tokens — which makes it a true generative model that can complete or synthesize text.

This has practical consequences. If I'm building a sentiment classifier or intent detector, I'd fine-tune a BERT-style model: lower hallucination risk, faster inference, better accuracy on the specific task. If I need open-ended text generation, summarization, or a chatbot, I need a generative model.

Generative models also include diffusion models — Stable Diffusion, DALL·E 3 — which learn to denoise from Gaussian noise to reconstruct images. They model P(x) via a score-matching objective rather than autoregression. The core idea is the same: the model has a learned distribution over inputs it can sample from."

**Tradeoff / production angle (1 min):**
"The big production tradeoff is hallucination. Because an LLM samples from a learned distribution, it can produce confident-sounding tokens that are factually wrong — the distribution assigns nonzero probability to false continuations. Discriminative models don't hallucinate in that sense; they can misclassify, but they won't invent a category that doesn't exist. In RAG architectures we often lean on discriminative retrieval — bi-encoder embedding models — to fetch the right documents, then hand off to a generative LLM to synthesize the answer. That pairing plays to the strengths of both."

**Wrap-up (30s):**
"So the short answer: discriminative models learn decision boundaries (P of y given x), generative models learn the data distribution and can synthesize novel examples. In applied AI we use both — discriminative models for classification/retrieval tasks and generative LLMs for synthesis — and the hallucination risk of generative models is a key engineering concern to manage with grounding, retrieval, and faithfulness checks."

---

## Pitfalls

- **Mistake:** Saying "BERT is discriminative because it's used for classification" without explaining *why* — i.e., that it models P(y|x) not P(x) — **Better:** Tie the classification use to the training objective (MLM masked prediction), and explain that the encoder doesn't model a distribution over output text sequences, so it can't generate.
- **Mistake:** Treating "generative" as synonymous with "LLM" and ignoring diffusion models, VAEs, or even classical models like Naïve Bayes — **Better:** Acknowledge the full taxonomy (autoregressive, diffusion, VAE) and explain that the defining trait is modeling P(x) or P(x,y), not the specific architecture.
- **Mistake:** Not connecting the generative/discriminative distinction to hallucination risk in production — **Better:** Explain that sampling from a learned distribution is why LLMs can produce confident incorrect outputs, and how retrieval grounding (RAG) or temperature=0 mitigates but doesn't eliminate this.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q1: How do LLMs work?](01-001-how-do-llms-work.md) | Prerequisite — establishes the autoregressive generative framing |
| [Q2: How do transformers work?](01-002-how-do-transformers-work.md) | Architecture basis — encoder vs decoder distinction maps directly to discriminative vs generative |
| [Q43: How do you reduce hallucinations in LLM outputs?](01-043-how-do-you-reduce-hallucinations-in-llm-outputs.md) | Follow-up — hallucination is a direct consequence of generative sampling |

---

## One-liner recall

> Discriminative models learn P(y|x) to classify; generative models learn P(x) or P(x,y) to synthesize — LLMs are autoregressive generative models that produce text by sampling P(next token | prior tokens), which is why they can hallucinate even at temperature=0.
