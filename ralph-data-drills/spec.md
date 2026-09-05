# Data Drills Generator — Spec

Generates SQL and statistics interview drills under `data-drills/` — **one group at a time**.

## Scope per run

Each Ralph session completes **one group block**:

1. One problem file per problem in that group (`problems.json`, filtered by `group`)
2. Group validation

A run never touches a second group. `data-drills/plan.md` holds the queue for the
active group only.

## Output artifacts

| Artifact | Path | Required |
|----------|------|----------|
| SQL problem | `data-drills/sql/<id>-<slug>.md` | Schema, Question, Hints, Solution, Expected Result, Common Wrong Answer, Why It Is Wrong |
| Stats problem | `data-drills/stats/<id>-<slug>.md` | Question, Hints, Worked Solution, Answer (+ Simulation iff `mc`) |
| Plan | `data-drills/plan.md` | Queue for current group only |
| Progress log | `data-drills/progress.txt` | Append-only run log |
| Status tracker | `data-drills/progress.md` | Per-problem status + **Problem index** table |
| Generator README | `ralph-data-drills/README.md` | How to run scaffold / once / loop / validate |
| Corpus README | `data-drills/README.md` | How to study the corpus |

`progress.txt` and `progress.md` are two different files and both are correct:
`progress.txt` is the flat append-only run log, `progress.md` is the status
tracker that holds the index table. Never write a table row into `progress.txt`.

## Problem sources

`ralph-data-drills/problems.json` is a JSON array. Each object carries
`id`, `family`, `group`, `title`, `slug`, `file`, `difficulty`, `topics`, `focus`
— plus, for SQL, optional `dialect` and (whenever `dialect` is present and not
`sqlite`) a required `skip_exec_reason`; and, for stats, `mc` and — iff `mc` is
true — `mc_tolerance` and `mc_tolerance_kind` (`"abs"` | `"rel"`).

`focus` is **metadata only**: one sentence saying what the problem must drill. It
never contains the schema, the query, the answer or the solution.

## Family = sql — required sections and blocks

Sections, in this order:

```
## Schema
## Question
## Hints
## Solution
## Expected Result
## Common Wrong Answer
## Why It Is Wrong
```

