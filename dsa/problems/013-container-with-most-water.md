# Container With Most Water — Medium — Greedy opposite ends (Two Pointers)

**LC:** https://leetcode.com/problems/container-with-most-water/
**NeetCode:** —
**Status:** `review`
**Generated:** ralph-dsa
**Last reviewed:** —
**Next review:** —

---

## Framing

### Trigger phrases
- "find two lines that together with the x-axis form a container"
- "container holds the **most water**"
- "return the **maximum amount of water** a container can store"
- "you may not slant the container" — area is bounded by the **shorter** vertical line
- n vertical lines at x = 1, 2, …, n with heights given in an array

### Constraints that matter
- n up to 10⁵ → O(n²) checking all pairs TLE; O(n) greedy two pointers is the target
- **Array is not sorted** — but opposite ends still work because the greedy move rule is about height, not monotonic sum
- Area formula: `width × min(height[left], height[right])` where `width = right - left`
- Lines cannot be reused — pointers only move inward, never outward

### Pattern
Greedy opposite ends — start at widest window; record area; always advance the pointer at the **shorter** line because the taller side cannot improve area once width shrinks.

---

## Approach

### Invariant
For current `(left, right)`, any optimal container using the shorter line as one boundary must pair it with some index between `left` and `right`. Moving the shorter pointer inward discards only pairings that cannot beat the best area already seen: width decreases, and height was already capped by that shorter line, so keeping it fixed while shrinking width cannot increase area.

### Steps
1. Set `left ← 0`, `right ← n - 1`, `best ← 0`.
2. While `left < right`:
   - Compute `width ← right - left`.
   - Compute `h ← min(height[left], height[right])`.
   - Update `best ← max(best, width × h)`.
   - If `height[left] < height[right]`, increment `left`; else decrement `right` (move the shorter side; on tie, either side is safe).
3. Return `best`.

### Pseudocode skeleton
```
function maxArea(height):
    left ← 0
    right ← length(height) - 1
    best ← 0

    while left < right:
        width ← right - left
        h ← min(height[left], height[right])
        best ← max(best, width * h)

        if height[left] < height[right]:
            left ← left + 1
        else:
            right ← right - 1

    return best
```

### Complexity
| | |
|-|-|
| **Time** | O(n) — each pointer moves at most n steps; one area evaluation per iteration |
| **Space** | O(1) — only indices and running max |

---

## Tradeoffs

### Brute force
Check every pair `(i, j)` with `i < j`, compute `min(height[i], height[j]) × (j - i)`, track maximum — O(n²) time, O(1) space. Straightforward but fails at n = 10⁵.

### Why this pattern
The bottleneck height is always the shorter of the two walls. When the window shrinks, width drops, so to beat the current best you need a taller bottleneck — that requires moving past the shorter wall and exploring pairings with a potentially taller partner. Moving the taller wall cannot raise `min(h_left, h_right)` while width only decreases, so those configurations are safe to skip.

### When NOT to use this
- **Trapping Rain Water** — asks for water *between* bars above each index, not area between two boundaries; same two-pointer shape but different accumulation rule (running max heights).
- **Need the actual pair of indices** — same O(n) scan works; store `(left, right)` whenever `best` updates.
- **3D container variants** — different geometry; not a two-line max-area problem.

---

## Pitfalls
- **Moving the taller pointer** — width shrinks and `min` height stays capped by the shorter side; you skip the only pairings that might improve area (those involving the shorter line with a taller inner line).
- **Using `(height[left] + height[right])` or `max` instead of `min`** — area is limited by the shorter wall; using max overcounts.
- **Nested loops out of habit** — correct but O(n²); interview expects the greedy shrink proof.
- **Confusing with Two Sum II move rules** — here movement is driven by **height comparison**, not sum vs target.

---

## Similar problems
| Problem | Same idea? |
|---------|------------|
| [Two Sum II](../problems/011-two-sum-ii.md) | Same opposite-ends loop; move rule uses sum vs target instead of shorter height |
| [Trapping Rain Water](../problems/014-trapping-rain-water.md) | Same pointer machinery; accumulates trapped water with running max heights, not max area |
| [3Sum](../problems/012-3sum.md) | Opposite ends on a subarray; inner loop maximizes coverage via sum, not area |

---

## One-liner recall

> Opposite ends: area = width × min(heights); always move the shorter line inward — the taller side cannot help once width shrinks.
