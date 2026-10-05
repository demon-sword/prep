# Implement Naive and Tiled Matrix Multiplication — Medium — gpu-kernels

**Contract:** `matmul_naive(A: np.ndarray, B: np.ndarray) -> np.ndarray and matmul_tiled(A: np.ndarray, B: np.ndarray, block: int) -> np.ndarray  # C = A @ B`
**Generated:** ralph-ml-coding

---

## Problem

Given two 2-D arrays `A` of shape `(m, k)` and `B` of shape `(k, n)`, compute `C = A @ B` twice: once with the plain triple loop, and once with a tiled (blocked) loop nest that processes the product in `block × block` output tiles. Both implementations run CPU-only here, written as explicit Python loops over the tile structure rather than as a single NumPy call. That is deliberate: the thing being rehearsed is the tiling discipline a GPU thread block follows, not the hardware itself. On device each block loads one tile of `A` and one tile of `B` into fast on-chip shared memory, multiplies them, accumulates, and moves to the next tile pair down the `k` dimension; this file reproduces exactly that loop structure, with the "shared memory" being an explicit small staging buffer per tile.

This is asked because tiling is the single most important performance idea in GPU computing, and it is easy to describe but surprisingly easy to get subtly wrong. A tiled matmul that drops edge tiles silently produces a correct-looking matrix with a band of zeros along the right and bottom edges whenever the problem size is not a multiple of the block size. A tiled matmul that accumulates in the input dtype can drift from the reference on float32 inputs, because the summation order changed and the rounding errors accumulate differently. And a tiled matmul whose inner loop reads strided memory in the wrong order can be slower than the naive version it was meant to beat — the FLOP count is identical either way, so all of the speedup comes from the memory access pattern, which is precisely what the code must get right.

**Input/output contract**

- `A` — shape `(m, k)`, `B` — shape `(k, n)`, any real numeric dtype. Inner dimensions must agree; a mismatch raises `ValueError`. One-dimensional or zero-size inputs raise `ValueError`.
- `block` — a positive integer tile size. Non-positive values raise `ValueError`. It does not need to divide any dimension; edge tiles are handled, not assumed away.
- `matmul_naive(A, B)` returns `C` of shape `(m, n)` computed by the `i, j, p` triple loop.
- `matmul_tiled(A, B, block)` returns the same `C`, computed tile by tile: for each `block × block` output tile, loop over `k` in slabs of width `block`, stage the current `A`-slab and `B`-slab into local tile buffers, and accumulate their partial product into the output tile.
- Both return a fresh array; neither mutates its inputs. The output dtype follows `np.result_type(A, B)`. Float inputs accumulate in float64 working precision and cast back once at the end (float32 inputs therefore track a float64 reference); integer inputs accumulate exactly in Python-int precision and cast back once at the end, so no float rounding ever touches the integer path.

**Edge cases that must hold**

- Sizes that are not multiples of `block` produce complete, correct edge tiles — no dropped rows or columns, no zero padding leaking into the result.
- `block` larger than any dimension degenerates to a single tile and still matches the reference.
- `block = 1` degenerates to the naive loop order and still matches the reference.
- float32 inputs must match a float64 reference more closely than a pure-float32 accumulation does; the tiled path therefore accumulates tile partials in float64 and casts back once, at the end.
- Non-contiguous inputs (a transposed view, a strided slice) are handled by value, not by accident of layout.

## Hints

<details><summary>Nudge</summary>

The naive version is three nested loops and one multiply-add. What is the smallest change to that nest that turns it into tiles — and which two of the three loops does the block size actually partition?

</details>

<details><summary>Approach</summary>

Build the naive `C[i, j] = sum_p A[i, p] * B[p, j]` first and test it against `np.matmul`. Then wrap it in two more loops: iterate `i0` over rows and `j0` over columns in steps of `block`, and for each output tile iterate `p0` over the shared dimension in steps of `block`, accumulating the partial product of the `(i0, p0)` slab of `A` with the `(p0, j0)` slab of `B`. Each slab slice is the "tile staged into shared memory" — copy it into a local buffer first so the structure mirrors device code, and clamp every slice end with `min(start + block, dim)` so edge tiles shrink instead of overrunning.

</details>

<details><summary>Key insight</summary>

Tiling changes nothing about the arithmetic — every `(i, j, p)` triple is still visited exactly once — so correctness reduces to two checks: the tile loops cover every output element (the `min` clamping is what guarantees this on edge tiles), and nothing is accumulated twice or skipped along `k` (the `p0` slabs must partition `0..k`, not overlap). The float32 subtlety is that reordering a long summation changes rounding; accumulating each tile partial into a float64 buffer and casting once at the end buys back the lost precision for the cost of one wider accumulator, which is exactly what real kernels do with FP32 accumulation of FP16 inputs.

</details>

## Solution

