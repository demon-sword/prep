# AI Engineer Interview Questions (2026)

Compiled from 100+ real interview reports. Focus: **Applied AI / LLM Engineer**.

---

## Interview round structure

| Round | Weight | Focus |
|-------|--------|-------|
| Recruiter screen | Low | Background, project fit |
| Technical screen | High | LLM fundamentals, RAG basics |
| Technical deep dive | **Highest** | RAG design, eval, agents, tradeoffs |
| System design | **Highest** | End-to-end AI architecture at scale |
| Project deep dive | **Very common** | Your RAG/agent project — failures, metrics |
| Coding | Medium (company-dependent) | LeetCode medium OR ML implementation |
| Behavioral | Medium | Ambiguity, cross-functional, AI ethics |

---

## Most important patterns (ranked)

### 1. RAG pipeline design (#1 pattern)

Interviewers expect the **full production pipeline**, not a definition:

| Stage | What they probe |
|-------|-----------------|
| Ingest | Doc updates, sync with source of truth |
| Chunk | Fixed vs semantic, parent-child, metadata |
| Embed | Model choice, domain tokenization |
| Store | Vector DB, hybrid search (dense + BM25) |
| Retrieve | Top-k, filters, query rewriting |
| Rerank | Cross-encoder vs bi-encoder |
| Generate | Context placement ("lost in the middle") |
| Evaluate | Faithfulness, context precision/recall (RAGAS) |
| Observe | Tracing, regression golden sets |

**Classic failure arc:** retrieval fails → add more context → latency spikes → users lose trust. Fix retrieval first.

### 2. Prompt vs RAG vs fine-tuning

1. Prompt engineering first (cheapest)
2. RAG when knowledge is missing or stale
3. Fine-tune (LoRA/QLoRA) only when behavior can't be fixed above

### 3. LLM fundamentals (screening)

Transformers, tokenization, embeddings, temperature/top-p, KV cache, context windows.

### 4. Evaluation & hallucination (most under-prepped)

Golden datasets, faithfulness, relevancy, production metrics (deflection rate, p95 latency, cost/query).

### 5. Agents & tool use (fast-rising)

Agent vs chain, when agentic is wrong, tool schemas, cost explosion, HITL, prompt injection.

### 6. Cost & latency optimization

Semantic caching, model tiering, prompt compression, rerank on top-N only, streaming (TTFT).

### 7. Safety & guardrails (senior / regulated)

Prompt injection, PII, red-teaming, real incident postmortems.

### 8. Coding (varies by company)

| Company type | Bar |
|--------------|-----|
| FAANG / big tech MLE | LeetCode medium–hard |
| Pure AI startups (e.g. Anthropic) | Often no LeetCode — project walkthrough |
| Applied AI | Python/NumPy, SQL, implement k-means / logistic regression |

---

## Top 15 most asked questions

| # | Question | Round |
|---|----------|-------|
| 1 | Design a RAG system for a customer support chatbot. How do you evaluate it? | System design |
| 2 | Prompt engineering vs RAG vs fine-tuning — when do you use each? | Technical |
| 3 | How do transformers / self-attention work? | Technical screen |
| 4 | What are embeddings and how are they used in RAG? | Technical |
| 5 | How do you reduce hallucinations in LLM outputs? | Technical |
| 6 | What's the difference between an agent and a simple LLM chain? | Technical |
| 7 | When would you fine-tune vs use prompt engineering? | Technical |
| 8 | How do you evaluate a RAG pipeline? What metrics? | Technical / design |
| 9 | How do you detect and mitigate hallucinations in production? | Technical |
| 10 | Scale an AI chat feature to 1M daily users | System design |
| 11 | How do you reduce latency in GenAI applications? | System design |
| 12 | How do you optimize cost at 1M queries/day? | System design |
| 13 | Hybrid search: when combine vector + BM25? | RAG deep dive |
| 14 | What is re-ranking and why do you need it? | RAG deep dive |
| 15 | Walk me through an AI project you built — hardest tradeoff? | Behavioral / project |

