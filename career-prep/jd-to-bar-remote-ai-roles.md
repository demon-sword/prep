# JD to Bar: Reading a Remote AI Role Ad Like an Interviewer

**Track:** career-prep
**Source:** LinkedIn job ad — 100% remote AI Engineer, 2+ years mandatory, 70 LPA fixed (shortlink coverage)
**Status:** `review`
**Hand-written:** yes — seed note; sets the convention for later `career-prep/` lanes

---

## Framing

### Why this note exists
A job ad is not a wish list — it is a compressed interview plan. Every expectation in the ad maps to a round (or a take-home rubric row) the hiring team already agreed on. Candidates who read the ad literally prepare for keywords; candidates who read it as a bar prepare for evidence. This note converts one real ad — a 100% remote AI Engineer role at 70 LPA fixed, 2+ years experience — into the five bars it implies, what "good" looks like for each, and how the take-home is likely scored.

### The ad, in one paragraph
The role asks for engineers who build and integrate AI solutions with modern AI/ML tech, turn ideas into production-ready systems, solve complex engineering problems, and keep learning new AI tools. Two hard filters sit on top: 2+ years of experience (mandatory) and fully remote work. Compensation is stated fixed at 70 LPA — no range, no "up to".

### What it tests (the meta-skill)
Whether you can translate vague hiring language into a preparation plan: which of your projects is evidence for which line, and where your gaps are before the interviewer finds them.

---

## Answer

### The five expectations → the five bars

**1. "Building and integrating AI solutions" → Bar: RAG/agentic pipeline depth**
- The interviewer is probing whether you have built a full retrieval pipeline, not called one API. Expect: chunking strategy, embedding choice, vector index (HNSW tradeoffs), reranking, and how you handle stale documents.
- Good sounds like: "I built a 9-stage RAG pipeline; the failure that taught me the most was…" with a named retrieval metric (recall@k, faithfulness) and what moved it.
- Prepare from: `../ai-engineering/categories/02-rag-systems.md`, `../ai-engineering/categories/03-agents-tool-use.md`, answers `01-011` (pipeline reliability) and `01-012` (complete RAG process).

**2. "Working with modern AI/ML technologies" → Bar: current-tool fluency, not trivia**
- The interviewer wants signal you ship with today's stack: fine-tuning when it beats prompting (LoRA vs full), agent memory patterns, and at least passing familiarity with the tools the market is actually demanding — LangGraph, MCP, GraphRAG, ReAct-style agents, multi-cloud LLM APIs.
- Good sounds like: naming where each tool fits and where it breaks (e.g., "GraphRAG pays off when relations matter for retrieval; it is overkill for flat FAQ corpora"), not reciting definitions.
- Prepare from: `../ai-engineering/concepts/29-rag-overview.html`, `30-vector-search.html`, `31-agents-overview.html`, `32-agent-memory.html`, `15-finetuning-types.html`, `16-lora.html`.

**3. "Turning ideas into production-ready systems" → Bar: serving, cost, and evals**
- This is the 70-LPA line. Anyone can demo; the bar is owning latency, cost per request, and quality measurement in production: prefill/decode behavior, batching/caching choices, eval pipelines, and what you monitor after launch (skew, staleness, regressions).
- Good sounds like: "At X requests/day our p99 was Y; we cut cost Z% with [caching|batching|distillation] and caught a regression with [eval set|judge pipeline] before users did."
- Prepare from: `../ai-engineering/concepts/38-production-llm-serving.html`, `23-evaluation-pipeline.html`, `../ai-engineering/categories/07-cost-latency.md`, `../ai-engineering/categories/05-evaluation-metrics.md`.

**4. "Solving complex engineering problems" → Bar: system design + debugging stories**
- Expect a design round (an AI-flavored system: chatbot, search, agent platform) plus "tell me about the hardest bug" follow-ups. The interviewer scores structured thinking: requirements → data flow → components → bottlenecks → tradeoffs.
- Good sounds like: asking clarifying questions first, stating numbers (scale, latency budget), then defending two rejected alternatives — not jumping to the architecture diagram.
- Prepare from: `../system-design/` design docs, `../dsa/patterns/` for the coding rounds that accompany it.

