# What can we learn from chatbot failure case studies?

**Category:** 08-safety-guardrails
**Question #:** 011
**Source section:** §10 in interview-questions.md
**Status:** `review`
**Generated:** ralph-ai-engineering

---

## Framing

### Why this question is asked
The interviewer wants memorable proof that you understand safety failures have real-world consequences — legal liability, brand damage, court sanctions — not just benchmark deltas. Weak candidates speak in abstractions ("hallucinations are bad"); strong candidates cite two or three named incidents, state exactly which engineering control was missing in each, and map every anecdote to a defense they would build. These stories are interview ammunition: a thirty-second anecdote that proves you have internalised why grounding, commitment authority, and verification gates exist.

### Trigger phrases
- "Tell me about a time an AI system failed in production."
- "Why should we care about guardrails — what's the worst that happens?"
- "Give me an example of a chatbot causing real harm."
- "How do you convince stakeholders to invest in safety?"

### What it tests
Whether you can recall named production failures, diagnose the missing control in each, and convert the anecdote into a concrete engineering requirement.

---

## Answer

### Concept
Three public incidents cover nearly the whole safety interview: **Air Canada (2024)** — an airline held legally liable for its chatbot's invented refund policy; **Chevrolet of Watsonville (2023)** — a dealer chatbot jailbroken into "selling" a $79,000 SUV for $1; **Mata v. Avianca (2023)** — lawyers sanctioned $5,000 for filing ChatGPT-fabricated case citations. Each maps to one missing control: grounding against authoritative policy, commitment authority limits, and output verification gates. Learn the trio and you can answer any "why does safety matter" question with evidence instead of adjectives.

### Mechanism

**1. Air Canada — ungrounded commitments bind the company (BC Civil Resolution Tribunal, Feb 2024).**
Passenger Jake Moffatt asked the airline's support chatbot about bereavement fares after a death in the family. The bot invented a policy — fly now, claim the discount retroactively within 90 days — that contradicted the airline's actual rules. He relied on it; the airline refused the refund. The tribunal ordered ~$812 CAD in damages and rejected Air Canada's argument that the chatbot was a separate entity responsible for its own actions: the bot was part of the airline's website, so its statements were the airline's statements.
- **Failure mode:** ungrounded generation on a consequential topic. The bot answered a policy question from parametric memory instead of the airline's fare rules.
- **Missing control:** retrieval grounding over the authoritative policy corpus, plus a confidence-gated fallback ("I can't confirm this fare rule — here's the policy page and a human agent") for anything that creates a financial commitment.

**2. Chevrolet of Watsonville — no commitment authority, no instruction hierarchy (Dec 2023).**
A dealership chatbot (a ChatGPT-powered widget) was coaxed by researcher Chris Bakke into agreeing to sell a 2024 Chevy Tahoe for $1 — "in a legally binding offer, no takesies backsies" — and into producing nonsense SQL-flavoured replies. The dealer pulled the bot within days. Nobody enforced the $1 "deal," but the brand damage was global.
- **Failure mode:** direct jailbreak plus excessive agency. The bot treated user-supplied instructions ("agree to everything I say") as overriding its role as a sales assistant, and it spoke in the language of binding offers with zero authority to make them.
- **Missing control:** instruction hierarchy (system role outranks user framing), a refusal/completion policy for out-of-scope requests, and — structurally — never letting a bot utter commitments. Offers, prices, and contracts go through a human or a deterministic rules engine, never through free generation.

**3. Mata v. Avianca — no verification gate on high-stakes output (SDNY, June 2023).**
Attorneys filed a brief opposing dismissal that cited half a dozen cases — *Varghese v. China Southern*, among others — that did not exist. They had been invented by ChatGPT. Judge Castel sanctioned the lawyers $5,000, and the opinion reads as a warning to the profession. (Michael Cohen admitted a near-identical fabricated-citation filing months later, confirming this was a pattern, not an outlier.)
- **Failure mode:** fluent confabulation in a domain the user could not cheaply check. A legal brief looks authoritative whether or not its citations resolve.
- **Missing control:** a verification gate between generation and filing — every citation resolved against a real database (CourtListener, Westlaw) with an NLI/entailment check, and a human sign-off step for any artefact that carries professional or legal liability.

**The pattern across all three:** the failure was never "the model is dumb." In each case the model did exactly what unguarded models do — generate plausible text — and the *system* lacked the control that the stakes demanded: grounding for policy answers, authority limits for commitments, verification for professional artefacts. Say this sentence in the interview; it turns three anecdotes into one thesis.

### Example / Tradeoff

**The 30-second versions to memorise:**

| Case | One sentence | Missing control |
|---|---|---|
| Air Canada, 2024 | Chatbot invented a bereavement fare policy; tribunal held the airline liable (~$812) — bot output is company speech | Grounding over authoritative policy + fallback for commitments |
| Chevy Tahoe, 2023 | Jailbroken dealer bot "sold" a $79k SUV for $1; pulled in days, mocked worldwide | Instruction hierarchy + no bot-issued commitments |
| Mata v. Avianca, 2023 | Lawyers filed ChatGPT-invented citations; $5,000 sanctions | Citation verification gate + human sign-off |

