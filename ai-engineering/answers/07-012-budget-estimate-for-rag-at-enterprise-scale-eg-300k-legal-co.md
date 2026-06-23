# Budget estimate for RAG at enterprise scale (e.g. 300K legal contracts)?

**Category:** 07-cost-latency
**Question #:** 012
**Source section:** §9 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
Interviewers at senior and staff levels want to know whether you can translate an AI architecture into real dollar figures before the project starts. Legal and enterprise document corpora are a canonical hard case: large ingestion cost, strict retrieval quality requirements, low query volume but high output quality demands, and potential compliance overhead. The question tests financial modeling instinct, cost-driver awareness, and the ability to justify infrastructure choices in a business context.

### Trigger phrases
- "We have 300K legal contracts — how would you estimate the cost to build a RAG system over them?"
- "What's your budget estimate for indexing and serving our document corpus?"
- "Walk me through cost modeling for an enterprise RAG deployment."

### What it tests
Whether you can decompose RAG costs into their three phases (ingestion, storage, serving), apply real pricing numbers, and communicate tradeoffs to non-technical stakeholders.

---

## Answer

### Concept
A RAG budget has three distinct phases: **ingestion** (a one-time or periodic batch cost), **storage** (ongoing monthly cost for the vector index), and **serving** (per-query cost for retrieval + generation). For 300K legal contracts, ingestion and storage dominate the initial budget; serving costs depend on query volume.

### Mechanism

**1. Corpus sizing**
- 300K contracts × ~15 pages average × ~500 words/page = ~2.25 billion words
- At ~0.75 tokens/word → ~1.7 billion tokens total
- After parent-child chunking (1024-token parents, 256-token children) with 20% overlap:
  - ~1.7M child chunks stored in vector index

**2. Ingestion cost (one-time)**

| Step | Tool | Cost estimate |
|------|------|--------------|
| PDF extraction (scanned/native) | AWS Textract ($1.50/1K pages) | 300K × 15 pages = 4.5M pages → **~$6,750** |
| Embedding generation | `text-embedding-3-small` ($0.02/1M tokens) | 1.7B tokens → **~$34** |
| Embedding generation (large, if needed) | `text-embedding-3-large` ($0.13/1M tokens) | 1.7B tokens → **~$221** |
| Compute/orchestration (Airflow, EC2) | | **~$200–$500** |
| **Total ingestion (one-time)** | | **~$7,000–$7,500** |

**3. Storage cost (monthly)**

| Component | Tool | Monthly cost |
|-----------|------|-------------|
| Vector index (1.7M × 1536-dim float32) | Pinecone s1 pod | **~$70/month** |
| Alternate: Qdrant self-hosted (8GB RAM) | 2× c6g.xlarge EC2 | **~$250/month** (includes HA) |
| Document object store (original PDFs, ~1TB) | S3 Standard | **~$23/month** |
| Metadata DB (PostgreSQL RDS t3.medium) | | **~$50/month** |
| **Total storage** | | **~$150–$350/month** |

**4. Serving cost (per-query)**

Assumptions: 5,000 queries/day (enterprise internal tool), average 3 chunks retrieved, cross-encoder reranking on top-20 candidates.

| Step | Cost per query |
|------|---------------|
| Query embedding | `text-embedding-3-small`: ~$0.00002 |
| ANN retrieval + reranking | Compute-bound, ~$0.001 (Cohere Rerank API) |
| Generation: GPT-4o-mini (2K input, 500 output) | ~$0.0009 |
| Generation: GPT-4o (for complex/sensitive docs) | ~$0.015 |
| **Blended (80% mini / 20% GPT-4o)** | **~$0.004/query** |

5,000 queries/day × $0.004 × 30 = **~$600/month**

**5. Evaluation + observability overhead**
- RAGAS golden-dataset eval (nightly, 200 queries × GPT-4o-mini judge): ~$5/night → **~$150/month**
- LangSmith traces: free tier covers 5K traces/day
- **Total eval/obs**: ~$150–$200/month

**6. Total monthly OpEx (steady state)**

| Category | Monthly |
|----------|---------|
| Storage | $150–$350 |
| Serving (5K queries/day) | $600 |
| Eval/observability | $150–$200 |
| **Total** | **$900–$1,150/month** |

**One-time ingestion: ~$7,500**

### Example / Tradeoff

**Self-hosted vs managed vector DB:** At 1.7M vectors, Pinecone (~$70/month) is cheaper than self-hosting Qdrant ($250/month HA) until you hit ~10M vectors or need strict data-residency for the legal corpus. For GDPR-regulated legal data, self-hosted Qdrant in a private VPC eliminates data-residency concerns and breaks even at scale.

