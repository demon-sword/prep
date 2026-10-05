# Implement Parallel Tree Reduction and Exclusive Prefix Scan — Medium — gpu-kernels

**Contract:** `tree_reduce(x: np.ndarray) -> float and exclusive_scan(x: np.ndarray) -> np.ndarray  # sum; then exclusive prefix sums`
**Generated:** ralph-ml-coding

---

## Problem

Given a one-dimensional array `x` of length `n`, compute two things. First, its sum via a pairwise tree reduction: repeatedly pair adjacent elements and add them, halving the active set each round, exactly as one CUDA thread block reduces its shared-memory segment before writing out a single partial sum. Second, its exclusive prefix scan via the Blelloch two-sweep construction: an up-sweep (reduce) phase that builds partial sums up a binary tree, then a down-sweep phase that pushes prefix values back down, so that `out[i]` holds the sum of all elements strictly before position `i` and `out[0]` is the additive identity. Both run CPU-only on plain Python loops over the tree structure; the pairing pattern, not the hardware, is what is being rehearsed.

This is asked because reduction and scan are the two collective primitives underneath nearly every GPU kernel that aggregates: normalisation denominators, softmax denominators, stream compaction, radix sort passes, and the cross-block tail of every large dot product. A tree reduction that folds the odd element out instead of carrying it forward silently drops data on every non-power-of-two input — the most common reduction bug in existence. An exclusive scan that confuses inclusive and exclusive indexing shifts every output by one position, which in a compaction kernel means every thread writes to its neighbour's slot. And a Blelloch sweep that branches on array bounds inside the inner loop instead of padding once up front is both slower and harder to verify, because the tree shape then differs between the two sweeps.

**Input/output contract**

- `x` — shape `(n,)`, any real numeric dtype, `n >= 1`. Empty or non-1-D inputs raise `ValueError`.
- `tree_reduce(x)` returns a Python `float`: the sum of all elements, combined pairwise in tree order (round by round, adjacent pairs), not left-to-right.
- `exclusive_scan(x)` returns an array of shape `(n,)`: float inputs accumulate in float64 working precision and return float64 (narrower floats widen to float64; float64 stays float64), while integer inputs accumulate in and return int64, exact with no float rounding: `out[0] == 0` and `out[i] == sum(x[:i])` for every `i`.
- Neither function mutates its input. Non-power-of-two lengths are handled by padding the working buffer with zeros (the additive identity) up to the next power of two, once, before either sweep — never by bounds-checking inside the sweep loops.

**Edge cases that must hold**

- `n = 1`: the reduction returns the single element; the scan returns `[0]`.
- Non-power-of-two lengths (7, 1000) reduce and scan exactly — the padding is internal and invisible in the output length.
- Negative entries, zeros, and mixed signs all work; the identity padding contributes nothing regardless of sign.
- Integer inputs stay exact (no float rounding in the integer path); float inputs accumulate in float64 working precision.

## Hints

<details><summary>Nudge</summary>

Both algorithms are the same binary tree walked in different directions. If the reduction climbs from leaves to root by pairing neighbours, what information does each internal node need to carry so that a second walk back down can hand every leaf the sum of everything to its left?

</details>

<details><summary>Approach</summary>

For the reduction, hold a working list, repeatedly replace each adjacent pair by its sum, and carry an unpaired trailing element forward unchanged when the length is odd; the survivor after the final round is the answer. For the scan, pad a float64 copy up to the next power of two, run the up-sweep (at stride `d`, each node at a multiple of `2d` absorbs its left neighbour `d` away), zero the root, then run the down-sweep (each node hands its value left and passes value-plus-left-sum right), and finally strip the padding. One helper that rounds `n` up to a power of two serves both paths.

</details>

<details><summary>Key insight</summary>

Padding once with the identity element makes every level of both sweeps uniform: no odd-length special cases, no bounds checks, the same indexing in the up-sweep and the down-sweep. The exclusive (rather than inclusive) convention is what makes the down-sweep work — the root starts at zero, "the sum of everything before everything", and each node splits its prefix into "mine goes left, mine-plus-left-subtree goes right", so every leaf ends up holding exactly the sum of the elements before it.

