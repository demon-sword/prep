# Search a 2D Matrix — Medium — Classic exact search, flattened 2D (Binary Search)

**LC:** https://leetcode.com/problems/search-a-2d-matrix/
**NeetCode:** —
**Status:** `review`
**Generated:** ralph-dsa
**Last reviewed:** —
**Next review:** —

---

## Framing

### Trigger phrases
- search for **target** in an **m × n** matrix
- each **row sorted** left to right; **first element of row** > **last element of previous row**
- return **true/false** (not index) — O(log(m·n)) expected
- matrix behaves like one **sorted 1D array** when read row-major

### Constraints that matter
- m, n up to 100 — O(log(m·n)) required; O(m·n) scan works on small inputs but misses the pattern
- **-10⁴ ≤ matrix[i][j], target ≤ 10⁴** — values fit in int; no special overflow on values
- Matrix may be **empty** (m = 0 or n = 0) — handle before binary search
- Row-major flattening is valid **only** because the global sorted property holds (not just per-row sorted)

### Pattern
Classic exact search on a virtual 1D array — binary search index `0..m·n-1`, map `mid → (mid/cols, mid%cols)` to read the cell.

---

## Approach

### Invariant
If target exists in the matrix, its flattened index lies in `[left, right]`. Each comparison at virtual index `mid` eliminates half the remaining indices while preserving that property.

### Steps
1. If matrix is empty, return `false`.
2. Set `rows ← m`, `cols ← n`, `left ← 0`, `right ← rows * cols - 1`.
3. While `left <= right`:
   - `mid ← left + (right - left) / 2`.
   - `value ← matrix[mid / cols][mid mod cols]`.
   - If `value == target`, return `true`.
   - If `value < target`, search right half → `left ← mid + 1`.
   - Else search left half → `right ← mid - 1`.
4. Return `false` when search space is exhausted.

### Pseudocode skeleton
```
function searchMatrix(matrix, target):
    if matrix is empty or matrix[0] is empty:
        return false

    rows ← length(matrix)
    cols ← length(matrix[0])
    left ← 0
    right ← rows * cols - 1

    while left <= right:
        mid ← left + (right - left) / 2
        row ← mid / cols
        col ← mid mod cols
        value ← matrix[row][col]

        if value equals target:
            return true

        if value < target:
            left ← mid + 1
        else:
            right ← mid - 1

    return false
```

### Complexity
| | |
|-|-|
| **Time** | O(log(m·n)) — halve virtual search space each step |
| **Space** | O(1) — only index pointers; no copy of matrix |

---

## Tradeoffs

### Brute force
Nested loops over every cell until target found or matrix exhausted. O(m·n) time, O(1) space. Simple but ignores the global sorted structure; fails the intended logarithmic requirement.

### Why this pattern
The problem guarantees a **total order** across the whole matrix when traversed row-major (each row sorted, and row i+1 starts after row i ends). That is exactly a sorted array of length m·n with a different indexing scheme. Standard binary search applies unchanged after index-to-cell mapping.

### When NOT to use this
- **Only rows sorted, columns not** (e.g. Search a 2D Matrix II) — flattening breaks global order; use **staircase from top-right** or **two binary searches** (row then column).
- **Need cell coordinates** — same BS logic, but return `(row, col)` instead of boolean when you find a match.
- **Unsorted matrix** — binary search precondition fails; use hash set or linear scan.

---

## Pitfalls
- **Flattening when global order is missing** — if only rows are sorted independently, `matrix[mid/cols][mid%cols]` does not visit values in sorted order; BS gives wrong answers.
- **Wrong index mapping** — use `row = mid / cols` and `col = mid % cols` (not `mid / rows`); swapping rows and cols breaks cell lookup.
- **Empty matrix edge case** — accessing `matrix[0]` when `m = 0` throws; check length before reading `cols`.
- **Integer division for row** — `mid / cols` must truncate toward zero (floor for non-negative mid); language-specific float conversion can introduce off-by-one errors.
- **`while left < right` for exact target** — can miss the only matching cell; use `left <= right` for existence search.

---

## Similar problems
| Problem | Same idea? |
|---------|------------|
| [Binary Search](../problems/028-binary-search.md) | Same exact search on a truly 1D sorted array |
| [Search in Rotated Sorted Array](../problems/032-search-in-rotated-sorted-array.md) | BS variant when global sorted order is broken by rotation |
| [Find Minimum in Rotated Sorted Array](../problems/031-find-minimum-in-rotated-sorted-array.md) | BS on modified sorted structure — compare mid vs boundary |

---

## One-liner recall

> Treat matrix as sorted array of length m·n; BS on `[0, m·n-1]`, cell at `(mid/cols, mid%cols)`, discard half like 1D binary search.
