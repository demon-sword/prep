# Ralph — Data Drills Generator

## Inputs (read every iteration)

| Doc | Path |
|-----|------|
| Spec | `ralph-data-drills/spec.md` |
| Plan | `data-drills/plan.md` |
| Problem list | `ralph-data-drills/problems.json` |
| Conventions | `data-drills/README.md` |
| SQL template | `data-drills/sql/_template.md` |
| Stats template | `data-drills/stats/_template.md` |

**Group:** {{GROUP}} ({{GROUP_NAME}})

## Rules

1. Read `data-drills/plan.md` — complete **exactly ONE** unchecked item from **Next** (first item only).
2. Read that problem's object in `ralph-data-drills/problems.json`. `focus` is metadata: it tells you what to drill. It is never the schema, query, answer or solution — you write those.
3. Copy the matching template (`data-drills/sql/_template.md` or `data-drills/stats/_template.md`) and fill **every** section. **No unfilled `<!-- ... -->` placeholders may remain** — the validator greps for them and fails the file.
4. Use **Task/subagent** when research helps (dialect semantics, a distribution's exact form, a standard result you want to confirm).
5. **One task per run** — do not start the next plan item.
6. Write the file to the exact `file` path from `problems.json`, set `**Status:** review` and `**Generated:** ralph-data-drills`, and fill Title / Family / Group / Difficulty / Topics from the same object.
7. After completing the task:
   - Check off the item in `plan.md` (move to Done, remove from Next)
   - Append one line to the run log `data-drills/progress.txt` with date + group + what you did
   - Add a row to the **Problem index** at the bottom of the status tracker `data-drills/progress.md` if missing

   These are two different files and both are correct: `progress.txt` is the flat
   append-only run log, `progress.md` is the status tracker that holds the index
   table. Do not write a table row into `progress.txt`.
8. Every problem, both families, needs a hint **ladder** under `## Hints`: **≥ 3 ordered list items, each strictly more specific than the last**. The first is a nudge — which family of tool to reach for. The last nearly gives it away — the shape of the query or the equation to solve, minus the final text or the arithmetic. Three restatements of the same hint is a FAIL in spirit even when it passes the count.
9. If **all** plan items are done and `bash ralph-data-drills/validate.sh {{GROUP}}` passes, output `<promise>COMPLETE</promise>`.

## Task-specific guidance

### family = sql — `data-drills/sql/<id>-<slug>.md`

Sections, in this order: `## Schema`, `## Question`, `## Hints`, `## Solution`,
`## Expected Result`, `## Common Wrong Answer`, `## Why It Is Wrong`.

**Schema** — `````` ```sql id=schema ``````

- Self-contained and runnable **start to finish**: `CREATE TABLE` statements
  followed by `INSERT` seed data, with no dependency on any prior state. The
  validator executes this block as a script into a fresh in-memory database.
- Keep it **small** — a handful of rows per table, few enough that a human can
  compute the expected output by hand.
- Keep it **rich enough to actually exercise the edge case being taught**. If the
  problem is about `NOT IN` and NULLs, the seed data must contain a NULL in the
  subquery column, or the trap never fires and the problem teaches nothing. If it
  is about ties in `RANK` vs `DENSE_RANK` vs `ROW_NUMBER`, seed an actual tie. If
  it is about join fan-out, seed the duplicate that fans out. Choose the rows so
  the wrong query and the right query genuinely disagree.
- Give columns realistic names and types; declare `PRIMARY KEY` where it is real.

**Solution** — `````` ```sql id=solution ``````

- **Exactly ONE statement.** A CTE chain is one statement; two semicolon-separated
  queries are not.
- **Must `ORDER BY` deterministically** — the validator compares row order as-is.
  If the natural ordering has ties, add a tie-breaker column so the order is
  total. "Any order is fine" is not an option here.
- Target **SQLite-compatible SQL** unless `problems.json` sets a `dialect` for
  this problem. If it does, write idiomatic SQL for that dialect and make sure
  `skip_exec_reason` in `problems.json` names the construct SQLite cannot run —
  the validator prints an explicit `SKIP-EXEC` line and a missing reason is a FAIL.

**Expected Result** — `````` ```csv id=expected ``````

- Header row of column names first, then one line per result row, CSV.
- It must be **what the query REALLY returns** against your own seed data.
  Mentally execute the query row by row before writing it down — and know that
  **the validator will run it for real**, compare column count and header names,
  compare numeric cells with tolerance `1e-6` and everything else as strings, and
  compare rows in order. A CSV that was written from what you meant the query to
  do rather than what it does is the most common way this family fails.

**Common Wrong Answer** — `````` ```sql id=wrong ``````

- A **plausible mistake a candidate actually makes** — `NOT IN` with a NULL,
  `WHERE` where `HAVING` was needed, `COUNT(*)` instead of `COUNT(col)`,
  `ROW_NUMBER` where `DENSE_RANK` was needed, a join that fans out and inflates a
  `SUM`. Not a strawman, not a typo, not a syntax error.
- **Exactly ONE statement**, and it must **execute successfully** — a query that
  errors out teaches nothing and is a FAIL.
- It must return a result **DIFFERENT** from `id=expected`. This is asserted by
  running it. If your "wrong" query happens to return the right rows on your seed
  data, the seed data is too tame — go back and add the row that separates them.

**Why It Is Wrong**

- Name the mechanism, not just the symptom: which rows differ, and what the engine
  actually did to produce them (`NULL` comparisons evaluating to unknown, the
  filter applying before aggregation, the duplicate multiplying the sum).

### family = stats — `data-drills/stats/<id>-<slug>.md`

Sections, in this order: `## Question`, `## Hints`, `## Worked Solution`,
`## Answer`, plus `## Simulation` **iff** `problems.json` sets `"mc": true`.

**Question**

- State every assumption the answer depends on — independence, with or without
  replacement, the prior, the units. The answer is one number, so the question
  must admit exactly one.

**Worked Solution**

- **Show the reasoning steps, not just the answer.** Define the events or random
  variables by name, state the identity you are using (Bayes, linearity of
  expectation, law of total expectation, first-step analysis), substitute the
  numbers, then simplify. A reader who disagrees with your result must be able to
  point at the exact line where they part ways.
- Give the exact value (a fraction, when there is one) alongside the decimal.

**Answer** — `````` ```text id=answer ``````

- **A single bare number.** No units, no prose, no fraction, no `≈`. The validator
  parses this block as a float. Round consistently with the tolerance.

**Simulation** — `````` ```python id=simulation ``````  (only when `"mc": true`)

- **Stdlib only**: `random`, `math`, `statistics`, `itertools`, `collections`,
  `fractions`. **`numpy`, `scipy` and `pandas` are rejected outright** — the
  validator screens the imports and FAILs on sight.
- **Seed deterministically** with `random.seed(...)` so the run reproduces.
- **Print the empirical estimate as a bare float on the LAST stdout line.**
  Anything else you print must come before it. No trailing units, no label.
- **Finish well under 20 seconds** — the validator kills it at 20 s and a timeout
  is a FAIL. Pick a trial count that comfortably beats the tolerance in
  `mc_tolerance` without running long; simulate the process, do not brute-force
  the whole sample space.

> **The simulation is EXECUTED and compared against your analytic answer.**
> The validator runs it, parses the last line as a float, and asserts
> `|empirical − analytic| ≤ mc_tolerance` (kind `abs`) or
> `≤ mc_tolerance × |analytic|` (kind `rel`). If the two disagree, the item is
> **rejected**. So: do not write an answer you cannot defend.
>
> And when they disagree, **the correct response is to re-derive the analytic
> result** — the simulation is usually right and the derivation usually has a
> conditioning bug. Do **not** widen `mc_tolerance`, do not change
> `mc_tolerance_kind` from `abs` to `rel` to buy slack, do not add a fudge factor
> to the simulation, and do not rewrite the simulation to model a different
> process that happens to agree with a wrong number. Fixing the thermometer to
> match the fever is the one failure this gate exists to catch, and doing it
> deliberately is worse than the original error. If after re-deriving you are
> genuinely convinced the analytic answer is right and the simulation is wrong,
> say so explicitly in `progress.txt` and fix the simulation's *model* — not its
> output.

## Fact-check gate (runs after you finish — you cannot bypass it)

Once you finish, a **separate agent** is given your finished file and nothing
else. It is told it did not write the file, and asked to find any incorrect
formula, wrong mechanism description, or false factual claim. Its verdict is
required before this item is accepted, and it does not see your reasoning — so a
claim that only looks right in context will be caught.

Write for that reviewer:

- Every formula must be correct as written, including normalisation terms,
  factorials and exponents. If you write Bayes, the denominator must be the full
  marginal, not just the likelihood of the observed branch.
- Every number must be real. Do not invent base rates, effect sizes, sample sizes
  or benchmark figures to make a sentence land. If a number is a modelling choice,
  say it is a modelling choice.
- Name the right test for the right data. Do not attribute a result, a paradox or
  a theorem to the wrong person or the wrong condition.
- Keep the prose consistent with the executable content. If `## Worked Solution`
  says the answer is 1/3, `id=answer` must not say `0.5`, and the simulation must
  not model a different game.
- Do not pad. A shorter section that is true beats a longer one that is not.

If this item comes back rejected, you will be shown the exact FAIL lines. Fix the
underlying fact — do not reword around it.

## Verification

After substantive edits:

```bash
bash ralph-data-drills/validate.sh {{GROUP}}
```

This runs your SQL against your own schema and your simulation against your own
answer. Run it yourself before claiming the item is done; do not wait for the
loop to tell you the query does not return what you said it returns.

Report failures in `data-drills/progress.txt` if blocked.

## Commit

One commit per plan item: `feat(data-drills): {{GROUP}} — <short description>`

Do not push unless asked.
