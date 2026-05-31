# Car Fleet — Medium — Stack simulation (merge dominated intervals)

**LC:** https://leetcode.com/problems/car-fleet/
**NeetCode:** —
**Status:** `review`
**Generated:** ralph-dsa
**Last reviewed:** —
**Next review:** —

---

## Framing

### Trigger phrases
- count **car fleets** arriving at a **target** — cars cannot pass each other
- faster car **catches up** to slower car ahead and travels as one fleet
- merge intervals / dominance from **right to left** on a line
- each car has **position** and **speed**; fleet speed is the slower car's speed

### Constraints that matter
- 1 ≤ n ≤ 10⁴ — O(n log n) sort is fine; O(n²) pairwise simulation is unnecessary
- Positions are distinct and strictly less than target — no cars start at destination
- Arrival time is `(target - position) / speed` — floating point; use `>` not `>=` for "slower than fleet ahead" (equal time means same fleet)
- Process cars **closest to target first** (sort by position descending) so "fleet ahead" is already on the stack

### Pattern
Stack simulation — sort by position descending; stack holds fleet **arrival times**; push only when current car is slower than the fleet immediately ahead (later arrival time).

---

## Approach

### Invariant
After processing cars from right to left, the stack holds one arrival time per distinct fleet, **monotonic increasing from bottom to top** (farthest-right fleet arrives earliest at bottom). The top is the slowest-arriving fleet among all processed cars. A car merges into the fleet ahead iff its own arrival time ≤ stack top.

### Steps
1. Zip `position[i]` with `speed[i]` into `(pos, spd)` pairs; sort by `pos` **descending** (nearest target first).
2. Initialize empty `stack` of arrival times.
3. For each `(pos, spd)` in sorted order:
   - `time ← (target - pos) / spd`
   - If stack empty or `time > stack.top`: push `time` (new fleet — cannot catch the one ahead).
   - Else: do nothing (catches fleet ahead; inherits its slower effective arrival).
4. Return `length(stack)`.

### Pseudocode skeleton
```
function carFleet(target, position, speed):
    n ← length(position)
    cars ← empty list of (position, speed) pairs

    for i from 0 to n - 1:
        append (position[i], speed[i]) to cars

    sort cars by position descending

    stack ← empty list   // fleet arrival times; top = slowest fleet seen so far

    for each (pos, spd) in cars:
        time ← (target - pos) / spd

        if stack empty or time > stack.top:
            push time onto stack
        // else: merges into fleet ahead — stack unchanged

    return length(stack)
```

### Complexity
| | |
|-|-|
| **Time** | O(n log n) — sort dominates; O(n) stack pass |
| **Space** | O(n) — stack and car pairs in worst case (every car is its own fleet) |

---

## Tradeoffs

### Brute force
Simulate each car catching the next: for each pair, compute catch-up time and merge fleets with union-find or repeated passes until stable. Correct but O(n²) or worse — overkill for n ≤ 10⁴ and harder to implement cleanly.

### Why this pattern
Once sorted right-to-left, only the **immediate car ahead** matters: if you cannot catch it before target, you form a new fleet; otherwise you inherit its arrival time. A stack of fleet times captures this in one linear scan — same "dominance from the right" idea as monotonic stack problems.

### When NOT to use this
- Cars can **pass** each other — each car arrives independently; answer is n (or count distinct arrival times without merging).
- Need **actual fleet groupings** or catch-up positions, not just count — requires storing car indices per fleet, not just times.
- **Dynamic** speed/position updates — static sort-once stack does not apply.

---

## Pitfalls
- **Sorting ascending instead of descending** — you must process nearest-to-target first so "fleet ahead" is already resolved on the stack.
- **Pushing every arrival time without comparing to stack top** — overcounts fleets; a faster car behind must merge when `time ≤ stack.top`.
- **Using integer division for arrival time** — `(target - pos) / spd` must be floating point; truncating can misclassify merge vs new fleet at boundary cases.
- **Comparing speeds directly instead of arrival times** — a car farther back may be faster yet still arrive later because of distance; always compare `(target - pos) / speed`.

---

## Similar problems
| Problem | Same idea? |
|---------|------------|
| [Daily Temperatures](../problems/025-daily-temperatures.md) | Monotonic stack scan; each element interacts with stack top once |
| [Largest Rectangle in Histogram](../problems/027-largest-rectangle-in-histogram.md) | Stack holds unresolved "active" elements; pop/merge on dominance condition |
| [Trapping Rain Water](../problems/014-trapping-rain-water.md) | Process from ends with running max; dominance of taller boundary (different structure, same "who blocks whom" intuition) |

---

## One-liner recall

> Sort cars by position descending; stack of arrival times — push `(target - pos) / speed` only if it exceeds stack top (new fleet), else merge into fleet ahead.