</details>

## Solution

```python
import numpy as np


def _check_1d(x):
    x = np.asarray(x)
    if x.ndim != 1:
        raise ValueError(f"input must be 1-D, got shape {x.shape}")
    if x.shape[0] == 0:
        raise ValueError("input must be non-empty")
    return x


def _next_pow2(n):
    """Smallest power of two >= n (n >= 1)."""
    p = 1
    while p < n:
        p *= 2
    return p


def tree_reduce(x):
    """Sum x by pairwise tree reduction, mirroring one block's shared-memory
    reduce: each round pairs adjacent elements, and an unpaired trailing
    element on odd-length rounds is carried forward, never dropped."""
    x = _check_1d(x)
    # Work in float64 so the reduction order (not the dtype) is what is
    # under test; integer inputs are converted back by exactness below.
    work = [float(v) for v in x]
    while len(work) > 1:
        nxt = []
        for i in range(0, len(work) - 1, 2):
            nxt.append(work[i] + work[i + 1])
        if len(work) % 2 == 1:
            nxt.append(work[-1])  # odd element rides forward untouched
        work = nxt
    total = work[0]
    if np.issubdtype(x.dtype, np.integer):
        return float(int(round(total)))
    return float(total)




def exclusive_scan(x):
    """Exclusive prefix sums via the Blelloch up-sweep / down-sweep.

    The working buffer is padded ONCE with zeros (the additive identity)
    to a power of two, so both sweeps use uniform stride indexing with
    no bounds checks inside the loops. Padding is stripped at the end.
    """
    x = _check_1d(x)
    n = x.shape[0]
    is_int = np.issubdtype(x.dtype, np.integer)
    # Integer inputs stay in int64 end to end (exact); floats accumulate
    # in float64 working precision.
    wtype = np.int64 if is_int else np.float64
    size = _next_pow2(n)
    buf = np.zeros(size, dtype=wtype)
    buf[:n] = x

    # Up-sweep (reduce): stride d = 1, 2, 4, ...; node j absorbs j - d.
    d = 1
    while d < size:
        for j in range(0, size, 2 * d):
            buf[j + 2 * d - 1] += buf[j + d - 1]
        d *= 2

    # The root now holds the total; exclusive means "before everything" = 0.
    buf[size - 1] = 0

    # Down-sweep: push prefixes down; each node splits its value left
    # ("mine goes left") and value-plus-left-subtree right.
    d = size // 2
    while d >= 1:
        for j in range(0, size, 2 * d):
            left = j + d - 1
            right = j + 2 * d - 1
            t = buf[left]
            buf[left] = buf[right]
            buf[right] = buf[right] + t
        d //= 2

    out = buf[:n]
    if is_int:
        return np.array(out, dtype=np.int64)
    return np.array(out, dtype=np.result_type(x.dtype, np.float64))
```

## Self-test