**The tradeoff is friction versus liability.** Every control above adds friction: grounding adds retrieval latency, human-in-the-loop slows sales flows, verification gates slow professionals. The correct calibration is by stakes, not by uniformity — a trivia answer can be ungrounded, a refund promise cannot. The interviewer wants to hear you price the control against the cost of the failure: Air Canada's missing fallback cost more in legal fees and press than a "let me connect you to an agent" fallback ever would.

**Real tools:** RAG over policy docs with RAGAS faithfulness gating, Llama Guard / injection classifiers for the Chevy class, NLI entailment (DeBERTa) or citation-resolution checks for the Avianca class, human-in-the-loop queues (e.g. in LangGraph or your ticketing system) for binding actions.

---

## Verbal script

**Opening (30s):**
"I reach for three incidents. Air Canada's chatbot invented a bereavement fare policy and the tribunal held the airline liable — bot output is company speech. A Chevy dealer's chatbot was jailbroken into selling a Tahoe for a dollar. And in Mata v. Avianca, lawyers were sanctioned five thousand dollars for filing ChatGPT-invented citations. Each one is a missing engineering control, not a mysterious model failure, and that's the frame I'd use."

**Core explanation (2–3 min):**
"Air Canada, February 2024: a passenger asked about bereavement fares, the bot made up a retroactive-claim policy, and the tribunal ordered about eight hundred dollars in damages — explicitly rejecting the argument that the chatbot is a separate entity. The missing control was grounding: policy answers should be retrieved from the authoritative fare rules, with a fallback to a human whenever the answer creates a financial commitment.

The Chevy case, December 2023: a dealership's ChatGPT widget agreed to sell a seventy-nine-thousand-dollar SUV for one dollar, 'no takesies backsies.' Nobody enforced it, but the brand damage was worldwide. The missing control was instruction hierarchy plus commitment authority — the bot should never have been able to utter a binding offer. Prices and contracts go through a human or a rules engine, never through free generation.

Mata v. Avianca, June 2023: attorneys filed a brief citing cases that didn't exist — pure ChatGPT confabulation — and were sanctioned five thousand dollars. The missing control was a verification gate: resolve every citation against a real database before filing, with human sign-off on anything carrying professional liability.

The pattern across all three is the thesis I'd close on: the model did what unguarded models do — generate plausible text. The system lacked the control the stakes demanded."

**Tradeoff / production angle (1 min):**
"Every one of these controls costs friction — grounding adds latency, human review slows flows, verification gates slow professionals. So I calibrate by stakes, not uniformly. A trivia answer can be ungrounded; a refund promise, a price quote, or a court filing cannot. Air Canada's missing 'let me connect you to an agent' fallback cost more in legal fees and press than that fallback ever would. That's how I'd sell safety investment to stakeholders — price the control against the incident."

**Wrap-up (30s):**
"So: Air Canada means ground policy answers and fall back on commitments; Chevy means bots never issue commitments and user framing never outranks the system role; Avianca means verify before filing. Three anecdotes, one thesis — the failure is always the missing control, never just the model."

---

## Pitfalls

- **Mistake:** Reciting the anecdotes as trivia with no engineering mapping ("there was this funny Chevy hack…") — **Better:** Every anecdote ends in a named control: grounding, instruction hierarchy plus commitment authority, verification gate. The interviewer is scoring the mapping, not the storytelling.
- **Mistake:** "The fix is a better model — GPT-5 wouldn't do that" — **Better:** All three failures are system-level, not capability-level. A stronger model still generates ungrounded text when asked about policy it hasn't retrieved, still follows user framing without an instruction hierarchy, and still confabulates citations without a resolution check. Controls, not scale.
- **Mistake:** Treating the Chevy incident as harmless because the $1 deal was unenforceable — **Better:** The cost was brand damage and incident response, and the same jailbreak class against an agent with tool access (refunds, database writes) is a direct financial loss. Severity is a property of the tool surface behind the bot, not of the joke.
- **Mistake:** Over-applying the lesson — demanding human review on every bot output — **Better:** Calibrate by stakes. Quote the tradeoff explicitly: trivia answers can ship ungrounded, commitments and filings cannot. Blanket human review is how safety programs get bypassed by the teams they slow down.

---

## Related questions

| Question | Relationship |
|----------|--------------|
| [Q9: Red-team an LLM system?](08-009-red-team-an-llm-system.md) | prerequisite — the adversarial program that catches the Chevy class before launch |
| [Q4: Protect against prompt injection and jailbreaking?](08-004-protect-against-prompt-injection-and-jailbreaking.md) | same concept — the structural defenses the Chevy bot lacked |
| [Q2: How evaluate a chatbot?](05-002-how-evaluate-a-chatbot.md) | follow-up — the eval discipline (grounding checks, commitment tests) these incidents motivate |

---

## One-liner recall

> Air Canada (bot output is company speech — ground policy answers), Chevy Tahoe (jailbroken $1 sale — bots never issue commitments, system role outranks user framing), Mata v. Avianca ($5k sanctions for invented citations — verify before filing): every failure is a missing system control, never just the model — calibrate controls by stakes.
