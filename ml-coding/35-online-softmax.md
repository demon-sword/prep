# Implement Stable and Online Softmax — Medium — gpu-kernels

**Contract:** `softmax_stable(logits: np.ndarray) -> np.ndarray and softmax_online(logits: np.ndarray) -> np.ndarray  # row-wise probabilities`
**Generated:** ralph-ml-coding

---

## Problem

Given a 2-D array `logits` of shape `(batch, classes)`, compute row-wise softmax probabilities twice. First with the standard numerically stable formulation: subtract each row's maximum, exponentiate, and normalise. Then with the online (single-pass) formulation: stream each row left to right maintaining a running maximum `m` and a running normaliser `d`, and whenever a new element exceeds `m`, rescale the accumulated `d` by `exp(m_old − m_new)` before folding the new element in. Both run CPU-only in float32; no GPU kernel is launched here. The online recurrence is the scalar algorithm at the heart of every fused GPU softmax kernel — and of blocked online softmax over tiles, as in FlashAttention — where a row never fits in fast memory at once and two passes over global memory would double the bandwidth cost.

This is asked because softmax is where naive code meets floating point reality. A direct `exp(x) / sum(exp(x))` overflows to `inf` the moment a logit reaches 90 in float32, producing `nan` probabilities that poison every downstream loss without raising. The max-subtraction fix is mathematically a no-op (it multiplies numerator and denominator by the same constant) but numerically the difference between a model that trains and one that diverges — and the online variant shows the same fix can be maintained incrementally, which is the entire reason fused kernels can compute softmax in a single pass over tiles that each carry their own local maximum.

**Input/output contract**

- `logits` — shape `(batch, classes)`, real numeric dtype, `batch >= 1`, `classes >= 1`. Any other dimensionality, or an empty dimension, raises `ValueError`.
- Both functions return shape `(batch, classes)` in float32 (float64 inputs are computed in float64 and returned in float64 — the working precision follows the input, never narrower).
- Every output row sums to 1 within float tolerance and contains only finite values, including for logits of ±1000 where naive `exp` overflows float32 (and float64 for +1000).
- Both are shift-invariant: adding a constant to a whole row leaves its output unchanged to float precision.

**Edge cases that must hold**

- A single class (`classes = 1`) returns all ones — the only distribution over one outcome.
- A single row works identically to a batch (no accidental squeeze or broadcasting of the max across rows).
- Rows of equal logits return the uniform distribution.
- `±1000` logits stay finite and sum to 1; a row mixing `+1000` and `-1000` puts probability ~1 on the large logit without overflow.
- Non-contiguous input (a strided view) is handled by value.

## Hints

<details><summary>Nudge</summary>

Softmax is invariant to adding a constant to a row. Which constant would you choose to make every exponent non-positive — and what does the update rule look like when that constant changes halfway through a left-to-right pass?

</details>

<details><summary>Approach</summary>

For the stable path, take the row max, subtract, exponentiate, divide by the sum — three vectorisable steps. For the online path, walk each row element by element keeping `(m, d)`: for a new logit `v`, if `v > m`, first rescale `d *= exp(m − v)` (the old accumulator was normalised against the old max, so it must be re-based), then set `m = v`; then `d += exp(v − m)`. Do not store per-element exponentials during that walk — each stored value would need re-basing every time the max moves — and instead emit `exp(v − m_final) / d_final` per element in a second lightweight pass once the final maximum is known. Test both against a float64 reference, not against each other: two implementations sharing a bug would agree and prove nothing.

</details>

<details><summary>Key insight</summary>

The rescaling step `d *= exp(m_old − m_new)` is the whole algorithm: it re-expresses the running sum under the new maximum without revisiting old elements, so the accumulator always equals what the two-pass method would have computed for the prefix seen so far. Once that invariant holds after every element, the final `d` equals the stable denominator exactly (up to float rounding), and the online pass is provably the same function — one pass, O(1) extra state, no overflow.

</details>

## Solution