**5. "Learning/experimenting with new AI tools" → Bar: a habit with artifacts**
- A trait, not a topic — it cannot be crammed. The only evidence is artifacts: side projects, write-ups, contributions, or a credible story about adopting a tool early and what surprised you.
- Good sounds like: "When MCP tool-use landed I rebuilt my side project's tool layer on it; the gotcha was…" — specific, recent, honest about what failed.
- Prepare from: `../ai-engineering/concepts/26-open-weight-vs-opensource.html`, `../system-design/claude/answers/03-mcp-tool-use-ui.md`.

### The take-home rubric (most likely shape)
Remote AI roles at this band frequently screen with a take-home before live rounds. Score yourself against the rubric the reviewer is most likely holding:

| Rubric row | What earns full marks | What fails |
|---|---|---|
| Working end-to-end path | `README` → one command → running demo, pinned deps | "Works on my machine", missing env vars, unpinned model versions |
| Retrieval quality | Stated chunking/embedding choice + one measured number (even rough recall@k on 20 hand-made queries) | No eval at all; "it looked good to me" |
| Production awareness | Latency/cost note, error handling on API failures, structured output validation | Unhandled exceptions, free-text parsing with regex prayers |
| Code as communication | Small diffs of intent: typed boundaries, a short design note on tradeoffs made | Clever abstractions, 500-line single file, no explanation of choices |
| Honesty about limits | "Known limitations" section listing what breaks and what you would do with one more day | Claiming completeness; hiding the weak parts the reviewer will find anyway |

### The two hard filters — read them literally
- **2+ years mandatory.** If you are below it, a referral still beats a cold application (see the companion checklist), but do not expect the filter to bend — mandatory in the ad text means an ATS or recruiter screen enforces it.
- **100% remote.** Remote-first teams screen for async communication in every round: written clarity, documented decisions, unprompted status updates. Treat every interview answer as a writing sample.

---

## Verbal scripts (how to sound like the bar, not the ad)

**"Walk me through your RAG experience" (30s → 3 min):**
"I'd start with the pipeline I owned end-to-end — [domain] corpus, [N] documents. The key insight was that retrieval quality dominated everything: swapping chunking strategy moved recall@k more than any model upgrade. A concrete example is [specific failure → fix → metric delta]. The production angle: we served it at [scale], and the thing that broke at scale was [staleness/latency/cost], which we handled with [mechanism]."

**"Tell me about a hard production problem" (2 min):**
Frame it as symptom → hypothesis → measurement → fix → prevention. Numbers at every step. End with what you monitor now so it never recurs silently.

---

## Pitfalls

- **Keyword-matching the ad ("I know LangGraph, MCP, GraphRAG, ReAct…")** — **Better:** one tool you have actually shipped with, including what broke. A single deep story beats five namedrops; interviewers at this band treat lists without scars as negative signal.
- **Preparing only model-side answers for a production-side bar** — **Better:** for every project, rehearse the serving story (latency, cost, eval, monitoring). The ad's highest-paid line is "production-ready systems", and candidates who can only discuss prompts fail exactly there.
- **Treating "70 LPA fixed" as negotiable-by-skill** — **Better:** fixed means the band is set; negotiation moves to joining bonus, ESOPs/refreshers, remote-setup allowances, and review-cycle timing. See the companion checklist. Pushing base against a stated-fixed number signals you did not read the ad.
- **No measured number anywhere in your stories** — **Better:** every claim gets a metric, even a rough one ("p99 ~2s", "recall@5 ≈ 0.8 on our 50-query golden set"). Senior bars are calibrated in numbers; adjectives ("fast", "accurate", "scalable") score zero.

---

## Related material

| Note | Relationship |
|------|--------------|
| [Remote AI job application checklist](remote-ai-job-application-checklist.md) | follow-up — referral flow, apply hygiene, and negotiation once the bar is understood |
| [](../ai-engineering/categories/02-rag-systems.md) | prerequisite — retrieval depth behind expectation 1 |
| [](../ai-engineering/categories/03-agents-tool-use.md) | prerequisite — agent patterns behind expectations 1–2 |
| [](../ai-engineering/categories/07-cost-latency.md) | prerequisite — serving economics behind expectation 3 |
| [](../ai-engineering/categories/05-evaluation-metrics.md) | prerequisite — eval method behind expectation 3 |

---

## One-liner recall

> Read each JD line as the interview round it implies, and walk in with one measured production story per line — the 70-LPA line is always "production-ready", so rehearse latency, cost, eval, and monitoring, not prompts.
