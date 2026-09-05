# Data privacy and PII in prompts and logs?

**Category:** 08-safety-guardrails
**Question #:** 007
**Source section:** §10 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
This question separates people who have shipped an LLM feature at a company with a real legal team from people who have shipped a demo. The weak answer is "we run a regex for emails and SSNs before logging." The interviewer is checking whether you know that PII enters and leaves an LLM system at *multiple* boundaries — ingestion, query time, log write, eval dataset, prompt cache — and that a leak at any one of them is a leak. For anyone interviewing at a healthcare, fintech, or enterprise SaaS company, this is a gating question: if you can't name the boundaries and the redaction strategies, you will not be trusted with production data.

### Trigger phrases
- "How do you handle PII in prompts and logs?"
- "We're in healthcare — how would you make this HIPAA-compliant?"
- "What happens to user data when you send it to a third-party model API?"
- "A user invokes GDPR right-to-erasure. Your data is in a vector index. What now?"
- "Can you log conversations for debugging?"

### What it tests
Whether you can enumerate every boundary where personal data enters or persists in an LLM pipeline, pick the right de-identification technique per boundary, and reason honestly about the residual risk you cannot fully eliminate.

---

## Answer

### Concept
PII handling in an LLM system is a **boundary problem, not a filter problem**. There is no single place to "scrub PII"; there are at least five places personal data can come to rest — the vector index, the outbound API request, the log/trace store, the eval dataset, and the provider's prompt cache — and each needs its own control. The engineering decision at each boundary is which de-identification technique to use, and the key distinction is **reversible vs irreversible**: redaction destroys the entity, pseudonymization and tokenization preserve a mapping so the answer can still refer to the real person. This maps to OWASP LLM02 (Sensitive Information Disclosure) and LLM08 (Vector and Embedding Weaknesses) in the 2025 Top 10.

### Mechanism

**Detection first: why regex alone fails.**

Regex is genuinely excellent for **structured** identifiers — SSN, credit card (plus a Luhn checksum to kill false positives), IBAN, phone, email, IP, MRN, policy number. It is close to useless for **unstructured** identifiers: names, street addresses, employers, job titles, dates of birth in prose, free-text clinical narrative. There is no pattern for "Sarah" that doesn't also match "Sarah Lawrence College" and every other capitalized token. You need NER.

The production answer is a **hybrid**, which is exactly what **Microsoft Presidio** is architected as: an `AnalyzerEngine` that runs (a) `PatternRecognizer` regexes with checksums, (b) a spaCy or Hugging Face transformer NER model for `PERSON` / `LOCATION` / `ORGANIZATION` / `DATE_TIME`, and (c) **context enhancement** — a token near the word "SSN:" gets its confidence score boosted — then an `AnonymizerEngine` with per-entity operators (`replace`, `mask`, `hash`, `encrypt`, `redact`). You extend it with deny-lists (your own employee directory, internal project codenames) and custom recognizers for domain identifiers.

Realistic accuracy expectations, which you should state rather than pretend: structured entities land around 98–99% recall with near-zero FP once checksummed; person names and addresses in messy prose land more like **90–95% recall** with a transformer NER model, and drop further on non-English text, transliterated names, and OCR'd documents. **Plan for the misses** — that is why redaction is a layer, not the whole strategy.

Latency: a spaCy-based Presidio analyzer runs roughly **10–30ms** per short message on CPU; a transformer NER backbone is more like **40–80ms** on CPU and 10–20ms on GPU. On a 2–4KB RAG chunk you are looking at 100–300ms, which is why ingestion-time scrubbing is a batch job and query-time scrubbing is on the hot path.

**The three boundaries (plus two people forget):**

```
                         ┌─────────────────────────────────────┐
  Source documents ──────► BOUNDARY 1: Ingestion               │
  (tickets, PDFs, CRM)   │  Presidio scrub BEFORE chunking     │
                         │  + embedding. Batch, latency-free.  │
                         └──────────────┬──────────────────────┘
                                        ▼
                                  [Vector index]  ◄── embeddings are NOT anonymous
                                        │
  User query ──────┐                    │
                   ▼                    ▼
        ┌───────────────────────────────────────────┐
        │ BOUNDARY 2: Query time, pre-API-call      │
        │  Scrub/tokenize user msg + retrieved ctx  │
        │  BEFORE the outbound provider request     │
        └──────────────┬────────────────────────────┘
                       ▼
                 [Model provider]  ◄── DPA + zero-data-retention
                       │
                       ▼
        ┌───────────────────────────────────────────┐
        │ Detokenize (if reversible) → user         │
        └──────────────┬────────────────────────────┘
                       ▼
        ┌───────────────────────────────────────────┐
        │ BOUNDARY 3: Log / trace write path        │
        │  Scrub BEFORE the write, not after.       │
        │  Covers app logs, LLM traces, APM, error  │
        │  reporting, analytics events.             │
        └───────────────────────────────────────────┘

  ALSO: BOUNDARY 4 — eval / golden datasets (copied from prod traffic)
        BOUNDARY 5 — provider-side prompt cache & your own semantic cache
```

