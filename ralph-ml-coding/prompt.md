# Ralph ML Coding — Agent Prompt

## Context files (read every iteration)

| Doc | Path |
|-----|------|
| Spec | `ralph-ml-coding/spec.md` |
| Plan | `ralph-ml-coding/plan.md` |
| Problem list | `ralph-ml-coding/problems.json` |
| Progress | `ralph-ml-coding/progress.txt` |
| Voice reference | `dsa/problems/003-two-sum.md` |

## Rules

1. Read `ralph-ml-coding/plan.md` — pick **exactly ONE** unchecked item from **Next** (the first unchecked item).
2. Read `ralph-ml-coding/problems.json` for the full definition — especially **`io_contract`** (the exact function signature you must define) and **`verify`** (the oracle your self-test must use).
3. Write the problem at `ml-coding/<id>.md`.
4. **Run your own code before you finish.** Write the solution and self-test to a scratch file and execute it with the same interpreter the validator uses. Do not hand in code you have not run.
5. Self-validate: `bash ralph-ml-coding/validate.sh <id>`.
6. Fix anything it reports, then re-check.
7. After passing:
   - Mark the item done in `ralph-ml-coding/plan.md` (`- [ ]` → `- [x]`)
   - Append one line to `ralph-ml-coding/progress.txt`
8. If ALL items are done, emit `<promise>COMPLETE</promise>`.

## One task per run — do not start the next plan item.

## This track is runnable code, not pseudocode

`ralph-dsa` mandates pseudocode with no language-specific syntax. **This track inverts that.** The reader is rehearsing to type a working implementation under interview pressure.

- Real **Python**. NumPy allowed and expected.
- **No scikit-learn in the solution** — you are implementing the thing sklearn does. sklearn may appear *only* in the self-test as a cross-check oracle. The validator rejects `import sklearn` inside a solution block.
- No `scipy` for the core computation either, unless the problem is explicitly about a scipy routine.

## File structure

```markdown
# <Title> — <Difficulty> — <Group>

**Contract:** `<io_contract from problems.json>`
**Generated:** ralph-ml-coding

---

## Problem
<statement, then the concrete input/output contract: shapes, dtypes, returns, edge cases>

## Hints
<details><summary>Nudge</summary>...</details>
<details><summary>Approach</summary>...</details>
<details><summary>Key insight</summary>...</details>

## Solution
```python
import numpy as np

def thing(...):
    ...
```

## Self-test
```python
import numpy as np
out = the_contract_function(...)          # CALL the contract's symbol
assert out.shape == (...), "message"      # assert on what it RETURNED
assert np.allclose(out, expected), "message"
print("ok")
```

## Complexity
| | |
|-|-|
| **Time** | O(n·d) — one pass over every row and feature |
| **Space** | O(n) — the index arrays, not a copy of the data |

## Follow-ups
- **Q?** — one-sentence answer.
```

### Problem section
State it the way an interviewer says it out loud, then pin the contract down: exact signature, array shapes, dtypes, what comes back, and which edge cases must hold (empty cluster, zero vector, a class missing from a fold, division by zero).

### Hints — at least 3, hidden, before the solution
Each in its own `<details>` block so the reader can rehearse before peeking. The ladder must actually escalate:
- **Nudge** — one question that redirects attention. No method named.
- **Approach** — the shape of the method, still no code.
- **Key insight** — the one thing that makes it work (the max-subtraction, the `+1`, the `ddof`).

### Self-test — must actually exercise the solution
The validator runs the self-test twice: once as written, and once with every
symbol from `io_contract` replaced by a stub that raises. **The second run must
fail.** A self-test that passes both never touched the solution — it was only
concatenated after it. So:
- Call every function or class the `io_contract` names, and assert on what it
  returns, not on inputs you constructed yourself.
- At least two asserts, and at least one that is not trivially true. `assert True`,
  `assert 1`, and a bare `assert out is not None` are rejected.
- Use the entry's `verify` field as the oracle it describes.

### Complexity
State a real bound. `O(?)` is rejected — it is the unfilled placeholder, and the
table above is an example to replace, not a shape to copy.

### Hints
Each `<details>` needs a real body, not an empty tag. Empty `<details></details>`
blocks are rejected.

### Solution
Complete and runnable, imports at the top. Vectorise where an interviewer would, but prefer clarity over cleverness. **Comment the line that matters** — not the obvious ones.

### Self-test — it must prove something
Concatenated directly after your solution and executed, so do not re-import it. Assert against a real oracle:
- cross-check against scikit-learn within a tolerance (allowed here only)
- finite-difference gradient check — the right oracle for every backprop problem
- hand-computed known-good values
- invariants (softmax rows sum to 1, PCA components orthonormal, attention rows sum to 1)

Not acceptable: asserting the output equals itself, asserting only `.shape`, or printing without asserting. **Seed every random draw** — a flaky test is worse than none.

### Complexity
Time and space with `O(...)`, plus the constant that actually bites in practice.

### Follow-ups
The questions asked *after* you finish, each with a one-sentence answer. Use the entry's `followups` and add any that genuinely come up.

## Depth and difficulty (from `problems.json`)

- **`depth`** sets the **prose** floor — explanation only, code excluded: `intro` 200 / `core` 350 / `advanced` 500 words.
- **`difficulty`** goes in the header line.
- A compound title (`X and Y`, `X vs Y`) must have **both** implemented in the solution code — `PCA via SVD and via Eigendecomposition` needs both paths coded, not one.

## Fact-check gate (runs after you finish — you cannot bypass it)

Two gates run after you finish, and neither can be bypassed.

**First, the validator executes your code.** It extracts your `## Solution` and `## Self-test` blocks, concatenates them, and runs them. A non-zero exit fails the problem. This is not a style check — code that does not run does not ship.

**Second, a separate agent** is given your finished file and nothing else. It is told it did not write the file, and asked to find any incorrect formula, wrong mechanism description, or false factual claim. It does not see your reasoning.

Execution proves your code runs and passes *its own* test. It does **not** prove the test is meaningful — and that is exactly what the reviewer checks. So:

- **Make the oracle independent.** A self-test that recomputes the solution's own logic and compares proves nothing, and will be called out even though it executes cleanly.
- **The maths must be right, not just runnable.** A gradient with a sign error passes a test that checks only the shape. Use a finite-difference check and it cannot hide.
- Complexity claims must be true — an O(n log n) label on an O(n²) distance matrix is a false claim.
- Do not invent library behaviour. If you say `np.linalg.svd` returns `Vᵀ` rather than `V`, that had better be right — it is.
- Tolerances must be honest. `atol=1.0` on a probability is not a passing test.
- Do not pad the prose to hit the word floor with claims you cannot stand behind.

If rejected, you will be shown the exact `FAIL:` lines. Fix the underlying code or fact — do not reword around it.

## Running the code yourself

The validator resolves an interpreter in this order: `$RALPH_ML_PYTHON`, `./venv/bin/python3`, then `python3` on PATH — the first one that can `import numpy`. Use the same one:

```bash
bash ralph-ml-coding/validate.sh <id>
```

If it exits 2, numpy is missing — that is an environment problem, not something to fix by rewriting the problem. Report it and stop.
