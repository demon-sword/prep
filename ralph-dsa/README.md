# Ralph — DSA Notes Generator

Headless Cursor Agent loop to generate NeetCode study notes under `dsa/` — **one category at a time**.

## Quick start (category 1)

```bash
# 1. Queue Arrays & Hashing (pattern + 9 problems + validate)
./ralph-dsa/scaffold.sh 01-arrays-hashing

# 2. Single agent iteration
./ralph-dsa/once.sh 01-arrays-hashing

# 3. Loop until category complete (~11 tasks)
./ralph-dsa/loop.sh 01-arrays-hashing 15

# 4. Validate manually
./ralph-dsa/validate.sh 01-arrays-hashing
```

## Next category

When category 1 passes validate:

```bash
./ralph-dsa/scaffold.sh 02-two-pointers
./ralph-dsa/loop.sh 02-two-pointers 10
```

Previous category is recorded under **Categories completed** in `dsa/plan.md`.

## Category slugs

| # | Slug | Problems |
|---|------|----------|
| 1 | `01-arrays-hashing` | 9 |
| 2 | `02-two-pointers` | 5 |
| 3 | `03-sliding-window` | 6 |
| 4 | `04-stack` | 7 |
| 5 | `05-binary-search` | 7 |
| 6 | `06-linked-list` | 11 |
| 7 | `07-trees` | 15 |
| 8 | `08-tries` | 3 |
| 9 | `09-heap` | 7 |
| 10 | `10-backtracking` | 9 |
| 11 | `11-graphs` | 13 |
| 12 | `12-advanced-graphs` | 6 |
| 13 | `13-1d-dp` | 12 |
| 14 | `14-2d-dp` | 11 |
| 15 | `15-greedy` | 8 |
| 16 | `16-intervals` | 6 |
| 17 | `17-math-geometry` | 8 |
| 18 | `18-bit-manipulation` | 7 |

## What each run produces

Per category:

| File | Description |
|------|-------------|
| `dsa/patterns/NN-<slug>.md` | Pattern doc with sub-patterns + pseudocode templates |
| `dsa/problems/NNN-<slug>.md` | One note per problem |
| `dsa/plan.md` | Task queue (one category active) |
| `dsa/progress.txt` | Append-only log |

See `ralph-dsa/spec.md` for required sections.

## Scripts

| Script | Purpose |
|--------|---------|
| `scaffold.sh <slug>` | Build `dsa/plan.md` for one category |
| `once.sh <slug>` | One Cursor Agent iteration |
| `loop.sh <slug> [max]` | Repeat until `<promise>COMPLETE</promise>` |
| `validate.sh <slug>` | Structural checks for category |
| `scripts/category_data.py` | Parse `neetcode-150-list.md` |

## Agent env

- `CURSOR_MODEL` — optional model slug
- `CURSOR_AGENT_TIMEOUT_SEC` — default `2700` (45m)
- `CURSOR_AGENT_OUTPUT_FORMAT` — default `stream-json`

## Logs

`ralph-dsa/.logs/<category-slug>-iter-*.log`

## Notes

- One plan item per iteration (pattern, then each problem, then validate)
- Problem notes use **pseudocode only** — see `dsa/problems/_template.md`
- Generated notes default to `**Status:** review` — update after you solve on LC
- `03-sliding-window.md` already exists as a manual example; Ralph will overwrite if re-run
