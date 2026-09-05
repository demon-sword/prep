# <!-- Problem Title -->

**Title:** <!-- human title, same as problems.json "title" -->
**Family:** `stats`
**Group:** <!-- one of the 6 stats-NN-* group slugs -->
**Difficulty:** `easy` | `medium` | `hard`
**Topics:** <!-- comma-separated, >=1, e.g. conditional probability, Bayes -->
**Status:** `todo` | `hint` | `solo` | `review` | `mastered`
**Generated:** <!-- ralph-data-drills or — -->

---

## Question

<!--
The puzzle as an interviewer would ask it. State every assumption the answer
depends on (independence, with/without replacement, prior, units) so the answer
is unambiguous — one number, not a range.
-->

---

## Hints

<!--
Ordered hint LADDER, >= 3 items, each strictly more specific than the last.
1 = a nudge (which frame: conditioning, symmetry, linearity of expectation).
2 = names the tool and the events/random variables to define.
3 = nearly gives it away (the equation to solve, minus the arithmetic).
-->

1.
2.
3.

---

## Worked Solution

<!--
Show the REASONING STEPS, not just the answer: define the events or random
variables, state the identity being used, substitute the numbers, then simplify.
A reader who disagrees with the answer must be able to point at the exact line
they disagree with. Give the exact value (fraction) alongside the decimal.
-->

---

## Answer

<!--
A single bare number. No units, no prose, no fraction, no "≈" — just the decimal
the validator will parse as a float. Round consistently with the tolerance.
-->

```text id=answer
```

---

## Simulation

<!--
REQUIRED iff problems.json sets "mc": true for this problem — otherwise delete
this whole section.

Stdlib only: random, math, statistics, itertools, collections, fractions.
numpy / scipy / pandas are rejected outright. Seed deterministically with
random.seed(...). Print the empirical estimate as a bare float on the LAST
stdout line. Must finish well under 20 s.

The validator EXECUTES this and compares the printed estimate against the
number in id=answer using mc_tolerance / mc_tolerance_kind. If they disagree,
re-derive the analytic answer — do not widen the tolerance and do not rig the
simulation to agree with a wrong answer.
-->

```python id=simulation
```
