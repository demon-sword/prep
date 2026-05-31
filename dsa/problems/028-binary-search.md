# Binary Search — Easy — Classic exact search (Binary Search)

**LC:** https://leetcode.com/problems/binary-search/
**NeetCode:** —
**Status:** `review`
**Generated:** ralph-dsa
**Last reviewed:** —
**Next review:** —

---

## Framing

### Trigger phrases
- find **target** in a **sorted** array of integers
- return **index** of target or **-1** if not present
- array is sorted in **ascending order** — O(log n) expected
- "binary search" in the title — canonical template problem

### Constraints that matter
- n up to 10⁴ — O(log n) binary search is required; O(n) linear scan works but misses the point
- **Distinct** values not guaranteed — duplicates still work with standard exact search
- **-10⁴ ≤ nums[i], target ≤ 10⁴** — no overflow issues on values; watch index overflow in `mid` calculation

### Pattern
Classic exact search — maintain `[left, right]` on a sorted array; compare `mid` to target; discard the half where target cannot lie.

---

## Approach

### Invariant
If target exists in `nums`, its index is always within `[left, right]`. Each iteration shrinks the interval by at least half while preserving that property.

### Steps
1. Set `left ← 0`, `right ← length(nums) - 1`.
2. While `left <= right`:
   - Compute `mid ← left + (right - left) / 2` (overflow-safe).
   - If `nums[mid] == target`, return `mid`.
   - If `nums[mid] < target`, target must be in the right half → `left ← mid + 1`.
   - Else target must be in the left half → `right ← mid - 1`.
3. Return `-1` when the loop exits (search space exhausted).

### Pseudocode skeleton
```
function search(nums, target):
    left ← 0
    right ← length(nums) - 1

    while left <= right:
        mid ← left + (right - left) / 2

        if nums[mid] equals target:
            return mid

        if nums[mid] < target:
            left ← mid + 1
        else:
            right ← mid - 1

    return -1
```

### Complexity
| | |
|-|-|
| **Time** | O(log n) — halve search space each iteration |
| **Space** | O(1) — only three index pointers |

---

## Tradeoffs

### Brute force
Scan left to right until `nums[i] == target` or end of array. O(n) time, O(1) space. Trivial to code but ignores the sorted property; fails the intended O(log n) requirement at scale.

### Why this pattern
Sorted order means: all elements left of any index are ≤ that index, all right are ≥. One comparison at `mid` eliminates half the remaining indices. With n = 10⁴, at most ~14 comparisons vs up to 10⁴ for linear scan.

### When NOT to use this
- **Unsorted array** — binary search precondition fails; use hash map for O(1) lookup or sort first O(n log n).
- **Rotated sorted array** — standard discard-half logic breaks; compare which half is sorted ([Search in Rotated Sorted Array](../problems/032-search-in-rotated-sorted-array.md)).
- **Find first/last occurrence of duplicate** — exact search returns any match; need boundary variants (`left < right` with `hi = mid` or `lo = mid + 1`).

---

## Pitfalls
- **`mid = (left + right) / 2` overflow** — on languages with large indices, use `left + (right - left) / 2`.
- **`while left < right` for exact target** — can skip the only matching index when `left == right`; use `left <= right` for exact search.
- **Off-by-one on discard** — after `nums[mid] < target`, set `left = mid + 1` (not `mid`); after `nums[mid] > target`, set `right = mid - 1` (not `mid`), or the loop may not shrink.
- **Returning -1 inside the loop** — only return -1 after the loop; returning early on `nums[mid] != target` is wrong.

---

## Similar problems
| Problem | Same idea? |
|---------|------------|
| [Search a 2D Matrix](../problems/029-search-a-2d-matrix.md) | Same exact search; flatten row-major index to 1D |
| [Search in Rotated Sorted Array](../problems/032-search-in-rotated-sorted-array.md) | BS variant — decide which half is sorted before discarding |
| [Find Minimum in Rotated Sorted Array](../problems/031-find-minimum-in-rotated-sorted-array.md) | BS on rotated array — compare `mid` vs `right` to find pivot |

---

## One-liner recall

> `left <= right`, safe mid, go right if `nums[mid] < target` else left; return mid on hit, -1 when done.
