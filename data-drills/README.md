# Data Drills (SQL + Statistics)

Interview drills for the analytical half of a data / ML / backend loop. Each file
is **one problem you attempt cold**, then check. They are practice reps, not
reference material — read the answer last, always.

## The two families

| Family | Folder | A file gives you |
|--------|--------|------------------|
| **SQL** | `sql/` | A runnable schema with seed data, a question, a hint ladder, a reference query, the exact expected result, and the wrong query people actually write — with why it is wrong |
| **Statistics** | `stats/` | A probability / inference question, a hint ladder, a worked derivation, the answer as a bare number, and (often) a Monte Carlo simulation you can run |

Groups:

| SQL | Statistics |
|-----|------------|
| `sql-01-window-functions` | `stats-01-probability-puzzles` |
| `sql-02-joins-and-nulls` | `stats-02-expectation-and-counting` |
| `sql-03-aggregation-grouping` | `stats-03-markov-and-processes` |
| `sql-04-ctes-and-recursion` | `stats-04-distributions-and-estimation` |
| `sql-05-time-and-cohorts` | `stats-05-inference-and-testing` |
| `sql-06-modeling-and-performance` | `stats-06-bias-and-reasoning` |

## How to practise without spoiling yourself

Every file is ordered so the spoilers come last, but they are all in one
scrollback — so use the ladder deliberately.

1. **Read only `## Question`** (and `## Schema` for SQL — the schema is part of
   the question, not the answer). Set a timer: 8 minutes for easy, 15 for medium,
   25 for hard.
2. **Write your answer down first.** For SQL, type the query into `sqlite3`. For
   stats, commit to a number before you look at anything.
3. **Stuck? Take exactly ONE hint.** `## Hints` is a ladder: hint 1 is a nudge
   toward the right family of tool, hint 2 names the construct, hint 3 nearly
   gives it away. Take them one at a time and go back to the timer after each.
   Jumping straight to hint 3 costs you the rep.
4. **Then check.** SQL: run your query and diff it against `## Expected Result`
   before reading `## Solution`. Stats: compare your number to `## Answer` before
   reading `## Worked Solution`.
5. **If you were wrong, read `## Why It Is Wrong` / `## Worked Solution` and
   re-solve tomorrow from a blank file.** Getting the right answer for the wrong
   reason is the thing these drills are built to expose.
6. **Update `**Status:**`** in the file header (`todo` → `hint` → `solo` →
   `review` → `mastered`) and the row in `progress.md`.

For SQL, a low-tech way to keep yourself honest: open the file, copy the schema,
and close it. Work from the schema alone in your terminal.

## Running a SQL problem yourself

Every `sql/` file's schema is self-contained — `CREATE TABLE` plus `INSERT` seed
data, no prior state needed. Copy the `````` ```sql id=schema `````` block into a scratch
file and load it:

```bash
# paste the id=schema block into schema.sql, then:
sqlite3 :memory: ".read schema.sql" "SELECT * FROM your_table;"
```

Or interactively, which is nicer for iterating on a query:

```bash
sqlite3
sqlite> .mode column
sqlite> .headers on
sqlite> .read schema.sql
sqlite> -- now type your attempt
```

To diff your attempt against the expected CSV directly:

```bash
sqlite3 -csv -header :memory: ".read schema.sql" "$(cat attempt.sql)" > mine.csv
diff mine.csv expected.csv
```

Row **order** matters — the reference solutions all `ORDER BY` deterministically,
and so should yours. Unless a file's header says otherwise, the SQL is
SQLite-compatible; a file that targets another dialect says so and explains which
construct SQLite cannot run.

Reading the `## Common Wrong Answer` query is worth as much as the solution. Run
it too, and look at exactly which rows move.

## Running a statistics simulation

Files whose problem ships a Monte Carlo check have a `## Simulation` section
containing a `python3` script. It is **stdlib only** (no numpy, scipy or pandas),
seeded, and finishes in a few seconds:

```bash
# paste the id=simulation block into sim.py, then:
python3 sim.py
```

The last line it prints is the empirical estimate. Compare it to `## Answer`.

Use the simulation as a **check on your own reasoning**, not as the source of the
answer: derive first, then simulate. And when you get a number you cannot square
with the simulation, the simulation is usually right and your conditioning is
usually wrong — that disagreement is the most valuable thing in the file.

Every simulation in this corpus has been executed and agrees with the stated
analytic answer inside a declared tolerance; every SQL solution has been run
against its own schema and matches its expected CSV. If you find one that does
not, that is a real bug — fix the file.

## Folder layout

```
data-drills/
├── README.md          # this file
├── plan.md            # generator queue (one group active)
├── progress.md        # per-problem status + problem index
├── progress.txt       # append-only run log
├── sql/
│   ├── _template.md   # blank skeleton — copy when adding a problem by hand
│   └── …              # e.g. sql-001-running-total.md
└── stats/
    ├── _template.md
    └── …              # e.g. stat-001-false-positive-rate.md
```

## Status legend

| Status | Meaning |
|--------|---------|
| `todo` | Not attempted |
| `hint` | Needed the hint ladder |
| `solo` | Solved unaided |
| `review` | Solved but needs spaced repetition (generated files start here) |
| `mastered` | Can re-derive the query or the derivation cold |

Review on schedule: day 1 → day 3 → day 7 → day 14.

## Adding a problem by hand

Copy `sql/_template.md` or `stats/_template.md`, fill every section, and delete
every `<!-- ... -->` comment. The generator's checker rejects a file that still
has one, and so should you.
