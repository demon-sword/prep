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
├── system-design/           # System design prep (frontend + backend)
│   ├── claude/ slack/ twitter/ # Topic folders with HTML study pages
│   ├── dream11/             # Backend: live leaderboard + winner declaration
│   └── README.md            # Interview format & conventions
├── frontend/                # JS interview visualizations
│   ├── js-event-loop-card.html
│   ├── js-this-keyword-card.html
│   └── recrew-interview-prep.html
├── machine_learning/        # ML Engineer / Data Scientist interview prep
│   └── concepts/            # 38 interactive HTML visualizations (self-contained)
├── backend/                 # Backend / distributed systems interview prep
│   └── concepts/            # 22 interactive HTML visualizations (self-contained)
├── mlops/                   # Production ML / MLOps prep
│   └── concepts/            # Interactive HTML concepts (30 planned, none generated yet)
├── ml-system-design/        # ML system design case studies (HTML, 14 planned)
├── ml-coding/               # Runnable "implement it from scratch" ML problems (.md, 32 planned)
├── data-drills/             # SQL + statistics drills (72 problems in 12 groups)
│   ├── sql/ stats/          # One .md per drill + _template.md
│   └── plan.md / progress.txt # Ralph queue & log (one group at a time)
├── study/                   # Spaced-repetition study system (state.json, study.sh/study.py)
├── ralph-ai-engineering/    # AI Eng notes generator (Cursor Agent loop)
├── ralph-concepts/          # Interactive HTML concept generator (41 concepts)
├── ralph-machine-learning/  # ML interactive HTML concept generator (38 concepts)
├── ralph-backend/           # Backend interactive HTML concept generator (22 concepts)
├── ralph-mlops/             # MLOps interactive HTML concept generator (30 concepts)
├── ralph-ml-system-design/  # ML system design case study generator (14 topics)
├── ralph-ml-coding/         # Runnable ML coding problem generator (32 problems)
├── ralph-data-drills/       # SQL + stats drill generator (72 problems / 12 groups)
├── ralph-dsa/               # DSA pattern/problem generator
├── ralph-system-design/     # System design topic generator
├── ralph-lib/               # ralph_sandbox.py — shared containment launcher for model code
├── ralph-common.sh          # Shared bash helpers sourced by the Ralph once.sh/loop.sh scripts
├── validate-corpus.sh       # Cross-file redundancy + (--final) completeness gate
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

**MLOps / Production ML Concepts** (`ralph-mlops/`):
```bash
./ralph-mlops/scaffold.sh                               # build plan.md from concepts.json
./ralph-mlops/once.sh [concept-id] [--model slug]       # generate one (or next in queue)
./ralph-mlops/loop.sh [concept-id] [max] [--model slug] # loop all 30, or retry one id
./ralph-mlops/validate.sh [concept-id]                  # validate HTML structure
```

Output: `mlops/concepts/<id>.html`. Concept IDs: `01-data-validation` through `30-ml-cost-management` (see `concepts.json`). The production-ML round — "your model is live and something is wrong, what do you look at and in what order" — monitoring, drift, feature stores, retraining, rollout. Env: `RALPH_MLOPS_MODEL`, `RALPH_MLOPS_TIMEOUT` (default 3600).

**ML System Design Case Studies** (`ralph-ml-system-design/`):
```bash
./ralph-ml-system-design/scaffold.sh                               # build plan.md from topics.json
./ralph-ml-system-design/once.sh [concept-id] [--model slug]       # generate one (or next in queue)
./ralph-ml-system-design/loop.sh [concept-id] [max] [--model slug] # loop all 14, or retry one id
./ralph-ml-system-design/validate.sh [concept-id]                  # validate HTML structure
```

