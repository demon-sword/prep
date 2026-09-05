# Ralph ML Coding — Runnable ML Interview Problems

Generates **"implement it from scratch" ML coding problems** under `ml-coding/` — one problem per file, each with a runnable Python solution and an executable self-test.

## Why this track exists

The repo contains exactly **one** ML coding snippet (cosine similarity in NumPy). There is no way to rehearse "implement k-means from scratch", which is a standard senior ML/DS round. The concept tracks explain mechanisms well, but explanation is not rehearsal — and all 36 `machine_learning/` pages contain zero code blocks.

Modelled on `ralph-dsa` (statement → hints → solution → complexity), with **one deliberate inversion**: `ralph-dsa/spec.md:51` mandates *"Pseudocode only — no language-specific syntax"*. Here the entire point is runnable code, so solutions are real Python.

## The defining feature: validation runs the code

**Only one other generator in this repo executes what it produces** (`ralph-data-drills`, which runs Monte Carlo simulations through the same launcher). `validate.sh` extracts the `## Solution` and `## Self-test` blocks from each file, concatenates them, and runs them with a timeout. If the process exits non-zero, the problem fails.

A generator that emits plausible-looking but non-running ML code is worse than useless for interview prep, so this is a hard gate.

Proven on a worked example: a softmax missing its max-subtraction — which looks completely correct — fails with

```
FAIL: 19-softmax-cross-entropy.md: SOLUTION DOES NOT PASS ITS OWN SELF-TEST:
  RuntimeWarning: invalid value encountered in divide |
  AssertionError: must not overflow on large logits
```

## Requirements

This track needs a Python with **numpy**. `scikit-learn` is optional but recommended — it is used *only inside self-tests* as a cross-check oracle, never in a solution.

```bash
python3 -m venv venv
./venv/bin/python3 -m pip install --upgrade pip
./venv/bin/python3 -m pip install numpy scikit-learn
```

Resolution order: `$RALPH_ML_PYTHON` → `./venv/bin/python3` → `./venv/bin/python` → `python3` → `python`, taking the first that can `import numpy`.

If none is found, `validate.sh` exits **2** with setup instructions. That is an *environment* failure, distinct from a content failure — `once.sh` aborts on it rather than burning retries against a problem the agent cannot fix, and re-reports it as **4** so it cannot be confused with its own exit 2, which means "item done, more remain".

> **Note on the current checkout:** `venv/` here contains only `lib/` — no `bin/`, no numpy — and no Python on PATH has numpy either. Run the setup above before the first loop, or this track will (correctly) refuse to run.

## Quick start

```bash
# 0. one-time: interpreter with numpy (see Requirements)

# 1. Scaffold the plan from problems.json
./ralph-ml-coding/scaffold.sh

# 2a. Generate one problem — next in queue
./ralph-ml-coding/once.sh

# 2b. Generate a specific problem by id
./ralph-ml-coding/once.sh 15-kmeans

# 3. Run the full loop
./ralph-ml-coding/loop.sh

# 4. Validate — this EXECUTES every solution
./ralph-ml-coding/validate.sh
./ralph-ml-coding/validate.sh 15-kmeans

# 5. Cross-file redundancy
../validate-corpus.sh ml-coding

# 6. End-of-run gate — also fails an empty or short corpus
../validate-corpus.sh --final ml-coding
```

## Problem file shape

```markdown
# Implement K-Means with K-Means++ Initialization — Medium — Clustering

**Contract:** `kmeans(X, k, seed, max_iter) -> (centroids, labels, inertia)`

## Problem      statement + concrete I/O contract
## Hints        ≥3 progressive hints, each hidden in <details>, before the solution
## Solution     runnable Python (NumPy yes, sklearn no)
## Self-test    assert-based, executed by the validator
## Complexity   O(...) time and space
## Follow-ups   what the interviewer asks next
```

## The sklearn rule

- **In a solution:** forbidden. You are implementing the thing sklearn does. The validator rejects `import sklearn` inside a solution block.
- **In a self-test:** encouraged. Comparing your k-means inertia against `sklearn.cluster.KMeans` within a tolerance is exactly the right oracle.

If a self-test imports sklearn and sklearn is not installed, the validator says so explicitly rather than reporting a bogus content failure.

## What else the validator checks

Beyond executing the code:

- required sections present, in order
- **≥3 hidden `<details>` hints, positioned before the solution** — you can't rehearse against a spoiler
- the `io_contract` function is actually defined by that name
- the self-test contains a real `assert` (word-boundary matched — `print("assertions passed")` does not count)
- an `O(...)` bound is stated
- ≥2 follow-ups
- depth-scaled prose floor, **code excluded**: `intro` 200 / `core` 350 / `advanced` 500 words
- no placeholder text
- compound-title coverage — `PCA via SVD and via Eigendecomposition` must code both paths

## Binding validation

No `|| true` anywhere in this track.