**Boundary 1 — Ingestion into the vector store.** Scrub *before* chunking and embedding, never after. Once text is embedded, the PII is in the vector, and re-scrubbing the source text does not change the vector. This is a batch job, so you can afford a transformer NER model and a second-pass LLM reviewer on low-confidence spans.

**Boundary 2 — Query time, before the outbound API call.** The user's own message often contains PII they typed voluntarily ("my account is under Jane Okafor, DOB 4/12/81"). Retrieved context may contain PII that survived Boundary 1. This runs synchronously on the hot path, so budget 20–50ms and use the cheaper analyzer configuration.

**Boundary 3 — The log write path.** This is the one that actually causes incidents, because logging is the most decentralized part of a system. It is not one place: application logs, LLM observability traces (LangSmith / Langfuse / Arize / OpenTelemetry GenAI spans), APM, error reporting (a stack trace with the prompt in the exception message), analytics events, and the request logs of whatever gateway sits in front. Redaction must be a **library in the write path**, not a scheduled cleanup job — if raw text touched disk, you had a breach, and deleting it afterward doesn't undo that. Enforce it with a shared logging wrapper plus a CI check that fails on raw `logger.info(prompt)`.

**Boundary 4 — Eval and golden datasets.** Teams scrub prod logs meticulously, then copy 500 real conversations into a golden set that lives in a git repo readable by the whole company. Same treatment, same retention policy, and never in a repo with broader access than the log store.

**Boundary 5 — Caches.** Your own semantic cache stores prompt text keyed by embedding; that is a PII store. Provider-side prompt caching means your prefix is retained server-side for the cache TTL, which needs to be reflected in your DPA analysis. Do not put per-user PII in a cached prefix.

**Choosing the de-identification technique:**

| Technique | What it does | Reversible | Use when | Cost / risk |
|-----------|--------------|------------|----------|-------------|
| **Redaction** | `Jane Okafor` → `[REDACTED]` | No | Logs, analytics, training corpora — anywhere you never need the entity back | Destroys coreference: "she" in the next sentence dangles, and the model loses the thread across a multi-turn conversation |
| **Masking** | `4111-1111-1111-1111` → `****-****-****-1111` | Partial | Support UIs where the last 4 confirm identity | Last-4 plus other fields can re-identify |
| **Pseudonymization** | `Jane Okafor` → `PERSON_1`, consistently within a session | No (mapping not stored) | Prompts where the model must reason about *distinct* entities but never name them | Consistent labels preserve coreference and relational reasoning — the big win over flat redaction |
| **Tokenization w/ reversible vault** | `Jane Okafor` → `<<PII:a83f>>`, mapping in an encrypted KMS-backed store | **Yes** | The answer must name the real person: "Draft an email to Jane confirming her appointment" | Requires a vault, key rotation, access logging; vault compromise = full re-identification |
| **Format-preserving encryption** | Structured IDs stay same-shape | Yes | Downstream systems validate format (account numbers) | Deterministic ciphertext leaks equality |
| **Hashing** | `email` → `sha256(email + salt)` | No | Joining analytics across events without storing the identifier | Unsalted hashes of low-entropy PII (emails, phone numbers) are trivially reversed by brute force — **always salt** |

**Why reversible tokenization is the one people miss.** The naive design redacts everything before the API call. Then the user asks "email Jane the confirmation" and the model has only `[REDACTED]` — the feature is broken. The fix is a tokenize/detokenize sandwich: replace each entity with an opaque token, send the tokenized prompt to the provider, and swap the real values back into the response after generation, in your own trust boundary. The model reasons over `<<PII:a83f>>` and never sees the name; the user sees "Jane." This gets you a genuine architectural property: **the provider never receives identifiable data, so a large class of DPA and cross-border transfer questions gets much simpler.** Costs: the token must be stable within a conversation, must survive the model paraphrasing around it, and you need a fallback for when the model mangles or invents a token — validate every token in the output against the vault and drop unrecognized ones.

