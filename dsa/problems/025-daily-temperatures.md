# Daily Temperatures — Medium — Monotonic stack (next greater)

**LC:** https://leetcode.com/problems/daily-temperatures/
**NeetCode:** —
**Status:** `review`
**Generated:** ralph-dsa
**Last reviewed:** —
**Next review:** —

---

## Framing

### Trigger phrases
- how many **days until a warmer** temperature
- **next greater element** to the right (distance in indices, not value)
- for each index, find nearest index to the right with **strictly larger** value
- "span" or wait time until condition met — classic monotonic stack

### Constraints that matter
- 1 ≤ n ≤ 10⁵ — O(n²) nested scans per index will TLE; need O(n) single pass
- Answer is **days to wait** (index difference), not the warmer temperature value
- Strict inequality: equal temps do **not** count as warmer — stack stays decreasing until strictly higher day appears

### Pattern
Monotonic stack (decreasing) of indices — store pending days waiting for a warmer day; when current temp breaks the order, pop and assign span `i - j`.

---

## Approach

### Invariant
Stack holds indices of days not yet resolved, in **strictly decreasing** temperature order (bottom = oldest unresolved, top = most recent). Every index on the stack has `answer[j] == 0` until popped. When `temps[i]` is warmer than `temps[stack.top]`, that top index’s next warmer day is `i`.

### Steps
1. Initialize `answer` as array of n zeros and empty `stack` of indices.
2. Scan `i` from 0 to n − 1:
   - While stack not empty and `temps[i] > temps[stack.top]`:
     - `j ← pop stack`
     - `answer[j] ← i - j`
   - Push `i` onto stack (still waiting for a warmer day to the right).
3. Indices left on stack at end have no warmer day ahead — already 0 in `answer`.
4. Return `answer`.

### Pseudocode skeleton
```
function dailyTemperatures(temps):
    n ← length(temps)
    answer ← array of n zeros
    stack ← empty list of indices   // decreasing temps: top = latest unresolved day

    for i from 0 to n - 1:
        while stack not empty and temps[i] > temps[stack.top]:
            j ← pop stack
            answer[j] ← i - j

        push i onto stack

    return answer
```

### Complexity
| | |
|-|-|
| **Time** | O(n) — each index pushed once and popped at most once |
| **Space** | O(n) — stack size in worst case (strictly decreasing entire array) |

---

## Tradeoffs

### Brute force
For each index `i`, scan `j = i + 1 .. n - 1` until `temps[j] > temps[i]`, then set `answer[i] = j - i`. Correct but O(n²) — fails at n = 10⁵.

### Why this pattern
The “next greater to the right” structure is exactly what a **decreasing monotonic stack** amortizes: each day waits on the stack until a later day warms it, then all consecutive cooler pending days below it are resolved in one forward scan.

### When NOT to use this
- Need the **value** of the next greater element, not distance — same stack, store `temps[j]` or peek after pop.
- Next greater on a **circular** array — duplicate array or modulo index with extra pass.
- **Next smaller** — flip comparison to `temps[i] < temps[stack.top]` and use increasing monotonic stack.
- Dynamic updates to temperatures — stack on static array does not apply; segment tree or similar.

---

## Pitfalls
- **Using `>=` instead of `>`** when comparing to stack top — equal temperatures must not pop; those days still wait for a strictly warmer day.
- **Storing temperatures on the stack instead of indices** — cannot compute `answer[j] = i - j` without original positions.
- **Setting answer on push instead of pop** — the warmer day is the current `i`, but the resolved index is the one popped (`j`), not `i`.
- **Scanning left from each index** — works for “next greater to the left” with a reversed pass or different stack discipline; this problem asks for days to the **right**.

---

## Similar problems
| Problem | Same idea? |
|---------|------------|
| [Largest Rectangle in Histogram](../problems/027-largest-rectangle-in-histogram.md) | Monotonic stack of indices; pop when current bar breaks increasing order; width from boundaries |
| [Car Fleet](../problems/026-car-fleet.md) | Stack simulation with dominance from the right; merge/skip by comparing to top |
| [Sliding Window Maximum](../problems/020-sliding-window-maximum.md) | Monotonic deque for extremum in a window; same “each element enters/exits once” amortized idea |

---

## One-liner recall

> Decreasing index stack: while today is warmer than stack top, pop and set answer[pop] = i − pop; push i.