Output: `ml-system-design/<id>.html` (flat, not a `concepts/` subdir). IDs: `01-feed-ranking-system` through `14-llm-inference-serving-platform` (see `topics.json`). Backend/ML system design, distinct from the frontend-flavoured `system-design/` folder; every case study carries a validator-enforced `#capacity` section — a page that asserts a number without showing the back-of-envelope arithmetic fails. Env: `RALPH_MLSD_MODEL`, `RALPH_MLSD_TIMEOUT` (default 3600).

**ML Coding Problems** (`ralph-ml-coding/`):
```bash
./ralph-ml-coding/scaffold.sh                               # build plan.md from problems.json
./ralph-ml-coding/once.sh [problem-id] [--model slug]       # generate one (or next in queue)
./ralph-ml-coding/loop.sh [problem-id] [max] [--model slug] # loop all 32, or retry one id
./ralph-ml-coding/validate.sh [problem-id]                  # EXECUTES the solution + self-test
```

Output: `ml-coding/<id>.md`. IDs: `01-train-test-split` through `32-bpe` (see `problems.json`). "Implement it from scratch" problems (statement → hints → solution → complexity) with **real runnable Python**, not pseudocode. `validate.sh` concatenates each file's `## Solution` and `## Self-test` blocks and runs them under `ralph-lib/ralph_sandbox.py`: a solution that does not run, or whose self-test fails, fails the problem. Needs a Python with numpy (`venv/` is tried before `PATH`); sklearn is optional and only ever a self-test cross-check. Exit 2 = cannot execute (environment fault) — callers must not retry the agent on it. Env: `RALPH_MLCODING_MODEL`, `RALPH_MLCODING_TIMEOUT` (default 3600), `RALPH_ML_PYTHON`, `RALPH_ML_EXEC_TIMEOUT` (default 60), `RALPH_ML_MEM_MB` (default 2048).

**SQL / Stats Data Drills** (`ralph-data-drills/`) — the unit of work is a **group slug**, not a problem id:
```bash
./ralph-data-drills/scaffold.sh <group-slug>            # e.g. sql-01-window-functions
./ralph-data-drills/once.sh <group-slug> [--agent cursor|claude] [--model slug] [iterations]
./ralph-data-drills/loop.sh <group-slug> [max] [--agent cursor|claude] [--model slug]
bash ralph-data-drills/validate.sh <group-slug>         # runs the queries and the simulations
```

Groups (12, six problems each), from `problems.json`:
```
sql-01-window-functions  sql-02-joins-and-nulls  sql-03-aggregation-grouping
sql-04-ctes-and-recursion  sql-05-time-and-cohorts  sql-06-modeling-and-performance
stats-01-probability-puzzles  stats-02-expectation-and-counting  stats-03-markov-and-processes
stats-04-distributions-and-estimation  stats-05-inference-and-testing  stats-06-bias-and-reasoning
```

Output: `data-drills/sql/<id>-<slug>.md` and `data-drills/stats/<id>-<slug>.md`; the plan/progress queue lives in `data-drills/`, one group at a time — scaffold the next group only after the current one validates. `validate.sh` executes the content: `family=sql` reference queries run against the problem's own schema in in-memory SQLite and are diffed against the stated expected output; `family=stats` Monte Carlo simulations run under `ralph-lib/ralph_sandbox.py` and are checked against the analytic answer. Env: `RALPH_AGENT` (`claude` default, or `cursor`), `CURSOR_MODEL`, `RALPH_DD_MEM_MB` (default 2048); `RALPH_DD_PROBLEMS` / `RALPH_DD_OUT` are test hooks that override the problems.json and output paths.

### Shared Ralph Infrastructure

**`ralph-common.sh`** — sourced by the generators' `once.sh`/`loop.sh` (`. "$PREP_ROOT/ralph-common.sh"`). It runs no agent loop itself; it provides the gates every track shares:

