# How protect sensitive/confidential data in a RAG pipeline?

**Category:** 02-rag-systems
**Question #:** 014
**Source section:** §2 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
This question probes production maturity and security consciousness. Interviewers want to know whether you think about data governance from the start or bolt it on as an afterthought. It tests knowledge of where data exposure happens in a RAG pipeline (ingestion, indexing, retrieval, generation, logs) and what concrete controls exist at each layer.

### Trigger phrases
- "How would you handle PII in a RAG system?"
- "Our knowledge base has confidential HR / legal / financial documents — how do you protect them?"
- "Walk me through your data security approach for a RAG pipeline."
- "What happens if a user queries for data they shouldn't see?"

### What it tests
Ability to reason about a defense-in-depth data security architecture across the full RAG pipeline — ingestion, retrieval, generation, and logging — using concrete tooling and access control patterns.

---

## Answer

### Concept
Sensitive data protection in RAG requires controls at **five distinct layers**: (1) ingestion / PII scrubbing, (2) access-controlled indexing, (3) retrieval-time ACL enforcement, (4) generation-time prompt hygiene, and (5) logging / observability redaction. Any single-layer approach leaves the other four exposed.

### Mechanism

**Layer 1 — Ingestion: PII detection and redaction**
- Run Microsoft Presidio (or AWS Comprehend) on every document before chunking.
- Detect entities: SSN, credit card numbers, email addresses, phone numbers, medical record numbers (HIPAA).
- Action: redact (`[REDACTED]`) or pseudonymize (replace with a consistent token for intra-doc coherence) before text reaches the chunker.
- Store original (unredacted) documents in a separate, access-controlled vault (e.g., S3 with KMS encryption + restrictive IAM policy); the vector store only holds sanitized text.

**Layer 2 — Indexing: document-level ACL metadata**
- Attach security metadata to every chunk at index time: `{"doc_id": "hr-review-2025", "acl": ["group:hr", "group:legal"], "classification": "confidential"}`.
- Pinecone, Weaviate, and Qdrant all support metadata filtering; Elasticsearch has document-level security.
- Never store raw sensitive fields (SSNs, salary) as filterable metadata — only ACL group identifiers.

**Layer 3 — Retrieval: per-user ACL enforcement**
- Before executing the ANN query, resolve the caller's identity (OAuth2 / Okta token) to their group memberships.
- Inject an ACL filter into every vector query: `filter={"acl": {"$in": user_groups}}`.
- This is the critical gate — if retrieval is bypassed, every downstream layer is irrelevant. Test it with dedicated security tests that verify a user from group A cannot retrieve group B documents.
- For Elasticsearch hybrid retrieval: apply the same document-level security (`_security` plugin or equivalent index-alias-based isolation).

**Layer 4 — Generation: prompt hygiene and output filtering**
- System prompt instructs the model not to reproduce verbatim sensitive content and to cite sources rather than quote at length.
- Post-generation: run a second Presidio pass on the LLM response before returning it to the user — catches cases where the model hallucinated or echoed PII from retrieved context.
- Consider differential privacy-style output filtering for medical / financial contexts (e.g., never output a string matching `\d{3}-\d{2}-\d{4}` SSN pattern).

**Layer 5 — Logging and observability**
- Redact queries and retrieved chunks in tracing systems (LangSmith, Langfuse, Datadog) before storage.
- Log access events (who queried, which doc IDs were retrieved) for audit, but not the actual content of sensitive chunks.
- Rotate and encrypt logs; apply the same retention policy as the source documents.

**Encryption and transport**
- All data in transit: TLS 1.3.
- All data at rest: AES-256 (S3 SSE-KMS, Pinecone at-rest encryption).
- Embedding vectors themselves can encode semantic information — treat the vector store as sensitive infrastructure, not just a performance cache.

### Example / Tradeoff

**Concrete stack (regulated HR knowledge base):**
- Presidio → MinHash dedup → parent-child chunker → Pinecone (ACL metadata) + Elasticsearch (doc security plugin)
- Retrieval: Okta group resolution → Pinecone metadata filter `{"acl": {"$in": groups}}` + ES doc-level security
- Generation: GPT-4o-mini T=0 with grounding prompt + Presidio post-gen scan
- Logging: Langfuse with PII fields redacted via custom middleware before storage

**Tradeoff — pseudonymization vs redaction:**
- Redaction (`[REDACTED]`) breaks intra-document coreference (e.g., "John Doe was promoted… he then…" loses the referent).
- Pseudonymization (consistent fake token per entity per document) preserves coherence but requires a secure entity-token mapping store; adds complexity and a new attack surface.
- For most RAG pipelines: redact at ingestion, preserve structure with parent-child chunking, and if coreference matters, use sentence-window retrieval to bring surrounding context without exposing the entity value.

