# Filter PII before data reaches LLM?

**Category:** 03-agents-tool-use
**Question #:** 033
**Source section:** §3 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
Every enterprise AI deployment eventually handles data that contains names, email addresses, SSNs, credit card numbers, or medical record IDs. Sending that data raw to a third-party LLM API creates legal exposure (GDPR, HIPAA, CCPA) and data-breach risk. Interviewers ask this to probe whether you understand privacy-by-design, can enumerate practical detection and anonymization techniques, and know the operational tradeoffs (accuracy vs. latency vs. utility loss).

### Trigger phrases
- "How do you prevent PII from leaking into your LLM prompts?"
- "What happens when user data goes through an agent that calls OpenAI?"
- "How do you handle PHI/PII in a production RAG or agent pipeline?"
- "Walk me through your data privacy strategy for an LLM application."

### What it tests
Production data-privacy architecture: the ability to systematically detect, remove or pseudonymize sensitive data at every entry point before it reaches an external model, without destroying answer quality.

---

## Answer

### Concept
PII filtering is a defense-in-depth pipeline that detects and neutralizes sensitive data (names, SSNs, emails, phone numbers, PHI, financial IDs) **before** any of it is sent to an external LLM, stored in a vector index, or written to logs. The goal is to prevent inadvertent disclosure while preserving enough semantic content for the LLM to remain useful.

### Mechanism

**Detection layer — Microsoft Presidio (open-source, production-grade):**
- Rule-based recognizers (regex + checksum): credit card numbers (Luhn), SSNs (`\d{3}-\d{2}-\d{4}`), email, phone, IP, IBAN.
- NER-based recognizers: spaCy or a fine-tuned BERT model for PERSON, ORG, GPE entity types.
- Confidence threshold (default 0.7): entities below threshold are flagged for manual review rather than auto-redacted.

**Anonymization strategies (choose by use case):**

| Strategy | How | When |
|----------|-----|-------|
| **Redaction** | Replace with `[REDACTED]` or `<PERSON>` | Simplest; destroys pronouns/coreference |
| **Pseudonymization** | Replace with fake-but-consistent token (`John Smith → USER_4921`) | Allows multi-turn coherence; reversible with a lookup table |
| **Masking** | Partial reveal (`john.s****@gmail.com`) | Low-sensitivity contexts |
| **Synthetic substitution** | Replace name with a plausible fake (Faker.js) | Preserves grammar and reading flow |
| **Encryption** | AES-256 with per-session key | Regulated domains requiring reversibility |

**Pipeline placement (every ingress point):**

```
User input
  → Presidio analyze()           ← detects PII entities with spans
  → anonymizer.anonymize()       ← replaces in-place with chosen strategy
  → [anonymized text to LLM]
  → LLM response
  → de-anonymize() if needed     ← swap pseudonyms back for display
```

For RAG pipelines, PII filtering happens **at ingestion time** (before chunking and embedding) so the vector index never stores raw sensitive text. At query time, the incoming question is filtered before embedding lookup.

**Logging hygiene:**
- Log `entity_types_detected` and `entity_count` — never the raw PII spans.
- Use structured PII-redacted logs; Presidio has a `log_decision_process` flag that must be set to false in production.

**Async scanning at scale:**
- For high-throughput pipelines (>1K QPS), run Presidio in a sidecar microservice with a 10ms p95 SLO; the main agent pipeline calls it async.
- Cache redaction results keyed on a SHA-256 hash of the input chunk to avoid re-scanning identical documents.

### Example / Tradeoff

**Healthcare agent (HIPAA):** A patient-triage agent ingests nurse notes that contain patient names, DOBs, and medication dosages. Presidio with a MedSpacy PHI recognizer detects 18 entity types (name, DOB, age, MRN, medication). Each entity is pseudonymized with a session-scoped lookup table: `"John Smith, DOB 1972-03-14" → "PATIENT_A, DOB REDACTED"`. The LLM reasons over pseudonymized text; the response is de-anonymized only in the display layer, which runs inside the hospital's on-prem boundary.

**Tradeoff — accuracy vs. latency:**
- Presidio NER adds ~8–15ms per 512-token chunk. At 1M chunks/day, that's ~$12/day in CPU cost.
- False negatives (missed PII) are the primary risk; false positives (over-redaction) degrade answer quality. Tune confidence thresholds on a domain-specific golden dataset with labeled PII spans.
- For very strict domains (HIPAA, PCI-DSS), prefer redaction over pseudonymization — pseudonym lookup tables are themselves sensitive data.

