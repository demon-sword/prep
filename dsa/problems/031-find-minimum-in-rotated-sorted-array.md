# Find Minimum in Rotated Sorted Array — Medium — Rotated sorted pivot (Binary Search)

**LC:** https://leetcode.com/problems/find-minimum-in-rotated-sorted-array/
**NeetCode:** —
**Status:** `review`
**Generated:** ralph-dsa
**Last reviewed:** —
**Next review:** —

---

## Framing

### Trigger phrases
- **rotated** sorted array — find the **minimum** element
- array was sorted ascending then **pivot**ed at some index
- O(log n) required — no linear scan
- all elements **unique** (LC 153) — simplifies mid vs end comparison

### Constraints that matter
- n up to 5000 — O(log n) binary search expected; O(n) scan works but misses the pattern
- **Distinct** values — when `nums[mid] > nums[right]`, the minimum is strictly in `(mid, right]`; no duplicate collapse at pivot
- Array is non-empty; rotation may be 0 (fully sorted) — algorithm still returns `nums[0]`
- Compare against `nums[right]`, not `nums[left]`, to decide which half contains the pivot/minimum

### Pattern
Rotated sorted — pivot search via binary search: compare `nums[mid]` to `nums[right]` to know which half still contains the rotation drop; shrink with `left < right` until `left` points at the minimum.

---

## Approach

### Invariant
The minimum index always lies in `[left, right]`. Each iteration discards a half that cannot contain the minimum while preserving that property.

### Steps
1. Set `left ← 0`, `right ← length(nums) - 1`.
2. While `left < right`:
   - `mid ← left + (right - left) / 2`.
   - If `nums[mid] > nums[right]`: the drop (pivot) is to the right of `mid` → minimum is in `(mid, right]` → `left ← mid + 1`.
   - Else: minimum is at `mid` or in `[left, mid)` → `right ← mid` (keep `mid` as candidate).
3. Return `nums[left]` — when `left == right`, that index is the minimum.

**Why compare to `right`?** When `nums[mid] <= nums[right]`, the right half `[mid..right]` is normally sorted (no pivot inside it), so the smallest value in the current window is at or left of `mid`. When `nums[mid] > nums[right]`, the pivot lies strictly right of `mid`.

### Pseudocode skeleton
```
function findMin(nums):
    left ← 0
    right ← length(nums) - 1

    while left < right:
        mid ← left + (right - left) / 2

        if nums[mid] > nums[right]:
            // pivot is in (mid, right]; min cannot be at or left of mid
            left ← mid + 1
        else:
            // min is at mid or in [left, mid)
            right ← mid

    return nums[left]
```

### Complexity
| | |
|-|-|
| **Time** | O(log n) — halve search space each iteration |
| **Space** | O(1) — only left, right, mid pointers |

---

## Tradeoffs

### Brute force
Scan the array once, track running minimum. O(n) time, O(1) space — correct but ignores the sorted/rotated structure and fails when interview expects O(log n).

### Why this pattern
Rotation leaves at least one half `[left..mid]` or `[mid..right]` normally sorted. Comparing `mid` to `right` identifies which side still contains the pivot in O(1), enabling logarithmic discard — same halving idea as classic binary search but on "where is the disorder" instead of "where is the target."

### When NOT to use this
- **Duplicates allowed** (LC 154) — `nums[mid] == nums[right]` can make both halves look sorted; need `right ← right - 1` or linear fallback when equal.
- **Need the pivot index** — return `left` (same as min index here); if only rotation count matters, same algorithm.
- **Search for a target value** — finding min is a pivot problem; searching a value uses a different branch (check which half is sorted, then whether target lies in it) — see [Search in Rotated Sorted Array](../problems/032-search-in-rotated-sorted-array.md).

---

## Pitfalls
- **`right ← mid - 1` when `nums[mid] <= nums[right]`** — can skip the minimum at `mid`; must use `right ← mid` because `mid` might be the answer.
- **`while left <= right` with exact-target updates** — boundary search for min/max uses `left < right`; mixing with classic `left <= right` causes off-by-one or early exit on two-element arrays.
- **Comparing `nums[mid]` to `nums[left]` instead of `nums[right]`** — ambiguous when left half is the long sorted run; the mid-vs-right rule is consistent for finding minimum.
- **Assuming rotation always exists** — fully sorted array has `nums[mid] <= nums[right]` always; loop still converges to index 0 correctly.

---

## Similar problems
| Problem | Same idea? |
|---------|------------|
| [Search in Rotated Sorted Array](../problems/032-search-in-rotated-sorted-array.md) | Same rotated structure — extends pivot logic to find a target index |
| [Binary Search](../problems/028-binary-search.md) | Same halving loop; here the predicate is "is pivot to the right of mid?" not equality with target |
| [Koko Eating Bananas](../problems/030-koko-eating-bananas.md) | Also uses `left < right` boundary search — different predicate but same shrink pattern |

---

## One-liner recall

> BS with `left < right`: if `nums[mid] > nums[right]` go right (`left = mid + 1`), else min at or left of mid (`right = mid`); return `nums[left]`.