**Embeddings are personal data.** Treat this as settled. Embedding-inversion research (GEIA, and the "Text Embeddings Reveal (Almost) As Much As Text" line of work, with recent zero-shot inversion methods) recovers named entities and sensitive spans from sentence embeddings at **recovery rates above 80%** against common encoders, sometimes with no paired training data at all. The operational consequence: **shipping embeddings of confidential documents to a third-party vector service is materially equivalent to shipping the documents**, and a vector index breach is a document breach. So: scrub before embedding, encrypt the index at rest, treat the vector DB as an in-scope system for your DPA and audit, and don't assume "it's just numbers" survives contact with a regulator.

**Provider-side controls (the contract layer):**
- A **DPA** with the model provider naming them a processor, with sub-processor disclosure and approved transfer mechanism (SCCs) if data crosses borders.
- **Zero-data-retention / no-training-on-inputs** — usually available on enterprise or platform-hosted tiers, often as an account flag or endpoint variant, and sometimes *not* on the default consumer-grade key. Verify it in writing for the exact key you ship with; this is a common and embarrassing gap.
- For HIPAA: a **BAA** must be in place before any PHI touches the API, and the same applies to your vector DB vendor and your observability vendor. Every processor in the chain, not just the model.
- **Self-hosted / VPC deployment** of an open-weight model is the answer when the data legitimately cannot leave your boundary — you trade capability and ops burden for eliminating the transfer question entirely.
- Retention: default logs to **30 days**, PII-adjacent traces shorter, with documented, automated deletion. "We keep everything forever in case it's useful" is not a retention policy.

**Right to erasure against a vector index.** GDPR Art. 17 is where LLM architecture and privacy law collide, and interviewers love it because most candidates have never thought about it. Deletion has to propagate to five places:

1. Source system of record — easy.
2. **Vector index** — you must be able to find every vector derived from that subject. This only works if you wrote a `subject_id` into the chunk metadata at ingestion time. Retrofitting is a re-index of the whole corpus, which is why this is an ingestion-time design decision, not a deletion-time one. Note also that most ANN indexes (HNSW especially) do *soft* deletes — the vector is tombstoned and excluded from results but still resident in the graph until a compaction or rebuild. "Deleted from search results" is not "erased from disk," and you need a scheduled rebuild to make the claim true.
3. **Logs and traces** — deletable only if indexed by subject; otherwise you rely on short retention, which is a legitimate and much simpler strategy.
4. **Caches** — semantic cache entries and any cached prefixes must be invalidated.
5. **Model weights** — if you fine-tuned on data containing that subject, you cannot surgically remove them. Machine unlearning is a research area, not a compliance control. The practical mitigations are: don't fine-tune on raw PII (scrub the training corpus), or accept that the remedy is retraining the adapter. Say this plainly in an interview — the honest "you can't, so here's how I avoid needing to" is a much stronger answer than pretending deletion is total.

### Example / Tradeoff

**Healthcare claims-support assistant (RAG over 4M claim notes + call transcripts, ~200K queries/day):**

- **Ingestion:** nightly Presidio batch with a transformer NER backbone plus custom recognizers for MRN and policy number; low-confidence spans (<0.6) routed to an LLM second-pass reviewer. Every chunk carries `member_id` in metadata specifically so erasure is a metadata filter delete rather than a corpus rebuild. Cost: ~3 hours of batch compute per full re-index, which is invisible to users.
- **Query time:** tokenize-with-vault, not redaction — the assistant has to say "Jane's claim was denied on 12 March," so member name, DOB, and MRN become vault tokens before the outbound call and are swapped back after. Added latency **~35ms p50, ~70ms p95** for analyze + tokenize, plus ~5ms detokenize. Against a ~1.4s end-to-end response, that is under 6% overhead — an easy sell.
- **Logs:** a single logging wrapper with Presidio in the write path; a CI lint rule fails any PR that passes a prompt or completion object to a logger directly. 30-day retention on scrubbed traces, 7 days on anything flagged PII-adjacent.
- **Provider:** enterprise endpoint with zero-data-retention enabled and confirmed in writing, BAA executed with the model provider, the vector DB vendor, and the observability vendor.
- **Residual-risk register** (the artifact that made legal comfortable): a written list of what is *not* covered — NER misses roughly 5–8% of unusual names and OCR-mangled addresses; free-text fields where a member writes their neighbor's name; the vault itself as a single point of re-identification; and prompt-cache prefixes. Each with a compensating control.

