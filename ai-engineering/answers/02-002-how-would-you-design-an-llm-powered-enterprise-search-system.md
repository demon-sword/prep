# How would you design an LLM-powered enterprise search system?

**Category:** 02-rag-systems
**Question #:** 002
**Source section:** §2 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
This question tests whether you understand the difference between a *demo RAG app* and a *production-grade enterprise search platform*. Interviewers want to see: (1) multi-source data federation across heterogeneous corpora (Confluence, Slack, Salesforce, SharePoint, email, code repos); (2) access control and permission propagation so users only retrieve what they're authorized to see; (3) relevance architecture at scale (billions of docs, sub-100ms retrieval); (4) how you measure and iterate on search quality in an org where "ground truth" is hard to define; and (5) cost/latency tradeoffs between different user segments (executives vs. support agents vs. engineers).

### Trigger phrases
- "How would you design an LLM-powered enterprise search system?"
- "Walk me through building a search experience like Glean or Notion AI across our internal tools."
- "We have data in Confluence, Slack, Salesforce, and GitHub — how do you build unified search?"
- "How would you replace our internal Elasticsearch search with something AI-powered?"

### What it tests
System design maturity at the intersection of LLM generation, multi-source retrieval, permission-aware access control, and production quality measurement.

---

## Answer

### Concept
An LLM-powered enterprise search system unifies an organization's heterogeneous data silos into a single retrieval surface, then layers an LLM on top to synthesize answers — not just return links. The fundamental challenge vs. a public RAG system is **permission-aware retrieval**: a junior engineer must not retrieve a board-level financial doc, even if it is semantically relevant to their query. Everything else — chunking, embedding, ranking — is layered on top of this access-control foundation.

### Mechanism

**Architecture has four planes:**

**1. Connectors & Ingestion (offline)**

| Source | Connector pattern | Sync cadence |
|--------|------------------|--------------|
| Confluence / Notion | OAuth2 REST API + webhook on page update | Near-real-time (webhook) + nightly full crawl |
| Slack / Teams | Events API + message history crawl | Real-time (events) for new messages; daily for threads |
| GitHub / GitLab | Webhooks on push; code files + PR descriptions | Per-push; exclude secrets (`.env`, credentials) |
| Salesforce / HubSpot | Streaming API for CRM records | Polling / event-driven |
| Email (Exchange/Gmail) | IMAP or Graph API | Batch nightly; high PII risk — often excluded |
| SharePoint / Drive | Delta query | Near-real-time |

Each connector normalizes documents into a **canonical schema**: `{id, source, content, metadata, acl, updated_at, checksum}`. A change-detection layer (hash-diff or last-modified) suppresses full re-index churn.

**2. ACL-Aware Index (the hardest part)**

Every chunk in the vector store carries an **ACL token list** — the set of user/group IDs authorized to see it. At query time, the retrieval is pre-filtered by the calling user's identity:

```
retrieve(query, user_id):
  user_groups = identity_service.get_groups(user_id)  # cached, TTL 60s
  results = vector_db.search(
      query_vector,
      filter={"acl": {"$overlap": user_groups}},  # Pinecone metadata filter
      top_k=50
  )
```

This is **non-negotiable** — ACL enforcement cannot live only in the application layer (a bug there leaks data). It must be enforced at the retrieval layer. Pinecone, Qdrant, and Weaviate all support metadata filtering on vector search; push ACL lists into each chunk's metadata at index time.

**3. Retrieval & Ranking (online)**

```
User query
  → Query understanding (intent classification: Q&A vs. navigation vs. lookup)
  → Query rewriting (HyDE or simple expansion for recall)
  → Hybrid retrieval: dense HNSW + BM25 with ACL filter
      → RRF fusion → top-50
  → Cross-encoder reranker (Cohere Rerank v3 or ms-marco-MiniLM) → top-5
  → LLM synthesis (a small fast model for cost; a frontier model for complex)
  → Response with citations + source links + freshness timestamps
```

**Query understanding** is important at enterprise scale:
- Navigation queries ("where is the PTO policy?") → just return the URL, skip LLM synthesis
- Factual lookups ("what is our Q3 revenue?") → LLM synthesis with citations
- Exploratory queries ("what decisions were made about Project X?") → multi-chunk synthesis, longer answer

**4. Quality & Observability**

| Layer | Metric | Tool |
|-------|--------|------|
| Retrieval offline | NDCG@5, MRR, recall@5 on golden set | RAGAS, custom eval harness |
| Generation offline | Faithfulness, answer relevancy | RAGAS |
| Production | Click-through rate (CTR), thumbs-up rate, zero-result rate, p95 latency, cost/query | Prometheus + Grafana |
| Continuous learning | Clicked results → implicit positive signal; reformulated queries → implicit negative | Fine-tune embedder or reranker over 3–6 months |

### Example / Tradeoff

**Concrete stack (mid-size company, ~5M internal documents):**
- Connectors: custom OAuth adapters + Airbyte for commodity sources
- Normalization: Apache Kafka topic per source → Flink processor → canonical schema
- Embedding: `text-embedding-3-large` for English, `multilingual-e5-large` for global orgs; batch pipeline via Celery/Ray
- Vector store: **Qdrant** self-hosted (ACL metadata filters, payload indexing, open-source) or **Pinecone** serverless for managed
- BM25: Elasticsearch with per-index ACL field filter
- Reranker: Cohere Rerank v3 (API) or `cross-encoder/ms-marco-MiniLM-L-12-v2` (self-hosted, ~15ms at top-50)
- LLM: a small fast model (85% of queries) + a frontier model (complex reasoning, triggered by classifier)
- Auth: SAML/OIDC SSO → group membership from IdP (Okta, Azure AD) cached in Redis TTL 60s

