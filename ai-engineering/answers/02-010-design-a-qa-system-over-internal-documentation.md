# Design a Q&A system over internal documentation.

**Category:** 02-rag-systems
**Question #:** 010
**Source section:** §2 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
This is a scoped variant of the flagship RAG design question, filtered to the internal-docs context (Confluence, Notion, GitHub wikis, Google Docs). The interviewer is probing whether you can translate the generic 9-stage RAG pipeline into a concrete production system with access control, freshness, heterogeneous formats, and measurable quality — not just define RAG in the abstract.

### Trigger phrases
- "Design a Q&A system over our internal documentation."
- "Build a Slack bot that answers questions from our Confluence / Notion."
- "How would you let employees search company knowledge?"
- "We have 50K engineering docs — how do we make them queryable?"

### What it tests
Ability to architect a production RAG pipeline tailored to internal knowledge bases — including ACL enforcement, connector freshness, hybrid retrieval, and a measurable evaluation framework.

---

## Answer

### Concept
An internal-docs Q&A system is a RAG pipeline that ingests heterogeneous company knowledge (wikis, runbooks, Slack threads, PDFs), maintains access-controlled vector and keyword indexes, retrieves the most relevant passages for each query, and generates cited, grounded answers — replacing "grep the wiki" with a conversational interface.

### Mechanism

**1. Ingestion & connectors**

| Source | Connector | Update cadence |
|--------|-----------|---------------|
| Confluence | Atlassian REST API v2 | Webhook on page update |
| Notion | Notion API | Polling every 15 min |
| GitHub wikis / Markdown repos | GitHub webhook | Push event |
| Google Docs | Drive API + push notifications | Push notification |
| PDFs / uploaded files | S3 trigger → extraction queue | On upload |

Each connector extracts: raw text, `doc_id`, `space_id` (for ACL), `author`, `last_modified`, `url`.

**2. Preprocessing**
- Markdown / HTML → plain text via `markdownify` or `BeautifulSoup`.
- Table extraction: Pandas or Unstructured.io → Markdown table string.
- Recursive/semantic chunking: 512-token chunks with 64-token overlap, preserving heading hierarchy as metadata (`h1`, `h2` fields).
- Parent-child: store full page as parent (for citation link), 512-token children as retrieval units.

**3. Embedding & indexing**
- Embedder: `text-embedding-3-small` (1536-dim) or `bge-large-en-v1.5` (self-hosted, ~40% cost reduction at scale).
- Vector index: Pinecone or Qdrant — namespaced by `space_id` / team for ACL isolation.
- Keyword index: Elasticsearch BM25 on same chunks — critical for exact-match queries (error codes, function names, acronyms).
- Metadata stored per chunk: `doc_id`, `space_id`, `acl_group_ids[]`, `last_modified`, `heading_path`.

**4. ACL enforcement**
- At query time: extract the requesting user's `group_ids` from SSO (Okta / Azure AD).
- Vector DB filter: `acl_group_ids` intersection with user groups (Pinecone metadata filter, Qdrant payload filter).
- Never rely on post-retrieval ACL filtering alone — enforce at retrieval to prevent data leakage.

**5. Query processing**
- Optional query rewrite: `"how do I deploy?"` → `"deployment process steps production environment"` via a lightweight rewrite LLM call.
- Hybrid search: dense retrieval (top-20) + BM25 (top-20), fused via Reciprocal Rank Fusion (RRF).
- Cross-encoder reranking: Cohere Rerank or `cross-encoder/ms-marco-MiniLM-L-6-v2` over top-40 → select top-5.

**6. Generation**
- System prompt: "Answer using only the provided context. If the answer is not in the context, say 'I don't have that information.' Cite sources with [doc title](url)."
- Temperature: 0 for factual grounding.
- Model: GPT-4o-mini for standard queries (~$0.15/1M input tokens); escalate to GPT-4o for complex multi-part questions (routed on query complexity score).
- Response includes inline citations with source URL and last-modified date.

**7. Evaluation**
- RAGAS: `faithfulness` (answer grounded in retrieved docs), `context_recall` (does retrieval surface the right docs), `answer_relevancy`.
- Golden dataset: 50–100 curated (question, expected answer, expected source) tuples — run on every index rebuild.
- Business metrics: answer acceptance rate (thumbs up/down), query deflection from support tickets, p95 latency.

**8. Observability**
- Trace each query: retrieval scores, reranker scores, tokens used, model selected.
- Alert on: `faithfulness < 0.8` on golden set, retrieval latency p99 > 500ms, ACL filter returning 0 results (likely SSO misconfiguration).

### Example / Tradeoff

A concrete stack for a 500-person engineering org with ~30K Confluence pages:

