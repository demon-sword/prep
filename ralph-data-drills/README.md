# Ralph — Data Drills Generator

Headless agent loop that generates SQL and statistics interview drills under
`data-drills/` — **one group at a time**.

What makes this generator different: `validate.sh` does not just check structure,
it **executes the content**. SQL reference queries are run against the problem's
own schema in an in-memory SQLite database and diffed against the stated expected
output; Monte Carlo simulations are run and checked against the analytic answer.
See `spec.md` → *Enforcement*.

## Quick start (group 1)

```bash
# 1. Queue the group (one plan item per problem + validate)
./ralph-data-drills/scaffold.sh sql-01-window-functions

# 2. Single agent iteration
./ralph-data-drills/once.sh sql-01-window-functions

# 3. Loop until the group is complete
./ralph-data-drills/loop.sh sql-01-window-functions 15

# 4. Validate manually (runs the queries and the simulations)
bash ralph-data-drills/validate.sh sql-01-window-functions
```

## Next group

When a group passes validate:

```bash
./ralph-data-drills/scaffold.sh sql-02-joins-and-nulls
./ralph-data-drills/loop.sh sql-02-joins-and-nulls 15
```

The previous group is recorded under **Groups completed** in `data-drills/plan.md`.

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

## Scripts

| Script | Purpose |
|--------|---------|
| `scaffold.sh <group>` | Build `data-drills/plan.md` for one group |
| `once.sh <group>` | One agent iteration (validate + fact-check gated) |
| `loop.sh <group> [max]` | Repeat until `<promise>COMPLETE</promise>` |
| `validate.sh <group>` | Structural checks **plus** execution of every SQL and simulation in the group |

`once.sh` and `loop.sh` take `--agent cursor|claude` and `--model <slug>`,
same flag parsing as `ralph-dsa`.

## What each run produces

| File | Description |
|------|-------------|
| `data-drills/sql/<id>-<slug>.md` | One SQL drill (schema, question, hints, solution, expected CSV, wrong answer) |
| `data-drills/stats/<id>-<slug>.md` | One stats drill (question, hints, worked solution, answer, optional simulation) |
| `data-drills/plan.md` | Task queue (one group active) |
| `data-drills/progress.txt` | Append-only run log |
| `data-drills/progress.md` | Status tracker + problem index |

See `ralph-data-drills/spec.md` for the required sections and fenced-block ids.

## Env (from `ralph-common.sh`)

| Var | Default | Effect |
|-----|---------|--------|
| `RALPH_MAX_ATTEMPTS` | `3` | Regeneration attempts per plan item before giving up |
| `RALPH_SKIP_FACTCHECK` | `0` | Set `1` to skip the adversarial fact-check pass (e.g. offline reruns) |
| `RALPH_FACTCHECK_TIMEOUT` | `900` | Seconds before the fact-check agent is killed |

Agent-level knobs (`CURSOR_MODEL`, `CURSOR_AGENT_TIMEOUT_SEC`,
`CURSOR_AGENT_OUTPUT_FORMAT`) behave as in `ralph-dsa`.

## Exit codes

| Code | Meaning |
|------|---------|
| `0` | Complete **and** verified — validate passed and the fact-check passed |
| `2` | Not complete — the agent did not emit `COMPLETE`, or validate rejected it and attempts remain |
| `3` | Gave up — `RALPH_MAX_ATTEMPTS` exhausted; the `FAIL:` lines are printed |
| `124` | Timeout |

## Logs

`ralph-data-drills/.logs/<group-slug>-iter-*.log`

## Notes

- One plan item per iteration (each problem, then validate).
- `problems.json` `focus` is metadata only — it never contains the schema, query,
  answer or solution.
- A problem whose `.md` does not exist yet is a **SKIP**, not a FAIL.
- A non-SQLite `dialect` is never silently skipped: validate prints
  `SKIP-EXEC <id> (dialect=<d>): <skip_exec_reason>` and counts it in the summary.
- Generated files default to `**Status:** review` — update after you solve them.

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
