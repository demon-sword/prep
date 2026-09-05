# Study System

Spaced-repetition retrieval practice across every track in this repo. One state file, one CLI, two generated views.

## The 30-second daily loop

```bash
./study/study.sh due      # what's due today
./study/study.sh drill    # practice it — question, pause, answer, rate
```

That's the whole ritual. `drill` shows the question, waits, reveals the answer, and records your rating. Marking a single item outside a drill is one command:

```bash
./study/study.sh mark 01-001 good
```

## Commands

| Command | What it does |
|---------|--------------|
| `./study/study.sh seed` | Build/refresh `state.json` from disk. Idempotent — never loses schedule. |
| `./study/study.sh due [--track T] [-n N]` | List items due today or overdue. |
| `./study/study.sh drill [--track T] [-n N]` | Interactive retrieval practice: shows the question, waits, reveals the answer, records your rating. |
| `./study/study.sh mark <id> <rating>` | Mark one item reviewed. `<id>` accepts any unique substring. |
| `./study/study.sh progress [--track T]` | Per-track progress table. |
| `./study/study.sh weak [-n N]` | Weakest items — lowest ease, most lapses, most overdue. |
| `./study/study.sh next` | The single highest-priority item right now. |
| `./study/study.sh render` | Regenerate `study/PROGRESS.md` and `dsa/progress.md`. |
| `./study/study.sh stats` | One-line summary. |

`python3 study/study.py <same args>` is equivalent — the `.sh` is just a wrapper.

**Tracks (11):** `ai-answers` (ai-engineering/answers) · `ai-concepts` · `ml-concepts` · `be-concepts` · `mlops-concepts` · `ml-coding` · `ml-sys-design` · `data-drills` · `dsa` (NeetCode 150) · `dsa-patterns` · `sys-design`

Concept, ML-coding, ML-system-design and data-drill items are seeded from the `ralph-*/` manifests, so they exist as study items before the generator has written their page. Until it does, the item links to its output directory or to the manifest that declares it — `render` warns if any path fails to resolve.

## Scheduling (SM-2)

Self-rating drives the next interval. Ratings:

| Rating | Quality | Aliases |
|--------|---------|---------|
| `again` | 0 | `a`, `1` |
| `hard` | 3 | `h`, `2` |
| `good` | 4 | `g`, `3` |
| `easy` | 5 | `e`, `4` |

- `again` resets `reps`, schedules a relearn for tomorrow, and increments `lapses`.
- The ease factor floors at **1.3** — a chronically hard item stays frequent instead of drifting away.

## Status vocabulary

Deliberately the same five words the repo already uses in [`dsa/README.md`](../dsa/README.md), now derived from the schedule instead of typed by hand:

| Status | Meaning |
|--------|---------|
| `todo` | Never reviewed |
| `hint` | Last attempt needed help — rated `again` or `hard` |
| `solo` | Rated `good`/`easy`, interval < 21d |
| `review` | Interval 21–59d |
| `mastered` | Interval ≥ 60d and reps ≥ 4 |

## Files

| File | Role |
|------|------|
| `study/state.json` | **Single source of truth.** `{"version":1,"generated":"<iso>","items":[...]}`, items sorted by `id`. Each item: `id`, `track`, `title`, `path`, `prompt`, `answer`, `status`, `reps`, `lapses`, `ease`, `interval_days`, `last_reviewed`, `next_due`, `history`. |
| `study/PROGRESS.md` | **Generated** by `render`. Do not hand-edit. |
| `dsa/progress.md` | **Generated** by `render`. Do not hand-edit. |

Any edit to those two views is overwritten on the next `render`. Change the schedule through `mark`/`drill`, not by typing statuses.

## Why this exists

Three trackers existed and none of them ever fired:

- `dsa/progress.md` — a 150-row table where every single row still said `todo`.
- `ai-engineering/answers/` — a `Status: review` field frozen at its default across all 202 files.
- `frontend/recrew-interview-prep.html` — a `Prep Progress: 0%` bar hardcoded in the markup.

All three needed a human to remember to update them, so nobody did. This replaces them with state that only moves when you actually practice, and views that are regenerated from it.
