# Ralph ML Coding — Spec

Generates **runnable "implement it from scratch" ML interview problems** under `ml-coding/` — one problem per file — for the ML/DS coding round.

## Why this track exists

The repo contains exactly **one** ML coding snippet (cosine similarity in NumPy). There is no way to rehearse "implement k-means from scratch", which is a standard senior ML/DS round. The concept tracks explain mechanisms well, but explanation is not rehearsal — and all 36 `machine_learning/` pages contain zero `<pre>` code blocks.

This track is **problem-based, not exposition-based**, and it is modelled on `ralph-dsa`: statement → hints → solution → complexity. It diverges from `ralph-dsa` on exactly one rule, deliberately.

## The divergence from ralph-dsa

`ralph-dsa/spec.md:51` mandates **"Pseudocode only — no language-specific syntax"**. That is right for DSA, where the point is the pattern and the candidate translates to their own language.

**This track inverts that rule.** The point here is runnable code:

- Solutions are **real Python**. NumPy is allowed and expected.
- **scikit-learn must NOT be used for the thing being implemented.** It may appear *only* inside the self-test, as a cross-check oracle (compare your k-means inertia against `sklearn.cluster.KMeans`). The validator rejects any `import sklearn` inside a solution block.
- Every solution ships an **executable self-test**, and the validator runs it.

## Output artifact per problem

| Attribute | Requirement |
|-----------|-------------|
| Path | `ml-coding/<id>.md` |
| Format | Markdown, matching `dsa/problems/` voice |
| Solution | Real Python (NumPy allowed, no sklearn) |
| Self-test | Assert-based, executed by `validate.sh` |

## Required sections (in order)

1. **`# <Title> — <Difficulty> — <Group>`** — the header line, `ralph-dsa` style
2. **`## Problem`** — the statement, plus a concrete **input/output contract**: exact function signature, array shapes, dtypes, what is returned, what edge cases must hold. `problems.json` gives the `io_contract` — the solution must define that function by that name.
3. **`## Hints`** — a progressive ladder of **at least 3** hints, each hidden in a `<details>` block so the reader can rehearse before peeking, and all of them **before** the solution:
   - *Nudge* — one question that redirects attention
   - *Approach* — the shape of the method, no code
   - *Key insight* — the one thing that makes it work
4. **`## Solution`** — one ```python block: a complete, runnable reference implementation. Imports at the top. No sklearn.
5. **`## Self-test`** — one ```python block that imports nothing from the solution (it is concatenated after it) and **asserts** the solution is correct against a real oracle. See below.
6. **`## Complexity`** — time and space, stated with `O(...)`, plus what dominates in practice.
7. **`## Follow-ups`** — the questions an interviewer actually asks *after* you finish. From the entry's `followups`, expanded with a sentence of answer each.

## The self-test — what counts as an oracle

The test must prove correctness against something independent, not restate the implementation. Good oracles:

- **Cross-check against scikit-learn** — your k-means inertia within a tolerance of `sklearn.cluster.KMeans`, your ROC-AUC against `roc_auc_score`. sklearn is allowed *here only*.
- **Finite-difference gradient check** — analytic gradient vs `(f(x+h) − f(x−h)) / 2h`. The right oracle for every backprop problem.
- **Hand-computed known-good values** — a 3×3 example worked out by hand.
- **Invariants** — softmax rows sum to 1, PCA components orthonormal, attention weights sum to 1, a permutation is a permutation.

Bad oracles: asserting the output equals what the function returned, asserting only the shape, or printing without asserting.

Seed every random draw. A test that fails one run in ten is worse than no test.

## Validation actually runs the code

This is the defining feature of the track and no other generator in this repo does it. `validate.sh`:

1. finds a Python with numpy (`$RALPH_ML_PYTHON`, then `./venv/bin/python3`, then PATH);
2. extracts the ```python block from `## Solution` and from `## Self-test`;
3. concatenates them into a temp file and **executes it under containment** (`ralph-lib/ralph_sandbox.py`) with a timeout;
4. **fails the problem if the process exits non-zero**, times out, or trips the memory cap.