**High-frequency follow-ups:** tokenization & cost, "lost in the middle", sparse vs dense retrieval, prompt injection, LoRA/PEFT.

---

## Frequency heatmap by seniority

From LockedIn AI session data:

| Level | Dominant topics |
|-------|-----------------|
| **0–2 yrs (screen)** | Transformers, tokenization, embeddings, prompt engineering |
| **2–5 yrs (mid)** | RAG design, evaluation, fine-tuning tradeoffs |
| **5+ yrs (senior)** | Agentic systems, production architecture, governance, team scaling |

---

# Question bank by category

## 1. LLM fundamentals

### Core concepts

- How do LLMs work?
- How do transformers work?
- What is tokenization and how does it affect LLM performance?
- What is the difference between pre-training and fine-tuning?
- Explain context windows and their limitations.
- What are scaling laws and why do they matter?
- What is temperature and top-p sampling? How do they affect outputs?
- Explain few-shot learning and chain-of-thought prompting.
- What is KV cache? How does it help in LLM inference?
- Can you describe the difference between GenAI and traditional programming for a real-world problem?
- How do you ensure LLM outputs are consistent and accurate in multi-step workflows?
- What's an RAG model? Explain the complete process.
- What are embeddings?
- How does chunking happen?
- What is the difference between discriminative and generative models?
- What is graph RAG? How does it differ from standard RAG?
- What is reflection in the context of LLM agents?
- Explain KL divergence.
- What is the difference between symbolic and connectionist AI?
- Describe text summarization techniques and when you'd use each.
- How do you do memory management and context management with LLMs?

### Architecture deep dives

- What is self-attention? How does it differ from multi-head attention?
- What is grouped query attention (GQA)? How does it differ from standard multi-head attention?
- BPE vs WordPiece vs character-level tokenization — tradeoffs?
- Encoder-only vs decoder-only vs encoder-decoder — when use each?
- Why are decoder-only models dominant even for non-generation tasks?
- What is positional encoding and why is it needed?
- MMLU, BigBench, HumanEval — what does each measure? Limitations?
- RLHF vs DPO — when prefer one over the other?
- What is Mixture of Experts (MoE)? How does it improve efficiency?
- How do LLMs generate text? Autoregressive decoding process.
- Beam search, top-k, top-p — when use each?
- What is FlashAttention and how does it work?
- Why is LLM inference memory-bounded?
- How do stop sequences work?
- What happens when you exceed the context window? How handle long documents?
- Risks of general-purpose tokenizers on legal/medical domains?

### Beginner staples (almost every screen)

- How does self-attention work in a transformer?
- What is tokenization, and why does it matter for cost and context windows?
- What is the difference between prompt engineering, RAG, and fine-tuning?
- What are embeddings, and how are they used in RAG?
- Semantic search vs keyword search?
- How do you reduce hallucinations in LLM outputs?
- What is the "lost in the middle" problem?
- When set temperature to 0 vs higher values?
- Bias-variance tradeoff?
- Overfitting — how prevent it?
- Imbalanced datasets — how handle?

---

## 2. RAG systems

### Architecture & design

- Design a RAG system for a customer support chatbot. How do you evaluate it? ⭐
- How would you design an LLM-powered enterprise search system?
- Design a GenAI document-processing pipeline for unstructured data (emails, PDFs, images).
- How would you use GPT-4 to generate accurate answers from proprietary documents?
- Design a generative QA assistant for your company's knowledge base.
- System processing huge PDF reports — how handle context when splitting documents?
- How efficiently generate and store embeddings for products and queries?
- How handle hallucination when no information is found in context?
- What RAG projects have you worked on?
- Design a Q&A system over internal documentation.
- How ensure quality of data the LLM interacts with?

### Retrieval strategies

