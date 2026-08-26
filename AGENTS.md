# AGENTS.md — Interview Prep Repository

This is a **personal interview preparation repository** with multiple domains and automated content generators ("Ralph" projects).

## Repository Structure

```
prep/
├── ai-engineering/          # AI Engineering interview prep
│   ├── concepts/            # 41 interactive HTML visualizations (self-contained)
│   ├── categories/          # Category overview docs (8 completed)
│   ├── answers/             # Per-question notes (200+ generated)
│   ├── interview-questions.md  # Source question bank
│   ├── plan.md / progress.txt # Ralph queue & log
│   └── convert_md_to_html.py  # Utility
├── dsa/                     # NeetCode 150 pattern-first DSA prep
│   ├── patterns/            # Pattern docs (9 completed)
│   ├── problems/            # Problem notes (34 completed)
│   └── neetcode-150-list.md # Source problem list
├── system-design/           # Frontend system design prep
│   ├── claude/ slack/ twitter/ # Topic folders with HTML study pages
│   └── README.md            # Interview format & conventions
├── frontend/                # JS interview visualizations
│   ├── js-event-loop-card.html
│   ├── js-this-keyword-card.html
│   └── recrew-interview-prep.html
├── machine_learning/        # ML Engineer / Data Scientist interview prep
│   └── concepts/            # 38 interactive HTML visualizations (self-contained)
├── backend/                 # Backend / distributed systems interview prep
│   └── concepts/            # 22 interactive HTML visualizations (self-contained)
├── ralph-ai-engineering/    # AI Eng notes generator (Cursor Agent loop)
├── ralph-concepts/          # Interactive HTML concept generator (41 concepts)
├── ralph-machine-learning/  # ML interactive HTML concept generator (38 concepts)
├── ralph-backend/           # Backend interactive HTML concept generator (22 concepts)
├── ralph-dsa/               # DSA pattern/problem generator
├── ralph-system-design/     # System design topic generator
├── venv/                    # Python venv (for generators)
└── tests/                   # (empty)
```

## Key Commands

### Ralph Generators (Cursor Agent loops)

Each Ralph project uses headless Cursor Agent (`claude -p --output-format stream-json`) to generate content. Run from repo root.

**AI Engineering Notes** (`ralph-ai-engineering/`):
```bash
./ralph-ai-engineering/scaffold.sh <category-slug>   # e.g. 08-safety-guardrails
./ralph-ai-engineering/once.sh <category-slug>       # single iteration
./ralph-ai-engineering/loop.sh <category-slug> [max] # repeat until COMPLETE
./ralph-ai-engineering/validate.sh <category-slug>   # structural validation
```

Categories (start with smallest):
```
08-safety-guardrails (10 Q) → 04-fine-tuning-training (12 Q) → 07-cost-latency (16 Q)
→ 02-rag-systems (34 Q) → 03-agents-tool-use (38 Q) → 05-evaluation-metrics (23 Q)
→ 06-ml-fundamentals (26 Q) → 01-llm-fundamentals (48 Q) → 09-system-design-ai (55 Q)
→ 10-behavioral (74 Q) → 11-context-management (15 Q)
```

**Interactive Concepts** (`ralph-concepts/`):
```bash
./ralph-concepts/scaffold.sh                    # build plan from concepts.json
./ralph-concepts/once.sh [concept-id]           # generate one (or next in queue)
./ralph-concepts/loop.sh [max] [--model slug]   # loop all 41 concepts
./ralph-concepts/validate.sh [concept-id]       # validate HTML structure
```

Concept IDs: `01-self-supervision` through `41-flash-attention` (see `concepts.json`)

**Machine Learning Concepts** (`ralph-machine-learning/`):
```bash
./ralph-machine-learning/scaffold.sh                    # build plan from concepts.json
./ralph-machine-learning/once.sh [concept-id]           # generate one (or next in queue)
./ralph-machine-learning/loop.sh [max] [--model slug]   # loop all 38 concepts
./ralph-machine-learning/validate.sh [concept-id]       # validate HTML structure
```

Concept IDs: `01-bias-variance-tradeoff` through `38-arima-forecasting` (see `concepts.json`). Deeper/broader classical-ML track for dedicated ML Engineer / Data Scientist interviews — distinct from `ai-engineering/categories/06-ml-fundamentals.md`, which stays scoped to what shows up in LLM/AI-engineer interviews.

**Backend / Distributed Systems Concepts** (`ralph-backend/`):
```bash
./ralph-backend/scaffold.sh                    # build plan from concepts.json
./ralph-backend/once.sh [concept-id]           # generate one (or next in queue)
./ralph-backend/loop.sh [max] [--model slug]   # loop all 22 concepts
./ralph-backend/validate.sh [concept-id]       # validate HTML structure
```

