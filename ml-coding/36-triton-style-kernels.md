# Emulate Triton-Style Blocked Kernels on CPU — Hard — gpu-kernels

**Contract:** `triton_style_add(x: np.ndarray, y: np.ndarray, block: int) -> np.ndarray and triton_style_affine_relu(x: np.ndarray, scale: float, bias: float, block: int) -> np.ndarray  # z = x + y; then relu(scale * x + bias)`
**Generated:** ralph-ml-coding

---

## Problem

Given one-dimensional vectors, emulate the Triton GPU programming model on the CPU. In Triton a kernel is launched over a grid of programs; each program computes its linear index via `program_id`, owns one contiguous block of `BLOCK` elements, loads that block (with a mask that disables out-of-range lanes in the tail block), computes, and stores the result back. No GPU exists in this environment and no Triton install is required: the launch geometry — grid sizing, per-program ranges, tail masking — is what is being rehearsed, executed as plain NumPy slice operations per program inside one shared launch helper. Two kernels are built on that helper: elementwise addition `z = x + y`, and a fused affine-plus-ReLU `z = relu(scale · x + bias)` that does in one pass what two kernels (a scale-add then a ReLU) would otherwise do in two.

This is asked because the jump from "NumPy one-liner" to "kernel that runs on an accelerator" is mostly about the partitioning discipline, and Triton is the gentlest real on-ramp to it. An emulation that sizes the grid with floor division instead of ceiling division silently drops the tail whenever the length is not a multiple of the block size — the single most common Triton beginner bug, and on device it corrupts silently rather than raising. An emulation without masking reads and writes past the end of the allocation; on the CPU that raises, on the GPU it reads a neighbour's memory. And writing the two kernels as separate launch loops instead of sharing one helper duplicates exactly the grid/mask logic that must stay identical across every kernel in a program — the fused kernel then exists to show why fusion matters (one pass over memory instead of two, with the intermediate never materialised), while the helper exists to show what stays shared.

**Input/output contract**

- `x`, `y` — shape `(n,)`, real numeric dtypes, `n >= 1`. For `triton_style_add` the shapes must match exactly; a mismatch raises `ValueError`. Non-1-D or empty inputs raise `ValueError`.
- `block` — the `BLOCK` compile-time constant: a positive integer. Zero or negative raises `ValueError`. It does not need to divide `n`; the tail program is masked.
- `scale`, `bias` — Python/NumPy scalars applied as `relu(scale · x + bias)`, elementwise, with `relu(v) = max(v, 0)`.
- Both functions return a fresh shape-`(n,)` array with dtype `np.result_type` of the inputs (plus the scalars for the affine kernel); inputs are never mutated. A non-contiguous input is handled by value.
- Both kernels route through one shared `_launch_grid(n, block)` helper that yields `(program_id, start, end)` triples — the CPU analogue of `program_id(axis=0)` times `BLOCK` — and every per-program slice is clamped to `[start, min(start + block, n)]`, the analogue of the Triton load/store mask.

**Edge cases that must hold**

- `block >= n` collapses the grid to a single program and still matches the NumPy one-liner exactly.
- `block = 1` launches `n` single-lane programs and still matches exactly.
- Lengths that are not multiples of `block` produce a correct tail with no overrun and no dropped elements.
- Integer inputs stay exact through both kernels (ReLU of ints is ints); float32 inputs round-trip without widening.
- `scale = 0` reduces the affine kernel to `relu(bias)` broadcast — constant output, still correct.

## Hints

<details><summary>Nudge</summary>

How many programs does a length-`n` vector need when each program owns `block` elements — and what is the range owned by the last program when `block` does not divide `n`?

</details>

<details><summary>Approach</summary>

Write `_launch_grid` first: `grid = ceil(n / block)` via `(n + block − 1) // block`, yielding `(pid, pid * block, min(pid * block + block, n))` per program. Then each kernel allocates its output, loops over the helper, loads the input slices for the program's range, applies the arithmetic (add, or scale-add-ReLU) to that slice only, and stores it into the matching output range. The mask is the `min` clamp — program code must never index past `end`. Verify each kernel against its one-line NumPy equivalent on divisible, non-divisible, single-program, and single-lane grids.

</details>

<details><summary>Key insight</summary>

Ceiling division plus a clamped tail range is the entire launch discipline: the grid covers every element exactly once, and the mask makes the overrun lanes no-ops instead of out-of-bounds accesses. Once the helper owns that logic, each kernel body is three lines (load, compute, store) and fusion is a free choice — the affine and the ReLU compose inside the compute line, so the intermediate vector is never written to memory at all, which is the bandwidth saving that motivates kernel fusion on real hardware.

</details>

## Solution