---

## Verbal script

**Opening (30s):**
"PII filtering is something I'd call a mandatory architectural concern for any agent or RAG system that handles user data. The failure mode is straightforward: send an SSN or patient name to OpenAI's API without consent or a BAA, and you've created a regulatory incident before any bugs surface. I'd design this as a defense-in-depth pipeline with PII detection at every data entry point."

**Core explanation (2–3 min):**
"The production tool I'd reach for first is Microsoft Presidio — it's open-source, HIPAA-aware, and combines rule-based recognizers (regex + Luhn checksum for credit cards) with NER recognizers powered by spaCy. You get entity spans with confidence scores, and you can tune the threshold.

The anonymization strategy depends on the use case. For a simple single-turn chat, redaction — replacing `John Smith` with `<PERSON>` — is the safest choice because there's no state to maintain. For a multi-turn agent where coreference matters — 'update his record' referring to a patient mentioned two turns ago — I'd use pseudonymization: a session-scoped lookup table that maps real entities to consistent fake tokens like PATIENT_A. The LLM reasons over pseudonymized text, and I de-anonymize only in the display layer, which stays inside the trust boundary.

Placement matters as much as the technique itself. For a RAG pipeline, I'd filter at ingestion time so the vector index never stores raw PII — otherwise you've just moved the exposure from the LLM API call to your Pinecone namespace. At query time, I'd filter the incoming question before the embedding lookup and before appending retrieved chunks to the prompt.

Logging is a common blind spot: I'd log entity types and counts for audit purposes but never the raw PII spans. Presidio has a `log_decision_process` flag that must be disabled in production."

**Tradeoff / production angle (1 min):**
"The main tension is accuracy vs. utility. Aggressive redaction eliminates PII but can break grammar and coreference in ways that confuse the LLM — 'REDACTED was admitted on REDACTED' loses meaning. Pseudonymization preserves flow but the lookup table itself is sensitive data that needs to be encrypted and scoped to the session.

At scale — say 1M documents/day — Presidio adds 8–15ms per 512-token chunk. I'd run it as a sidecar microservice with a 10ms p95 SLO and cache redaction results keyed on a content hash, so identical chunks don't get re-scanned.

The other risk is false negatives — PII Presidio misses. For regulated domains I'd add a secondary pass using a fine-tuned BERT NER model on domain-specific entity types like MRNs or ICD codes, and route anything above a high-value risk threshold to human review before the data ever enters the pipeline."

**Wrap-up (30s):**
"So the key principles are: filter at every entry point, not just the final prompt; choose your anonymization strategy based on whether you need session-level coreference; keep the lookup table inside your trust boundary; and measure both false-negative rate and utility impact on a golden dataset. Happy to go deeper on HIPAA-specific entity types or the de-anonymization display layer."

---

## Pitfalls

- **Mistake:** Saying "we filter PII in the prompt template" without mentioning ingestion-time filtering — **Better:** Explain that PII must be removed at ingestion (so the vector index is clean), at query time (user input), and in logs — three separate entry points, not just one.
- **Mistake:** Recommending only redaction (`[REDACTED]`) for all cases without discussing coreference degradation — **Better:** Contrast redaction vs. pseudonymization vs. synthetic substitution and tie the choice to whether the agent needs multi-turn coherence or strict irreversibility.
- **Mistake:** Treating PII filtering as a prompt-layer concern only and ignoring logging and vector store exposure — **Better:** Name all three storage surfaces (LLM API call, vector index, structured logs) and explain the mitigation for each.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q25: Biggest security risks with tool-using agents](03-025-biggest-security-risks-with-tool-using-agents.md) | Broader threat taxonomy — PII leakage is one of four attack vectors |
| [Q31: Agents in regulated domains (financial, healthcare)](03-031-agents-in-regulated-domains-financial-healthcare.md) | HIPAA/GDPR compliance context where PII filtering is mandatory |
| [Q14: How protect sensitive/confidential data in a RAG pipeline](02-014-how-protect-sensitive-confidential-data-in-a-rag-pipeline.md) | RAG-specific ACL + Presidio ingestion-time filtering |

---

## One-liner recall

> Run Microsoft Presidio at every data entry point (ingestion, query, logs) to detect and pseudonymize PII before it reaches the LLM API, using session-scoped lookup tables for multi-turn coherence and redaction for strict irreversibility.
