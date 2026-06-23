# Minimize harmful outputs while staying useful?

**Category:** 08-safety-guardrails
**Question #:** 002
**Source section:** §10 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
Interviewers probe whether you understand that safety and utility are in tension — and that naive over-blocking destroys product value just as surely as under-blocking causes harm. They want to see a **calibration mindset**: measuring false positive rates, tuning thresholds against real traffic, and using layered defenses that minimize harm without blanket refusals.

### Trigger phrases
- "How do you minimize harmful outputs without making the model too restrictive?"
- "How do you balance safety and helpfulness in an LLM product?"
- "Our users complain the model refuses too much — how do you fix that?"

### What it tests
Ability to treat harm-helpfulness as a **calibrated engineering tradeoff** — not a binary switch — using layered classifiers, threshold tuning, graceful degradation, and scope-appropriate refusal design.

---

## Answer

### Concept
Minimizing harm while staying useful requires treating the harm-helpfulness tradeoff as a **continuous dial, not a binary flag**. The goal is not to refuse anything risky but to route the right requests to the right response: full answer for safe requests, scoped partial answers for borderline requests, and graceful refusals for genuinely harmful ones — each with the minimum restrictiveness necessary for the risk level.

### Mechanism

**Three-zone response model:**

| Zone | Request type | Response strategy |
|------|-------------|-------------------|
| Safe | Clearly in-policy | Full, direct answer |
| Borderline | Ambiguous intent, dual-use content | Scoped partial answer + caveat + redirect |
| Harmful | Clear policy violation | Graceful refusal + alternative path |

**The key insight:** most harmful-output incidents come from the "borderline" zone being miscategorized as "harmful" (over-refusal) or as "safe" (under-blocking). The engineering work is in calibrating that middle zone.

**Five levers for the calibration:**

1. **Harm taxonomy + classifier threshold tuning**
   - Define a concrete harm taxonomy (e.g. violence, self-harm, illegal activity, PII leakage, brand risk) — not a vague "harmful content" bucket.
   - Use **Llama Guard 3** or a fine-tuned DistilBERT classifier per category, each with its own threshold.
   - Tune each threshold separately on 1,000+ labeled production queries. Target: FP rate (over-refusal) < 0.5%, recall (catch rate) > 95% for Tier-1 harms (violence, CSAM) and > 85% for Tier-2 (policy violations).
   - Measure separately: over-refusal rate and under-blocking rate are **independent KPIs**, not a single dial.

2. **Scoped partial answers for borderline queries**
   - Instead of full refusal, answer the safe portion and redirect the rest.
   - Example: "How do I handle a medication overdose?" → a medical chatbot should answer the first-aid steps (safe, high-value) but decline to give specific medication quantities (harmful). A full refusal of the query fails both goals.
   - Implement via prompt instruction: "If the query is partially answerable, provide the safe portion and explain what you cannot address and why."

3. **Intent detection before classification**
   - A query about "how to pick a lock" is harmful from a criminal and benign from a locksmith or someone locked out. Pass user context (account tier, stated use case, prior conversation) into the classifier or system prompt.
   - Use a lightweight **intent router** (DistilBERT fine-tuned on your user population) as a pre-classifier stage to segment queries before applying the harm classifier. This cuts over-refusal on dual-use content by 30–50% in practice.

4. **Graceful refusal design (not dead ends)**
   - Every refusal should include: (a) what you can't help with in this context, (b) what you *can* help with instead, (c) an external resource if applicable (helpline, documentation link).
   - Bad refusal: "I can't help with that." — strands the user.
   - Good refusal: "I'm not able to provide [X] here, but I can help with [Y]. For [X], you may want to contact [resource]." — preserves helpfulness within safety bounds.

5. **Continuous calibration in production**
   - Monitor over-refusal rate (thumbs-down on legitimate queries flagged as harmful) as a first-class SLO, alongside harmful output rate.
   - Route flagged borderline outputs (confidence 0.6–0.9) to human review for label collection → use as hard negatives in monthly classifier fine-tuning.
   - A/B test threshold changes: shadow-mode classifier comparison before promoting to production.

### Example / Tradeoff

**Legal contract Q&A assistant:** Users asked questions like "What happens if I breach this contract?" — a legitimate and common query. An initial DistilBERT classifier trained on generic harm data was flagging "breach" as a legally sensitive term and refusing ~12% of contract questions. Fix: (a) narrowed the harm taxonomy to PII extraction and legal advice solicitation specifically (not contract terminology), (b) added intent detection (user is a lawyer or contract party = low-risk context), (c) changed the refusal for true legal-advice queries to a scoped partial answer ("I can explain what the contract says about breach; I can't advise you on what action to take — for that, consult a licensed attorney"). Over-refusal rate dropped from 12% to 1.8%. Harmful output rate held flat at < 0.3%.