**The central tradeoff — over-redaction destroys utility.** Aggressive scrubbing at query time turns "Why was Jane Okafor's claim from 12 March denied?" into "Why was [PERSON]'s claim from [DATE] denied?" and the retrieval quality collapses because the discriminating tokens are gone, then the answer is useless because it can't name anything. Measured on that system: naive full redaction dropped retrieval recall@10 by roughly 15 points versus consistent tokenization, which preserves the entity as a stable, distinct symbol. **The technique choice is a retrieval-quality decision as much as a privacy decision**, and that is the sentence that shows you've actually built one of these.

**The other tradeoff — latency and failure mode.** Every boundary adds a synchronous hop. And you must decide what happens when the PII service is down: fail-open (ship unscrubbed data to the provider) or fail-closed (drop the request)? For regulated data the answer is fail-closed, and that means your PII service's availability is now your product's availability. Budget for it — run it in-process as a library rather than as a network hop where you can, precisely to avoid adding a dependency that can take you down.

---

## Verbal script

**Opening (30s):**
"I'd reframe this slightly, because 'handle PII' sounds like one filter and it's really five boundaries. Personal data can come to rest in the vector index, in the outbound API request, in the log and trace store, in eval datasets copied from prod, and in caches. A leak at any one of those is a leak, so I'd walk the boundaries, and at each one the real decision is which de-identification technique — because that choice has a big effect on whether the product still works."

**Core explanation (2–3 min):**
"Detection first. Regex is great for structured identifiers — SSN, credit cards with a Luhn check, phone, email, MRN — and close to useless for names and addresses in prose, because there's no pattern for 'Sarah' that doesn't also match half your corpus. So it's a hybrid: I'd use Microsoft Presidio, which is architected exactly this way — pattern recognizers with checksums, plus a spaCy or transformer NER model for person, location, org, date, plus context enhancement that boosts confidence for tokens sitting next to the word 'SSN'. I'd extend it with custom recognizers for our domain identifiers and a deny-list for our own employee directory. And I'd be honest about accuracy: structured entities are 98, 99 percent recall; names and addresses in messy text are more like 90 to 95, and worse on non-English or OCR'd input. I plan for the misses rather than claiming a clean sweep.

Boundary one is ingestion into the vector store, and the rule is scrub before chunking and embedding, never after — once the text is embedded the PII is in the vector, and cleaning the source doesn't change the vector. It's a batch job so I can afford the expensive transformer model and an LLM second pass on low-confidence spans.

Boundary two is query time, right before the outbound provider call. That covers PII the user typed themselves and anything that survived boundary one. It's on the hot path so I budget 20 to 50 milliseconds.

Boundary three is the log write path, and this is the one that actually causes incidents, because logging is decentralized. It isn't one place — it's app logs, LLM traces in LangSmith or Langfuse, APM, error reporting where a stack trace carries the prompt in the exception message, analytics, gateway request logs. Redaction has to be a library in the write path, not a nightly cleanup job, because if raw text touched disk you already had a breach. I enforce it with a shared logging wrapper plus a CI rule that fails a PR passing a prompt object straight to a logger.

The two people forget: eval datasets, because teams scrub prod meticulously and then copy 500 real conversations into a golden set in a git repo the whole company can read. And caches — your own semantic cache is a PII store, and provider-side prompt caching retains your prefix server-side for the TTL.

On technique: the key axis is reversible versus not. Redaction is irreversible and fine for logs, but it destroys coreference — the model loses 'she' in the next sentence. Pseudonymization to consistent labels like PERSON_1 keeps distinct entities distinct without naming them. And the one people miss is tokenization with a reversible vault. If the product has to say 'email Jane the confirmation,' redaction breaks the feature. So I swap each entity for an opaque token, send the tokenized prompt, and swap real values back into the response inside my own trust boundary. The model reasons over the token and never sees the name — which means the provider literally never receives identifiable data, and a whole class of DPA and cross-border transfer questions gets much simpler.

One thing I'd push on regardless of what anyone assumes: embeddings are personal data. Inversion attacks recover named entities from sentence embeddings at above 80 percent rates, including zero-shot with no paired data. So shipping embeddings of confidential documents to a third-party vector service is materially the same as shipping the documents. Scrub before embedding, encrypt at rest, and put the vector DB in scope for the DPA."

