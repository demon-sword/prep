# Koko Eating Bananas — Medium — Search on answer (Binary Search)

**LC:** https://leetcode.com/problems/koko-eating-bananas/
**NeetCode:** —
**Status:** `review`
**Generated:** ralph-dsa
**Last reviewed:** —
**Next review:** —

---

## Framing

### Trigger phrases
- **minimize** eating speed / rate such that Koko finishes in **H hours**
- each hour she eats from **one pile** only; partial pile takes **one full hour**
- piles are independent — total time is sum of per-pile hours
- "smallest integer k" / "minimum speed" with a feasibility check

### Constraints that matter
- n up to 10⁴, pile sizes up to 10⁹, h up to 10⁹ — cannot simulate hour-by-hour; need O(n log max(pile))
- Answer k is an **integer** in `[1, max(piles)]` — at most max pile size is ever needed per pile
- Feasibility is **monotone**: if speed k works, any speed ≥ k also works → binary search on answer
- Each pile contributes `ceil(pile / speed)` hours — must use ceiling, not floor

### Pattern
Search on answer — binary search the minimum speed `k` in `[1, max(piles)]`; at each candidate, run `canFinish(k)` that sums ceiling hours across piles.

---

## Approach

### Invariant
The true minimum feasible speed lies in `[lo, hi]`. If `canFinish(mid)` is true, `mid` is feasible and the answer is ≤ mid; if false, the answer is > mid.

### Steps
1. Set `lo ← 1`, `hi ← max(piles)`.
2. While `lo < hi`:
   - `mid ← lo + (hi - lo) / 2`.
   - If `canFinish(piles, h, mid)`, shrink right → `hi ← mid`.
   - Else need faster eating → `lo ← mid + 1`.
3. Return `lo` (first feasible speed).

**canFinish(piles, h, speed):**
1. `hours ← 0`.
2. For each `pile`, add `ceil(pile / speed)` to `hours`; return false early if `hours > h`.
3. Return true if total `hours ≤ h`.

### Pseudocode skeleton
```
function minEatingSpeed(piles, h):
    lo ← 1
    hi ← max(piles)

    while lo < hi:
        mid ← lo + (hi - lo) / 2
        if canFinish(piles, h, mid):
            hi ← mid
        else:
            lo ← mid + 1

    return lo

function canFinish(piles, h, speed):
    hours ← 0
    for pile in piles:
        hours ← hours + ceil(pile / speed)
        if hours > h:
            return false
    return true
```

### Complexity
| | |
|-|-|
| **Time** | O(n log M) where M = max(piles) — each BS step runs O(n) feasibility check |
| **Space** | O(1) — only lo/hi/mid and running hour sum |

---

## Tradeoffs

### Brute force
Try every speed k from 1 to max(piles); for each k, simulate all piles and sum hours. O(n · M) time where M can be 10⁹ — TLE. Same feasibility logic, no search structure.

### Why this pattern
Feasibility flips once: speeds below the minimum needed fail; at and above it succeed. That monotone predicate turns "find minimum k" into binary search over a discrete range, cutting O(M) candidates to O(log M).

### When NOT to use this
- **No monotone predicate** — if faster speed could somehow increase total hours (not true here), BS on answer is invalid; prove monotonicity first.
- **Need the schedule** (which pile each hour) — BS only finds k, not the assignment; greedy pile-by-pile simulation is separate.
- **Continuous speed** — problem asks for integer k; floating mid without integer boundaries causes infinite loops.

---

## Pitfalls
- **Floor instead of ceil** — pile of 7 at speed 3 needs 3 hours (3+3+1), not 2; use `ceil(pile / speed)` or `(pile + speed - 1) / speed`.
- **Wrong hi bound** — `hi = sum(piles)` is safe but slow; `hi = max(piles)` is tight because one pile never needs more than its size per hour.
- **`while lo <= hi` with wrong updates for minimize** — use `lo < hi` with `hi = mid` when feasible and `lo = mid + 1` when not; mixing variants returns off-by-one.
- **Skipping monotonicity check** — always verify: if k works, k+1 works; otherwise binary search discards the true answer.

---

## Similar problems
| Problem | Same idea? |
|---------|------------|
| [Binary Search](../problems/028-binary-search.md) | Core BS loop structure — here applied to answer space not array indices |
| [Find Minimum in Rotated Sorted Array](../problems/031-find-minimum-in-rotated-sorted-array.md) | Also finds a minimum via `lo < hi` boundary search |
| [Median of Two Sorted Arrays](../problems/034-median-of-two-sorted-arrays.md) | Another BS where the search variable is not a direct array index |

---

## One-liner recall

> BS speed in `[1, max(piles)]`; `can(k)` = sum of `ceil(pile/k)` ≤ h; if feasible shrink hi else raise lo; return lo.