- Compare sparse vs dense retrieval. When use each?
- Common RAG failure points — how debug them?
- How protect sensitive/confidential data in a RAG pipeline?
- What vector databases have you used? Which and why?
- Financial report: page 1 says "amounts in thousands" — how handle doc-wide context when chunking?
- What is hybrid search? When combine vector + BM25?
- What is re-ranking? Cross-encoder vs bi-encoder?
- Scale RAG to 10M+ articles — sharding, caching, retrieval optimization.
- RAG returns relevant docs but users can't find the answer — search engine vs answer engine?
- How evaluate a RAG pipeline? NDCG, MRR, precision@k, recall?
- Citations and source attribution in RAG?
- How does ANN search work? HNSW indexing?
- Where do embeddings fail? Negation, temporal reasoning, precision requirements.
- Semantic caching — reduce cost and latency?
- RAG with multi-turn conversation context?
- Key tradeoffs: latency vs accuracy, chunk size vs context, cost vs quality?
- Optimize RAG latency in production?

### RAG failure modes (production focus)

- Bad chunking (fixed-size vs semantic)
- Vocabulary mismatch (dense-only failing on keywords)
- Lost in the middle / context pollution
- Hallucination when retrieved context is irrelevant or absent
- Stale indexes, embedding drift
- Weak evaluation hiding retrieval failures

---

## 3. Agents & tool use

### Fundamentals

- What is an AI agent and its role in a broader system?
- Agent vs simple LLM chain? ⭐
- What makes a system truly agentic? What does NOT qualify?
- When is agentic architecture the wrong solution?
- How define and enforce agent autonomy boundaries?
- Essential components of an agent beyond an LLM?
- Prevent agents from over-reasoning or over-planning?

### Architecture

- Walk through a production-ready agent architecture.
- What logic belongs in orchestrator vs LLM?
- Design a safe and debuggable agent loop.
- Termination conditions in long-running agents?
- How decompose high-level goals into executable steps?
- Chain-of-thought vs tree-of-thought vs graph planning?
- Detect and stop infinite planning loops?
- Partial observability or missing information?
- How agents decide a task is "done"?
- Planning failures hardest to detect in production?
- Stateless vs stateful agents?
- Version and roll back agent behavior?
- Architect an agent system: loop, tools, memory, orchestration, safety.

### Tools

- How agents decide which tool to use?
- Tool schemas that reduce hallucinated actions?
- Sandbox tool execution safely?
- Tool failures, retries, idempotency?
- Biggest security risks with tool-using agents?
- Control cost explosions from tool calls?

### Memory

- Types of memory: working, episodic, semantic, procedural?
- Long-term memory without polluting it?

### Production & safety

- Human-in-the-loop patterns — when trigger human review?
- Monitor autonomous agent behavior in production?
- Agents in regulated domains (financial, healthcare)?
- Orchestration vs choreography for multi-agent systems?
- Filter PII before data reaches LLM?
- Evaluate agent performance — tool selection, action advancement, context adherence?
- Explain agentic systems to non-technical stakeholders?

### Design prompts

- Agent analyzing support tickets, drafting responses, escalating.
- Agents collaborating on research reports with citations.
- Agent reviewing code and suggesting improvements.

---

## 4. Fine-tuning & training

- When fine-tune vs prompt engineering? ⭐
- What is PEFT/LoRA and when use it?
- QLoRA vs LoRA — when choose one?
- What is RLHF and why important?
- Fine-tune or prompt-engineered RAG?
- Design a model for math problems — data, SFT, post-training, eval.
- Scalable efficient LLM training system — compute and data constraints.
- RLHF pipeline: SFT, reward model, PPO. How does DPO simplify?
- Instruction tuning vs pre-training?
- Speculative decoding — speed up inference?
- Convert implicit user behavior (edits, acceptance) into training signals?
- Quantization — tradeoffs between size, speed, accuracy?

---

## 5. Evaluation & metrics

### Hallucination

