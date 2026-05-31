# Two Sum II — Medium — Opposite ends (Two Pointers)

**LC:** https://leetcode.com/problems/two-sum-ii-input-array-is-sorted/
**NeetCode:** —
**Status:** `review`
**Generated:** ralph-dsa
**Last reviewed:** —
**Next review:** —

---

## Framing

### Trigger phrases
- "array is sorted in **non-decreasing order**"
- "find two numbers such that they add up to a specific **target**"
- "return the **indices** of the two numbers" (1-indexed here)
- "exactly one solution exists" / "you may not use the same element twice"

### Constraints that matter
- Sorted ascending → moving `left` right increases sum; moving `right` left decreases sum — monotonic control
- n up to 3×10⁴ → O(n²) nested loops TLE; O(n) two pointers or O(n) hash map both work
- **1-indexed** answer required — add 1 to zero-based pointer values before returning
- Exactly one solution → no need to collect all pairs or handle duplicates in output

### Pattern
Opposite ends on sorted array — `left` at start, `right` at end; compare `nums[left] + nums[right]` to target; shrink from the side that must change to approach the target.

---

## Approach

### Invariant
If a valid pair exists in the current window `[left .. right]`, it remains discoverable by only moving pointers inward. When `sum < target`, every pair involving `nums[left]` with any index ≤ `left` is too small (array sorted), so `left` must advance. When `sum > target`, every pair involving `nums[right]` with any index ≥ `right` is too large, so `right` must retreat.

### Steps
1. Set `left ← 0`, `right ← length(nums) - 1`.
2. While `left < right`:
   - Compute `sum ← nums[left] + nums[right]`.
   - If `sum == target`, return `[left + 1, right + 1]` (1-indexed).
   - If `sum < target`, increment `left` (need a larger value).
   - Else decrement `right` (need a smaller value).
3. Return none if no pair found (problem guarantees one solution, so loop always exits early with a hit).

### Pseudocode skeleton
```
function twoSum(numbers, target):
    left ← 0
    right ← length(numbers) - 1

    while left < right:
        sum ← numbers[left] + numbers[right]

        if sum equals target:
            return [left + 1, right + 1]

        if sum < target:
            left ← left + 1
        else:
            right ← right - 1

    return none
```

### Complexity
| | |
|-|-|
| **Time** | O(n) — each pointer moves at most n steps; never backtracks |
| **Space** | O(1) — only two indices; no hash map |

---

## Tradeoffs

### Brute force
Check every pair `(i, j)` with `i < j` — O(n²) time, O(1) space. Simple but fails at n = 3×10⁴.

### Why this pattern
Sorting is already given, so the sum at `(left, right)` tells you exactly which pointer to move. No hash map needed; pointer movement is deterministic and each index is visited once. This is the canonical warm-up for 3Sum's inner two-pointer loop.

### When NOT to use this
- **Unsorted array (Two Sum I)** — increasing `left` does not guarantee a larger complement from the other side; use hash map for O(n) one-pass lookup.
- **Need all pairs summing to target** — single opposite-ends scan finds one pair per anchor; enumerate with nested loops or fix one index and scan.
- **Array cannot be sorted** (e.g. must preserve original index order for reporting) — sort-with-indices or hash map instead.

---

## Pitfalls
- **Returning 0-indexed positions** — LeetCode 167 expects `[index1, index2]` with 1-based indexing; off-by-one fails all tests.
- **Moving the wrong pointer when `sum < target`** — advancing `right` or decrementing `left` breaks monotonicity and can skip the answer; too small always means `left++`.
- **Using hash map out of habit** — works in O(n) but wastes O(n) space when the sorted property already enables O(1) space two pointers.

---

## Similar problems
| Problem | Same idea? |
|---------|------------|
| [Two Sum](../problems/003-two-sum.md) | Same goal (pair to target) but unsorted → hash complement, not two pointers |
| [3Sum](../problems/012-3sum.md) | Inner loop is identical opposite-ends scan with target `0 - nums[i]` |
| [Valid Palindrome](../problems/010-valid-palindrome.md) | Same converging pointer mechanics; here compare numeric sum instead of chars |

---

## One-liner recall

> Sorted array, two ends: sum too small → left++; too big → right--; equal → return 1-indexed pair.