Fenced blocks (info string form `<lang> id=<name>`, matched by
````^```[a-z]+ id=([a-z_]+)\s*$````):

| Block | Content |
|-------|---------|
| ````` ```sql id=schema ````` | CREATE TABLE + INSERT seed data. Runnable start-to-finish. |
| ````` ```sql id=solution ````` | The reference query. Exactly ONE statement. |
| ````` ```csv id=expected ````` | Header row of column names, then the expected rows. CSV. |
| ````` ```sql id=wrong ````` | The common wrong-answer query. Exactly ONE statement. Must RUN but produce a DIFFERENT result than `id=expected` — that is asserted. |

## Family = stats — required sections and blocks

Sections, in this order:

```
## Question
## Hints
## Worked Solution
## Answer
## Simulation      (iff problems.json "mc" is true)
```

| Block | Content |
|-------|---------|
| ````` ```text id=answer ````` | The analytic answer as a single bare number (no units, no prose). |
| ````` ```python id=simulation ````` | Required iff `mc` is true. STDLIB ONLY (random, math, statistics, itertools, collections, fractions). numpy/scipy/pandas are FORBIDDEN and `validate.sh` rejects them. Must seed deterministically (`random.seed(...)`). Must print the empirical estimate as a bare float on the LAST stdout line. Must finish well under 20 s. |

## Both families

- `## Hints` must contain a hint **ladder** of ≥ 3 ordered list items, increasing
  in specificity — first a nudge, last nearly giving it away.
- No unfilled `<!-- ... -->` template placeholders may remain in a generated file.
- Header field block mirrors the DSA problem note: Title, Family, Group,
  Difficulty, Topics, Status, Generated.

## Group slugs

| # | Slug | Covers |
|---|------|--------|
| 1 | `sql-01-window-functions` | ROW_NUMBER/RANK/DENSE_RANK, LAG/LEAD, running totals, moving averages |
| 2 | `sql-02-joins-and-nulls` | self-joins, anti-joins, NOT EXISTS vs NOT IN NULL traps, join fan-out bugs |
| 3 | `sql-03-aggregation-grouping` | GROUP BY + HAVING, pivoting, median/percentiles without a builtin |
| 4 | `sql-04-ctes-and-recursion` | CTEs, recursive CTEs, gaps-and-islands |
| 5 | `sql-05-time-and-cohorts` | date bucketing, cohort/retention, funnel conversion, sessionization |
| 6 | `sql-06-modeling-and-performance` | top-N per group, deduplication, slowly changing dimensions, query-plan/index reasoning |
| 7 | `stats-01-probability-puzzles` | conditional probability, Bayes, false-positive medical test, Monty Hall |
| 8 | `stats-02-expectation-and-counting` | expected value, variance, birthday, coupon collector, order statistics |
| 9 | `stats-03-markov-and-processes` | Markov chains, expected hitting time |
| 10 | `stats-04-distributions-and-estimation` | distribution choice, MLE by hand, confidence intervals |
| 11 | `stats-05-inference-and-testing` | t vs chi-square vs Mann-Whitney selection, p-value traps, power, sample size, A/B sizing |
| 12 | `stats-06-bias-and-reasoning` | Simpson's paradox, regression to the mean, survivorship/selection bias, Fermi estimation |

## Quality rules

- **Schemas are self-contained.** A reader must be able to paste `id=schema`
  into a fresh `sqlite3` session and have it work, with no prior state.
- **Seed data is small but adversarial.** A handful of rows, chosen so the edge
  case being taught actually fires — NULLs when the lesson is about NULLs, ties
  when the lesson is about ties.
- **Solutions are deterministic.** One statement, explicit `ORDER BY`, because
  row order is compared as-is.
- **The wrong answer is a real mistake**, not a strawman or a syntax error.
- **Worked solutions show reasoning**, not just the result — the reader must be
  able to point at the line they disagree with.
- **The answer is a bare number.** Exact fractions belong in the worked solution;
  `id=answer` holds only the float.
- **Simulations are stdlib-only, seeded, and fast.**
- **Synthesize** — do not paste problem statements or editorials verbatim from
  LeetCode, StrataScratch, Glassdoor or a textbook.
- **Target SQLite** unless `problems.json` marks a `dialect`; a non-SQLite
  dialect requires a `skip_exec_reason` naming the construct SQLite cannot run.

## Enforcement — these gates are binding

`validate.sh` exit codes are honoured by `once.sh` and `loop.sh`. There is no
`|| true` on any validate invocation. A failing validation is never accepted, a
`COMPLETE` promise is not believed unless validation passes, and a rejected item
is regenerated with the exact `FAIL:` lines fed back into the next attempt. After
`RALPH_MAX_ATTEMPTS` failed attempts the run stops with exit 3 rather than
accepting unverified content.

A `COMPLETE` promise is checked against the corpus itself, not just against the
files in it. A per-file validator iterates over what exists, so on an empty
corpus it checks nothing and reports a clean pass — right for a mid-run sweep,
and a lie for the final gate. `ralph_require_complete` requires that the run
actually produced something before COMPLETE is accepted.

**What makes this generator different from the others: validation does not merely
check that sections exist — it EXECUTES the content.**

- Every SQLite-dialect SQL problem is run for real. `validate.sh` opens an
  in-memory SQLite database, executes `id=schema` as a script, executes
  `id=solution`, and compares the returned rows against the parsed `id=expected`
  CSV — column count and header names must match, numeric cells are compared
  with tolerance `1e-6`, everything else as strings, and row order is compared
  as-is. Then it executes `id=wrong` and asserts its result **differs** from
  expected. A "common wrong answer" that quietly returns the right rows is not a
  teaching example, and it is rejected.
- A non-SQLite dialect is not silently waved through. The runner emits an
  explicit `SKIP-EXEC <id> (dialect=<d>): <skip_exec_reason>` line and counts it
  in the summary; a missing or empty `skip_exec_reason` is a FAIL.
- Every Monte Carlo statistics problem is run for real. The simulation is
  screened for forbidden imports (numpy, scipy, pandas → FAIL), executed with
  `python3` under a 20 s timeout, and its last stdout line is parsed as a float.
  That empirical estimate must land within the declared tolerance of the
  analytic number in `id=answer` — `|empirical − analytic| ≤ mc_tolerance` for
  kind `abs`, or `≤ mc_tolerance × |analytic|` for kind `rel`. A simulation that
  crashes, times out, or prints no float is a FAIL. When `mc` is false,
  `id=answer` must still parse as a float.

This is the gate that catches a confidently-wrong probability answer, which is
the dominant failure mode in generated statistics content. A plausible-sounding
derivation with a subtly wrong conditioning step reads fine and reviews fine; it
does not survive ten million trials of the thing it claims to describe. The same
applies to SQL: a query that "obviously" handles the NULL case either returns
the expected rows or it does not. **A claim can no longer merely look plausible —
it has to survive being run.**

`validate.sh` exits 0 only if there are zero FAILs, prints `FAIL: ...` lines to
stderr (`ralph_validate` greps `^\s*FAIL[: ]`), and prints a summary with counts
of OK / SKIP / SKIP-EXEC / FAIL. A problem whose `.md` does not yet exist is a
SKIP, not a FAIL.

A second, independent fact-check agent then reads the finished file — and only
that file — looking for wrong formulas, wrong mechanism descriptions and false
claims. Its PASS is required too. Execution proves the numbers are consistent;
the fact-check agent catches the case where the whole framing is wrong.
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

## Environment

| Var | Default | Effect |
|---|---|---|
| `RALPH_DD_OUT` | `<repo>/data-drills` | Where drills are written **and** read. Honoured by `scaffold.sh`, `once.sh`, `loop.sh` and `validate.sh` — it used to be read only by the validator, so setting it pointed the checker at a directory the generator never wrote to. |
| `RALPH_DD_PROBLEMS` | `ralph-data-drills/problems.json` | The drill queue. Same story: validator-only before. |
| `RALPH_DD_MEM_MB` | 2048 | RSS cap for the Monte Carlo sandbox |
| `RALPH_LOOP_SLEEP` | 5 | Seconds `loop.sh` pauses between iterations |
| `RALPH_MAX_STALLS` | 3 | Consecutive no-output iterations before the loop stops |
| `RALPH_MAX_ATTEMPTS` | 3 | Rejected `COMPLETE` promises before giving up (budget survives across `once.sh` processes) |
| `RALPH_SKIP_FACTCHECK` | 0 | `1` skips the adversarial pass |
