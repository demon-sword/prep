# Fine-tune or prompt-engineered RAG?

**Category:** 04-fine-tuning-training
**Question #:** 005
**Source section:** §4 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
This question probes whether a candidate understands the distinct failure modes that RAG and fine-tuning address, and whether they can make a principled cost-benefit call rather than defaulting to either extreme. Interviewers at mid-to-senior level want to see that you've shipped both approaches and have concrete signals for when one beats the other — not just abstract "it depends."

### Trigger phrases
- "Would you fine-tune the model or just add retrieval?"
- "We have a domain-specific QA problem — fine-tune or RAG?"
- "When is fine-tuning better than RAG + prompt engineering?"
- "Our RAG pipeline still produces bad answers — should we fine-tune?"

### What it tests
Ability to diagnose the root cause of an LLM product failure (knowledge gap vs behavior gap vs format gap) and select the correct adaptation mechanism, including cost-benefit reasoning and hybrid combinations.

---

## Answer

### Concept
Fine-tuning and RAG solve *different* problems: RAG closes a **knowledge gap** (the model lacks facts or they're stale), while fine-tuning closes a **behavior gap** (the model has the knowledge but can't reliably format, reason, or respond in the required style). Choosing the wrong tool — fine-tuning when you needed better retrieval, or RAG when the model can't follow the output format — is one of the most common production mistakes in applied AI.

### Mechanism

**Use RAG (prompt-engineered) when:**

1. **The failure is factual** — the model answers from stale training data or halluccinates facts that live in your private corpus (product docs, customer records, legal contracts). RAG retrieves the ground truth at query time.
2. **Your data changes frequently** — a fine-tuned model encodes knowledge at training time; RAG indexes are updateable within minutes via CDC pipelines (Debezium + Kafka + Pinecone upsert).
3. **You need citations / attributability** — RAG naturally surfaces source chunks; a fine-tuned model can't tell you *which document* it learned from.
4. **You have < 1K labeled examples** — RAG needs no training data, only a document corpus.
5. **You're in early product stage** — RAG iteration cycle is hours; fine-tuning is days-to-weeks.

**Use fine-tuning when:**

1. **The failure is behavioral, not factual** — the model knows the material but can't produce the right format (structured JSON, a specific citation style, medical SOAP notes), safety constraints, or tone consistently even with detailed prompting.
2. **Inference cost or latency is the constraint** — baking instructions and domain style into weights lets you use a smaller (cheaper, faster) model without a large system prompt or retrieval overhead. A fine-tuned Llama 3 8B can beat a prompted GPT-4o-mini at 10% of the cost per call.
3. **You have confidential data that can't enter prompts** — if proprietary context can't be injected into inference-time prompts (due to security or IP policy), fine-tuning encodes that knowledge into weights at training time on a controlled cluster.
4. **You need guaranteed output schema** — fine-tuning on structured-output examples is more reliable than prompt-only JSON extraction for complex nested schemas.
5. **RAG retrieval itself is the bottleneck** — if retrieval accuracy is the root cause and the relevant context is too diffuse to retrieve (general domain style, not specific documents), fine-tuning may outperform RAG.

**The hybrid pattern (most production systems eventually reach this):**

Fine-tuned model + RAG retrieval is the strongest combination: fine-tuning teaches the model *how* to reason, format, and respond; RAG provides *what* facts to reason over. Example: fine-tune a Llama 3 8B on your company's QA style (tone, citation format, structured output schema) with LoRA, then deploy it with a Pinecone RAG pipeline for live knowledge retrieval. This gives smaller model cost + dynamic knowledge + consistent behavior.

### Example / Tradeoff

**Customer support QA at a SaaS company (real pattern):**

- **RAG baseline:** GPT-4o-mini + Pinecone hybrid BM25+dense retrieval. Faithfulness RAGAS score 0.78, but 22% of answers used incorrect product-name casing, missed required disclaimer text, and returned inconsistent JSON for the ticket API.
- **Root cause diagnosis:** Retrieval recall@5 was 0.87 (good) — the facts were present. The failure was behavioral: the model couldn't consistently follow the output schema and safety instructions even with a 1K-token system prompt.
- **Fix:** LoRA fine-tuning on 8K labeled (ticket, response) pairs (Llama 3 8B, rank=32, α=64, 3 epochs). Kept RAG for live product catalog retrieval. Outcome: schema compliance 78%→99%, disclaimer adherence 81%→100%, cost $0.018/ticket → $0.004/ticket vs GPT-4o-mini RAG.
- **Tradeoff:** Fine-tune iteration cycle was 2 weeks (data curation + training + eval). The system prompt fix would have taken 2 hours — but it had already been tried 4 times without success, which was the signal to escalate to fine-tuning.