- What metrics for benchmarking LLM performance?
- How evaluate a chatbot?
- Detect and mitigate hallucinations in production? ⭐
- Prevent factual errors in summarization?
- Reduce hallucinations in a medical chatbot?
- LLM confidently wrong — debug RAG giving confident wrong answers?
- SHAP, LIME, model interpretability?
- Measure hallucination rate in production?

### Metrics & frameworks

- Perplexity, ROUGE, BLEU — pitfalls of n-gram metrics?
- Testing strategies for non-deterministic outputs?
- Measure accuracy in generative systems?
- Operational/business metrics: win rate, deflection rate, p95 latency?
- Evaluate and monitor model in production, not just offline?
- Bias/fairness tradeoffs — example?
- Time to first token — why matter for UX?
- "Vibes-based" eval vs formal eval framework?
- Golden dataset for evaluation and regression testing?
- Feedback and reinforcement loops — system gets better over time?
- Success metrics for an ML model?

### Testing strategies

- A/B testing for prompt variations?
- Test new model before full deployment — canary, interleaved, shadow?
- Two models, same accuracy, different confidence — which choose? Calibration?
- Chatbot accuracy dropped 95% → 80% in six weeks — diagnose before retraining?

---

## 6. ML fundamentals (still ~20–30% of interviews)

- Data pre-processing and feature engineering?
- SQL vs NoSQL for AI workloads?
- Diagnose performance bugs in a model?
- Optimize for latency or throughput? (personal assistant, one request)
- Data parallelism for single-request assistant?
- Transformers — why foundational? ⭐
- Real-time vs batch processing for data updates?
- Ingest structured, unstructured, event data?
- Bias-variance tradeoff?
- Why neural networks not first choice for tabular data?
- Imbalanced datasets in real projects?
- RNN vs LSTM?
- Debug model that runs but doesn't learn — broadcasting, dimension mismatches?
- Statistics: probability, distributions, regression, Bayesian, hypothesis testing?
- Supervised vs unsupervised learning?
- Regularization — L1, L2, dropout?
- Feature scaling — normalization vs standardization?
- Implement cosine similarity in NumPy (Amazon)
- Precision vs recall — fraud detection?
- F1 score, ROC curve?
- Linear vs logistic regression?
- Gradient descent?
- Classification algorithms?
- GANs basic principles?
- CNN architecture?
- BERT architecture?

---

## 7. Python & software engineering

- Race conditions in code?
- Python: immutable vs mutable passed to function?
- Python: `is` vs `==`?
- Build reproducible code?
- Sorted odd numbers from list without built-in sort?
- 2D maze shortest path?
- Parentheses — count needed to close all?
- Handle exceptions in GenAI applications?

---

## 8. Infrastructure & MLOps

- Design large-scale AI model deployment system?
- Distributed training for deep learning?
- Scalable data pipeline for ML?
- GenAI system handling traffic spikes without overwhelming provider?
- Monitor production AI systems?
- Major scaling challenges for LLM-powered applications?

---

## 9. Cost & latency optimization

### Most common (reported at multiple companies)

1. Your app gets 1M queries/day — how optimize cost? ⭐
2. How reduce token costs at scale? ⭐
3. How reduce latency in GenAI applications? ⭐

### Cost

- Cost and capacity planning for LLM app at scale?
- GPT-based API calls cost-efficient under heavy load?
- Quantization and model distillation for inference?
- Cost vs quality: when is small open-source model "good enough"?
- Trim prompts + cache embeddings — before/after cost breakdown?
- Multi-layer caching: retrieval, prompt, response?
- Model tiering — small distilled vs large LLM?
- Prompt compression?
- Budget estimate for RAG at enterprise scale (e.g. 300K legal contracts)?

### Latency

- Latency/cost/relevancy tradeoff triangle?
- Latency vs throughput for LLM serving?
- Benchmark each LLM call in multi-step pipeline?
- Real bottleneck in LLM serving throughput? PagedAttention?