Step 3 is the one place in this repo where running untrusted code is the *point*, so it is the most contained: an isolated interpreter (`-I`), an allowlisted environment so the code cannot read this shell's credentials, no network, no filesystem writes outside its own sandbox directory, a resident-memory cap, and a timeout that kills the whole process **group** — a detached grandchild does not outlive the run. If `ralph-lib/ralph_sandbox.py` is missing the validator exits `2` rather than falling back to an uncontained run.

It also checks: required sections; ≥3 hidden hints, positioned before the solution; the `io_contract` function is actually defined; no sklearn in the solution; a real `assert` in the self-test; an `O(...)` bound; ≥2 follow-ups; depth-scaled prose floor (code excluded); no placeholders; compound-title coverage in the code.

`validate.sh` exit codes: `0` pass, `1` content failure, **`2` no interpreter with numpy** — an environment problem, which `once.sh` treats as fatal rather than burning retries on it, re-reporting it as `4`. `once.sh`'s own `2` already means "one item done, more remain", so the two must not share a number.

## Per-problem depth and difficulty

`problems.json` carries both:

- **`depth`** — sets the **prose** floor (explanation, not code): `intro` 200 / `core` 350 / `advanced` 500 words. Code blocks are excluded from the count.
- **`difficulty`** — `easy` | `medium` | `hard`, about coding effort. Goes in the header line.

## Quality rules

- **Runnable, not illustrative.** If it does not execute, it does not ship.
- **Vectorise where an interviewer would**, but prefer clarity over cleverness — a reader is rehearsing to write this under pressure on a whiteboard or in a shared editor.
- **Handle the edge case the problem names.** Empty cluster in k-means, a class absent from a fold, a zero vector in cosine similarity, division by zero in normalisation.
- **Seed everything random.**
- **Comment the line that matters** — the max-subtraction in softmax, the `ddof` in a variance, the `+1` in Laplace smoothing.
- **State complexity honestly**, including the constant that bites (an O(n²) distance matrix is fine at n=1000 and fatal at n=10⁶).

## Enforcement — these gates are binding

`validate.sh` exit codes are honoured by `once.sh` and `loop.sh`. A failing validation is never accepted, a `COMPLETE` promise is not believed unless validation passes, and a rejected item is regenerated with the exact `FAIL:` lines fed back into the next attempt. After 3 failed attempts the run stops with an error rather than accepting unverified content.

A `COMPLETE` promise is checked against the corpus itself, not just against the
files in it. A per-file validator iterates over what exists, so on an empty or
half-finished corpus it checks nothing and reports a clean pass — right for a
mid-run sweep, and a lie for the final gate. `ralph_require_complete` closes it:
every item in `plan.md`, and every item in the queue JSON in case the plan was
never re-scaffolded, must have produced a file. The same reasoning applies
per-item: an item the agent never wrote is SKIPped and passes, so `once.sh`
confirms the file exists before believing the validator.

Two gaps that a per-file validator cannot see are closed outside it. An item that was never written is SKIPped and reported as a pass, so `once.sh` checks that the iteration's file actually exists before believing gate 1. And a corpus that was never generated has nothing to fail, so a `COMPLETE` promise additionally requires that every problem in `plan.md` — and every problem in `problems.json`, in case the plan was never re-scaffolded — produced a file.

A second, independent fact-check agent then reads the finished file — and only that file — hunting incorrect formulas, wrong mechanisms and false claims. Its PASS is required too. Execution proves the code *runs and passes its own test*; it does not prove the test is a meaningful oracle, and that gap is exactly what the fact-check pass covers.

`../validate-corpus.sh ml-coding` flags near-duplicate problems.

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

## Progress log

```
2026-08-30 | 15-kmeans | Implement K-Means with K-Means++ Initialization | OK
```
