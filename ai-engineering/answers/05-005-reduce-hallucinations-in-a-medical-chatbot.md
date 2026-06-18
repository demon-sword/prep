# Reduce hallucinations in a medical chatbot?

**Category:** 05-evaluation-metrics
**Question #:** 005
**Source section:** §5 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
Medical AI is the highest-stakes domain for hallucinations — a fabricated drug dosage or contraindication can cause patient harm. Interviewers use this question to test whether a candidate understands that the general hallucination mitigation playbook must be hardened for regulated, safety-critical contexts: tighter retrieval gates, stronger post-generation validation, mandatory audit trails, and HITL escalation. It also probes domain-specific awareness (medical terminology, clinical workflows, HIPAA).

### Trigger phrases
- "How would you reduce hallucinations in a medical chatbot?"
- "You're building a clinical assistant — how do you ensure it doesn't make up drug information?"
- "Your healthcare chatbot is confidently giving wrong dosage advice — how do you fix it?"

### What it tests
Ability to apply layered hallucination mitigation in a high-stakes regulated domain, including domain-specific retrieval, NLI validation, HITL design, and compliance-aware logging.

---

## Answer

### Concept
In a medical chatbot, hallucinations are not just a quality problem — they are a safety and liability problem. The standard defense-in-depth stack (retrieval grounding, T=0, faithfulness gate) applies, but every layer is tightened: retrieval uses curated medical corpora (not general web), post-generation validation uses NLI entailment (not just LLM judge) for auditability, HITL escalation is mandatory for clinical-action questions, and all outputs are logged for compliance (HIPAA). Domain-adapted embeddings and terminology normalization address the medical vocabulary gap that breaks general-purpose RAG.

### Mechanism

**Layer 1 — Curated, domain-specific retrieval (the most important layer)**
- Source only from authoritative corpora: **UpToDate**, **PubMed**, **FDA drug label database**, **clinical guidelines** (ACC, NICE, WHO) — not general web or Wikipedia.
- Index with **BioLORD** or **PubMedBERT** embeddings (not `text-embedding-ada-002`) to avoid tokenization failures on clinical terms (warfarin, metformin, ICD-10 codes).
- Use **hybrid BM25 + dense retrieval with RRF** — medical queries often include exact drug names, ICD-10 codes, dosage units that BM25 handles better than dense-only.
- Apply a **cosine similarity retrieval gate** (θ ≥ 0.75 for medical, vs 0.70 generic) — if no chunk clears the threshold, return a graceful "I don't have authoritative information on that" abstention rather than generating from parametric memory.
- Add **metadata filters**: indication, drug class, guideline version, publication year — to surface the most current recommendations.

**Layer 2 — Grounding prompt at T=0**
- Closed-world instruction: `"Answer ONLY using the clinical passages provided below. If the answer is not in the passages, say: 'I don't have reliable information on this — please consult a clinician.' Do not use prior medical knowledge."`
- Set `temperature=0` for all clinical responses.
- Require **inline citations**: `[Source: ACC/AHA Guidelines 2023, p.12]` — forces the model to anchor each claim and makes faithfulness verifiable.
- **Scope restriction prompt**: distinguish information vs advice — `"Provide clinical information, not personalized medical advice."`

**Layer 3 — Synchronous NLI entailment validation (not async for medical)**
- Run **DeBERTa-v3 NLI** (`cross-encoder/nli-deberta-v3-large`) on every output sentence vs its cited source chunk.
- If any sentence receives a `contradiction` label → **block the response** and return the abstention message.
- If entailment score < 0.80 → route to HITL review queue, do not return to user.
- NLI is preferred over LLM-as-judge here: it's auditable, deterministic, fast (~50ms), and does not itself hallucinate.
- For drug dosage, contraindications, and adverse event claims: apply a **regex/NER extraction step** (SpaCy + medspaCy) to identify numeric claims and verify against structured drug database (RxNorm/OpenFDA API).

**Layer 4 — HITL escalation for high-risk query classes**
- Classify every query into risk tiers using a lightweight classifier (GPT-4o-mini or fine-tuned BERT):
  - **Tier 1** (general info: "What is metformin?"): auto-respond with NLI-validated output.
  - **Tier 2** (clinical guidance: "What is the standard first-line treatment for T2DM?"): auto-respond + log for clinician spot-check.
  - **Tier 3** (patient-specific advice: "Should I take 1000mg metformin given my kidney disease?"): block auto-response → escalate to clinician queue + show: "This question requires a clinician review."
- Hard-block any query containing personal pronouns ("my", "I") combined with medication + dosage — these are patient-specific advice requests.

**Layer 5 — Compliance-aware logging and monitoring**
- Log all queries, retrieved chunks, and responses to **HIPAA-compliant** storage (PHI pseudonymized with Presidio before logging).
- Track `hallucination_rate` (NLI contradiction detections / total responses) as a separate SLO — alert at >0.5% (tighter than generic 2% SLO).
- Run nightly **golden dataset regression** (500 Q&A pairs, human-labeled faithfulness) on every model or embedding change before deployment.
- Retain audit trail for **6 years** (HIPAA minimum) — immutable S3 with Object Lock.

### Example / Tradeoff

