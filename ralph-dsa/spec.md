# DSA Notes Generator — Spec

Generates NeetCode 150 study notes under `dsa/` — **one category at a time**.

## Scope per run

Each Ralph session completes **one category block**:

1. Pattern doc for the category
2. One problem note per problem in that category
3. Category validation

## Output artifacts

| Artifact | Path | Required |
|----------|------|----------|
| Pattern doc | `dsa/patterns/NN-<slug>.md` | Recognition, Sub-patterns (≥2), Templates (pseudocode), Anti-patterns, NeetCode checklist, One-page summary |
| Problem note | `dsa/problems/NNN-<slug>.md` | Framing, Approach (invariant, steps, pseudocode skeleton), Tradeoffs, Pitfalls, Similar problems, One-liner |
| Plan | `dsa/plan.md` | Queue for current category only |
| Progress log | `dsa/progress.txt` | Append-only run log |

## Problem note format

Follow `dsa/problems/_template.md`:

1. **Framing** — trigger phrases, constraints, pattern name
2. **Approach** — invariant, numbered steps, **pseudocode skeleton** (language-agnostic)
3. **Tradeoffs** — brute force, why this pattern, when NOT to use it

Header fields:

- `**LC:**` — LeetCode URL from `neetcode-150-list.md`
- `**Status:**` — set to `review` for Ralph-generated notes
- `**Generated:**` — optional `ralph-dsa` marker

## Pattern doc format

Follow `dsa/patterns/_template.md` and `dsa/patterns/03-sliding-window.md` as reference.

Must include:

- Problem signals table
- ≥2 sub-patterns with When / Mechanism / Examples
- Pseudocode templates (not Python/Java)
- Anti-patterns table
- Checklist table of all problems in this category (#, name, difficulty, sub-pattern, status `generated`)

## Quality rules

- **Pseudocode only** in skeletons — no language-specific syntax
- **Synthesize** — do not paste NeetCode transcripts or LeetCode editorials verbatim
- **Cross-link** — problem notes reference sibling problems in the same category
- **Accurate complexity** — state time/space for the optimal approach
- Pattern doc is written **before** problem notes in the queue (agent may read it when writing problems)

## Reference docs

| Doc | Use |
|-----|-----|
| `dsa/neetcode-150-list.md` | Problem #, name, difficulty, LC link |
| `dsa/patterns/recognition-guide.md` | Pattern vocabulary |
| `dsa/README.md` | Study conventions |

## Category slugs

| Cat | Slug |
|-----|------|
| 1 | `01-arrays-hashing` |
| 2 | `02-two-pointers` |
| 3 | `03-sliding-window` |
| 4 | `04-stack` |
| 5 | `05-binary-search` |
| 6 | `06-linked-list` |
| 7 | `07-trees` |
| 8 | `08-tries` |
| 9 | `09-heap` |
| 10 | `10-backtracking` |
| 11 | `11-graphs` |
| 12 | `12-advanced-graphs` |
| 13 | `13-1d-dp` |
| 14 | `14-2d-dp` |
| 15 | `15-greedy` |
| 16 | `16-intervals` |
| 17 | `17-math-geometry` |
| 18 | `18-bit-manipulation` |