```python
import numbers

import numpy as np


def _launch_grid(n, block):
    """Yield (program_id, start, end) for each program in the grid.

    The CPU analogue of Triton's grid = (cdiv(n, BLOCK),) with
    pid = tl.program_id(0) and offs = pid * BLOCK + arange(BLOCK).
    Ceiling division guarantees coverage; clamping end to n is the
    analogue of the tl.load/tl.store mask that disables tail lanes.
    """
    if int(block) <= 0:
        raise ValueError(f"block must be positive, got {block}")
    block = int(block)
    grid = (int(n) + block - 1) // block  # ceil(n / block), never floors away a tail
    for pid in range(grid):
        start = pid * block
        end = min(start + block, n)       # the mask: lanes past n do nothing
        yield pid, start, end


def _check_1d(v, name):
    v = np.asarray(v)
    if v.ndim != 1:
        raise ValueError(f"{name} must be 1-D, got shape {v.shape}")
    if v.shape[0] == 0:
        raise ValueError(f"{name} must be non-empty")
    return v


def triton_style_add(x, y, block):
    """z = x + y, one block per emulated Triton program.

    Mirrors: pid = program_id(0); offs = pid*BLOCK + arange(BLOCK);
    mask = offs < n; z = load(x+offs, mask) + load(y+offs, mask);
    store(z_ptr+offs, z, mask)."""
    x = _check_1d(x, "x")
    y = _check_1d(y, "y")
    if x.shape != y.shape:
        raise ValueError(f"shape mismatch: {x.shape} vs {y.shape}")
    n = x.shape[0]
    out = np.empty(n, dtype=np.result_type(x, y))
    for _pid, start, end in _launch_grid(n, block):
        # Load-compute-store per program; slices never exceed [start, end),
        # so the tail program touches only its valid lanes (the mask).
        out[start:end] = x[start:end] + y[start:end]
    return out


def triton_style_affine_relu(x, scale, bias, block):
    """z = relu(scale * x + bias), fused into a single emulated kernel.

    Mirrors a Triton kernel that folds the activation into the same
    program as the affine: one load of x, one store of z, and the
    scale-add-max compose in registers (here: in the slice expression),
    so the affine intermediate is never materialised the way two
    separate kernels would materialise it."""
    x = _check_1d(x, "x")
    if not isinstance(scale, numbers.Real) or not isinstance(bias, numbers.Real):
        raise ValueError("scale and bias must be real scalars")
    n = x.shape[0]
    out_dtype = np.result_type(x.dtype, type(scale), type(bias))
    # Integer inputs keep an exact integer path; floats compute in their own width.
    out = np.empty(n, dtype=out_dtype if np.issubdtype(out_dtype, np.integer)
                   else np.result_type(x.dtype, np.float32))
    for _pid, start, end in _launch_grid(n, block):
        tile = x[start:end] * scale + bias   # fused: no intermediate stored
        out[start:end] = np.maximum(tile, 0)  # the ReLU, same program
    return out
```

## Self-test