---

## 10. Safety & guardrails

- When and how implement LLM guardrails?
- Minimize harmful outputs while staying useful?
- Detect policy violations / offensive content?
- Protect against prompt injection and jailbreaking?
- Handle exceptions in GenAI applications?
- Constitutional AI and alignment?
- Data privacy and PII in prompts and logs?
- Bias in training data and generated content?
- Red-team an LLM system?
- Generated code gets executed — prevent malicious code?

---

## 11. System design — AI

### Most frequently asked

- Design a RAG system for customer support ⭐
- Scale an AI chat feature to 1M daily users ⭐
- Design for 1M users (scale beyond prototype) ⭐

### Full list

- Design ChatGPT.
- Design Claude chat service.
- Small language model on a phone — polite and safe.
- Review junior dev's inference batching system design.
- Design OpenAI Playground (conversation/thread simulation).
- Real-time chatbot API — latency, sessions, concurrency, safety.
- Document Q&A Assistant.
- Hallucination-Free Banking Chatbot.
- Hospital Voice Assistant — noise, privacy, latency, domain vocab.
- Feedback Loop for Writing Tools.
- Legal Contract Generation with compliance.
- AI Search scaling to 10M+ articles.
- Resume Classifier for Team Routing.
- AI Candidate Sourcing — 750M profiles, semantic search, <500ms latency.
- Process 10k user uploads/month (payslips, IDs) — extract, validate, handle LLM downtime.
- Doctors auto-send billing to insurers from patient notes.
- Conversational recommender — chat + retrieval + DB.
- Fast autocomplete using LLMs.
- AI-powered legal assistant.
- Generative resume builder with memory.
- Internal Slack bot for HR questions.
- GitHub Copilot-style JS tool.
- AI co-pilot — real-time streaming completions.
- Midjourney/Stable Diffusion — queueing, GPU scheduling.
- Perplexity-style real-time LLM search.
- Ghibli Image Generator — prompt, model selection, GPU, cost throttling, safety.
- Dynamic Questionnaire Engine (JSON-driven insurance).
- User profile system — 100M users, batch migration.
- Distributed search — 1B docs, 1M QPS + 10K LLM req/s.
- Hybrid search — 10M docs, <50ms response.
- Remove dead links across hundreds of client websites.
- UX for slow AI assistant?
- Surface model limitations/errors without breaking trust?
- Scalable image-generation pipeline for millions.
- Scale generative content platform.
- In-Memory DB: SET, GET, BEGIN, ROLLBACK, COMMIT, nested transactions.
- AI recommendation system.
- Fraud detection system.
- Chatbot architecture end-to-end (LLM + backend + data flow).
- Distributed job queue for 100k+ GPU training jobs.
- Temperature prediction — inconsistent global datasets (hybrid ML-LLM).
- End-to-end RAG service: ingestion, indexing, retrieval, generation, evals, tracing, guardrails.
- Rate limiter (design + code core).
- Scaling AI to millions: latency, cost, batching, caching, streaming, failure modes.
- ChatGPT cross-conversation memory.
- Multi-step agentic workflow (scheduling, code review, email).
- Content/policy violation detection.
- Unified query engine across email, calendar, docs, chat.
- Implement AI application start to finish — kickoff through deployment.
- Scalable reliable automation workflow — error handling, monitoring, debugging.
- Real-time vs batch for data updates?
- Ingest structured, unstructured, event data?

---

## 12. System design — traditional (still asked at Amazon, Databricks, etc.)

- Design GitHub Actions, Slack, Online Chess, Payment System, Webhook Callback.
- TinyURL, Instagram/TikTok feed, Twitter/X, YouTube/Netflix, Uber.
- WhatsApp/Messenger, distributed KV store, Google Docs, Yelp/Maps.
- Rate limiter (global, per-user, distributed).
- Discord, Stripe, distributed job scheduler, notification system (1B/day).
- Strongly-consistent distributed DB, HFT matching engine.
- p99 latency 50ms → 2s overnight — debug and fix?
- Global WebSocket (10M+ connections).
- Global feature flag / config service.