```python
import numpy as np


def _check_2d(logits):
    x = np.asarray(logits)
    if x.ndim != 2:
        raise ValueError(f"logits must be 2-D, got shape {x.shape}")
    if 0 in x.shape:
        raise ValueError("logits must have non-empty dimensions")
    return x


def softmax_stable(logits):
    """Row-wise softmax with max-subtraction: shift each row by its max
    (a mathematical no-op that keeps every exponent <= 0), then
    exponentiate and normalise. Working precision follows the input."""
    x = _check_2d(logits)
    work = x.astype(np.float64) if x.dtype == np.float64 else x.astype(np.float32)
    # The max-subtraction: exp(v - m) <= 1 for every element, so no
    # overflow is possible no matter how large the raw logits are.
    m = work.max(axis=1, keepdims=True)
    e = np.exp(work - m)
    return (e / e.sum(axis=1, keepdims=True)).astype(work.dtype, copy=False)


def softmax_online(logits):
    """Row-wise softmax with streaming row statistics plus one emit pass.

    Pass 1 walks each row left to right maintaining (m, d): the running
    maximum and the running normaliser sum(exp(v - m)) over the prefix.
    When a new logit exceeds m, the accumulator is re-based with
    d *= exp(m_old - m_new) instead of revisiting old elements — the
    scalar core of every fused GPU softmax kernel. Pass 2 writes each
    output against the final maximum, as a fused kernel writes its
    outputs once the row statistics are known."""
    x = _check_2d(logits)
    out_dtype = np.float64 if x.dtype == np.float64 else np.float32
    wtype = out_dtype
    xb = np.array(x, dtype=wtype)
    batch, classes = xb.shape
    out = np.empty_like(xb)
    for r in range(batch):
        # Pass 1 — streaming statistics: one left-to-right walk keeping
        # only (m, d). Stored per-element exponentials are NOT kept here,
        # because every stored value would need re-basing each time the
        # running maximum moves; the accumulator re-basing below is enough.
        m = xb[r, 0]    # running maximum over the prefix
        d = wtype(1.0)  # sum(exp(v - m)) over the prefix so far
        for j in range(1, classes):
            v = xb[r, j]
            if v > m:
                # Re-base the accumulator under the new maximum without
                # touching earlier elements: each old term exp(u - m_old)
                # equals exp(u - m_new) * exp(m_new - m_old), so scaling
                # the whole sum by exp(m_old - m_new) re-normalises it.
                d *= np.exp(m - v)
                m = v
            d += np.exp(v - m)
        # Pass 2 — emit against the final maximum, as a fused kernel
        # writes its outputs once the row statistics are known.
        for j in range(classes):
            out[r, j] = np.exp(xb[r, j] - m) / d
    return out.astype(out_dtype, copy=False)
```
## Self-test

