# Implement a Seeded Train-Test Split — Easy — data-prep

**Contract:** `train_test_split(X: np.ndarray, y: np.ndarray, test_size: float, seed: int) -> tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]  # X_train, X_test, y_train, y_test`
**Generated:** ralph-ml-coding

---

## Problem

Given a feature matrix and its label vector, shuffle the rows with a seeded random number generator and cut them into a training partition and a test partition. Do not use `sklearn.model_selection.train_test_split` — that is the thing being implemented.

This looks like three lines and mostly is, but it is asked because the failure modes are quiet ones. A split that reshuffles `X` and `y` with two separate draws destroys the correspondence between a row and its label, and every downstream metric is then measuring noise while looking entirely healthy. A split that is not reproducible makes two experiment runs incomparable, so you cannot tell a real improvement from a lucky partition. And a split that duplicates a row into both halves leaks the answer into the test set, which inflates the score in exactly the direction that makes you ship the model.

**Input/output contract**

- `X` — shape `(n, d)`, any numeric dtype. `y` — shape `(n,)`, any dtype, aligned row-for-row with `X`.
- `test_size` — a float in `[0, 1]`. The test partition gets `round(test_size * n)` rows.
- `seed` — an int. Two calls with the same `(X, y, test_size, seed)` must return byte-identical arrays.
- Returns exactly four arrays in the order `X_train, X_test, y_train, y_test`, with `X_train.shape[0] == y_train.shape[0]` and likewise for the test half.

**Edge cases that must hold**

- The train and test row sets are disjoint and their union is every row exactly once — a permutation, not a sample with replacement.
- Ambiguous rounding is resolved deterministically. Python's `round` is half-to-even, so `round(2.5) == 2`: with `n = 10` and `test_size = 0.25` the test half has 2 rows, not 3, on every run and every platform.
- `test_size = 0.0` and `test_size = 1.0` return an empty partition rather than raising. A `test_size` outside `[0, 1]`, or an `X` and `y` whose lengths disagree, raise `ValueError`.
- Seeding is local to the call. Do not consume the global `np.random` state, or an unrelated draw elsewhere in the program silently changes your split.

## Hints

<details><summary>Nudge</summary>

You need `X` and `y` reordered the same way. What if you shuffled something other than the data itself, and applied the result to both?

</details>

<details><summary>Approach</summary>

Build one random permutation of the row positions `0..n-1`. Slice that single ordering into a test prefix and a train suffix, then use each slice to index both `X` and `y`. Because one ordering drives all four gathers, alignment is structural rather than something you have to remember to preserve.

</details>

<details><summary>Key insight</summary>

Shuffle indices, not data. A permutation of `0..n-1` is by construction disjoint-and-complete when you cut it in two, so the no-overlap and full-coverage properties come for free instead of needing a membership check. For reproducibility, build a fresh `np.random.default_rng(seed)` inside the function: it makes the split a pure function of `(n, seed)`, unaffected by whatever else in the process has been drawing random numbers.

</details>

## Solution

```python
import numpy as np


def train_test_split(X, y, test_size, seed):
    """Split X and y into train/test partitions using a seeded permutation.

    Returns (X_train, X_test, y_train, y_test).
    """
    X = np.asarray(X)
    y = np.asarray(y)

    if X.shape[0] != y.shape[0]:
        raise ValueError(f"X has {X.shape[0]} rows but y has {y.shape[0]}")
    if not 0.0 <= float(test_size) <= 1.0:
        raise ValueError(f"test_size must lie in [0, 1], got {test_size}")

    n = X.shape[0]

    # A fresh Generator seeded per call: the split depends only on (n, seed) and
    # never on the global np.random state that some other code may have consumed.
    rng = np.random.default_rng(seed)
    perm = rng.permutation(n)

    # Python's round() is half-to-even: round(2.5) == 2, not 3. Ambiguous
    # fractions therefore resolve identically on every run and platform.
    n_test = int(round(float(test_size) * n))

    test_idx = perm[:n_test]
    train_idx = perm[n_test:]

    # One gather per array, driven by one permutation — that shared ordering is
    # what keeps each row with its own label. Fancy indexing copies, so doing it
    # exactly once costs a single pass instead of shuffling the data in place.
    return X[train_idx], X[test_idx], y[train_idx], y[test_idx]
```

## Self-test