---

## 13. System troubleshooting

- p95 latency 100ms → 2000ms — identify bottlenecks rapidly.
- 10x traffic spike during product launch?
- Primary data center offline six hours?

---

## 14. Coding — LeetCode / algorithms

Companies like Amazon still run full SWE coding bars.

- Word Search on Grid (Trie + DFS).
- LRU Cache — HashMap + Doubly Linked List, O(1).
- Prime numbers 0–100.
- Two strings anagrams?
- Serialize Binary Tree (space-optimized, backward compatibility).
- LeetCode 2408: Design SQL.
- LeetCode 981: Time Based Key-Value Store.
- Unix `cd` with symbolic link resolution.
- Reverse linked list (AI-assisted coding — prompt LLM effectively).
- Excel column name from number (702 → "AAA").
- Tree from list — index = node value, value = parent.
- CodeSignal GCA: 4 questions / 70 min.
- Union Find + DistilBERT sentiment on CSV.
- Banking app HashMap/TreeMap — task executor, pause tasks.
- gRPC timeout — async boundary, retries, DLQ, idempotency, scale.
- Serialization discussion — compression, streaming, backward compat (Microsoft senior).

---

## 15. Coding — company-specific

### OpenAI

- KV Store Serialize/Deserialize.
- In-Memory Database — SQL-like operations.
- Versioned key-value store (Time Travel Hash).
- Credits management — expiration rules, usage requirements.
- Refactoring round: 100–120 lines nested code → maintainable, tests green.

### Anthropic (4-level progressive)

- Level 1: SET/GET/DELETE
- Level 2: SCAN/SCAN_BY_PREFIX
- Level 3: Timestamped ops + TTL
- Level 4: File compression/decompression + storage management

---

## 16. Coding — ML / AI

- 1-NN and feedforward neural network.
- Transformer bug-fix — position embedding, KV cache.
- PyTorch code completion + complexity analysis.
- Multi-Head Attention from memory.
- Full Transformer layer from memory.
- LoRA adapter from scratch.
- Efficient LLM API batch processing.
- Debug embeddings code.
- Scripts preparing text for fine-tuning.
- gRPC financial report generation — async, threads, batch.
- NN, LSTM, RNN from scratch (NumPy/PyTorch).
- Cached attention and GQA variants.
- Beam search, top-k, top-p from scratch.
- Autoregressive generation with top-p sampling.
- Logistic regression — SGD, L2, early stopping (NumPy).
- Stratified K-fold splitting.

---

## 17. Coding — practical / data processing

- JSON extract + feed to AI model + summarize (30 min, browser allowed).
- Concurrent web crawler — robots.txt, rate limiting, circular refs.

---

## 18. Behavioral

### Project deep dives (very common 2026)

- Walk through an AI project end-to-end.
- Project you're most proud of — your role?
- Most challenging GenAI work?
- Time you reduced hallucinations/cost in production? ⭐
- Optimized process/workflow for efficiency or scale?
- Challenging prompt engineering problem you solved?
- Is there an actual eval framework, or vibes-based? ⭐
- Present "proud" project — design, tradeoffs, what broke, what you'd change.
- Past projects (Apple, Discord, Anduril).
- Recent/favorite project and difficulties (Meta).
- Technical challenge overcome.
- Greatest career accomplishment (Meta).
- What level of prompts have you written?

### Conflict & collaboration

- Conflict with another person — resolution and rationale (OpenAI).
- Collaborate with non-technical stakeholders?
- Workload in distributed team?
- Disagreed with teammate on approach?
- Struggled to work with colleague (Meta).
- Difficult stakeholder?
- Explain complex concept to non-technical person?
- Convinced someone to change their mind?
- Team members difficult to work with (Visa)?
- Communication to resolve ambiguity (Anthropic).