**Tradeoff / production angle (1 min):**
"The tradeoff that bites is over-redaction destroying utility. On a claims assistant I worked through, naive full redaction turned 'why was Jane Okafor's claim from March 12th denied' into 'why was PERSON's claim from DATE denied' — and retrieval recall@10 dropped about 15 points, because the discriminating tokens were exactly the ones we deleted. Consistent tokenization preserved the entity as a stable distinct symbol and got that back. So technique choice is a retrieval-quality decision as much as a privacy one.

The question I'd expect next is right to erasure against a vector index, and it's genuinely hard. Deletion has to propagate to the source system, the vector index, logs, caches, and model weights. The vector part only works if you wrote a subject_id into chunk metadata at ingestion — retrofitting that is a full re-index, so it's an ingestion-time design decision. And most ANN indexes do soft deletes: HNSW tombstones the vector and excludes it from results, but it's still on disk until compaction, so you need a scheduled rebuild before you can honestly claim erasure. Weights are the honest dead end — if you fine-tuned on data containing that subject you can't surgically remove them, unlearning isn't a compliance control, so the mitigation is don't fine-tune on raw PII in the first place and accept that the remedy is retraining the adapter.

Last operational point: decide the failure mode. If the PII service is down, do you fail open and ship unscrubbed data, or fail closed and drop the request? For regulated data it's fail-closed, which means the scrubber's availability is now the product's availability — so I'd run it in-process as a library rather than a network hop."

**Wrap-up (30s):**
"So: five boundaries, hybrid regex-plus-NER detection via Presidio, technique chosen per boundary with reversible tokenization where the answer has to name a real person, embeddings treated as personal data, zero-data-retention and a BAA or DPA with every processor including the vector and observability vendors, and subject_id in chunk metadata from day one so erasure is a filtered delete instead of a re-index. Plus a written residual-risk register, because pretending detection is 100% is how you lose the legal team's trust. Happy to dig into the tokenization vault design or the erasure path."

---

## Pitfalls

- **Mistake:** "We run a regex over prompts before logging to strip emails and SSNs." — **Better:** Regex handles structured identifiers well (with checksums) but cannot find names, addresses, employers, or free-text clinical detail — you need a hybrid regex + NER pipeline like Presidio with context enhancement, and you need it at *every* boundary, not just the log path. Naming only the log boundary tells the interviewer you've never had to reason about the vector index or the outbound API call.

- **Mistake:** "We anonymize before embedding, so the vector database is fine — it's just numbers." — **Better:** Embeddings are invertible enough to be treated as personal data; inversion attacks recover named entities at over 80% rates, so a vector index breach is a document breach. The vector DB is an in-scope processor: it needs encryption at rest, DPA/BAA coverage, and `subject_id` metadata so right-to-erasure is a filtered delete — and remember HNSW soft-deletes, so an erasure claim needs a compaction or rebuild behind it.

- **Mistake:** Redacting everything before the API call and not noticing the product broke — or claiming GDPR erasure is fully solvable when the model was fine-tuned on the data. — **Better:** Use reversible tokenization with a KMS-backed vault when the response must reference the real entity, and detokenize inside your own trust boundary; and say plainly that fine-tuned weights cannot be surgically erased, so the control is not fine-tuning on raw PII and treating adapter retraining as the remedy. Honest residual risk beats an overclaim every time.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q14: How protect sensitive/confidential data in a RAG pipeline?](02-014-how-protect-sensitiveconfidential-data-in-a-rag-pipeline.md) | same concept — RAG-specific view of the ingestion and retrieval boundaries |
| [Q33: Filter PII before data reaches the LLM](03-033-filter-pii-before-data-reaches-llm.md) | prerequisite — the query-time boundary in isolation |
| [Q1: When and how implement LLM guardrails?](08-001-when-and-how-implement-llm-guardrails.md) | related — PII scrubbing is the cross-cutting layer of the guardrail stack |

---

## One-liner recall

> PII is a five-boundary problem — ingestion before embedding, query time before the outbound call, the log/trace write path, eval datasets copied from prod, and caches — detected with a hybrid regex+NER pipeline (Presidio, ~98% on structured IDs but only 90–95% on names in prose), de-identified per boundary with redaction for logs and **reversible vault tokenization** wherever the answer must name a real entity (naive redaction cost ~15 points of retrieval recall), backed by zero-data-retention plus DPAs/BAAs with every processor including the vector DB, `subject_id` in chunk metadata so erasure is a filtered delete plus compaction rather than a re-index — and an honest residual-risk register, because embeddings are personal data and fine-tuned weights cannot be un-trained.
