# Valid Parentheses — Easy — Matching stack (Stack)

**LC:** https://leetcode.com/problems/valid-parentheses/
**NeetCode:** —
**Status:** `review`
**Generated:** ralph-dsa
**Last reviewed:** —
**Next review:** —

---

## Framing

### Trigger phrases
- determine if a string of **brackets** is **valid** / balanced
- each opening bracket must be closed by the **same type** in the **correct order**
- only `()`, `[]`, `{}` — nested pairs with LIFO closing
- "valid parentheses" — classic stack matching problem

### Constraints that matter
- n up to 10⁴ — O(n) single pass is fine; O(n²) rescanning pairs is unnecessary
- string contains only bracket characters — no need to skip non-bracket chars
- odd length → immediately invalid (cannot pair all symbols)

### Pattern
Matching stack — push opening brackets; on closing bracket, pop must match the expected opener; valid iff stack is empty at end.

---

## Approach

### Invariant
Stack holds unmatched opening brackets in order from bottom (outermost) to top (innermost). When reading a closing bracket, the most recent unmatched opener (stack top) must be its partner.

### Steps
1. If length of s is odd, return false.
2. Build map: closing char → matching opening char (`)` → `(`, `]` → `[`, `}` → `{`).
3. Initialize empty stack.
4. For each character ch in s:
   - If ch is opening (`(`, `[`, `{`), push ch onto stack.
   - Else ch is closing: if stack empty or `stack.pop()` ≠ `map[ch]`, return false.
5. Return true iff stack is empty.

### Pseudocode skeleton
```
function isValid(s):
    if length(s) is odd:
        return false

    pairs ← map closing to opening: ")"→"(", "]→"[", "}"→"{"
    stack ← empty list

    for ch in s:
        if ch equals "(" or ch equals "[" or ch equals "{":
            push ch onto stack
        else:
            if stack is empty:
                return false
            top ← pop stack
            if top ≠ pairs[ch]:
                return false

    return stack is empty
```

### Complexity
| | |
|-|-|
| **Time** | O(n) — one pass, O(1) work per character |
| **Space** | O(n) — worst case all opens, e.g. `"((("` |

---

## Tradeoffs

### Brute force
Repeatedly find and remove innermost adjacent pairs `()`, `[]`, `{}` until string empty or no removal possible. Each scan is O(n), up to O(n) rounds → O(n²). Works for small n but wasteful when a single left-to-right stack pass suffices.

### Why this pattern
Closing a bracket must match the **most recently opened** unmatched bracket — exactly LIFO. A stack encodes nesting depth: inner pairs close before outer pairs. One left-to-right scan with push/pop is O(n) and needs no backtracking.

### When NOT to use this
- **Single bracket type only** (e.g. only `(` and `)`) — a running counter of open minus close suffices; stack is still fine but optional.
- **Generate all valid strings of n pairs** — backtracking with open/close counts, not a validation scan ([Generate Parentheses](../problems/024-generate-parentheses.md)).
- **Evaluate arithmetic with operators** — stack machine for RPN, not delimiter matching ([Evaluate RPN](../problems/023-evaluate-reverse-polish-notation.md)).

---

## Pitfalls
- **Using one counter for multiple bracket types** — `([)]` has balanced counts but wrong nesting; must use a stack (or type-specific validation).
- **Forgetting to check stack empty on close** — `")"` or `"]"` alone should return false before pop.
- **Not checking stack empty at end** — `"("` passes every close check but is invalid; final `stack is empty` is required.
- **Pushing closing brackets onto the stack** — only push opens; closes always trigger a pop-and-compare against the map.

---

## Similar problems
| Problem | Same idea? |
|---------|------------|
| [Generate Parentheses](../problems/024-generate-parentheses.md) | Same balance rule (close only after open); search/enumerate instead of validate |
| [Evaluate Reverse Polish Notation](../problems/023-evaluate-reverse-polish-notation.md) | Stack-based parsing; operands/operators instead of bracket pairs |
| [Min Stack](../problems/022-min-stack.md) | Stack ADT design; push/pop discipline with extra invariant |

---

## One-liner recall

> Push opens; on close, pop must match map[close]; return stack empty.