```python
import numpy as np

gen = np.random.default_rng(37)

# 1. Both agree with a float64 reference on random logits, and rows sum to 1.
for batch, classes in ((1, 1), (1, 5), (4, 1), (8, 16), (3, 100), (16, 7)):
    L = (gen.normal(size=(batch, classes)) * 6).astype(np.float32)
    ref64 = np.exp(L.astype(np.float64) - L.max(axis=1, keepdims=True))
    ref64 /= ref64.sum(axis=1, keepdims=True)
    for fn in (softmax_stable, softmax_online):
        got = fn(L)
        assert got.shape == (batch, classes), f"{fn.__name__} shape wrong"
        assert np.all(np.isfinite(got)), f"{fn.__name__} non-finite on random input"
        assert np.allclose(got.sum(axis=1), 1.0, atol=1e-6), \
            f"{fn.__name__} rows do not sum to 1"
        assert np.allclose(got.astype(np.float64), ref64, atol=1e-5), \
            f"{fn.__name__} drifts from float64 reference"
    assert np.allclose(
        softmax_stable(L).astype(np.float64),
        softmax_online(L).astype(np.float64), atol=1e-5), \
        "stable and online disagree"

# 2. Extreme logits stay finite where naive exp overflows.
big = np.array([[1000., 1001., 999.], [-1000., -999., -1001.]], dtype=np.float32)
for fn in (softmax_stable, softmax_online):
    got = fn(big)
    assert np.all(np.isfinite(got)), f"{fn.__name__} overflowed at +-1000"
    assert np.allclose(got.sum(axis=1), 1.0, atol=1e-5), \
        f"{fn.__name__} rows do not sum to 1 at +-1000"
# The argmax row must concentrate mass on the largest logit.
assert softmax_online(big)[0, 1] > 0.5 and softmax_stable(big)[1, 1] > 0.5
# Naive exp genuinely overflows here — proving the test has teeth.
with np.errstate(over='ignore'):
    assert not np.all(np.isfinite(np.exp(big) / np.exp(big).sum(axis=1, keepdims=True))), \
        "naive softmax unexpectedly finite; test premise broken"

# 3. Shift-invariance: adding 500 to a row changes nothing.
L = gen.normal(size=(5, 9)).astype(np.float32)
for fn in (softmax_stable, softmax_online):
    assert np.allclose(fn(L + 500.0).astype(np.float64),
                       fn(L).astype(np.float64), atol=1e-5), \
        f"{fn.__name__} not shift-invariant"

# 4. Edge shapes: single class -> ones; uniform rows -> uniform; strided input.
assert np.array_equal(
    softmax_stable(np.array([[3.], [7.]])), np.ones((2, 1), dtype=np.float32))
assert np.array_equal(
    softmax_online(np.array([[3.], [7.]])), np.ones((2, 1), dtype=np.float32))
uni = np.full((2, 6), 2.5, dtype=np.float32)
assert np.allclose(softmax_online(uni), np.full((2, 6), 1 / 6), atol=1e-6)
L = np.ascontiguousarray(gen.normal(size=(6, 12)).astype(np.float32))[::2, ::3]
assert np.allclose(softmax_stable(L).sum(axis=1), 1.0, atol=1e-6), \
    "strided input mishandled"

# 5. Contract violations raise.
for bad in (np.ones(4), np.ones((2, 2, 2)), np.zeros((0, 3)), np.zeros((3, 0))):
    for fn in (softmax_stable, softmax_online):
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
| **Time** | O(batch·classes) for both — each element is visited a constant number of times (three vector passes for stable, one scalar pass plus one normalise for online) |
| **Space** | O(batch·classes) for the output; the online pass adds only O(1) running state `(m, d)` per row plus one row buffer |

On the CPU both are memory-bandwidth-bound and the two-pass stable version is usually faster, because vectorised passes beat a Python-level scalar loop — which is precisely why this file is rehearsal, not production code. On a GPU the tradeoff inverts: the stable version reads the row twice from slow global memory (once for the max, once for the sum), while the online recurrence reads it once and keeps `(m, d)` in registers, halving global traffic. That single-pass property composes: FlashAttention applies the same rescaling across tiles, where each tile arrives with its own local max and the running output is re-based exactly the way `d` is re-based here. The accuracy caveat travels with it — the rescaling multiplies rounding error by `exp(m_old − m_new)`, so rows whose max jumps late accumulate slightly more error than the two-pass result, bounded in practice well below float32 noise for sane logit ranges.

## Follow-ups

- **Why does the online formulation matter for a fused kernel but not for plain NumPy code?** — A fused kernel's whole purpose is touching global memory once: the two-pass version forces a second full read of the row (or materialising it in SRAM, which caps the sequence length), while the online recurrence folds the max-tracking into the single pass with two registers of state — on the CPU, where both passes hit cache anyway, the vectorised two-pass version wins instead.
- **How does this rescaling trick generalize to online softmax over blocks (FlashAttention)?** — Each block computes its local max and local sum, and the running global `(m, d)` absorbs the block with the identical re-basing — `d_global = d_global · exp(m_global − m_new) + d_block · exp(m_block − m_new)` — so the attention output accumulates correctly without ever materialising the full score matrix, which is what drops memory from quadratic to linear.
- **Where does float32 accumulation error show up, and when must you accumulate in float64?** — The denominator sums up to `classes` positive terms, so its rounding grows with vocabulary size; with 100k-class vocabularies in float32 the tail probabilities lose several ULPs, and training-loss computations (which take `log` of the sum) amplify that — accumulate `d` in float32 for inference but prefer float64 (or the log-sum-exp path) for loss computation over large vocabularies.
