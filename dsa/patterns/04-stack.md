# 04. Stack (NeetCode category)

LIFO structure for matching nested symbols, evaluating postfix expressions, and monotonic scans that answer “next greater/smaller” or maintain a decreasing/increasing frontier in O(n).

---

## Recognition

### Problem signals
| You read… | Likely sub-pattern |
|-----------|---------------------|
| valid / balanced **parentheses**, brackets, tags | Matching stack |
| **postfix** / RPN / calculator with operators | Stack machine |
| **next greater** / warmer day / span to the right | Monotonic stack (increasing) |
| **largest rectangle** in histogram / max area under bars | Monotonic stack + width at pop |
| **getMin** in O(1) alongside push/pop | Augmented stack |
| merge **fleets** / process from right with dominance | Monotonic stack (simulation) |
| generate all valid **n pairs** of parentheses | Backtracking + balance invariant |

### Constraints that confirm it
- Processing order is **nested** or **last-in-first-out** (inner closes before outer)
- Need O(1) access to the **most recent** unmatched or dominant element
- Linear scan with each element pushed/popped **at most once** → O(n) total
- “Next element to the right that is greater/smaller” on a static array

### When NOT stack
| Situation | Use instead |
|-----------|-------------|
| Subarray sum / product with negatives | Prefix sum, sliding window |
| Top-K across stream | Heap |
| Shortest path in graph | BFS / Dijkstra |
| All subsets / permutations without nesting structure | Backtracking (explicit); stack is optional |
| Sorted search on array | Binary search |

---

## Sub-patterns

### Matching stack — nested open/close
**When:** validate or transform sequences of paired delimiters; inner must close before outer  
**Mechanism:** push opening symbols; on close, pop must match; empty stack at end means valid  
**Examples:** Valid Parentheses

### Stack machine — postfix / expression evaluation
**When:** tokens are operands and operators in postfix order, or evaluate left-to-right with deferred ops  
**Mechanism:** push numbers; on operator, pop two operands, apply, push result; final stack top is answer  
**Examples:** Evaluate Reverse Polish Notation

### Monotonic stack — next greater / span
**When:** for each index, find nearest index to the right (or left) with greater/smaller value  
**Mechanism:** maintain stack of indices in **monotonic** order (e.g. decreasing temps); when current breaks order, pop and assign answer for popped indices  
**Examples:** Daily Temperatures

### Monotonic stack — largest rectangle / area under curve
**When:** max area of rectangle with height = bar[i] in histogram  
**Mechanism:** increasing stack of indices; on shorter bar, pop and compute width using current index and new stack top as boundaries  
**Examples:** Largest Rectangle in Histogram

### Augmented stack — O(1) min (or max)
**When:** design stack with push/pop/top/getMin all O(1)  
**Mechanism:** parallel **min stack** pushes current min alongside value; pop both together  
**Examples:** Min Stack

### Stack simulation — merge dominated intervals
**When:** process entities right-to-left; faster/slower dominance determines merging  
**Mechanism:** stack holds “active” leaders; compare new item with top to merge or push  
**Examples:** Car Fleet

### Backtracking — balanced generation
**When:** enumerate all valid length-2n strings of `(` and `)`  
**Mechanism:** track `open` and `close` counts; add `(` if open < n; add `)` if close < open; base case length 2n  
**Examples:** Generate Parentheses (same balance idea as matching stack, but search tree not LIFO scan)

---

## Templates

Pseudocode only — not tied to any language.

### Matching stack — valid parentheses
```
function isValid(s):
    stack ← empty list
    map ← closing char → matching opening char

    for ch in s:
        if ch is opening:
            push ch onto stack
        else if ch is closing:
            if stack empty or stack.pop() ≠ map[ch]:
                return false

    return stack is empty
```

### Stack machine — evaluate RPN
```
function evalRPN(tokens):
    stack ← empty list

    for tok in tokens:
        if tok is operator:
            b ← pop stack
            a ← pop stack
            push apply(tok, a, b) onto stack
        else:
            push numeric value of tok onto stack

    return stack top
```

### Monotonic stack — next greater to the right
```
function dailyTemperatures(temps):
    n ← length(temps)
    answer ← array of n zeros
    stack ← empty list of indices   // decreasing temps (top = warmest pending)

    for i from 0 to n - 1:
        while stack not empty and temps[i] > temps[stack.top]:
            j ← pop stack
            answer[j] ← i - j
        push i onto stack

    return answer
```

### Monotonic stack — largest rectangle in histogram
```
function largestRectangleArea(heights):
    stack ← empty list of indices   // increasing heights
    best ← 0

    for i from 0 to length(heights):
        h ← heights[i] if i < length(heights) else 0   // sentinel flush

        while stack not empty and h < heights[stack.top]:
            height ← heights[pop stack]
            left ← stack.top + 1 if stack not empty else 0
            width ← i - left
            best ← max(best, height * width)

        push i onto stack

    return best
```