**Tradeoff: freshness vs. relevance**
- Stale index: a document updated 10 minutes ago won't appear in results. For volatile sources (Slack, email), you need near-real-time sync or a freshness penalty heuristic that surfaces recently-modified docs higher.
- Solution: maintain a "recency bucket" — docs modified in the last 24h get a freshness score boost (e.g., multiply relevance score by 1.2), avoiding full re-embed for every edit.

**Scale numbers:**
- 5M docs × 3 chunks/doc avg = 15M vectors at 1536-dim = ~90GB in memory (Qdrant) or ~$450/mo (Pinecone serverless)
- p95 retrieval: ~120ms (HNSW + filter) + 200ms (rerank) = ~320ms retrieval; LLM adds 500–800ms
- Cost: $0.004–0.006/query at scale with a small fast model; semantic caching (GPTCache) cuts ~30% for FAQ-heavy usage

---

## Verbal script

**Opening (30s):**
"I'd think about this in four layers: connectors that normalize all your data sources into a common format, an ACL-aware index that enforces permissions at retrieval time (not just in the application layer), a hybrid retrieval and reranking pipeline to get the most relevant content to the LLM, and a quality loop that improves relevance over time using implicit signals. Let me walk through each."

**Core explanation (2–3 min):**
"The first challenge that's unique to enterprise search versus a public RAG system is access control. Every document chunk needs to carry its ACL — the list of user and group IDs allowed to see it — as metadata in the vector store. At query time, I filter by the calling user's group membership before doing ANN search. This is non-negotiable: you can't enforce permissions only at the application layer because one missed code path leaks data.

For connectors, I'd build source-specific adapters for each system — Confluence, Slack, GitHub, Salesforce — each producing a canonical document schema with content, metadata, ACL, and a checksum for change detection. I'd stream these through a Kafka topic into a normalization layer, then batch-embed with text-embedding-3-large for English content.

The retrieval layer is hybrid: dense HNSW for semantic similarity plus BM25 for exact-match terms like product names, ticket IDs, and code identifiers. I'd fuse with Reciprocal Rank Fusion to get 50 candidates, then run a cross-encoder reranker — either Cohere Rerank or a self-hosted ms-marco model — to get down to 5 genuinely relevant chunks before the LLM sees anything.

I'd also add query understanding upfront: if the query looks like navigation ('where is the expense policy?'), I skip LLM synthesis entirely and just surface the document link — that's 20–30% of enterprise search queries and costs nothing to serve correctly."

**Tradeoff / production angle (1 min):**
"The hardest operational challenge is freshness. Slack messages from 10 minutes ago matter for enterprise search; the nightly re-index cadence that works for support docs doesn't cut it here. I'd run near-real-time event-driven sync for high-velocity sources (Slack, email, Jira comments) with a freshness score boost for recently modified docs, so users don't distrust the system when they search for something they just saw.

For quality, I'd set up a golden query set — 500 representative queries across departments — with expected answer docs and expected answer content. Offline RAGAS metrics gate every retrieval or embedding change. In production, I'd track zero-result rate, thumbs-up/down, and query reformulations as implicit signals; after a few months, I'd fine-tune the reranker on clicked results to improve domain-specific relevance."

**Wrap-up (30s):**
"The system that trips most teams up is treating enterprise search like a public RAG demo — they skip ACL enforcement, use a single embedding model for all source types, and have no quality measurement. Get the permission layer right at index time, add hybrid retrieval for exact-match terms, and build a golden dataset before you ship. Happy to go deeper on any piece — ACL propagation, connector design, or the freshness vs. relevance tradeoff."

---

## Pitfalls

- **Mistake:** Describing the system without mentioning access control — **Better:** "ACL enforcement is the first thing I'd design: every chunk in the vector store carries a list of authorized user/group IDs from the source system, and retrieval filters on that list using the caller's identity — enforced at the DB layer, not just in application code."
- **Mistake:** Using a single uniform embedding model and chunking strategy for all sources — **Better:** "Slack messages (short, informal) need different chunking than Confluence pages (long, structured with headers). I'd tune chunk size and embedding model per source type, and consider a multilingual model if the org is global."
- **Mistake:** Saying "I'd just use one big model for everything" without segmenting query types — **Better:** "Navigation queries (30% of volume) get no LLM call — just a direct link. Simple factual queries go to a small fast model. Only complex synthesis queries (10%) justify a frontier model, which I'd trigger via an intent classifier."
- **Mistake:** No plan for keeping the index fresh for real-time sources like Slack — **Better:** "High-velocity sources need near-real-time event-driven sync with a freshness score boost; I'd separate them from slow-moving docs that can tolerate a nightly crawl."

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q1: Design a RAG system for a customer support chatbot](02-001-design-a-rag-system-for-a-customer-support-chatbot-how-do-yo.md) | Simpler single-source RAG; foundation for this multi-source design |
| [Q17: What is hybrid search? When combine vector + BM25?](02-017-what-is-hybrid-search-when-combine-vector-bm25.md) | Core retrieval strategy used in enterprise search |
| [Q14: How protect sensitive/confidential data in a RAG pipeline?](02-014-how-protect-sensitiveconfidential-data-in-a-rag-pipeline.md) | Expands on ACL enforcement and PII handling introduced here |

---

## One-liner recall

> Enterprise search = multi-source ACL-aware RAG: normalize all sources into a canonical schema with ACL metadata, enforce permissions at vector retrieval time (not app layer), use hybrid search + cross-encoder reranking, segment queries by type (navigation vs. factual vs. exploratory), and measure with a golden dataset + production click signals.