```python
import numpy as np


def _check_2d(A, B):
    A = np.asarray(A)
    B = np.asarray(B)
    if A.ndim != 2 or B.ndim != 2:
        raise ValueError(
            f"both inputs must be 2-D, got shapes {A.shape} and {B.shape}")
    if A.shape[1] != B.shape[0]:
        raise ValueError(
            f"inner dimensions disagree: {A.shape} @ {B.shape}")
    if 0 in A.shape or 0 in B.shape:
        raise ValueError("zero-size inputs are not supported")
    return A, B


def matmul_naive(A, B):
    """C = A @ B via the plain i, j, p triple loop.

    This is the loop nest one GPU thread would execute for its single
    output element, written out for the whole matrix. Integer inputs take
    an exact Python-int path; floats accumulate in float64 working
    precision so the naive path is the reference-quality baseline the
    tiled path is compared against.
    """
    A, B = _check_2d(A, B)
    m, k = A.shape
    n = B.shape[1]
    out_dtype = np.result_type(A, B)
    if np.issubdtype(out_dtype, np.integer):
        C = np.zeros((m, n), dtype=object)
        for i in range(m):
            for j in range(n):
                s = 0
                for p in range(k):
                    s += int(A[i, p]) * int(B[p, j])
                C[i, j] = s
        return np.asarray(C, dtype=out_dtype)
    C = np.zeros((m, n), dtype=np.float64)
    for i in range(m):
        for j in range(n):
            s = 0.0
            for p in range(k):
                s += float(A[i, p]) * float(B[p, j])
            C[i, j] = s
    return C.astype(out_dtype, copy=False)


def matmul_tiled(A, B, block):
    """C = A @ B tile by tile, mirroring a GPU thread-block kernel.

    Each block x block output tile is accumulated from successive slabs
    along k. The slab slices are first copied into small local buffers —
    the CPU stand-in for staging a tile into on-chip shared memory —
    then multiplied into the output tile. Edge tiles shrink via min()
    clamping instead of assuming divisibility. Integer inputs accumulate
    exactly in Python-int precision; floats accumulate tile partials in
    float64 with a single cast back at the very end.
    """
    if int(block) <= 0:
        raise ValueError(f"block must be positive, got {block}")
    block = int(block)
    A, B = _check_2d(A, B)
    m, k = A.shape
    n = B.shape[1]
    out_dtype = np.result_type(A, B)
    if np.issubdtype(out_dtype, np.integer):
        # Exact integer path: same tile/slab traversal, but the inner
        # tile product uses Python ints so large int64 values (beyond
        # 2**53) never pass through float64.
        C = np.zeros((m, n), dtype=object)
        for i0 in range(0, m, block):
            i1 = min(i0 + block, m)          # shrinks on the bottom edge tile
            for j0 in range(0, n, block):
                j1 = min(j0 + block, n)      # shrinks on the right edge tile
                for p0 in range(0, k, block):
                    p1 = min(p0 + block, k)  # slabs partition 0..k exactly
                    for i in range(i0, i1):
                        for j in range(j0, j1):
                            s = 0
                            for p in range(p0, p1):
                                s += int(A[i, p]) * int(B[p, j])
                            C[i, j] = C[i, j] + s
        return np.asarray(C, dtype=out_dtype)
    # One wide accumulator for the whole output: tile partials add into
    # float64, and the single cast back happens at the very end.
    C = np.zeros((m, n), dtype=np.float64)
    for i0 in range(0, m, block):
        i1 = min(i0 + block, m)          # shrinks on the bottom edge tile
        for j0 in range(0, n, block):
            j1 = min(j0 + block, n)      # shrinks on the right edge tile
            for p0 in range(0, k, block):
                p1 = min(p0 + block, k)  # slabs partition 0..k exactly
                # Stage both tiles, as a block would copy into shared memory.
                a_tile = np.array(A[i0:i1, p0:p1], dtype=np.float64)
                b_tile = np.array(B[p0:p1, j0:j1], dtype=np.float64)
                C[i0:i1, j0:j1] += a_tile @ b_tile
    return C.astype(out_dtype, copy=False)
```

## Self-test