**Textract vs native PDF parsing:** Scanned contracts add $6,750 in Textract costs upfront. If >80% of the corpus is digitally-born PDFs (selectable text), PyMuPDF parses them for free — only route scanned/image-heavy docs through Textract. This halves extraction costs.

**Sensitivity tiers:** Legal contracts often need citation-level accuracy. Run GPT-4o-mini for background synthesis tasks and GPT-4o only for clause extraction or compliance comparisons. This 80/20 blend keeps serving costs at $0.004/query vs $0.015/query for GPT-4o-only.

---

## Verbal script

**Opening (30s):**
"I'd break this into three phases: ingestion (one-time batch), storage (ongoing), and serving (per-query). The numbers look very different for each, and where you spend money depends a lot on query volume and quality requirements. Let me walk through each."

**Core explanation (2–3 min):**
"Starting with ingestion — 300K contracts at ~15 pages each is about 4.5 million pages. The dominant cost is extraction: if the contracts are scanned PDFs, AWS Textract at $1.50 per thousand pages comes to about $6,750. If they're native digital PDFs, PyMuPDF is essentially free, which changes the picture dramatically. After extraction, embedding generation at text-embedding-3-small pricing is around $34 for the full corpus. So ingestion runs $7,000–$7,500 one-time.

Storage is remarkably cheap. 1.7 million 1536-dimensional vectors fit in a Pinecone s1 pod for about $70 per month — or a self-hosted Qdrant cluster for $250/month if you need data residency for the legal corpus.

Serving is where the ongoing bill lives. At 5,000 queries per day — which is typical for an internal enterprise tool — using an 80/20 blend of GPT-4o-mini and GPT-4o, you're looking at about $0.004 per query, or roughly $600/month in generation costs. Add reranking via Cohere Rerank, storage, and eval observability, and your steady-state OpEx is around $900–$1,150 per month."

**Tradeoff / production angle (1 min):**
"The biggest lever is extraction method — native parsing vs. Textract changes upfront costs by $6,000+. The second lever is model tiering: routing routine queries to GPT-4o-mini and only complex clause analysis to GPT-4o cuts serving costs 5–10×. For a legal corpus specifically, I'd also flag that data residency and audit requirements may push you toward self-hosted infrastructure, which shifts the cost structure but gives you compliance headroom."

**Wrap-up (30s):**
"So in summary: about $7,500 to ingest, roughly $1,000/month to run at 5K queries/day, and the biggest optimizations are native PDF parsing where possible, model tiering, and self-hosting if data residency is non-negotiable."

---

## Pitfalls

- **Mistake:** Quoting only embedding + generation costs and ignoring ingestion/extraction — **Better:** Lead with the three-phase breakdown (ingestion, storage, serving) and note that ingestion is often the largest one-time cost for large corpora; for 300K scanned docs, Textract extraction alone can dwarf embedding costs by 200×.
- **Mistake:** Assuming all queries will use the largest/most expensive model — **Better:** Explicitly introduce model tiering (80% GPT-4o-mini / 20% GPT-4o) and show the cost delta; failing to tier is often a 5–10× overspend in enterprise RAG.
- **Mistake:** Ignoring storage costs or saying "vector DBs are cheap" without numbers — **Better:** Give concrete figures (Pinecone $70/month for 1.7M vectors; S3 $23/month for 1TB PDFs) and note that at 10M+ vectors, self-hosting becomes cheaper than managed services.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q1: Your app gets 1M queries/day — how optimize cost?](07-001-your-app-gets-1m-queriesday-how-optimize-cost.md) | Serving-cost optimization levers that reduce the per-query line item |
| [Q4: Cost and capacity planning for LLM app at scale](07-004-cost-and-capacity-planning-for-llm-app-at-scale.md) | General cost-modeling framework this answer instantiates for a specific domain |
| [Q10: Model tiering — small distilled vs large LLM?](07-010-model-tiering-small-distilled-vs-large-llm.md) | How to set up the 80/20 GPT-4o-mini/GPT-4o dispatch that drives cost savings |

---

## One-liner recall

> Enterprise RAG budget has three phases — one-time ingestion (~$7.5K for 300K legal contracts, dominated by PDF extraction), monthly storage (~$150–$350 for vector DB + object store), and per-query serving (~$0.004 blended with model tiering) totaling ~$1K/month at 5K queries/day.
