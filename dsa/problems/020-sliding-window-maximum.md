# Sliding Window Maximum — Hard — Fixed window + monotonic deque (Sliding Window)

**LC:** https://leetcode.com/problems/sliding-window-maximum/
**NeetCode:** —
**Status:** `review`
**Generated:** ralph-dsa
**Last reviewed:** —
**Next review:** —

---

## Framing

### Trigger phrases
- maximum in every **window of size k** sliding along the array
- return an array of length `n - k + 1` with the max of each contiguous subarray of length k
- "sliding window maximum" — explicit fixed window + aggregate query per position
- deque / monotonic queue when brute-force max per window is too slow

### Constraints that matter
- n up to 10⁵, k up to n → O(n·k) brute force TLE; need O(n) with a deque
- nums can be negative — comparisons are numeric, not sign-specific tricks
- k = 1 is trivial (each element is its own window max); k = n is one window

### Pattern
Fixed window of size k — maintain a **monotonic decreasing deque of indices** so the front always holds the index of the current window's maximum; evict indices outside `[right - k + 1 .. right]` from the front.

---

## Approach

### Invariant
Deque stores indices `i` with `nums[i]` strictly decreasing from front to back (front = largest in deque). Every index in the deque lies in the current window `[right - k + 1 .. right]` once `right >= k - 1`. The maximum of the window is always `nums[deque.front]`.

### Steps
1. Initialize empty deque (list of indices). Result list empty.
2. For `right` from 0 to n - 1:
   - While deque not empty and `nums[deque.back] <= nums[right]`, pop back — smaller values can never be window max while `right` is in the window.
   - Push `right` onto deque.
   - If `deque.front <= right - k`, pop front — index left of window start.
   - If `right >= k - 1`, append `nums[deque.front]` to result (window `[right - k + 1 .. right]` is complete).
3. Return result.

### Pseudocode skeleton
```
function maxSlidingWindow(nums, k):
    n ← length(nums)
    if k equals 1:
        return copy of nums
    if k equals n:
        return list containing max(nums)

    deque ← empty list of indices
    result ← empty list

    for right from 0 to n - 1:
        while deque not empty and nums[deque.back] <= nums[right]:
            remove last element from deque

        append right to deque

        windowStart ← right - k + 1
        while deque not empty and deque.front < windowStart:
            remove first element from deque

        if right >= k - 1:
            append nums[deque.front] to result

    return result
```

### Complexity
| | |
|-|-|
| **Time** | O(n) — each index pushed once and popped at most once from deque |
| **Space** | O(k) — deque holds at most k indices |

---

## Tradeoffs

### Brute force
For each start `i` from 0 to n - k, scan `nums[i .. i + k - 1]` for the maximum. O(n·k) time; with n = 10⁵ and k = 10⁴ this is ~10⁹ operations — TLE.

### Why this pattern
The window only shifts by one index per step. The previous window's max either stays valid (still inside range) or must be replaced by a larger value that entered on the right. A decreasing deque keeps candidates for "future window max" in order; popping from the back removes values that can never win once a larger or equal value appears to their right.

### When NOT to use this
- **Variable-length** window with a validity constraint → variable sliding window + freq map, not deque max.
- **Sum or average** over window k → fixed window with running sum, no deque.
- **Global maximum** (no window) → single scan `max(nums)`, O(n) O(1).
- **Min in each window** → same deque pattern with **increasing** monotonic order (pop while `nums[back] >= nums[right]`).

---

## Pitfalls
- **Storing values instead of indices in the deque** — cannot tell if the max index left the window; always store indices and compare `deque.front` to `right - k`.
- **Using `deque.front <= right - k` without `windowStart`** — off-by-one: window `[right - k + 1 .. right]` evicts indices `< right - k + 1`, i.e. `front < right - k + 1` or `front <= right - k` depending on convention; stick to one rule and test k = 1.
- **Appending to result before the first full window** — only record when `right >= k - 1`.
- **Forgetting to pop equal values from the back** — use `<=` when maintaining decreasing order so duplicate max values don't block eviction of stale smaller indices correctly.
- **Re-scanning the deque for max each step** — front is always the answer; O(1) per window after maintenance.

---

## Similar problems
| Problem | Same idea? |
|---------|------------|
| [Permutation in String](../problems/018-permutation-in-string.md) | Fixed window size k sliding one step; different state (freq match vs deque max) |
| [Minimum Window Substring](../problems/019-minimum-window-substring.md) | Contiguous window optimization; variable length + validity instead of fixed k + max query |
| [Best Time to Buy and Sell Stock](../problems/015-best-time-to-buy-and-sell-stock.md) | One-pass O(n) with auxiliary state (running min vs monotonic deque) |

---

## One-liner recall

> Decreasing deque of indices: pop smaller backs, drop front if outside window, append `nums[front]` once `right >= k - 1`.