- `ralph_validate <cmd...>` — runs a validator, echoes its report, leaves the `FAIL:` lines in `RALPH_FAIL_LINES`, and returns the validator's exit code. **Call it as `ralph_validate ... || RC=$?`** — never `set +e; ...; set -e`. Helpers must not touch the caller's shell options: that is how the retry/give-up paths in nine generators were once silently turned into dead code.
- `ralph_factcheck <file> <subject> [model]` — adversarial second-opinion pass. A fresh agent is handed the finished file and nothing else (no spec, no plan, no transcript) and must end with `<factcheck>PASS</factcheck>` or `<factcheck>FAIL</factcheck>`; no verdict tag counts as unverified, not a pass. Findings land in `RALPH_FACTCHECK_NOTES`.
- `ralph_feedback` — builds the "PREVIOUS ATTEMPT REJECTED" correction block appended to the next attempt's prompt.
- `ralph_require_complete <plan> <outdir> <ext> [extra-dir...]` — the end-of-run completeness gate. Per-file validators iterate over the files that exist, so an empty corpus reports "0 checked, 0 failed" and exits 0; this asks instead whether every planned *and* every queued id exists on disk.
- `ralph_rejects_bump` / `ralph_rejects_clear` — the retry budget, kept in a file under the generator's state dir keyed by `RALPH_RUN_ID`, because `loop.sh` re-execs `once.sh` each iteration and an in-process counter would reset every time.
- `ralph_stream_json_result`, `ralph_newest_since`, `ralph_loop_pause`, `ralph_queue_file`, `ralph_queue_ids` — stream-json result extraction, "what did this iteration actually produce", inter-iteration pause, and queue-file (`concepts.json` / `topics.json` / `problems.json`) discovery.

Shared env vars it honours: `RALPH_MAX_ATTEMPTS` (default 3), `RALPH_FACTCHECK_TIMEOUT` (default 900), `RALPH_SKIP_FACTCHECK` (`1` skips the adversarial pass — e.g. offline reruns), `RALPH_LOOP_SLEEP` (default 5), `RALPH_MAX_STALLS` (default 3), `RALPH_RUN_ID`.

**`ralph-lib/ralph_sandbox.py`** — the one containment launcher for model-written code, shared so the two tracks that execute it cannot drift apart: `ralph-ml-coding/validate.sh` runs each solution against its self-test, `ralph-data-drills/validate.sh` runs each Monte Carlo simulation against its analytic answer. Layers: own process session (group kill), isolated interpreter (`-I`), environment rebuilt from an allowlist so the child never sees the parent's secrets, `RLIMIT_NPROC`/`FSIZE`/`CORE` (plus `RLIMIT_AS` where the kernel honours it), an RSS watchdog, macOS seatbelt via `sandbox-exec` (no network, no writes outside the run's temp dir), a CPython audit hook as the fallback backstop, and a timeout that SIGKILLs the whole process group. API: `ralph_sandbox.run(python_bin, source, timeout)`. **If the file is missing, both validators exit 2 rather than run untrusted code uncontained** — an environment fault, not something the agent can fix by rewriting content. Full detail in `ralph-ml-coding/README.md`.

| Env var | Default | Effect |
|---------|---------|--------|
| `RALPH_SANDBOX_MEM_MB` | 2048 | Resident-memory ceiling for the code under test |
| `RALPH_SANDBOX_MAX_PROCS` | 0 | `RLIMIT_NPROC`; 0 = no fork at all |
| `RALPH_SANDBOX_FSIZE_MB` | 64 | `RLIMIT_FSIZE` — bytes the code may write |

**`validate-corpus.sh`** — corpus-level checks no per-file validator can see (three separate answers each explaining self-attention from scratch, for instance):

```bash
./validate-corpus.sh                              # every track, redundancy only
./validate-corpus.sh concepts backend             # named tracks
./validate-corpus.sh --final                      # + completeness gate (flag may sit anywhere)
RALPH_DEDUP_STRICT=1 ./validate-corpus.sh mlops   # redundant-topic warnings become failures
```

