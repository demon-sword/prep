# Search in Rotated Sorted Array — Medium — Rotated sorted search (Binary Search)

**LC:** https://leetcode.com/problems/search-in-rotated-sorted-array/
**NeetCode:** —
**Status:** `review`
**Generated:** ralph-dsa
**Last reviewed:** —
**Next review:** —

---

## Framing

### Trigger phrases
- **rotated** sorted array — find **index** of a given **target**
- array was sorted ascending then **pivot**ed; all values **unique**
- return index if found, **-1** if absent — O(log n) expected
- "search in rotated sorted array" — not just find minimum

### Constraints that matter
- n up to 5000 — O(log n) binary search required; linear scan is correct but misses the pattern
- **Distinct** elements — no duplicate-collapse edge cases (LC 81 is the follow-up with duplicates)
- Target may be anywhere in `[0, n-1]` or missing entirely
- At each step, **exactly one** of `[left..mid]` or `[mid..right]` is normally sorted (unless window is size 1)

### Pattern
Rotated sorted — target search via binary search: identify which half is sorted, then check whether target lies in that half's value range; discard the other half.

---

## Approach

### Invariant
If `target` exists in the original array, its index lies in `[left, right]`. Each iteration removes a half that cannot contain `target` while preserving that property.

### Steps
1. Set `left ← 0`, `right ← length(nums) - 1`.
2. While `left <= right`:
   - `mid ← left + (right - left) / 2`.
   - If `nums[mid] == target`, return `mid`.
   - If `nums[left] <= nums[mid]` — **left half** `[left..mid]` is sorted:
     - If `nums[left] <= target < nums[mid]`, target is in left half → `right ← mid - 1`.
     - Else → `left ← mid + 1`.
   - Else — **right half** `[mid..right]` is sorted:
     - If `nums[mid] < target <= nums[right]`, target is in right half → `left ← mid + 1`.
     - Else → `right ← mid - 1`.
3. Return `-1` when the window is empty.

**Why check sorted half first?** Rotation breaks global order but leaves one side monotonic. Range check `nums[left] <= target < nums[mid]` (or the right-side analogue) only works on the sorted half — applying it to the unsorted half gives wrong discards.

### Pseudocode skeleton
```
function searchRotated(nums, target):
    left ← 0
    right ← length(nums) - 1

    while left <= right:
        mid ← left + (right - left) / 2

        if nums[mid] equals target:
            return mid

        if nums[left] <= nums[mid]:
            // left half [left..mid] is sorted
            if nums[left] <= target and target < nums[mid]:
                right ← mid - 1
            else:
                left ← mid + 1
        else:
            // right half [mid..right] is sorted
            if nums[mid] < target and target <= nums[right]:
                left ← mid + 1
            else:
                right ← mid - 1

    return -1
```

### Complexity
| | |
|-|-|
| **Time** | O(log n) — halve search space each iteration |
| **Space** | O(1) — only left, right, mid pointers |

---

## Tradeoffs

### Brute force
Linear scan for `target`. O(n) time, O(1) space — works on small n but ignores sorted/rotated structure and fails when O(log n) is expected.

### Why this pattern
Same rotation insight as finding the minimum: one half is always normally sorted. Once you know which half is sorted, a constant-time range check tells you whether `target` can live there — enabling logarithmic discard without ever sorting or finding the pivot explicitly.

### When NOT to use this
- **Duplicates allowed** (LC 81) — `nums[left] == nums[mid]` makes "left half sorted" ambiguous; need `left ← left + 1` when equal or fall back to linear in worst case.
- **Need minimum only** — simpler pivot search with `left < right` and mid-vs-right compare ([Find Minimum in Rotated Sorted Array](../problems/031-find-minimum-in-rotated-sorted-array.md)).
- **Unsorted array** — no half is guaranteed sorted; use hash map or linear scan.

---

## Pitfalls
- **Using classic BS `nums[mid] < target → left = mid + 1`** — global order is broken; must first decide which half is sorted, then range-check target inside that half.
- **Off-by-one in range checks** — use `target < nums[mid]` on left sorted half and `target <= nums[right]` on right (strict on the side of `mid` already ruled out) to avoid infinite loops or skipping the answer.
- **`while left < right` instead of `left <= right`** — can exit before checking the last element; exact target search needs `left <= right`.
- **Assuming both halves sorted when `left == mid`** — two-element window still works: one half is trivially sorted; test with `[3,1]`, target `1`.

---

## Similar problems
| Problem | Same idea? |
|---------|------------|
| [Find Minimum in Rotated Sorted Array](../problems/031-find-minimum-in-rotated-sorted-array.md) | Same rotated structure — finds pivot/min instead of arbitrary target |
| [Binary Search](../problems/028-binary-search.md) | Classic discard-half; here you add "which half is sorted?" before comparing to target |
| [Search a 2D Matrix](../problems/029-search-a-2d-matrix.md) | Also maps index to value then BS — global order is intact there, broken here by rotation |

---

## One-liner recall

> BS with `left <= right`: if left half sorted, target in `[nums[left], nums[mid])` → go left else right; if right half sorted, target in `(nums[mid], nums[end]]` → go right else left; return -1 if window empties.