```python
import numpy as np

# Tag every row with its own original index in column 0. That makes each
# returned row traceable back to where it came from, which is what lets the
# test check the permutation property without the function reporting indices.
n, d = 40, 3
gen = np.random.default_rng(0)
X = np.column_stack([np.arange(n, dtype=float), gen.normal(size=(n, d - 1))])
y = np.arange(n) * 10          # y[i] == 10*i, so any misalignment is visible

X_tr, X_te, y_tr, y_te = train_test_split(X, y, 0.25, seed=7)

tr_idx = X_tr[:, 0].astype(int)
te_idx = X_te[:, 0].astype(int)

# 1. A true permutation: every row exactly once across the two halves.
assert np.array_equal(np.sort(np.concatenate([tr_idx, te_idx])), np.arange(n)), \
    "train + test is not a permutation of 0..n-1"
assert set(tr_idx).isdisjoint(set(te_idx)), "a row leaked into both partitions"

# 2. Rows still carry their own labels.
assert np.array_equal(y_tr, tr_idx * 10), "X_train rows lost their y_train labels"
assert np.array_equal(y_te, te_idx * 10), "X_test rows lost their y_test labels"
assert np.array_equal(X_te, X[te_idx]), "X_test rows were altered, not just gathered"

# 3. Hand-computed sizes, including the half-to-even case (0.25*10 = 2.5 -> 2).
for size, frac, expected in [(40, 0.25, 10), (10, 0.25, 2), (7, 0.3, 2),
                             (10, 0.5, 5), (10, 0.0, 0), (10, 1.0, 10)]:
    Xs = np.arange(size, dtype=float).reshape(size, 1)
    ys = np.arange(size)
    a, b, c, e = train_test_split(Xs, ys, frac, seed=1)
    assert b.shape[0] == expected, f"n={size} test_size={frac}: got {b.shape[0]}, want {expected}"
    assert a.shape[0] == size - expected, f"n={size}: train size wrong"

# 4. Determinism: same seed byte-identical, different seed genuinely different.
again = train_test_split(X, y, 0.25, seed=7)
for got, want in zip(again, (X_tr, X_te, y_tr, y_te)):
    assert np.array_equal(got, want), "same seed produced a different split"

other = train_test_split(X, y, 0.25, seed=8)[1][:, 0].astype(int)
assert not np.array_equal(np.sort(other), np.sort(te_idx)), \
    "seed 8 selected the same test rows as seed 7"

# 5. Contract violations are rejected, not silently mangled.
for bad in (-0.1, 1.5):
    try:
        train_test_split(X, y, bad, seed=0)
    except ValueError:
        pass
    else:
        raise AssertionError(f"test_size={bad} should have raised ValueError")
try:
    train_test_split(X, y[:-1], 0.25, seed=0)
except ValueError:
    pass
else:
    raise AssertionError("mismatched X/y lengths should have raised ValueError")

print("ok")
```

## Complexity

| | |
|-|-|
| **Time** | O(n + n·d) — one linear-time permutation of the row indices, then one gather that touches every element of `X` once |
| **Space** | O(n + n·d) — the permutation is only `n` integers, but the four returned arrays are copies totalling the size of `X` and `y` |

The permutation is never the bottleneck; the gather is. Fancy indexing on a permuted index array reads `X` in scattered order, so on a large matrix it is memory-bandwidth-bound and cache-hostile in a way a contiguous slice of the same size is not. If `X` is large enough for that to hurt, return `train_idx` and `test_idx` instead of the four arrays and let the caller index lazily — the split itself is then O(n) in both time and space, and no data is copied at all.

## Follow-ups

- **Why shuffle before splitting instead of taking the last 20% of rows?** — Real datasets arrive ordered by something (collection date, label, source file), so a positional tail is a biased sample of that ordering rather than a random one; shuffling makes the test set exchangeable with the training set, which is the assumption every generalisation estimate rests on.
- **How does this change for time-series data where rows are ordered?** — It inverts: shuffling leaks the future into the training set, so you split by time (train on everything before a cutoff, test after it) and typically use rolling-origin or expanding-window validation instead of a random partition.
- **When is a single held-out split not enough to trust the estimate?** — When `n` is small or the test half is, because the variance of the estimate across different random splits then swamps the difference between the models you are comparing — that is when you move to k-fold cross-validation and report the mean and spread across folds.
- **Should the split be stratified?** — With a rare class, a plain permutation can leave a fold with very few positives or none at all, which makes per-class metrics unstable or undefined; stratifying the permutation within each class fixes it and is the subject of the k-fold problem in this track.