Tracks: `ai-engineering`, `concepts`, `machine-learning`, `backend`, `dsa`, `system-design`, `mlops`, `ml-system-design`, `ml-coding`, `data-drills`. Two signals: **COPIED TEXT** (5-gram shingle overlap coefficient, binding — over threshold exits 1) and **REDUNDANT TOPIC** (TF-IDF cosine over unigrams+bigrams, advisory unless strict). Without `--final`, a track with fewer than 2 usable docs prints `SKIP` and exits 0 — correct mid-generation, but it makes an ungenerated track look identical to a finished one; `--final` (or `RALPH_CORPUS_FINAL=1`) additionally fails a track whose corpus is empty, and — for the tracks with a flat id queue — names the planned ids that were never produced. Env: `RALPH_DEDUP_THRESHOLD` (0.35), `RALPH_DEDUP_COSINE` (0.15), `RALPH_DEDUP_MIN_SHINGLES` (40), `RALPH_DEDUP_STRICT` (0), `RALPH_CORPUS_FINAL` (0). Exit 0 = clean, 1 = at least one binding failure.

### HTML Preview / Testing

```bash
# Open any .html directly in browser
open ai-engineering/concepts/06-qkv-attention.html

# For local server (fetch/modules):
python3 -m http.server 8765
# then http://localhost:8765/ai-engineering/concepts/...
```

Playwright MCP is used by Ralph agents for validation (screenshot, console check).

## Study System

Spaced-repetition retrieval practice over every track. `study/state.json` is the **single source of truth** — one JSON object per study item (`id`, `track`, `title`, `path`, `prompt`, `answer`, `status`, `reps`, `lapses`, `ease`, `interval_days`, `last_reviewed`, `next_due`, `history`), sorted by `id`.

Daily loop:
```bash
./study/study.sh due      # what's due today
./study/study.sh drill    # question → pause → answer → rate
```

```bash
./study/study.sh seed                        # build/refresh state.json from disk (idempotent)
./study/study.sh due [--track T] [-n N]      # items due today or overdue
./study/study.sh drill [--track T] [-n N]    # interactive retrieval practice
./study/study.sh mark <id> <rating>          # <id> = any unique substring
./study/study.sh progress [--track T]        # per-track progress table
./study/study.sh weak [-n N]                 # lowest ease, most lapses, most overdue
./study/study.sh next                        # highest-priority item right now
./study/study.sh render                      # regenerate the two generated views
./study/study.sh stats                       # one-line summary
```

`python3 study/study.py <same args>` is equivalent — the `.sh` is just a wrapper.

Scheduling is SM-2. Ratings: `again` (0) · `hard` (3) · `good` (4) · `easy` (5); aliases `a`/`h`/`g`/`e` and `1`/`2`/`3`/`4`. `again` resets reps, increments `lapses`, and relearns tomorrow; ease floors at 1.3. Status is derived, not typed — it reuses the DSA vocabulary: `todo` (never reviewed) → `hint` (rated again/hard) → `solo` (good/easy, interval < 21d) → `review` (21–59d) → `mastered` (≥ 60d and reps ≥ 4).

Tracks (11, the whole of `TRACKS` in `study/study.py`): `ai-answers` · `ai-concepts` · `ml-concepts` · `be-concepts` · `mlops-concepts` · `ml-coding` · `ml-sys-design` · `data-drills` · `dsa` · `dsa-patterns` · `sys-design`.

Every track is seeded from the generators' own manifests (`ralph-*/concepts.json`, `problems.json`, `topics.json`), which are read-only here. Because the manifests run ahead of the generators, an item becomes studiable the moment it is declared — before its page exists — and its link degrades to the output directory, then to the manifest. **So a new corpus is picked up by `./study/study.sh seed` automatically**: add entries to a manifest the study system already reads and they appear; add a whole new manifest and it needs one `build_items()` line.

