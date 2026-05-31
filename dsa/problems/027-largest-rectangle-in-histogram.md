# Largest Rectangle in Histogram — Hard — Monotonic stack (rectangle width at pop)

**LC:** https://leetcode.com/problems/largest-rectangle-in-histogram/
**NeetCode:** —
**Status:** `review`
**Generated:** ralph-dsa
**Last reviewed:** —
**Next review:** —

---

## Framing

### Trigger phrases
- **largest rectangle** area in a **histogram** of bar heights
- max area of rectangle whose **height** equals one bar and **width** spans contiguous bars (all bars in width ≥ that height)
- bars in a row; rectangle cannot skip bars — width is a contiguous index range
- classic **monotonic stack** capstone — pop when current bar is shorter; width from stack boundaries

### Constraints that matter
- 1 ≤ n ≤ 10⁵ — O(n²) trying every pair of bars as left/right bounds will TLE
- Heights are non-negative integers; width can be 0 only if array empty (not in typical constraints)
- Area = `height × width` where `height` is the popped bar and `width` is count of indices where every bar ≥ that height
- **Sentinel** pass (virtual height 0 at index `n`) flushes remaining stack in one loop — avoids separate cleanup

### Pattern
Monotonic stack (increasing) of indices — when current height breaks increasing order, pop index `j`, compute max rectangle with height `heights[j]` and width bounded by current `i` (right) and new stack top (left).

---

## Approach

### Invariant
Stack holds indices of bars not yet “closed,” in **strictly increasing** height order (bottom = leftmost open tall bar, top = rightmost). For each pop at index `j`, the first shorter bar to the right is current `i`; the first shorter bar to the left is `heights[stack.top]` after pop (if any). Every bar is pushed once and popped once.

### Steps
1. Initialize empty `stack` of indices and `best ← 0`.
2. Loop `i` from `0` to `n` (inclusive — `i == n` uses height `0` as sentinel):
   - `h ← heights[i]` if `i < n`, else `0`.
   - While stack not empty and `h < heights[stack.top]`:
     - `j ← pop stack`
     - `height ← heights[j]`
     - `left ← stack.top + 1` if stack not empty, else `0`
     - `width ← i - left`
     - `best ← max(best, height × width)`
   - If `i < n`, push `i` onto stack.
3. Return `best`.

### Pseudocode skeleton
```
function largestRectangleArea(heights):
    n ← length(heights)
    stack ← empty list of indices   // increasing heights
    best ← 0

    for i from 0 to n:
        if i < n:
            h ← heights[i]
        else:
            h ← 0   // sentinel: flush all bars

        while stack not empty and h < heights[stack.top]:
            j ← pop stack
            barHeight ← heights[j]
            if stack not empty:
                left ← stack.top + 1
            else:
                left ← 0
            width ← i - left
            best ← max(best, barHeight * width)

        if i < n:
            push i onto stack

    return best
```

### Complexity
| | |
|-|-|
| **Time** | O(n) — each index pushed once, popped once; sentinel adds one extra iteration |
| **Space** | O(n) — stack holds increasing subsequence of indices in worst case |

---

## Tradeoffs

### Brute force
For each bar `j` as rectangle height, expand left and right while adjacent bars ≥ `heights[j]`, then area = `heights[j] × (right - left + 1)`. Correct but O(n²) — fails at n = 10⁵.

### Why this pattern
Each bar’s maximum-width rectangle is fixed the moment a **shorter** bar appears on the right (current `i`) and on the left (next stack top after pop). The increasing stack defers that calculation until boundaries are known — same amortized O(n) discipline as “next greater,” but width uses **both** neighbors.

### When NOT to use this
- **2D maximal rectangle** in a binary matrix — reduce rows to 1D histogram per row, then run this per row (stack still applies per row).
- Need **all** maximal rectangles, not just global max — different bookkeeping on pop.
- Heights change dynamically online — static monotonic stack does not apply without rebuild.

---

## Pitfalls
- **Width = `i - j` only** after popping `j` — wrong when taller bars sit between `j` and the true left boundary; use `left = stack.top + 1` (or 0 if empty) **after** pop.
- **Storing heights on the stack instead of indices** — cannot recover width boundaries; always store indices and read `heights[idx]`.
- **Skipping sentinel flush** — bars left on stack at end never get a right boundary; append virtual `i = n` with `h = 0` to pop them all.
- **Using decreasing stack discipline from Daily Temperatures** — this problem needs **increasing** stack; pop when current `h` is **less than** stack top height.

---

## Similar problems
| Problem | Same idea? |
|---------|------------|
| [Daily Temperatures](../problems/025-daily-temperatures.md) | Monotonic stack of indices; pop when current element breaks order; assign answer at pop |
| [Car Fleet](../problems/026-car-fleet.md) | Stack resolves “who is still active” in one pass; merge/skip by comparing to top |
| [Trapping Rain Water](../problems/014-trapping-rain-water.md) | Bar heights and bounded width between taller boundaries; different two-pointer, same height-line intuition |

---

## One-liner recall

> Increasing index stack; on shorter bar (or sentinel 0), pop, area = heights[pop] × (i − (stack.top + 1 or 0)); push index after while-loop.
