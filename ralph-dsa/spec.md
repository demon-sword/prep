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
| Status tracker | `dsa/progress.md` | Per-problem status + **Problem notes index** table |

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

## Enforcement — these gates are binding

`validate.sh` exit codes are honoured by `once.sh` and `loop.sh`. A failing
validation is never accepted, a `COMPLETE` promise is not believed unless
validation passes, and a rejected item is regenerated with the exact `FAIL:`
lines fed back into the next attempt. After 3 failed attempts the run stops
with an error rather than accepting unverified content.

A `COMPLETE` promise is checked against the corpus itself, not just against the
files in it. A per-file validator iterates over what exists, so on an empty
corpus it checks nothing and reports a clean pass — right for a mid-run sweep,
and a lie for the final gate. `ralph_require_complete` requires that the run
actually produced something before COMPLETE is accepted.

A second, independent fact-check agent then reads the finished file — and only
that file — looking for incorrect formulas, wrong mechanisms and false claims.
Its PASS is required too.

`../validate-corpus.sh` runs across a finished corpus and flags near-duplicate
explanations between files (copied 5-grams, and same-topic redundancy).

`--final` (or `RALPH_CORPUS_FINAL=1`) additionally fails a track whose corpus is empty or short of its queue — the end-of-run form of the same question `ralph_require_complete` asks inside the loop.
### Loop safety

`loop.sh` used to dispatch on a handful of exit codes and let everything else
fall through to the next iteration, with nothing sleeping in between. Against an
agent binary that exits immediately that is 80 real invocations in nine seconds.
Three guards now bound the damage:

- **Any exit code that is not "one item done, more remain" stops the loop.**
  Previously `1` matched no branch at all.
- **Three consecutive iterations that write no new file stop the loop** with exit
  `5`. An agent that produces nothing looks exactly like one doing real work if
  you only read exit codes. `RALPH_MAX_STALLS` tunes it; the counter resets the
  moment a file appears.
- **`RALPH_LOOP_SLEEP`** (default 5s) pauses between iterations.

The rejection budget lives in `<generator>/.state/`, not in a shell variable,
because `loop.sh` starts a fresh `once.sh` process for every iteration — an
in-process counter reset each time, and a 3-strike cap silently became a
`MAX`-strike one. It is keyed by run, so a new run starts with a full budget and
a `once.sh` invoked by hand is never charged for a previous run's strikes.