```python
import numpy as np

gen = np.random.default_rng(11)

# 1. Square, tall, wide, and non-multiple-of-block shapes agree with BLAS.
shapes = [(9, 9, 9), (10, 6, 14), (14, 10, 6), (7, 5, 3), (1, 4, 1), (16, 16, 16)]
for m, k, n in shapes:
    A = gen.normal(size=(m, k))
    B = gen.normal(size=(k, n))
    ref = A @ B
    assert np.allclose(matmul_naive(A, B), ref, atol=1e-9), \
        f"naive mismatch at {(m, k, n)}"
    for block in (1, 2, 3, 4, 5, 32):
        got = matmul_tiled(A, B, block)
        assert got.shape == (m, n), f"tiled shape {got.shape} != {(m, n)}"
        assert np.allclose(got, ref, atol=1e-9), \
            f"tiled mismatch at {(m, k, n)} block={block}"

# 2. Hand-computed 2x3 @ 3x2 with an awkward block size (edge tiles both ways).
A = np.array([[1., 2., 3.], [4., 5., 6.]])
B = np.array([[7., 8.], [9., 10.], [11., 12.]])
want = np.array([[58., 64.], [139., 154.]])
assert np.array_equal(matmul_naive(A, B), want), "naive 2x3@3x2 wrong"
assert np.array_equal(matmul_tiled(A, B, 2), want), "tiled 2x3@3x2 block=2 wrong"

# 3. Precision: the tiled float32 path must track float64 closely.
Af = gen.normal(size=(48, 64)).astype(np.float32)
Bf = gen.normal(size=(64, 40)).astype(np.float32)
ref64 = Af.astype(np.float64) @ Bf.astype(np.float64)
err_tiled = np.abs(matmul_tiled(Af, Bf, 16).astype(np.float64) - ref64).max()
err_f32 = np.abs((Af @ Bf).astype(np.float64) - ref64).max()
assert err_tiled <= err_f32 + 1e-6, \
    f"tiled fp32 accumulation worse than BLAS sgemm: {err_tiled} vs {err_f32}"
assert err_tiled < 1e-4, f"tiled fp32 error too large: {err_tiled}"

# 4. Integer inputs stay exact, including values beyond 2**53 that
#    float64 cannot represent (the integer path never touches float).
Ai = np.array([[2**60 + 1, 3], [5, 7]])
Bi = np.array([[1, 0], [0, 1]])
for block in (1, 2, 7):
    for fn in (matmul_naive, lambda X, Y: matmul_tiled(X, Y, block)):
        got = fn(Ai, Bi)
        assert got.dtype == np.result_type(Ai, Bi), "int out dtype wrong"
        assert np.array_equal(got, Ai), f"int exactness failed block={block}"
Ci = (np.arange(12).reshape(4, 3) - 5)
Di = (np.arange(15).reshape(3, 5) - 7)
assert np.array_equal(matmul_naive(Ci, Di), Ci @ Di), "int naive mismatch"
assert np.array_equal(matmul_tiled(Ci, Di, 2), Ci @ Di), "int tiled mismatch"

# 5. Non-contiguous inputs behave identically (handled by value, not layout).
At = np.ascontiguousarray(gen.normal(size=(12, 8))).T  # (8, 12) strided view
Bt = np.ascontiguousarray(gen.normal(size=(12, 18)))[:, ::2]  # (12, 9) strided
assert np.allclose(matmul_tiled(At, Bt, 5), At @ Bt, atol=1e-9), \
    "non-contiguous inputs mishandled"

# 6. Contract violations raise instead of silently miscomputing.
for bad_A, bad_B in [(np.ones((2, 3)), np.ones((4, 2))),
                     (np.ones(3), np.ones((3, 3))),
                     (np.zeros((0, 3)), np.zeros((3, 2)))]:
    for fn in (matmul_naive, lambda X, Y: matmul_tiled(X, Y, 2)):
        try:
            fn(bad_A, bad_B)
        except ValueError:
            pass
        else:
            raise AssertionError(f"no ValueError for shapes {np.shape(bad_A)}, {np.shape(bad_B)}")
for bad_block in (0, -4):
    try:
        matmul_tiled(np.ones((2, 2)), np.ones((2, 2)), bad_block)
    except ValueError:
        pass
    else:
        raise AssertionError(f"block={bad_block} should have raised ValueError")

print("ok")
```

## Complexity

| | |
|-|-|
| **Time** | O(m·k·n) — identical FLOP count for both paths; every `(i, j, p)` triple is visited exactly once |
| **Space** | O(m·n) for the output, plus O(block²) staging per tile in the tiled path |

The FLOP count is the same either way, so the constant is the whole story. The naive nest streams all of `B` once per output row — O(m·k·n) memory traffic against a slow level of the hierarchy — while the tiled nest reuses each staged tile `block` times, cutting traffic to roughly O(m·k·n / block). On a GPU that reuse is what keeps the data in shared memory instead of round-tripping to HBM on every use; the price is the `block²` staging buffers and the edge-tile clamping logic. Python-loop overhead dominates both paths here (this file is for rehearsing the structure, not for speed), which is why the inner tile multiply itself is still delegated to `@` — the tile traversal order is the part under test.

## Follow-ups

- **Why does tiling speed up matmul on a GPU even though it performs the same number of FLOPs?** — Because matmul is memory-bound at small tile sizes: the naive order reloads each element of `B` once per output row from slow HBM, while a tile staged into shared memory is reused `block` times after a single load, so arithmetic intensity rises with the block size and the kernel stops waiting on the memory bus.
- **How do you pick the block size, and what breaks when it is too large?** — The tile has to fit in the block's shared-memory budget alongside the accumulator, so too large a block either fails to launch or reduces occupancy (fewer blocks resident per SM); too small a block wastes the reuse opportunity and leaves memory bandwidth on the table — 16×16 and 32×32 are the usual starting points, tuned against the profiler.
- **Where does Tensor-Core / split-K tiling diverge from this basic scheme?** — Tensor Cores replace the scalar multiply-add with 16×16×16 matrix-fragment instructions, so tiles become fragment-shaped and the `k` loop gets an extra level; split-K additionally partitions `k` across blocks and finishes with a small reduction over partial sums, trading one extra synchronisation for parallelism when `m·n` alone cannot fill the GPU.