- `once.sh` resolves the target problem, runs the agent, then runs `validate.sh <id>` and **honours its exit code**
- an item the agent never wrote is SKIPped by the validator, which exits 0 — `once.sh` checks the file exists before believing that pass
- on failure it feeds the exact `FAIL:` lines — including the Python traceback — back into the next attempt's prompt
- capped at `RALPH_MAX_ATTEMPTS` (default 3), then exits **3**
- a missing interpreter aborts immediately instead of retrying
- a `COMPLETE` promise is only believed if a full-corpus validation passes **and** every planned problem produced a file
- `loop.sh` treats 3 and 4 as fatal; **2 means "keep going"**

### Exit codes

| Code | `validate.sh` | `once.sh` / `loop.sh` |
|---|---|---|
| 0 | everything checked passes | done, nothing left |
| 1 | content failure | final validation failed |
| 2 | no Python with numpy | **one item done, more remain** — the loop continues |
| 3 | — | gave up after `RALPH_MAX_ATTEMPTS` |
| 4 | — | environment cannot run solutions |
| 5 | — | `loop.sh` only: 3 consecutive iterations produced nothing |
| 124 | — | agent timed out |

`validate.sh`'s 2 and `once.sh`'s 2 mean opposite things, which is why `once.sh` translates one into 4. They were the same number once, and `loop.sh` consequently stopped after its first success and blamed the environment for it.

## Adversarial fact-check

After generation, a **separate** `claude -p` invocation gets only the finished file and is told it did not write it. Read-only (`--allowedTools "Read,Grep,Glob"`), and must emit `<factcheck>PASS</factcheck>`.

Execution and fact-check cover different failures, which is why both run. Execution proves the code runs and passes *its own* test. It cannot tell whether the test is a meaningful oracle — a self-test that recomputes the solution's own logic and compares passes cleanly and proves nothing. Catching that is the reviewer's job.

## Security note

This validator executes model-generated Python on your machine, by design — there is no way to verify code runs without running it. That makes it the one place in this repo where executing untrusted code is the purpose rather than a side effect, so it runs under the shared containment launcher in `ralph-lib/ralph_sandbox.py`, which `ralph-data-drills` uses too:

| Layer | What it stops |
|---|---|
| `-I` isolated interpreter | `PYTHON*` env influence, user site-packages, script dir on `sys.path` |
| Allowlisted environment | reading this shell's credentials — the child sees ~9 variables, none inherited from you |
| macOS seatbelt (`sandbox-exec`) | **all** network, and every filesystem write outside the run's own directory |
| `RLIMIT_NPROC` = 0 | fork bombs, and detached grandchildren, at the kernel — including a `ctypes` call straight to `fork(2)` |
| `RLIMIT_FSIZE` / `RLIMIT_CORE` | filling the disk; core-dumping whatever the code held |
| RSS watchdog | a memory bomb taking the machine into swap (`setrlimit(RLIMIT_AS)` is a no-op on Darwin, so polling is the enforcement) |
| Audit hook | sockets, process spawning, out-of-sandbox writes — the portable fallback where there is no OS sandbox |
| `killpg` on timeout | descendants outliving the run; `subprocess`'s own timeout kills only the direct child |

The kernel sandbox is the boundary that holds; the audit hook is a backstop that `ctypes` could talk around, and it says so rather than pretending otherwise. On a platform with no OS sandbox the validator still runs, and `Containment:` in its report header names exactly which layers are in force — read it before trusting a green run on a non-macOS machine.

Still treat `ml-coding/` as code you are about to read, not code you have vetted.

## Environment

| Var | Default | Effect |
|---|---|---|
| `RALPH_ML_PYTHON` | — | Interpreter used to execute solutions |
| `RALPH_ML_EXEC_TIMEOUT` | 60 | Seconds per solution+test run |
| `RALPH_ML_MEM_MB` | 2048 | Resident-memory cap per run, in MB |
| `RALPH_MAX_ATTEMPTS` | 3 | Regeneration attempts before giving up |
| `RALPH_FACTCHECK_TIMEOUT` | 900 | Seconds for the fact-check pass |
| `RALPH_SKIP_FACTCHECK` | 0 | `1` skips the adversarial pass |
| `RALPH_LOOP_SLEEP` | 5 | Seconds `loop.sh` pauses between iterations |
| `RALPH_MAX_STALLS` | 3 | Consecutive no-output iterations before the loop stops |
| `RALPH_RUN_ID` | set by `loop.sh` | Identifies one run. Used by the category-shaped tracks' on-disk rejection budget; this track's retry budget is in-process (one `once.sh` per item), so it has no effect here. |
| `RALPH_MLCODING_MODEL` | — | Model slug for generation |
| `RALPH_MLCODING_TIMEOUT` | 3600 | Seconds per generation attempt |

## Files

```
ralph-ml-coding/
├── spec.md         what a problem must contain, and the pseudocode inversion
├── prompt.md       the agent's per-iteration instructions
├── problems.json   the problem queue + io_contract + verify + followups
├── plan.md         queue (built by scaffold.sh)
├── progress.txt    append-only run log
├── scaffold.sh     builds plan.md from problems.json
├── once.sh         one problem, binding validation + fact-check
├── loop.sh         runs once.sh until done
└── validate.sh     structural checks + EXECUTES every solution
```

Shared helpers live in `../ralph-common.sh`.
