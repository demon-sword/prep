# <!-- Problem Title -->

**Title:** <!-- human title, same as problems.json "title" -->
**Family:** `sql`
**Group:** <!-- one of the 6 sql-NN-* group slugs -->
**Difficulty:** `easy` | `medium` | `hard`
**Topics:** <!-- comma-separated, >=1, e.g. window functions, LAG -->
**Status:** `todo` | `hint` | `solo` | `review` | `mastered`
**Generated:** <!-- ralph-data-drills or — -->

---

## Schema

<!--
Self-contained and runnable start to finish: CREATE TABLE statements followed by
INSERT seed data. Keep it small (a handful of rows per table) but rich enough to
actually exercise the edge case being taught — if the problem is about NULLs,
seed NULLs; if it is about ties, seed a tie. SQLite-compatible unless
problems.json marks a "dialect".
-->

```sql id=schema
```

---

## Question

<!--
The prompt as an interviewer would ask it. State exactly which columns must come
back, what they are named, and the required ORDER BY — the validator compares
column names and row order.
-->

---

## Hints

<!--
Ordered hint LADDER, >= 3 items, each strictly more specific than the last.
1 = a nudge (which family of tool). 2 = names the construct.
3 = nearly gives it away (the shape of the query, minus the final text).
-->

1.
2.
3.

---

## Solution

<!--
The reference query. EXACTLY ONE statement. Must ORDER BY deterministically —
the validator runs this against id=schema in an in-memory SQLite database and
compares the rows, in order, against id=expected.
-->

```sql id=solution
```

---

## Expected Result

<!--
What the solution REALLY returns. Header row of column names first, then one
line per result row, CSV. Mentally execute the query against the seed data —
this is asserted by execution, not by eye.
-->

```csv id=expected
```

---

## Common Wrong Answer

<!--
A plausible mistake a candidate actually makes — not a syntax error and not a
strawman. EXACTLY ONE statement. It must RUN successfully and must return a
result DIFFERENT from id=expected; both are asserted.
-->

```sql id=wrong
```

---

## Why It Is Wrong

<!--
Name the mechanism, not just the symptom: which row(s) differ, and what the
engine actually did that produced them.
-->