**Scale consideration:** At 1M+ documents, PII scanning becomes a bottleneck. Run Presidio async in a processing queue (SQS + Lambda or Kafka), not synchronously in the ingestion path. Budget ~50ms/doc for Presidio on CPU; GPU-accelerated NER (spaCy with cuBLAS) can 10× throughput.

---

## Verbal script

**Opening (30s):**
"Great question — this is something I think about in layers, because a RAG pipeline has at least five places where sensitive data can leak, and securing only one leaves the rest open. I'd walk through ingestion, indexing, retrieval, generation, and logging."

**Core explanation (2–3 min):**
"Starting at ingestion: before any document gets chunked, I'd run Microsoft Presidio to detect and redact PII — SSNs, email addresses, credit card numbers, whatever's relevant to the domain. The original, unredacted documents live in an encrypted S3 vault with tight IAM policies; only the sanitized text reaches the vector store.

At the indexing layer, I'd attach ACL metadata to every chunk — something like `acl: ['group:hr', 'group:legal']` — using the vector DB's metadata filtering. Pinecone, Qdrant, and Weaviate all support this. The key discipline is that sensitive values like salary figures never go into filterable metadata fields.

The most critical layer is retrieval. When a user query comes in, I resolve their identity via the OAuth2 token — say Okta group memberships — and inject an ACL filter into the ANN query before it hits the index. This is the security gate that everything else depends on. I'd have dedicated security tests that assert group-A users cannot retrieve group-B documents, run on every deploy.

At the generation layer, my system prompt instructs the model to cite sources rather than quote verbatim, and I run a second Presidio pass on the LLM response before it goes back to the user. That catches cases where the model echoed PII from retrieved context.

Finally, for logging and observability — I'd redact sensitive content from traces in tools like Langfuse or Datadog, and log access events (who retrieved which doc IDs) for audit purposes without storing the chunk content itself."

**Tradeoff / production angle (1 min):**
"The main tradeoff I'd flag is pseudonymization vs redaction. Pseudonymization — replacing a name with a consistent fake token — preserves coreference chains within a document, which matters for narratives, but it adds a new secure mapping store to maintain. For most RAG pipelines I'd start with redaction and only add pseudonymization if context coherence is causing retrieval quality issues.

At scale, PII scanning becomes a throughput bottleneck. Presidio on CPU takes about 50ms per document; at 1M documents that's hours of synchronous blocking. I'd move it to an async processing queue — SQS and Lambda or Kafka — and use GPU-accelerated NER if throughput demands it."

**Wrap-up (30s):**
"So the mental model is: defense in depth across five layers, with retrieval-time ACL enforcement as the critical gate. I'd love to go deeper on any layer — the ACL filter injection, the PII scanning approach, or the logging redaction patterns."

---

## Pitfalls

- **Mistake:** Saying "we encrypt the data at rest and in transit" as the complete answer — **Better:** Encryption covers transport and storage but does nothing to prevent an authenticated user from retrieving documents outside their access scope; ACL enforcement at retrieval time is the real gate.
- **Mistake:** Scrubbing PII from the final LLM response only, ignoring the retrieval context — **Better:** Presidio (or equivalent) must run at ingestion before chunks reach the index; a model can reproduce PII from its context window even if you filter its output, so the source data must be clean.
- **Mistake:** Storing ACL-sensitive field values (salary, SSN) as vector metadata for filtering purposes — **Better:** Store only group/role identifiers in metadata; keep sensitive field values in a separate encrypted store; never let filterable metadata be a data exfiltration channel.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q11: How ensure quality of data the LLM interacts with?](02-011-how-ensure-quality-of-data-the-llm-interacts-with.md) | prerequisite — data quality controls are the foundation for security controls |
| [Q10: Design a Q&A system over internal documentation](02-010-design-a-qa-system-over-internal-documentation.md) | same architecture, adds ACL enforcement as a primary design constraint |
| [Q8: How handle hallucination when no information is found in context?](02-008-how-handle-hallucination-when-no-information-is-found-in-con.md) | related — abstention and grounding prompts serve double duty: accuracy and preventing data leakage via confabulation |

---

## One-liner recall

> Protect RAG data with five layers: Presidio PII redaction at ingestion, ACL metadata on every chunk, per-user group filter injected at retrieval (the critical gate), Presidio post-gen scan on LLM output, and PII-redacted logs — encryption alone is not access control.