```python
import numpy as np

gen = np.random.default_rng(53)

# 1. Both kernels match their NumPy one-liners on divisible and tail grids.
for n in (1, 2, 7, 16, 17, 100, 1000):
    xf = (gen.normal(size=n) * 5).astype(np.float32)
    yf = (gen.normal(size=n) * 5).astype(np.float32)
    for block in (1, 2, 3, 16, 32, n, n + 10):
        assert np.array_equal(triton_style_add(xf, yf, block), xf + yf), \
            f"add mismatch at n={n} block={block}"
        for scale, bias in ((2.0, -1.0), (0.0, 0.5), (-1.5, 0.0)):
            got = triton_style_affine_relu(xf, scale, bias, block)
            want = np.maximum(xf * scale + bias, 0)
            assert np.allclose(got, want, atol=1e-6), \
                f"affine_relu mismatch at n={n} block={block} s={scale} b={bias}"

# 2. Hand-computed add with a tail: n=5, block=2 -> programs [0:2] [2:4] [4:5].
assert np.array_equal(
    triton_style_add(np.array([1., 2., 3., 4., 5.]),
                     np.array([10., 20., 30., 40., 50.]), 2),
    np.array([11., 22., 33., 44., 55.])), "tail-block add wrong"

# 3. Hand-computed fused kernel: relu(2x - 3) over [0, 1, 2, 3].
assert np.array_equal(
    triton_style_affine_relu(np.array([0., 1., 2., 3.]), 2.0, -3.0, 2),
    np.array([0., 0., 1., 3.])), "fused affine_relu wrong"
# scale=0 broadcasts relu(bias).
assert np.array_equal(
    triton_style_affine_relu(np.array([-4., 9.]), 0.0, -2.0, 8),
    np.array([0., 0.])), "scale=0 affine_relu wrong"

# 4. Integer exactness, dtypes, and non-contiguous inputs.
xi = gen.integers(-10, 10, size=37)
yi = gen.integers(-10, 10, size=37)
assert np.array_equal(triton_style_add(xi, yi, 8), xi + yi), "int add inexact"
assert np.array_equal(
    triton_style_affine_relu(xi, 2, -3, 8),
    np.maximum(xi * 2 - 3, 0)), "int affine_relu inexact"
xd = gen.normal(size=20)
assert triton_style_add(xd, xd.copy(), 7).dtype == np.result_type(xd, xd), \
    "add dtype wrong"
xs = np.ascontiguousarray(gen.normal(size=40))[::2]  # strided, n=20
ys = np.ascontiguousarray(gen.normal(size=40))[::2]
assert np.array_equal(triton_style_add(xs, ys, 6), xs + ys), \
    "non-contiguous inputs mishandled"

# 5. The grid helper itself: full coverage, no overlap, tail clamped.
for n, block in ((20, 6), (17, 16), (5, 2), (9, 9), (100, 7)):
    ranges = list(_launch_grid(n, block))
    assert ranges[0][1] == 0 and ranges[-1][2] == n, "grid does not span [0, n)"
    for (p0, s0, e0), (p1, s1, e1) in zip(ranges, ranges[1:]):
        assert e0 == s1, f"gap/overlap between programs {p0} and {p1}"
        assert 0 < e0 - s0 <= block and 0 < e1 - s1 <= block, \
            "program range exceeds block"
    assert len(ranges) == (n + block - 1) // block, \
        "grid size is not ceil(n / block)"

# 6. Contract violations raise.
for bad_block in (0, -3):
    for fn in (lambda b: triton_style_add(np.ones(4), np.ones(4), b),
               lambda b: triton_style_affine_relu(np.ones(4), 1.0, 0.0, b)):
        try:
            fn(bad_block)
        except ValueError:
            pass
        else:
            raise AssertionError(f"block={bad_block} should have raised ValueError")
for bad_x, bad_y in ((np.ones((2, 2)), np.ones((2, 2))), (np.ones(0), np.ones(0)),
                     (np.ones(3), np.ones(4))):
    try:
        triton_style_add(bad_x, bad_y, 4)
    except ValueError:
        pass
    else:
        raise AssertionError(f"no ValueError for shapes {bad_x.shape}, {bad_y.shape}")
try:
    triton_style_affine_relu(np.ones((2, 2)), 1.0, 0.0, 4)
except ValueError:
    pass
else:
    raise AssertionError("2-D input to affine_relu should have raised ValueError")

print("ok")
```

## Complexity

| | |
|-|-|
| **Time** | O(n) — each element is loaded, computed, and stored a constant number of times; the grid loop adds O(n / block) program iterations of pure overhead |
| **Space** | O(n) for the output; O(block) transient slice per program (a view, not a copy) |

The complexity is deliberately boring — elementwise kernels are entirely memory-bandwidth-bound, so the only number that matters is passes over memory. That is the whole argument for fusion: separate scale-add and ReLU kernels make four passes (read, write, read, write) while the fused kernel makes two (read `x`, write `z`), nearly doubling effective bandwidth on large vectors. The block size changes nothing asymptotically here; on real hardware it trades occupancy (many small programs keep more SMs fed) against per-program SRAM and launch overhead, and the tail mask costs one comparison per lane — negligible next to the memory traffic it protects.

## Follow-ups

- **What does the mask argument do in a real Triton kernel, and what breaks when you omit it?** — The mask predicates every lane whose index overruns the tensor: masked loads return a safe default (often 0) and masked stores are skipped. Omit it and the tail program reads a neighbour allocation's bytes into the computation and writes its outputs over someone else's memory — silent corruption on device, where nothing bounds-checks for you.
- **How do grid size and block size trade off occupancy against per-program SRAM usage?** — Smaller blocks mean more programs, which spreads more evenly over SMs (better occupancy and load balance) but each program still pays fixed launch/setup cost and holds its tiles in SRAM; larger blocks amortise that overhead and vectorise better but fewer fit concurrently per SM, and a block whose working set exceeds SRAM simply fails to launch — hence powers of two between 32 and 1024, tuned per kernel.
- **When is fusing the affine and ReLU into one kernel a win over two kernels?** — Whenever the operation is memory-bound rather than compute-bound: fusion halves global-memory passes and never materialises the intermediate, which dominates for elementwise chains. It stops winning when the fused working set no longer fits in SRAM/registers (spilling back to memory undoes the saving) or when the intermediate is consumed by multiple downstream kernels anyway.