**Key tradeoff:** Precision vs recall per harm category. For Tier-1 harms (CSAM, imminent violence), recall dominates — accept higher FP rates, accept more refusals. For Tier-2 harms (competitor mentions, mild policy violations), precision dominates — fewer refusals, more helpfulness. Mixing both into a single threshold produces a classifier that is simultaneously too aggressive on Tier-2 and not aggressive enough on Tier-1.

---

## Verbal script

**Opening (30s):**
"The framing I'd use here is that harmful outputs and unhelpful outputs are both product failures — just different kinds. Over-refusing is not 'safe'; it erodes trust and defeats the product. So my approach is to treat this as a calibration engineering problem: measure both error types independently, tune them separately, and design responses that gracefully handle the middle ground."

**Core explanation (2–3 min):**
"I start by defining a concrete harm taxonomy. Vague 'harmful content' buckets produce classifiers that are either too broad or too narrow. I want categories: violence, self-harm, illegal activity, PII exfiltration, brand/regulatory risk — each with its own classifier and threshold, because they have very different acceptable error rates. For Tier-1 harms like CSAM or imminent violence, I'll accept a 5% false-positive rate to get 99%+ recall. For Tier-2 policy violations, I'll tune for a 0.5% FP rate and accept 85% recall.

The second thing I'd add is a **three-zone response model**. Safe queries get full answers. Borderline queries get scoped partial answers with a redirect — not a flat refusal. This is where most of the work is. For example, on a medical chatbot, 'What is the maximum safe dose of ibuprofen?' from a caregiver context is a legitimate query. A full refusal is unhelpful; the right answer is to provide the standard dosing information and redirect to a pharmacist for patient-specific advice.

Third, I add **intent routing** before the harm classifier. Context matters enormously — 'how to pick a lock' is dual-use. A DistilBERT intent router trained on my user population segments queries by likely intent before they hit the harm classifier. This alone cuts over-refusal by 30–40% on dual-use content without touching recall on genuine threats.

Finally, every refusal is designed to preserve partial helpfulness — what I *can* do, what I can't do in this context, and where to go instead. 'I can't help with that' is a dead end. A well-designed refusal keeps the user in the product."

**Tradeoff / production angle (1 min):**
"The main production tension is per-category threshold management. If you lump all harm categories into one classifier with one threshold, you'll be simultaneously too aggressive on low-risk policy violations and not aggressive enough on high-risk harms. The fix is category-specific tuning, which requires labeled data per category. The other gotcha is model upgrades — every time you swap the underlying LLM or change the system prompt, the over-refusal rate can shift significantly. I track both harmful output rate and over-refusal rate as deployment gates, not just pre-launch metrics."

**Wrap-up (30s):**
"So the answer is: minimize harm by treating it as a calibration problem, not a binary switch. Separate harm taxonomy → per-category classifiers → three-zone response model (safe / scoped / refused) → intent routing → graceful refusal design. Monitor over-refusal and harmful output rate as independent KPIs in production."

---

## Pitfalls

- **Mistake:** "We set a high safety threshold to catch everything" without measuring the false positive (over-refusal) rate. — **Better:** Over-refusal is a product failure. Explain how you measure the FP rate on real production queries, target < 0.5% for Tier-2 harms, and tune each category threshold separately — not a single global dial.

- **Mistake:** "We refuse anything that could be harmful" — treating refusal as the safe default for all borderline queries. — **Better:** Describe the three-zone model: borderline queries deserve scoped partial answers (answer the safe portion, redirect the rest), not flat refusals. Full refusal of a dual-use query is a helpfulness failure that also erodes user trust in the product.

- **Mistake:** "We use a single harm classifier across all topics." — **Better:** A single classifier conflates Tier-1 harms (CSAM, imminent violence — need 99%+ recall) with Tier-2 policy violations (competitor mentions — need < 0.5% FP rate). Per-category classifiers with separate thresholds are required for production calibration.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q1: When and how implement LLM guardrails?](08-001-when-and-how-implement-llm-guardrails.md) | Prerequisite — guardrail architecture that enforces the harm-helpfulness tradeoff |
| [Q3: Detect policy violations / offensive content?](08-003-detect-policy-violations-offensive-content.md) | Same layer — classifier implementation specifics for the harm detection step |
| [Q9: Red-team an LLM system?](08-009-red-team-an-llm-system.md) | Follow-up — how to verify calibration holds against adversarial inputs |

---

## One-liner recall

> Minimize harm without over-refusal by defining a per-category harm taxonomy, tuning each classifier threshold separately against real traffic (FP < 0.5% for Tier-2, recall > 95% for Tier-1), using a three-zone response model (full / scoped / refused) for borderline queries, and monitoring both harmful output rate and over-refusal rate as independent production KPIs.