### Augmented stack — min stack
```
structure MinStack:
    values ← empty list
    mins ← empty list

    function push(x):
        append x to values
        if mins empty or x ≤ mins.top:
            append x to mins

    function pop():
        v ← pop values
        if v equals mins.top:
            pop mins
        return v

    function getMin():
        return mins.top
```

### Stack simulation — car fleet
```
function carFleet(target, position, speed):
    // pair (position, time to target) sorted by position descending
    stack ← empty list   // stack of fleet arrival times (monotonic increasing from top)

    for each car in cars sorted by position descending:
        time ← (target - position) / speed
        if stack empty or time > stack.top:
            push time onto stack
        else:
            // merges into fleet above — do not push

    return length(stack)
```

### Backtracking — generate parentheses
```
function generateParenthesis(n):
    result ← empty list

    function dfs(open, close, path):
        if length(path) equals 2 * n:
            append copy of path to result
            return
        if open < n:
            dfs(open + 1, close, path + "(")
        if close < open:
            dfs(open, close + 1, path + ")")

    dfs(0, 0, empty string)
    return result
```

---

## Decision flow

```mermaid
flowchart TD
  A[Problem] --> B{Nested pairs / LIFO order?}
  B -->|Validate or match| C[Matching stack]
  B -->|Postfix / operators| D[Stack machine]
  B -->|No| E{Per-index nearest greater/smaller?}
  E -->|Yes| F[Monotonic stack]
  E -->|No| G{Design push/pop + extra query?}
  G -->|getMin O(1)| H[Augmented stack]
  G -->|No| I{Merge by dominance scanning backward?}
  I -->|Yes| J[Stack simulation]
  I -->|No| K{Enumerate all valid nested strings?}
  K -->|Yes| L[Backtracking + balance]
```

---

## Anti-patterns

| Misroute | Why it fails | Use instead |
|----------|--------------|-------------|
| O(n²) scan for next greater each index | TLE on n = 10⁵ | Monotonic stack O(n) |
| Count brackets with counters only (no stack) when multiple types `()[]{}` | Cannot verify correct nesting order | Matching stack |
| Pop only one operand for binary operator | Wrong RPN evaluation | Pop two, order matters for `-` `/` |
| Store values in monotonic stack instead of **indices** | Cannot compute spans/widths | Store indices; read `heights[i]` |
| Recompute rectangle width as `i - j` only on pop without left boundary | Wrong width when bars between are taller | Width = `i - stack.top - 1` after pop |
| Push every car time on Car Fleet without comparing to stack top | Overcounts fleets | Only push if new time > top (slower fleet) |
| DFS generate `)` when `close >= open` | Invalid strings in output | Enforce `close < open` |
| Recursion depth n = 20k for Generate Parentheses | Stack overflow in some langs | Iterative stack or backtracking with explicit stack |
| Use heap for “next greater” on static array | O(n log n) unnecessary | Monotonic stack O(n) |

---

## Complexity cheat sheet

| Variant | Time | Space |
|---------|------|-------|
| Matching stack | O(n) | O(n) |
| Stack machine (RPN) | O(n) | O(n) |
| Monotonic stack (next greater / histogram) | O(n) | O(n) |
| Augmented min stack | O(1) per op | O(n) |
| Car fleet simulation | O(n log n) sort + O(n) stack | O(n) |
| Generate parentheses | O(4ⁿ / √n) output size; O(n) recursion depth | O(n) path |
| Brute force next greater per index | O(n²) | O(1) — avoid |

---

## NeetCode 150 — problems in this bucket

| # | Problem | Difficulty | Sub-pattern | Status |
|---|---------|------------|-------------|--------|
| 21 | Valid Parentheses | Easy | Matching stack | generated |
| 22 | Min Stack | Medium | Augmented stack | generated |
| 23 | Evaluate Reverse Polish Notation | Medium | Stack machine | generated |
| 24 | Generate Parentheses | Medium | Backtracking + balance | generated |
| 25 | Daily Temperatures | Medium | Monotonic — next greater | generated |
| 26 | Car Fleet | Medium | Stack simulation | generated |
| 27 | Largest Rectangle in Histogram | Hard | Monotonic — rectangle width | generated |

---

## One-page summary

- **Open/close validation** → push opens; on close, pop must match; end with empty stack.
- **RPN / calculator** → push numbers; operator pops two, pushes result.
- **Next greater to the right** → decreasing monotonic stack of indices; pop when current is warmer/taller.
- **Largest rectangle** → increasing stack of indices; on shorter bar, pop and compute width with `i` and new top as bounds; sentinel height 0 at end.
- **Min stack** → second stack tracks running minimum; pop both when values equal min.
- **Car fleet** → sort by position descending; stack of arrival times; push only if slower than top fleet.
- **Generate parentheses** → backtrack: add `(` if open < n, add `)` if close < open; not always explicit stack but same balance rule.