### Leadership & ownership

- Mentored teammates remotely?
- Drove technical decisions at scale?
- Mentored engineers to senior roles?
- Showed leadership (OpenAI EM).
- Led initiative / owned challenging task?
- Took initiative to solve a problem?
- Short-term sacrifices for long-term gains?
- Prioritize tasks?
- Lead under risk and uncertainty (Anthropic)?
- Manager trade-offs (OpenAI EM)?
- Team career growth (OpenAI EM)?
- Tight deadline project?
- Management style, execution, culture (Anthropic).

### Technical decision-making

- Preferred model provider for creative writing?
- Compare Cursor, Windsurf, Claude Code?
- Recent AI paper or development?
- AI side projects?
- Why particular storage over alternatives?
- How decide which model for inference?
- Frameworks familiar with? What built?
- Models and cloud providers worked with?
- Complex problem — how solved?
- Technical misjudgment caused delay (Anthropic)?
- Midway realized project unfeasible (Anthropic)?
- Quickly learn new technology for project?
- Real-time vs batch processing?

### Failure & learning

- Most challenging project?
- What would you do differently?
- Negative feedback — how handled?
- Mistake and lesson learned?
- Project didn't go as planned (Anthropic)?
- AI solution failed — how addressed (Google DeepMind)?
- Why should we NOT hire you? (Google, Visa)
- Think outside the box to complete task?

### AI-specific behavioral (very common 2026)

- Stay updated with fast-changing AI tech? ⭐
- Collaborate with non-technical stakeholders on AI features? ⭐
- Addressed ethical concerns in ML project?
- Safety-first decision (Anthropic)?
- Identified major risk in AI system (Mistral)?
- Reduced cost or latency in production AI system?
- Manage ambiguity in ML projects?
- Use AI coding agents in your work?
- Applied GenAI to non-traditional problem?
- Fact-check AI outputs — how validate?

### Culture & motivation

- Why OpenAI / Microsoft / this company?
- Why change now?
- Tell me about yourself.
- Walk through resume (OpenAI).
- Career decisions and culture fit (Anthropic).
- AI-safety conflicts with project goals (Anthropic)?
- Why pursue research?

---

## 19. Project deep dive round (structured presentation)

### Opening questions

- Most technically challenging project (OpenAI — 45 min to peer).
- Project you owned end-to-end — key decisions (Anthropic — 25 min + discussion).
- Project most proud of (OpenAI).
- Recent/favorite project and difficulties (Meta).

### Follow-up probes

- Why that storage/model/architecture over alternatives?
- Actual eval framework or vibes-based? (OpenAI)
- Alternative approaches considered and rejected?
- Different requirements or scale constraints?
- What broke in production?
- Cost and latency numbers?
- What would you rebuild differently?

---

## 20. Take-home assignments (common formats)

- Build a RAG pipeline over provided docs + eval report.
- Agent with 2–3 tools + demo video.
- Fine-tune small model on dataset + before/after metrics.
- Debug broken ML training pipeline.
- Design doc + partial implementation for AI feature.

---

## Quick prep checklist

- [ ] Answer top 15 out loud (3–5 min each)
- [ ] Whiteboard RAG 9-stage pipeline with failure modes
- [ ] Prompt vs RAG vs fine-tuning decision tree
- [ ] One system design: customer support RAG at 1M users (with cost/latency numbers)
- [ ] Project deep dive: 10 min + eval metrics + what broke
- [ ] Hybrid search + reranking explained with tradeoffs
- [ ] Hallucination mitigation layers (RAG, temp=0, faithfulness check, HITL)
- [ ] Agent vs chain + when NOT to use agents
- [ ] 3 cost/latency optimization questions with concrete levers
- [ ] DSA: keep NeetCode going if targeting FAANG

---

*Last updated: May 2026. Sources linked in [README](./README.md).*
