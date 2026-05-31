# Min Stack — Medium — Augmented stack (Stack)

**LC:** https://leetcode.com/problems/min-stack/
**NeetCode:** —
**Status:** `review`
**Generated:** ralph-dsa
**Last reviewed:** —
**Next review:** —

---

## Framing

### Trigger phrases
- design a **stack** that supports **push**, **pop**, **top**, and **getMin**
- retrieve the **minimum element in O(1)**
- all operations must be **constant time**
- "Min Stack" — classic augmented ADT design problem

### Constraints that matter
- Up to 3 × 10⁴ calls — O(1) per operation required; scanning the stack on `getMin` is O(n) and fails at scale
- Values can **repeat** — multiple equal minimums must be handled correctly on pop
- Negative numbers allowed — min tracking must work for any integer in range

### Pattern
Augmented stack — maintain a parallel min stack that stores the current minimum at each depth; push/pop both stacks in sync when the value equals the tracked min.

---

## Approach

### Invariant
After every operation, `mins.top` equals the minimum among all elements currently in `values`. Each entry on `mins` corresponds to one occurrence of that minimum at a particular stack depth (duplicates are pushed when a new equal min arrives).

### Steps
1. Maintain two stacks: `values` (all pushed elements) and `mins` (running minimum frontier).
2. **push(x):** append x to `values`; if `mins` is empty or x ≤ `mins.top`, append x to `mins`.
3. **pop():** remove top of `values`; if that value equals `mins.top`, also pop `mins`.
4. **top():** return top of `values` without removing.
5. **getMin():** return top of `mins`.

### Pseudocode skeleton
```
structure MinStack:
    values ← empty list
    mins ← empty list

    function push(x):
        append x to values
        if mins is empty or x ≤ mins.top:
            append x to mins

    function pop():
        v ← pop values
        if v equals mins.top:
            pop mins

    function top():
        return values.top

    function getMin():
        return mins.top
```

### Complexity
| | |
|-|-|
| **Time** | O(1) per push, pop, top, getMin |
| **Space** | O(n) — worst case all pushes are new minimums (decreasing sequence) |

---

## Tradeoffs

### Brute force
Store elements in a single stack; on `getMin`, scan all elements — O(n) per query. With up to 3 × 10⁴ mixed operations, worst-case O(n²) total time; violates the O(1) requirement.

### Why this pattern
The minimum only changes when you push a new smaller value or pop the current minimum. A second stack records "min at this depth" so `getMin` is always one peek. Each element is pushed/popped from `values` once and from `mins` at most once — amortized O(1).

### When NOT to use this
- **Only push and getMin, no pop** — a single variable tracking global min suffices; no parallel stack needed.
- **getMax instead of getMin** — same idea with a max stack (or store pairs `(val, minSoFar)` in one stack).
- **Median or k-th smallest in stream** — need heap or order-statistics structure, not a min stack.

---

## Pitfalls
- **Using `<` instead of `≤` when pushing to `mins`** — duplicate minimums (e.g. push 0, push 0, pop) leave `mins` empty while `values` still has a 0; `getMin` breaks. Push to `mins` when `x ≤ mins.top`.
- **Forgetting to pop `mins` when popping the current min** — `getMin` returns a value no longer in the stack.
- **Scanning on getMin** — works for small tests but fails the design constraint; interviewers expect O(1).
- **Storing only one copy of the min without count** — fails when multiple identical mins exist and you pop one of them.

---

## Similar problems
| Problem | Same idea? |
|---------|------------|
| [Valid Parentheses](../problems/021-valid-parentheses.md) | Stack ADT with push/pop discipline; no extra invariant |
| [Evaluate Reverse Polish Notation](../problems/023-evaluate-reverse-polish-notation.md) | Stack as evaluation engine; single stack, different operations |
| [Daily Temperatures](../problems/025-daily-temperatures.md) | Monotonic stack tracks dominance; min stack tracks extremum |

---

## One-liner recall

> Two stacks: push to `mins` when x ≤ min top; pop from `mins` when popped value equals min top; `getMin` = peek `mins`.