A clinical decision support chatbot at a hospital system:
- **Stack:** PubMedBERT embeddings → Pinecone + Elasticsearch BM25 hybrid → GPT-4o at T=0 with closed-world prompt + citation requirement → DeBERTa NLI gate (sync, 50ms) → tier classifier for HITL routing.
- **Before:** general-purpose RAG with `text-embedding-ada-002` + GPT-4o at T=0.7 → 6.4% hallucination rate on drug dosage queries (model blended parametric knowledge with retrieved context).
- **After domain adaptation:** PubMedBERT + hybrid retrieval + NLI gate → 0.4% hallucination rate; NLI gate blocked 3.2% of responses that would have contained contradictions.
- **HITL impact:** tier-3 escalation caught 100% of patient-specific advice requests; clinician review queue processed ~8% of daily queries.

**Tradeoff table:**

| Technique | Latency added | Hallucination reduction | Medical necessity |
|---|---|---|---|
| Domain embeddings (PubMedBERT) | None | ~40% on clinical terms | High — generic embeds fail on ICD/drug codes |
| Hybrid BM25+dense + retrieval gate | +30ms | ~30% | High — exact drug names need BM25 |
| T=0 + closed-world prompt | None | ~25–35% | Essential |
| Sync NLI entailment gate | +50ms | Catches ~3% residual | Essential for medical |
| HITL tier-3 escalation | High (human) | Near-perfect for clinical advice | Required for safety |

---

## Verbal script

**Opening (30s):**
"Medical chatbots are the hardest hallucination problem because the cost of a wrong answer isn't a bad user experience — it's a patient safety incident. So I'd apply the standard defense-in-depth stack but tighten every layer for the clinical domain: curated retrieval from authoritative medical sources, synchronous NLI validation rather than async, mandatory HITL for patient-specific advice, and HIPAA-compliant audit logging."

**Core explanation (2–3 min):**
"I'd start with retrieval, because it's the highest-leverage layer. In a general RAG system I'd use text-embedding-ada-002 and retrieve from a broad corpus. For medical, I'd swap to PubMedBERT or BioLORD embeddings — these are trained on clinical text and correctly encode terms like warfarin, metformin, and ICD-10 codes that general tokenizers fragment. I'd source exclusively from curated authoritative corpora: UpToDate, FDA drug labels, PubMed, ACC/AHA guidelines. And I'd use hybrid BM25+dense retrieval because drug names and dosage units are exact-match queries that BM25 handles better than dense-only. The retrieval gate threshold I'd set at 0.75 cosine similarity — stricter than a generic 0.70 — because in medicine I'd rather abstain than hallucinate.

At the prompt layer: closed-world instruction at T=0 with mandatory inline citations. Every claim must reference a specific source chunk. For post-generation validation, I'd use synchronous DeBERTa NLI — not async like in a consumer app. If any sentence contradicts its cited source, I block the response immediately. In medicine, a 50ms latency penalty for NLI validation is an easy tradeoff against a hallucinated contraindication.

For query routing, I'd implement a tier classifier: general info questions auto-respond, clinical guidance questions get logged for spot-check, and anything that reads as patient-specific advice — 'my', 'I', combined with dosage or medication — gets hard-blocked and escalated to a clinician queue."

**Tradeoff / production angle (1 min):**
"The main tension is between coverage and latency. Synchronous NLI adds ~50ms; HITL escalation adds minutes to hours. The right threshold depends on use case: a patient-facing consumer app needs aggressive HITL; a tool used by clinicians who can interpret uncertain answers can run with lighter guardrails but still needs the NLI gate. I'd also monitor hallucination rate as a separate SLO at 0.5%, not 2%, and run golden-dataset regression before every model or embedding change — not just on release."

**Wrap-up (30s):**
"So the medical stack is: domain embeddings + curated retrieval + strict cosine gate → closed-world prompt at T=0 with citations → synchronous NLI entailment → HITL tier routing → HIPAA-compliant audit trail. The key difference from a general chatbot is that every layer is tighter and the fallback is always abstention, never a confident guess. Happy to go deeper on any layer — NLI gate design, tier classifier training, or the HIPAA logging architecture."

---

## Pitfalls

- **Mistake:** Saying "I'd lower the temperature to 0 and add a good system prompt" without mentioning domain-adapted embeddings — **Better:** Explain that general-purpose embeddings fragment clinical terminology (ICD-10 codes, drug names), causing retrieval failures that a good prompt cannot fix; PubMedBERT or BioLORD embeddings are the first-order fix.
- **Mistake:** Using async RAGAS faithfulness monitoring (acceptable for consumer apps) without noting that medical requires synchronous NLI blocking — **Better:** Explain that in medical contexts you cannot let a hallucinated response reach the user even once; the NLI gate must be synchronous and must block, not just log, contradictions.
- **Mistake:** Not mentioning HITL escalation for patient-specific advice queries — **Better:** Describe the tier classifier pattern: automatically detect "patient-specific advice" queries using personal pronouns + medication + dosage combination, and route these to a clinician queue rather than generating any auto-response.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q3: Detect and mitigate hallucinations in production](05-003-detect-and-mitigate-hallucinations-in-production.md) | Parent concept — general 4-layer stack; this Q applies it to a regulated domain |
| [Q4: Prevent factual errors in summarization](05-004-prevent-factual-errors-in-summarization.md) | Same NLI entailment gate pattern; medical chatbot has synchronous rather than async variant |
| [Q8: Measure hallucination rate in production](05-008-measure-hallucination-rate-in-production.md) | How to instrument and SLO the hallucination rate this architecture is designed to minimize |

---

## One-liner recall

> Medical chatbot hallucinations require domain embeddings (PubMedBERT), curated-source-only hybrid retrieval with a strict cosine gate, closed-world T=0 prompt with citations, synchronous DeBERTa NLI blocking (not async), and HITL escalation for any patient-specific advice query.
