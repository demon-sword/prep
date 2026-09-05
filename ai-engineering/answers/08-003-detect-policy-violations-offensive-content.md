# Detect policy violations / offensive content?

**Category:** 08-safety-guardrails
**Question #:** 003
**Source section:** §10 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
Interviewers want to see whether you can translate an abstract "prevent bad outputs" goal into a **concrete, measurable detection pipeline**. The question probes whether you know the difference between a provider content filter, a custom classifier, and a rules-based layer — and when each is appropriate. For senior roles, it also tests your understanding of the precision-recall tradeoff, threshold calibration, and how detection signals feed back into model improvement.

### Trigger phrases
- "How do you detect policy violations or offensive content in your LLM application?"
- "What's your approach to content moderation for user-generated prompts and model outputs?"
- "Walk me through how you'd build a classifier to catch harmful outputs at scale."

### What it tests
Ability to design a multi-layer, production-calibrated content-moderation pipeline — covering input and output, synchronous and async paths — that correctly distinguishes harm categories and keeps false positive rates low.

---

## Answer

### Concept
Policy violation and offensive-content detection is a **classification problem at two boundaries**: user input (before the LLM call) and model output (after generation). A mature detection system combines a fast pre-trained safety classifier, a fine-tuned domain-specific policy classifier, and an async audit tier — each tuned independently by harm category rather than using a single global threshold.

### Mechanism

**Detection stack (two boundaries, three tiers):**

```
[User input]
    │
    ├─► [Tier 1 — Pre-LLM input scan, synchronous]
    │       Fast safety classifier (Llama Guard, <50ms GPU)
    │       Rules: blocklist keywords / regex for known patterns (URLs, phone #s, account numbers)
    │       Block → return canned refusal, skip LLM call, log event
    │
    ▼
[LLM call + RAG retrieval]
    │
    ├─► [Tier 2 — Output scan, synchronous or async]
    │       Safety classifier (Llama Guard rerun on output)
    │       Domain policy classifier (fine-tuned DistilBERT on company taxonomy)
    │       Synchronous: high-stakes domains (healthcare, finance) — block before delivery
    │       Async: medium-risk consumer apps — deliver + flag for human review queue
    │
    ├─► [Tier 3 — Async audit pipeline]
            Kafka event → batch NLP analysis → human review → label collection
            Feeds monthly classifier fine-tuning loop
```

**Key design decisions:**

1. **Harm taxonomy before tooling.** Define categories explicitly before choosing classifiers:
   - **Tier-1 harms** (CSAM, self-harm, imminent violence, illegal instructions): synchronous block, >99% recall priority, accept FP rates up to 5%.
   - **Tier-2 policy violations** (competitor mentions, medical/legal advice solicitation, PII extraction, brand risk): synchronous or async, <0.5% FP rate priority, >85% recall.
   - **Tier-3 quality issues** (off-topic, factually wrong, tone violations): async only, human review queue.

2. **Classifier selection per tier:**
   - **Llama Guard** (Meta, open-weight, ~7B params): multi-label harm classifier trained on MLCommons taxonomy. Runs in <60ms on a GPU inference server. Out-of-the-box for Tier-1 harms.
   - **Perspective API** (Google): specialised for toxicity, identity attack, insult, profanity. Good for consumer-facing comment/chat moderation.
   - **Fine-tuned DistilBERT or DeBERTa**: required for company-specific Tier-2 policies (industry jargon, custom prohibited topics, regulatory constraints). Train on 1,000–5,000 labeled examples per category.
   - **Rules and blocklists**: fast exact-match layer for known patterns (profanity lists, PII regex for SSNs/credit cards, competitor product names). Zero latency, zero false negatives for exact matches — run before the ML classifier.

3. **Threshold calibration workflow:**
   - Hold out 1,000+ representative production queries per category (balanced flagged/clean).
   - For Tier-1: tune threshold for recall > 99%, then measure FP rate (acceptable if < 5%).
   - For Tier-2: tune for FP < 0.5% on real traffic, then verify recall > 85%.
   - Use precision-recall curves, not ROC curves — at low positive rates (rare violations), AUC-ROC is misleading.
   - Re-calibrate monthly or after any LLM/prompt change.

4. **Async audit pipeline for scale:**
   - At 1M queries/day, synchronous ML classification on 100% of outputs adds 50–150ms. Where latency SLOs are tight (<300ms p95), use a hybrid: synchronous rules + Tier-1 classifier synchronously; Tier-2 policy classifier asynchronously via Kafka.
   - All flagged events land in a review queue (internal tooling or **Amazon Mechanical Turk** / **Scale AI** for labeling at scale). Labels feed the monthly fine-tuning loop for the policy classifier.

### Example / Tradeoff

**E-commerce customer support bot (1.2M queries/day):** Deployed a 3-tier stack:
1. Synchronous input: regex blocklist (PII patterns) + Llama Guard for Tier-1 harms (< 60ms GPU).
2. Synchronous output: fine-tuned DistilBERT for Tier-2 violations (competitor mentions, refund abuse language) at 45ms — synchronous because incorrect refund info is a financial liability.
3. Async audit: Kafka stream → 5% sample to a small fast model LLM judge → human review queue for edge cases → weekly label collection.

