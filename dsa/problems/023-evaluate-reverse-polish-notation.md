# Evaluate Reverse Polish Notation — Medium — Stack machine (Stack)

**LC:** https://leetcode.com/problems/evaluate-reverse-polish-notation/
**NeetCode:** —
**Status:** `review`
**Generated:** ralph-dsa
**Last reviewed:** —
**Next review:** —

---

## Framing

### Trigger phrases
- evaluate an expression in **reverse Polish notation** (postfix)
- operands appear **before** their operator
- token array of numbers and operators `+`, `-`, `*`, `/`
- "RPN" / "postfix calculator" — classic stack evaluation

### Constraints that matter
- 1 ≤ tokens.length ≤ 10⁴ — single left-to-right pass with O(1) stack ops per token is required
- Each token is a valid integer or one of four operators — no parentheses to parse
- Division **truncates toward zero** (not floor toward −∞); matters for negative quotients
- Guaranteed valid expression — always exactly one final value; no divide-by-zero in tests

### Pattern
Stack machine — scan tokens left to right; push operands; on operator, pop two values, apply, push result; final stack top is the answer.

---

## Approach

### Invariant
After processing tokens[0..i], the stack holds the partial results of the postfix prefix in bottom-to-top order, ready for remaining operators. Stack size equals number of unresolved operand slots in the partially evaluated expression.

### Steps
1. Initialize empty stack.
2. For each token in tokens:
   - If token is an operator (`+`, `-`, `*`, `/`):
     - Pop `b` (right operand), then pop `a` (left operand).
     - Compute `result ← apply(operator, a, b)` — note order for `-` and `/`.
     - Push `result` onto stack.
   - Else token is an integer: push its numeric value onto stack.
3. Return stack top (only one value remains).

### Pseudocode skeleton
```
function evalRPN(tokens):
    stack ← empty list
    ops ← set { "+", "-", "*", "/" }

    for tok in tokens:
        if tok in ops:
            b ← pop stack          // right operand (pushed more recently)
            a ← pop stack          // left operand
            if tok is "+":
                push a + b onto stack
            else if tok is "-":
                push a - b onto stack
            else if tok is "*":
                push a * b onto stack
            else if tok is "/":
                push truncate_toward_zero(a / b) onto stack
        else:
            push integer value of tok onto stack

    return stack.top
```

### Complexity
| | |
|-|-|
| **Time** | O(n) — each token pushed once, each operator causes two pops and one push |
| **Space** | O(n) — worst case stack holds all operands before any operator (e.g. `"2","3","+"` never happens in valid RPN; worst is roughly n/2 for unbalanced prefix) |

---

## Tradeoffs

### Brute force
Convert RPN to infix or prefix, parse with recursion/shunting-yard, then evaluate — extra parsing passes and string manipulation; O(n) but more code and error-prone for interview time.

### Why this pattern
Postfix is designed for stack evaluation: every operator immediately consumes the two most recent operands. One linear scan, O(1) work per token, no lookahead or precedence rules needed.

### When NOT to use this
- **Infix expression** with parentheses and operator precedence — use shunting-yard to convert to RPN first, or recursive descent.
- **Unary operators or variables** — extend the machine with unary handling or symbol table; plain RPN template assumes binary ops only.
- **Floating-point with rounding rules** — truncation semantics differ from language defaults; verify spec.

---

## Pitfalls
- **Wrong pop order for `-` and `/`** — first pop is the right operand; `["4","3","-"]` must yield 1, not −1. Always compute `a op b` where `a` was pushed before `b`.
- **Floor division vs truncate toward zero** — in Python, `//` floors; LeetCode expects truncate toward zero for negatives (e.g. `7 / -3 → -2`, not -3). Use `int(a / b)` or language-specific truncate.
- **Checking operator membership incorrectly** — negative numbers like `"-11"` are operands, not operators; test token against the operator set, not "starts with `-`".
- **Forgetting to push result back** — after applying operator, the combined value must go back on the stack for upstream operators.

---

## Similar problems
| Problem | Same idea? |
|---------|------------|
| [Valid Parentheses](../problems/021-valid-parentheses.md) | Stack processes tokens sequentially; matching vs evaluation |
| [Min Stack](../problems/022-min-stack.md) | Stack ADT as core structure; RPN uses plain push/pop only |
| [Largest Rectangle in Histogram](../problems/027-largest-rectangle-in-histogram.md) | Different stack use (monotonic); both rely on LIFO discipline |

---

## One-liner recall

> Scan left to right: push numbers; on operator pop b then a, push `a op b` (truncate division toward zero); return stack top.