```python
import numpy as np

gen = np.random.default_rng(23)

# 1. Reduction matches np.sum on awkward lengths, signs, and zeros.
#    Floats compare with tolerance: tree order rounds differently than
#    NumPy's pairwise order, so exact equality is the wrong assertion.
for n in (1, 2, 3, 7, 16, 100, 1000, 1024):
    xf = gen.normal(size=n) * 100
    assert np.allclose(tree_reduce(xf), float(np.sum(xf.astype(np.float64))),
                       rtol=1e-12, atol=1e-9), \
        f"float reduce mismatch at n={n}"
    xi = gen.integers(-50, 50, size=n)
    assert tree_reduce(xi) == float(int(np.sum(xi))), \
        f"int reduce mismatch at n={n}"
assert tree_reduce(np.zeros(13)) == 0.0, "all-zeros reduce failed"
assert tree_reduce(np.array([42.0])) == 42.0, "n=1 reduce failed"

# 2. Hand-computed tree order: ((1+2)+(3+4)) + ((5+6)+(7+8)) structure
#    must pair neighbours, and the odd element must ride forward.
assert tree_reduce(np.array([1., 2., 3., 4.])) == 10.0
assert tree_reduce(np.array([1., 2., 3., 4., 5.])) == 15.0

# 3. Exclusive scan matches the shifted-cumsum oracle, both parities.
for n in (1, 2, 3, 5, 8, 15, 16, 100, 1000):
    xf = gen.normal(size=n) * 10
    got = exclusive_scan(xf)
    want = np.concatenate([[0.0], np.cumsum(xf)[:-1]])
    assert got.shape == (n,), f"scan shape {got.shape} != {(n,)} at n={n}"
    assert np.allclose(got, want, atol=1e-9), f"float scan mismatch at n={n}"
    assert got[0] == 0.0, "exclusive scan must start at the identity"
    xi = gen.integers(-20, 20, size=n)
    got_i = exclusive_scan(xi)
    want_i = np.concatenate([[0], np.cumsum(xi)[:-1]])
    assert np.array_equal(got_i, want_i), f"int scan mismatch at n={n}"

# 4. Hand-computed scan: [3, 1, 4, 1, 5] -> [0, 3, 4, 8, 9].
assert np.array_equal(
    exclusive_scan(np.array([3, 1, 4, 1, 5])), np.array([0, 3, 4, 8, 9])), \
    "hand-computed scan wrong"
assert np.array_equal(
    exclusive_scan(np.array([7.5])), np.array([0.0])), "n=1 scan wrong"

# 5. Inputs are never mutated.
probe = gen.normal(size=37)
snapshot = probe.copy()
tree_reduce(probe)
exclusive_scan(probe)
assert np.array_equal(probe, snapshot), "input was mutated"

# 6. Contract violations raise.
for bad in (np.array([]), np.ones((3, 3)), np.ones((2, 2, 2))):
    for fn in (tree_reduce, exclusive_scan):
        try:
            fn(bad)
        except ValueError:
            pass
        else:
            raise AssertionError(f"no ValueError for shape {bad.shape}")

print("ok")
```

## Complexity

| | |
|-|-|
| **Time** | O(n) work for both — the tree visits n−1 internal additions for the reduction and 2·(n−1) for the two scan sweeps — at O(log n) parallel depth |
| **Space** | O(n) for the padded scan buffer (at most 2n); O(n) transient list for the reduction |

The work/depth split is the point of the tree shape: a sequential accumulation does the same O(n) additions but at O(n) depth, so on `p` parallel lanes it cannot beat O(n) time, while the tree finishes in O(n/p + log n). The Blelloch scan does roughly twice the additions of the reduction (up-sweep plus down-sweep) to buy that same logarithmic depth for prefix sums — a scan built from `n` sequential accumulations would be O(n²) work and unusable. The padding at most doubles memory (just under 2n for `n = 2^k + 1`), which on device is the reason scans allocate the next power of two in shared memory up front rather than handling the tail with divergent branches.

## Follow-ups

- **Why is a tree reduction faster than a sequential accumulation on parallel hardware?** — The sequential chain has O(n) data dependencies, so no two additions can overlap; the tree exposes O(n) independent pairs per round and finishes in O(log n) rounds, letting hundreds of threads each do useful work in every round instead of one thread waiting on the previous sum.
- **What changes between an inclusive and an exclusive scan, and where is each used?** — Exclusive `out[i] = sum(x[:i])` leaves `out[0] = 0` and totals at `out[n-1] + x[n-1]`; inclusive `out[i] = sum(x[:i+1])` ends with the total. Compaction and allocation use exclusive (each element learns its destination slot before writing), while running totals and cumulative distributions use inclusive.
- **How does a multi-block reduction combine per-block partial sums?** — Each block reduces its segment to one partial sum in shared memory and writes it to a small global array; a second kernel (or a final single-block pass, or an atomic add when contention is low) reduces those `num_blocks` partials to the total — the two-level structure mirrors the tree, with global memory as the link between levels.