Results after calibration: Tier-1 recall 99.3%, FP 1.1%. Tier-2 recall 88%, FP 0.4%. Over-refusal rate (legitimate queries blocked): 0.38% — within the 0.5% SLO. Monthly classifier updates closed the gap on seasonal vocabulary shifts (new product names, promotions).

**Key tradeoff:** Synchronous vs async for Tier-2. Synchronous doubles detection latency but is required when a policy violation reaching the user creates legal or financial liability. For brand-risk violations (tone issues, off-topic responses), async detection is sufficient — harm is low, latency savings are real.

---

## Verbal script

**Opening (30s):**
"I approach this as a classification pipeline problem, not a single-model problem. The key design choices are: where in the pipeline to place each check, whether it's synchronous or async, and how to calibrate each classifier independently by harm category. Let me walk through the architecture I'd build."

**Core explanation (2–3 min):**
"I start by defining the harm taxonomy before touching any tooling. I split violations into three tiers. Tier-1 harms — CSAM, self-harm, imminent violence, explicit illegal instructions — need synchronous blocking with recall above 99%; I'll accept a higher false positive rate there. Tier-2 policy violations — competitor mentions, medical advice solicitation, PII extraction, regulatory non-compliance — need a lower false positive rate, under 0.5%, because over-blocking legitimate queries damages the product.

For the actual detection tooling: I'd use **Llama Guard** from Meta for Tier-1 — it's open-weight, runs under 60ms on a GPU, and covers the MLCommons harm taxonomy out of the box. For company-specific Tier-2 policies, I'd fine-tune a **DistilBERT or DeBERTa** classifier on 2,000–5,000 labeled examples from our own policy taxonomy. I'd also add a fast regex/blocklist layer in front of both classifiers — exact-match PII patterns, known profanity, competitor product names — because that catches known violations at zero latency.

The detection runs at two boundaries. On the input side, synchronous: if the user message triggers Tier-1 or Tier-2, I block before calling the LLM at all — saves cost and latency. On the output side, it depends on the risk level. For high-stakes domains like healthcare or financial advice, I run the classifier synchronously on the generated response and block before delivery. For medium-risk consumer apps with tight latency budgets, I deliver the response and fan it out asynchronously to a Kafka queue, where it gets scored, flagged, and routed to a human review queue.

Threshold calibration is the part most candidates skip. I hold out 1,000 representative labeled production queries per category and tune thresholds on PR curves, not ROC curves — at the low positive rates you see in production, AUC-ROC is deceptive. I re-calibrate after every LLM swap or major prompt change."

**Tradeoff / production angle (1 min):**
"The main tension is synchronous vs async for Tier-2 violations. Synchronous adds 50–150ms per query — at 1M queries/day, that's a real cost and latency hit. Async is faster, but a small fraction of policy-violating responses reach users before being caught. Whether that's acceptable depends entirely on the regulatory and liability context. For a healthcare chatbot, it's not acceptable. For a general-purpose writing assistant, it often is. I'd also call out that multi-language content is much harder — classifiers trained on English often miss policy violations in code-switching or non-Latin-script text, so for global products I'd need multilingual models or language-specific classifiers."

**Wrap-up (30s):**
"So the detection pipeline is: define harm taxonomy → fast rules/blocklist → Llama Guard for Tier-1 → fine-tuned DistilBERT for Tier-2 policy violations → synchronous at input, synchronous or async at output depending on liability — all feeding an async audit loop that labels edge cases and re-trains classifiers monthly. Happy to go deeper on calibration or the async pipeline architecture."

---

## Pitfalls

- **Mistake:** "We use the API provider's built-in content filter" without a custom policy classifier. — **Better:** Provider filters catch egregious Tier-1 harms but are blind to company-specific Tier-2 violations (competitor mentions, domain-specific prohibited topics, regulatory language). Describe adding a fine-tuned DistilBERT or DeBERTa classifier on your own policy taxonomy, trained on labeled production data.

- **Mistake:** Treating policy violation detection as a single threshold on a single classifier with no separate tuning per category. — **Better:** Tier-1 harms (violence, CSAM) need recall > 99% — you'll accept higher FP rates. Tier-2 policy violations need FP < 0.5% — you tune differently. A single threshold produces a classifier that is simultaneously too aggressive on low-stakes violations and not aggressive enough on high-stakes harms.

- **Mistake:** Only checking model outputs, not user inputs. — **Better:** Input-side detection is cheaper (skip the full LLM call on a block) and catches a different attack surface (jailbreak prompts, extraction attempts). The detection stack should run at both boundaries: pre-LLM input scan and post-LLM output scan.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q1: When and how implement LLM guardrails?](08-001-when-and-how-implement-llm-guardrails.md) | Prerequisite — guardrail architecture that wraps the detection classifiers |
| [Q4: Protect against prompt injection and jailbreaking?](08-004-protect-against-prompt-injection-and-jailbreaking.md) | Adjacent — input-side classifier must also handle adversarial injection attempts |
| [Q9: Red-team an LLM system?](08-009-red-team-an-llm-system.md) | Follow-up — how to verify detection coverage and find classifier blind spots |

---

## One-liner recall

> Detect policy violations with a two-boundary, three-tier pipeline: fast regex/blocklist + Llama Guard (Tier-1, synchronous) at input; fine-tuned DistilBERT for company-specific Tier-2 violations (synchronous for high-liability domains, async for medium-risk) at output — with separate precision-recall calibration per harm category and a monthly retraining loop fed by human-reviewed flagged samples.