| Component | Choice | Why |
|-----------|--------|-----|
| Connectors | Atlassian webhooks + Notion polling | Real-time for Confluence, acceptable lag for Notion |
| Embedder | `text-embedding-3-small` | $0.02/1M tokens, 1536-dim, strong on technical English |
| Vector DB | Qdrant (self-hosted) | Cost control at 30K docs, Okta group payload filters |
| Keyword index | Elasticsearch 8.x | BM25 for function names, error codes, acronyms |
| Reranker | Cohere Rerank API | 10ms p99 add, +15% answer accuracy vs no rerank |
| Generator | GPT-4o-mini (default) / GPT-4o (escalated) | Cost: ~$40/day at 5K queries/day |
| Delivery | Slack `/ask` command + web UI | Meets users where they work |

**Key tradeoff — freshness vs cost:** Webhook-driven ingestion keeps docs current but adds connector complexity. For a first version, nightly batch re-index is simpler but risks stale answers. Use webhooks only for high-churn spaces (e.g., engineering runbooks) and batch for archival content.

---

## Verbal script

**Opening (30s):**
"I'd frame this as a specialized RAG system optimized for three things the generic case often ignores: access control, document freshness, and heterogeneous source formats. Let me walk through the key design decisions."

**Core explanation (2–3 min):**
"I'd start with connectors — one per source type. For Confluence I'd use their REST API v2 with webhook notifications so updates propagate within seconds. For Notion I'd poll every 15 minutes since their webhook support is less reliable. Each connector extracts text, metadata, and crucially the ACL groups that can see the document.

For chunking, I'd use recursive chunking at ~512 tokens with 64-token overlap, preserving the heading hierarchy as metadata. This matters because a question about 'deploying the payment service' should surface the H2 section inside a larger runbook, not a random 512-token window.

The index is dual: a vector store — I'd use Qdrant or Pinecone — namespaced by team space, and an Elasticsearch BM25 index. The keyword index is non-negotiable for internal docs because users query exact error codes, function names, and product acronyms that embeddings struggle with.

ACL enforcement happens at the retrieval layer: I extract the user's Okta groups, pass them as a metadata filter to Qdrant, and the BM25 query also filters by `acl_group_ids`. Never do post-retrieval ACL filtering — you risk leaking document titles or snippets from unauthorized sources.

At generation, I use GPT-4o-mini with temperature=0 and a grounding prompt that instructs the model to cite sources with URL and last-modified date. If the retrieved context doesn't contain the answer, the model says so explicitly rather than hallucinating."

**Tradeoff / production angle (1 min):**
"The big tension I've seen in practice is freshness vs. simplicity. Webhooks give you near-real-time updates but each connector is a failure surface. For v1, I'd do nightly batch re-ingestion for stable docs and webhooks only for the highest-churn spaces. The second tension is retrieval coverage vs. noise — bigger top-k catches more relevant docs but pollutes the context window and inflates cost. A cross-encoder reranker lets you cast a wide net at retrieval (top-40) then narrow to top-5, keeping answer quality high without ballooning prompt size."

**Wrap-up (30s):**
"The north star metric I'd track is answer acceptance rate — thumbs up/down from users — alongside a RAGAS golden dataset run on every index rebuild. That combination catches both retrieval failures and hallucinations before they erode user trust. Happy to go deeper on ACL patterns, evaluation setup, or the reranker choice."

---

## Pitfalls

- **Mistake:** Describing the system without mentioning ACL/access control at all — **Better:** Explicitly cover per-user group filtering at the retrieval layer (Qdrant payload filter, Pinecone metadata filter) and explain why post-retrieval filtering is insufficient.
- **Mistake:** Using only dense vector search for an internal-docs system where users query exact error codes, function names, and acronyms — **Better:** Describe hybrid BM25+dense retrieval with RRF fusion; keyword search is critical for internal technical vocabulary that embeddings mangle.
- **Mistake:** Proposing nightly batch re-index as a complete freshness solution without acknowledging the stale-answer failure mode — **Better:** Distinguish high-churn spaces (engineering runbooks → webhooks) from archival content (historical design docs → nightly batch), and mention surfacing `last_modified` in the answer citation so users can judge freshness themselves.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q1: Design a RAG system for a customer support chatbot](02-001-design-a-rag-system-for-a-customer-support-chatbot-how-do-yo.md) | Parent pattern — same 9-stage pipeline, different domain and access-control requirements |
| [Q5: Design a generative QA assistant for your company's knowledge base](02-005-design-a-generative-qa-assistant-for-your-companys-knowledge.md) | Near-identical framing — compare ACL, freshness, and model-tiering strategies |
| [Q17: What is hybrid search? When combine vector + BM25?](02-017-what-is-hybrid-search-when-combine-vector-bm25.md) | Core retrieval mechanism — RRF fusion is central to internal-docs system quality |

---

## One-liner recall

> Internal-docs Q&A = standard RAG pipeline plus three non-negotiables: per-user ACL filtering at retrieval time (not post-filter), hybrid BM25+dense search for exact internal terminology, and webhook-driven freshness for high-churn spaces.
