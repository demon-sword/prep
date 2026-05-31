# Generate Parentheses — Medium — Backtracking + balance (Stack)

**LC:** https://leetcode.com/problems/generate-parentheses/
**NeetCode:** —
**Status:** `review`
**Generated:** ralph-dsa
**Last reviewed:** —
**Next review:** —

---

## Framing

### Trigger phrases
- generate **all combinations** of well-formed parentheses
- given **n pairs** of parentheses, return every valid arrangement
- only `(` and `)` — must be **balanced** at every prefix
- classic backtracking / DFS enumeration problem

### Constraints that matter
- 1 ≤ n ≤ 8 — output is Catalan-sized (~4ⁿ / √n strings); brute enumeration of all 2^(2n) binary strings is feasible only for tiny n but wasteful
- Must produce **only valid** strings — cannot generate all 2^(2n) strings and filter (works for n ≤ 8 but wrong approach at scale)
- Recursion depth at most 2n — safe for n ≤ 8; same balance rule as matching-stack validation

### Pattern
Backtracking with balance invariant — track counts of opens and closes placed; add `(` if open < n; add `)` only if close < open; base case when path length is 2n.

---

## Approach

### Invariant
At every node in the DFS tree, `path` is a valid prefix: for all prefixes of `path`, `#(` ≥ `#)` and `#(` ≤ n, `#)` ≤ n. No invalid string is ever extended.

### Steps
1. Initialize empty `result` list and call `dfs(0, 0, "")` where `open` = `(` count, `close` = `)` count.
2. **Base case:** if `length(path) == 2 * n`, append a copy of `path` to `result` and return.
3. **Choice 1 — add `(`:** if `open < n`, recurse with `open + 1`, same `close`, `path + "("`.
4. **Choice 2 — add `)`:** if `close < open` (never close more than opened), recurse with same `open`, `close + 1`, `path + ")"`.
5. Return `result` after exploring all branches.

### Pseudocode skeleton
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

### Complexity
| | |
|-|-|
| **Time** | O(4ⁿ / √n) — number of valid strings is the nth Catalan number; each string has length 2n |
| **Space** | O(n) recursion depth for path; O(4ⁿ / √n) output storage (not counted in some analyses) |

---

## Tradeoffs

### Brute force
Generate all 2^(2n) strings of `(` and `)` and filter with a validity check (stack or running balance). Works for n ≤ 8 but explores exponentially many invalid strings; O(2^(2n) · n) time vs pruning at build time.

### Why this pattern
The same rule that validates parentheses (never more `)` than `(` in any prefix) doubles as a **pruning rule** during generation. Only valid prefixes are extended, so every leaf is a valid full string with no post-filtering.

### When NOT to use this
- **Count only, don't enumerate** — use Catalan number formula or DP recurrence; no need to materialize all strings.
- **Single answer or lexicographically k-th** — different techniques (iterative construction, rank/unrank on Catalan tree).
- **Multiple bracket types with ordering rules** — extend constraints beyond simple open/close counts.

---

## Pitfalls
- **Adding `)` when `close >= open`** — produces strings like `())(`; always guard with `close < open` before placing a close paren.
- **Adding `(` when `open >= n`** — exceeds pair budget; guard with `open < n`.
- **Mutating shared path without backtracking** — if using a mutable char array, must undo append after each recursive call; string concatenation avoids this but copies more.
- **Forgetting to copy path at base case** — appending a reference to a mutable buffer that gets reused corrupts stored results.

---

## Similar problems
| Problem | Same idea? |
|---------|------------|
| [Valid Parentheses](../problems/021-valid-parentheses.md) | Same balance rule; stack validates one string, backtracking generates all valid strings |
| [Evaluate Reverse Polish Notation](../problems/023-evaluate-reverse-polish-notation.md) | Stack category sibling; different use of LIFO (evaluation vs nesting structure) |
| [Daily Temperatures](../problems/025-daily-temperatures.md) | Also in Stack bucket; monotonic stack vs explicit DFS tree |

---

## One-liner recall

> DFS from empty string: add `(` if open < n, add `)` if close < open; collect when length is 2n.