| Criterion | RAG | Fine-tune | Hybrid |
|-----------|-----|-----------|--------|
| Knowledge gap (missing facts) | ✅ Best | ❌ Poor (brittle memorization) | ✅ Best |
| Behavior/style gap | ⚠️ Partial (big prompt) | ✅ Best | ✅ Best |
| Data currency | ✅ Real-time updates | ❌ Stale at training | ✅ Real-time updates |
| Iteration speed | ✅ Hours | ❌ Days–weeks | ❌ Days–weeks |
| Inference cost | ⚠️ Retrieval overhead + large model | ✅ Smaller model possible | ✅ Smaller model + retrieval |
| Source attribution | ✅ Natural | ❌ None | ✅ Natural |
| Data need | No labeled data | 1K–100K examples | Both |

---

## Verbal script

**Opening (30s):**
"I treat this as a root-cause question before a solution question. The key diagnostic is: *why* is the current system failing? If it's failing because the model doesn't have the right facts — stale, private, or domain-specific — that's a knowledge gap and RAG is the right tool. If it's failing because the model *has* the knowledge but can't reliably format the answer, follow safety constraints, or produce the right tone, that's a behavior gap and fine-tuning is the right tool. The mistake I see most often is teams reaching for fine-tuning when they haven't fixed their retrieval."

**Core explanation (2–3 min):**
"So my decision framework starts with diagnosis. I'd look at RAGAS context_recall — if relevant chunks aren't being retrieved, fix retrieval first: hybrid search, better chunking, cross-encoder reranking. If recall is fine (0.85+) but the generated answers are still wrong in format or style, that's the signal to consider fine-tuning.

For RAG: it's the right default because it's updateable, needs no labeled training data, gives you source attribution, and iterates fast. It handles knowledge gaps well and can handle moderate behavior guidance through prompt engineering — a detailed system prompt with examples covers a lot of ground.

Fine-tuning earns its place when prompt iteration has genuinely failed — say, 3–4 serious attempts at improving the system prompt still produce inconsistent schema or tone — and when I have at least 1K labeled examples. In practice I'd use LoRA (rank 32, α=64, targeting q_proj/v_proj) on a smaller base model, which also solves the cost problem: a fine-tuned Llama 3 8B can often beat a prompted GPT-4o-mini at 10–20% of the per-call cost.

The strongest production pattern is the hybrid: fine-tune for behavior and style, RAG for live knowledge. Fine-tuning teaches the model *how* to respond; RAG tells it *what facts* to use."

**Tradeoff / production angle (1 min):**
"The practical tradeoff is iteration speed. RAG prompt changes deploy in hours; a fine-tuning cycle — data curation, training, eval, regression, deploy — is 1–2 weeks and requires the right infrastructure. So the break-even question is: have I spent more engineering time wrestling with the system prompt than a fine-tune cycle would cost? If yes, it's time to escalate. Also: fine-tuning encodes knowledge at a point in time — if your domain data changes weekly, you're now on a retraining treadmill, which tips the scales back toward RAG for the knowledge component."

**Wrap-up (30s):**
"So: RAG by default for knowledge gaps and early-stage products; fine-tuning when you have a confirmed behavior gap, ≥1K labeled examples, and prompt iteration has hit a ceiling. The hybrid of fine-tuned model + RAG retrieval is usually the production sweet spot for mature systems. Happy to go deeper on LoRA mechanics or how to build the labeled dataset for fine-tuning."

---

## Pitfalls

- **Mistake:** Saying "fine-tuning gives the model better knowledge of our domain" — **Better:** Clarify that fine-tuning primarily changes behavior and style, not reliable factual recall; for domain facts, RAG retrieval is more accurate and updateable; SFT can memorize facts but is brittle under paraphrase and causes hallucination on unseen facts
- **Mistake:** Jumping to fine-tuning after one or two failed RAG prompts, without checking retrieval quality — **Better:** Always check RAGAS context_recall first; if recall@5 < 0.80, the problem is retrieval, not generation — fix chunking, add hybrid BM25 search, or add a cross-encoder reranker before considering fine-tuning
- **Mistake:** Treating fine-tuning and RAG as mutually exclusive — **Better:** Describe the hybrid pattern explicitly: fine-tune for behavior/style/schema consistency, keep RAG for live knowledge retrieval; this is the dominant production architecture for mature QA systems

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q1: When fine-tune vs prompt engineering?](04-001-when-fine-tune-vs-prompt-engineering.md) | Parent decision: full cost ladder including RAG as a rung |
| [Q2: What is PEFT/LoRA and when use it?](04-002-what-is-peftlora-and-when-use-it.md) | Follow-up: mechanics of fine-tuning once you've decided to fine-tune |
| [Q21: How evaluate a RAG pipeline?](../answers/02-021-how-evaluate-a-rag-pipeline.md) | Critical prerequisite: you must evaluate retrieval quality (context_recall) before deciding RAG has failed |

---

## One-liner recall

> RAG fixes knowledge gaps (missing or stale facts); fine-tuning fixes behavior gaps (bad format, style, schema compliance despite good retrieval) — diagnose root cause with RAGAS context_recall before choosing, and use both together for mature production systems.