Concept IDs: `01-caching-strategies` through `22-connection-pooling` (see `concepts.json`). 8 of the 22 (`01`–`08`) are seeded from hand-written source notes in `ralph-backend/sources/` — the generator adapts them faithfully rather than inventing theory; the rest are written from scratch in the same voice. Each concept page also has a dedicated `#interview-line` section (the exact sentence to say when the topic comes up), not just theory/viz/takeaways.

**DSA Notes** (`ralph-dsa/`):
```bash
./ralph-dsa/scaffold.sh <category-slug>         # e.g. 01-arrays-hashing
./ralph-dsa/once.sh <category-slug>
./ralph-dsa/loop.sh <category-slug> [max]
./ralph-dsa/validate.sh <category-slug>
```

Categories: `01-arrays-hashing` (9) → `02-two-pointers` (5) → ... → `18-bit-manipulation` (7)

**System Design** (`ralph-system-design/`):
```bash
./ralph-system-design/scaffold.sh <topic>       # e.g. slack
./ralph-system-design/loop.sh <topic> [max]
./ralph-system-design/validate.sh <topic>
```

### HTML Preview / Testing

```bash
# Open any .html directly in browser
open ai-engineering/concepts/06-qkv-attention.html

# For local server (fetch/modules):
python3 -m http.server 8765
# then http://localhost:8765/ai-engineering/concepts/...
```

Playwright MCP is used by Ralph agents for validation (screenshot, console check).

## Conventions Agents Must Follow

### AI Engineering Answers (`ai-engineering/answers/`)
- Format per `ai-engineering/answers/_template.md` (6 required sections)
- **Verbal script** = first-person interview voice ("I'd start by...", "The key insight is...")
- Status defaults to `review` — update to `mastered` after practicing
- Cross-link related questions via `Related questions` section

### AI Engineering Concepts (`ai-engineering/concepts/`)
- Self-contained HTML: inline CSS/JS, only Google Fonts CDN allowed
- Dark terminal theme (CSS vars in `ralph-concepts/spec.md`)
- Interactive visualization required (not static diagram)
- 5 sections: header, `#theory`, `#visualization`, `#takeaways`, `.concept-nav`

### DSA Problems (`dsa/problems/`)
- Filename: `NNN-slug.md` (zero-padded NeetCode number)
- Format per `dsa/problems/_template.md` (3 parts: Framing, Approach, Tradeoffs)
- Pseudocode only — no language-specific implementations
- Status: `todo` → `hint` → `solo` → `review` → `mastered`

### DSA Patterns (`dsa/patterns/`)
- Filename: `NN-topic-slug.md` (matches NeetCode category order)
- Format per `dsa/patterns/_template.md`
- Include: recognition signals, sub-patterns, templates, anti-patterns, problem checklist

### System Design Topics (`system-design/<topic>/`)
- Each topic: design-doc.md, architecture HTML, interview HTML, answers/, answers-html/
- Architecture map HTML required before/alongside section answers
- Answer format: Problem framing → Approach → Tradeoffs

## Environment

- Python venv at `venv/` (used by `convert_md_to_html.py`)
- Cursor Agent env vars (optional):
  - `CURSOR_MODEL` — model slug (e.g. `claude-sonnet-4`)
  - `CURSOR_AGENT_TIMEOUT_SEC` — default 2700 (45 min)
  - `CURSOR_AGENT_OUTPUT_FORMAT` — default `stream-json`
- Ralph Concepts env:
  - `RALPH_CONCEPTS_MODEL` — model slug
  - `RALPH_CONCEPTS_TIMEOUT` — default 3600
- Ralph Machine Learning env:
  - `RALPH_ML_MODEL` — model slug
  - `RALPH_ML_TIMEOUT` — default 3600
- Ralph Backend env:
  - `RALPH_BACKEND_MODEL` — model slug
  - `RALPH_BACKEND_TIMEOUT` — default 3600

## What NOT to Do

- Don't edit generated files directly — re-run the Ralph generator
- Don't commit generated HTML visualizations from root (they're in `ai-engineering/concepts/`)
- Don't add test files — `tests/` is empty and unused
- Don't assume this is a deployable app — it's personal study material

## Quick Reference

| Task | Command |
|------|---------|
| Generate next AI Eng category | `./ralph-ai-engineering/scaffold.sh 02-rag-systems && ./ralph-ai-engineering/loop.sh 02-rag-systems 42` |
| Generate next DSA category | `./ralph-dsa/scaffold.sh 02-two-pointers && ./ralph-dsa/loop.sh 02-two-pointers 10` |
| Generate next concept HTML | `./ralph-concepts/once.sh` |
| Validate concept HTML | `./ralph-concepts/validate.sh` |
| Preview concept in browser | `open ai-engineering/concepts/06-qkv-attention.html` |
| Generate next ML concept HTML | `./ralph-machine-learning/once.sh` |
| Validate ML concept HTML | `./ralph-machine-learning/validate.sh` |
| Generate next Backend concept HTML | `./ralph-backend/once.sh` |
| Validate Backend concept HTML | `./ralph-backend/validate.sh` |
| Run local server for HTML | `python3 -m http.server 8765` |