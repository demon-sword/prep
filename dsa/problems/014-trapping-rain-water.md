# Trapping Rain Water — Hard — Greedy opposite ends + running max (Two Pointers)

**LC:** https://leetcode.com/problems/trapping-rain-water/
**NeetCode:** —
**Status:** `review`
**Generated:** ralph-dsa
**Last reviewed:** —
**Next review:** —

---

## Framing

### Trigger phrases
- "compute how much water it can trap after raining"
- "elevation map" / "non-negative integer array representing an elevation map"
- "water trapped between bars"
- "each bar width is 1" — volume at an index depends on **walls to the left and right**, not a single pair
- "return the **total** amount of trapped water"

### Constraints that matter
- n up to 2×10⁴ → O(n²) per-index scanning TLE; O(n) required
- Heights are **non-negative**; water level at `i` is `min(maxLeft, maxRight) - height[i]` when that min exceeds `height[i]`
- Need **at least three** bars for any trap — return 0 for n < 3
- O(1) extra space variant is standard interview answer (two pointers); prefix-max arrays are O(n) space alternative

### Pattern
Greedy opposite ends — maintain `leftMax` and `rightMax` while shrinking the window; process the side with the **smaller** current bar height first, because the opposite side’s running max is already a safe bound for that index.

---

## Approach

### Invariant
At each step, `leftMax` is the maximum height seen in `[0 .. left]` and `rightMax` in `[right .. n-1]`. If `height[left] <= height[right]`, then `rightMax >= height[right] >= height[left]`, so the water level above `left` is limited by `leftMax` (the weaker bound is on the left). Accumulate `leftMax - height[left]` when `leftMax` exceeds current height, then advance `left`. Symmetric when the right side is lower.

### Steps
1. If `length(height) < 3`, return 0.
2. Set `left ← 0`, `right ← n - 1`, `leftMax ← 0`, `rightMax ← 0`, `water ← 0`.
3. While `left < right`:
   - If `height[left] <= height[right]`:
     - `leftMax ← max(leftMax, height[left])`
     - `water ← water + (leftMax - height[left])`
     - `left ← left + 1`
   - Else:
     - `rightMax ← max(rightMax, height[right])`
     - `water ← water + (rightMax - height[right])`
     - `right ← right - 1`
4. Return `water`.

### Pseudocode skeleton
```
function trap(height):
    n ← length(height)
    if n < 3:
        return 0

    left ← 0
    right ← n - 1
    leftMax ← 0
    rightMax ← 0
    water ← 0

    while left < right:
        if height[left] <= height[right]:
            leftMax ← max(leftMax, height[left])
            water ← water + (leftMax - height[left])
            left ← left + 1
        else:
            rightMax ← max(rightMax, height[right])
            water ← water + (rightMax - height[right])
            right ← right - 1

    return water
```

### Complexity
| | |
|-|-|
| **Time** | O(n) — each index visited once by a pointer |
| **Space** | O(1) — only running maxes and counters |

---

## Tradeoffs

### Brute force
For each index `i`, scan left for max height and right for max height, add `min(leftPeak, rightPeak) - height[i]` if positive — O(n²) time, O(1) space. Correct but too slow.

### Prefix max arrays (alternative optimal time)
One pass build `prefixMax[i]` and `suffixMax[i]`; for each `i`, add `min(prefixMax[i], suffixMax[i]) - height[i]` when positive — O(n) time, O(n) space. Easier to explain per-index formula; use when space is not constrained.

### Why this pattern
Same opposite-ends machinery as Container With Most Water, but accumulation uses **running peaks** instead of max area. Processing the lower side first guarantees the unprocessed side’s max is at least as tall as the current bar, so you can commit trapped water at that index without knowing the full opposite profile.

### When NOT to use this
- **Container With Most Water** — maximize area between two lines; move shorter wall for greedy area, not sum of per-index water.
- **Histogram largest rectangle** — needs stack/monotonic stack, not two pointers on ends.
- **2D trapping rain** — grid DP / heap variants; 1D two-pointer does not generalize.

---

## Pitfalls
- **Updating max after subtracting wrong order** — must set `leftMax ← max(leftMax, height[left])` then add `(leftMax - height[left])`; using old `leftMax` before update undercounts on rising slopes.
- **Processing the taller side first** — you cannot know the binding water level for an index until the smaller-side bound is known; always handle `height[left] <= height[right]` branch first.
- **Reusing Container With Most Water move rule** — moving shorter height for *area* is different from processing lower side for *trap*; trap adds water then advances the lower pointer.
- **Forgetting n < 3** — no valley exists; return 0 early to avoid empty loop confusion.

---

## Similar problems
| Problem | Same idea? |
|---------|------------|
| [Container With Most Water](../problems/013-container-with-most-water.md) | Same two-pointer shrink; maximizes area, does not sum per-cell water |
| [3Sum](../problems/012-3sum.md) | Opposite ends on a subarray; sum target instead of running max bounds |
| [Two Sum II](../problems/011-two-sum-ii.md) | Opposite ends; monotonic sum move instead of peak accumulation |

---

## One-liner recall

> Opposite ends with `leftMax`/`rightMax`: process the lower side first, add `peak - height` at that index, then advance — O(n) O(1).