**Hard rule:** `study/PROGRESS.md` and `dsa/progress.md` are **generated** by `./study/study.sh render`. Agents must never hand-edit them — change state via `mark`/`drill`, then re-render. See `study/README.md`.

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
- Ralph MLOps env:
  - `RALPH_MLOPS_MODEL` — model slug
  - `RALPH_MLOPS_TIMEOUT` — default 3600
- Ralph ML System Design env:
  - `RALPH_MLSD_MODEL` — model slug
  - `RALPH_MLSD_TIMEOUT` — default 3600
- Ralph ML Coding env:
  - `RALPH_MLCODING_MODEL` — model slug
  - `RALPH_MLCODING_TIMEOUT` — default 3600
  - `RALPH_ML_PYTHON` — interpreter used to execute solutions (else `venv/`, then `PATH`; needs numpy)
  - `RALPH_ML_EXEC_TIMEOUT` — default 60 (seconds per solution)
  - `RALPH_ML_MEM_MB` — default 2048 (resident-memory cap for the code under test)
- Ralph Data Drills env:
  - `RALPH_AGENT` — `claude` (default) or `cursor` backend
  - `CURSOR_MODEL` — model slug (this track has no dedicated `*_MODEL` var)
  - `RALPH_DD_MEM_MB` — default 2048 (Monte Carlo sandbox memory cap)
  - `RALPH_DD_PROBLEMS` / `RALPH_DD_OUT` — test hooks overriding `problems.json` and the output dir
- Shared Ralph env (`ralph-common.sh`, all generators):
  - `RALPH_MAX_ATTEMPTS` — default 3 (regenerations of one unit before giving up)
  - `RALPH_FACTCHECK_TIMEOUT` — default 900
  - `RALPH_SKIP_FACTCHECK` — `1` skips the adversarial fact-check pass
  - `RALPH_LOOP_SLEEP` — default 5 (seconds between loop iterations)
  - `RALPH_MAX_STALLS` — default 3 (no-new-content iterations before `loop.sh` gives up)
  - `RALPH_RUN_ID` — identifies one `loop.sh` run so retry budgets survive across `once.sh` processes
- Sandbox env (`ralph-lib/ralph_sandbox.py`):
  - `RALPH_SANDBOX_MEM_MB` — default 2048
  - `RALPH_SANDBOX_MAX_PROCS` — default 0 (no fork)
  - `RALPH_SANDBOX_FSIZE_MB` — default 64
- Corpus validation env (`validate-corpus.sh`):
  - `RALPH_DEDUP_THRESHOLD` (0.35) · `RALPH_DEDUP_COSINE` (0.15) · `RALPH_DEDUP_MIN_SHINGLES` (40)
  - `RALPH_DEDUP_STRICT` (0) — make redundant-topic warnings binding
  - `RALPH_CORPUS_FINAL` (0) — same as passing `--final`

## What NOT to Do

- Don't edit generated files directly — re-run the Ralph generator
- Don't hand-edit `study/PROGRESS.md` or `dsa/progress.md` — both are generated; run `./study/study.sh render`
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
| Generate next MLOps concept HTML | `./ralph-mlops/once.sh` |
| Validate MLOps concept HTML | `./ralph-mlops/validate.sh` |
| Generate next ML system design case study | `./ralph-ml-system-design/once.sh` |
| Validate ML system design case study | `./ralph-ml-system-design/validate.sh` |
| Generate next ML coding problem | `./ralph-ml-coding/once.sh` |
| Validate ML coding problems (runs the code) | `./ralph-ml-coding/validate.sh` |
| Generate a data-drills group | `./ralph-data-drills/scaffold.sh sql-01-window-functions && ./ralph-data-drills/loop.sh sql-01-window-functions 15` |
| Validate a data-drills group (runs SQL + sims) | `bash ralph-data-drills/validate.sh sql-01-window-functions` |
| Cross-file redundancy check | `./validate-corpus.sh` |
| Completeness gate after a finished run | `./validate-corpus.sh --final` |
| Run local server for HTML | `python3 -m http.server 8765` |